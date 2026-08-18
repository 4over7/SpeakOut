# lib/services/ — Service 层

> 业务服务层。配置 / LLM 调用 / 笔记 / 聊天历史 / 音频设备 / 云账户 / 计费 / 自动更新。**全部 singleton**，UI 层 + Engine 层都依赖这层。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律
- Engine 协作：Engine 调 ConfigService 读配置、调 LLMService 做润色

## 这层是干什么的

把"业务规则 + 持久化 + 副作用"从 Engine 和 UI 隔离出来。每个服务有清晰职责，singleton 模式，全局可用。

## 服务全清单（13 个）

> 规模列是**量级**不是精确行数（精确值必然漂移）。`engine_types.dart` 是共享类型定义，不是 service。

| Service | 文件 | 规模 | 职责 |
|---|---|---|---|
| **`ConfigService`** | `config_service.dart` | ~600 | **唯一**配置读写入口（包装 SharedPreferences），所有偏好/凭证/状态都过它 |
| **`LLMService`** | `llm_service.dart` | ~730 | **唯一** LLM 调用入口，支持 OpenAI/Anthropic/Ollama 三种 API 格式 + 流式 + 翻译 + 梳理 |
| `AppService` | `app_service.dart` | ~240 | 应用生命周期总控：启动时调 init()，关闭时 dispose() 全部子服务 |
| `CloudAccountService` | `cloud_account_service.dart` | ~830 | 云账户 CRUD（多账户管理 + 凭证安全存储） |
| `AudioDeviceService` | `audio_device_service.dart` | ~300 | 麦克风设备枚举、用户偏好、蓝牙检测、设备变化 Stream |
| `UpdateService` | `update_service.dart` | ~590 | 检查更新、下载 DMG（带断点续传）、Helper 脚本启动安装 |
| `ChatService` | `chat_service.dart` | ~150 | 聊天历史持久化（JSON 文件）、metadata（如 ASR 原文）|
| `BillingService` | `billing_service.dart` | ~230 | Cloudflare Workers Gateway 通信：许可证验证、Token 生成、额度计费 |
| `VocabService` | `vocab_service.dart` | ~220 | 行业词典 + 个人词库 → 注入 LLM prompt 的 `<vocab_hints>` |
| `DiaryService` | `diary_service.dart` | ~50 | 闪念笔记 Markdown 文件按天追加 |
| `OverlayController` | `overlay_controller.dart` | ~80 | 录音浮窗 MethodChannel（show/update/hide → AppDelegate）|
| `NotificationService` | `notification_service.dart` | ~66 | macOS 系统通知（应用内 + 横幅消息）|
| `ConfigBackupService` | `config_backup_service.dart` | ~160 | 配置导入/导出（JSON）。**默认不导出凭证** — 须显式 `includeCredentials=true` 才含密钥（v1.9.0 加固）|

## 关键设计决策

### 1. 全局 singleton + 显式 init/dispose
所有 service 都是 `factory ServiceName() => _instance` 模式。`AppService` 在启动时统一 `init()`，关闭时 `dispose()` 关闭 stream / 取消 timer / 关闭文件句柄（防内存泄漏，2026-03-29 集中修过一轮）。

### 2. ConfigService 是配置唯一入口
**禁止**任何模块直接 `SharedPreferences.getInstance()`。所有 getter 都走 `ConfigService()`，所有 setter 都走 `ConfigService().setXxx()`。原因：
- 默认值集中管理（`AppConstants.kDefaultXxx`）
- 写入有时需要触发副作用（如改音频设备 → 通知 AudioDeviceService 重启）
- 测试时 mock 一个 service 比 mock 整个 SharedPreferences 容易

### 3. LLMService 三条调用路径（但枚举只有两个值）
- OpenAI 兼容（绝大多数：DeepSeek/阿里云/Groq/智谱/Kimi/MiniMax/Doubao 等）
- Anthropic（Claude）
- Ollama（本地）
- 入口在 `correctText()` / `correctTextStream()`。⚠️ 分流是**两段式**，别只看枚举：
  先判 `providerType == 'ollama'` → 走 `_correctTextOllama()`；**其余**才按
  `provider.llmApiFormat` 分流，而 `enum LlmApiFormat` **只有 `openai` / `anthropic`**（无 ollama 成员）
- 模型特定参数（如 V4 thinking off）通过 `_applyModelSpecificParams()` helper 注入

### 4. 流式 stream 在 dispose() 时必须关
所有 service 用 `StreamController` 暴露状态变化。`dispose()` 不关 stream → 内存泄漏 + 单元测试 hang。

### 5. 云账户凭证存储（⚠️ 当前为明文 SharedPreferences）
**现状（2026-06-13 核实）**：云账户凭证（`cloud_cred_*`）、阿里云 AK/SK、LLM key 实际**仍明文存 SharedPreferences**（见 `cloud_account_service.dart`、`config_service._preloadSecureKeys`）。早期文档曾声称"已迁 keychain"，与实现不符，现更正为实话。
- 配置导出默认排除凭证（`ConfigBackupService.exportToFile` 的 `includeCredentials` 默认 false）。
- updateAccount 会清理被移除的旧凭证 key（差集），避免残留 secret。
- **TODO（需单独排期，不可顺手做）**：迁移到 `flutter_secure_storage`（macOS keychain）。涉及 entitlement 变更 + 现有明文数据迁移 + 公证签名验证，需专门测试与回滚方案。

### 6. ChatService metadata 字段扩展
聊天气泡可携带 `metadata` map，用于 dictation 气泡折叠展开 ASR 原文（v1.6.x 起）。新增类似功能时复用此字段，**不要扩 message 主表 schema**。

## 数据流

```
UI 触发动作（如「保存设置」）
  → ConfigService.setXxx()
  → SharedPreferences 持久化
  → 必要时 broadcast 到订阅者（如 AudioDeviceService.deviceChanges）

CoreEngine 录音结束
  → 调 LLMService.correctText(rawAsr, vocabHints: VocabService().getVocabHints())
  → LLMService 内部 _resolveLlmConfig() 选 provider/account/model
  → HTTP/WS 到云端
  → 返回润色文本
  → 顺便 ChatService.append(asr=rawAsr, llm=corrected, metadata)
```

## 不要做什么

- ❌ **不要直接 `SharedPreferences.getInstance()`** — 走 `ConfigService()`
- ❌ **不要在 UI / Engine 直接发 LLM HTTP 请求** — 走 `LLMService()`
- ❌ **不要 new singleton 第二个实例**（`LLMService.new()`） — 用 `LLMService()` 拿全局
- ❌ **新加 service 必须实现 `dispose()`** — 关 stream / 取消 timer
- ❌ **不要在 service 内 `import 'package:flutter/material.dart'`** — service 层无 UI 依赖
- ❌ **不要用 `print()`** — 日志走 `AppLog.d/i/w/e`（在 `lib/config/app_log.dart`）

## 测试

`test/services/` 下 20+ 个文件，**以目录实际内容为准**，这里只标几处需要知道的：

| 测试 | 覆盖 |
|---|---|
| `llm_service_test.dart` + `llm_blackbox_test.dart` | Golden prompt + 流式协议 + 三种 API 格式 |
| `cloud_account_import_test.dart` | 账户导入/合并/回滚/凭证清理（27 例，写路径的主要安全网）|
| `write_chain_discipline_test.dart` | **纪律测试**：链内代码不得再调公开写方法（会死锁，不是报错）|
| `config_backup_service_test.dart` | 导出默认不含凭证 |
| `vocab_csv_test.dart` | CSV 引号/转义/空字段 |
| `think_tag_filter_test.dart` | 流式剥 `<think>`（标签被 delta 切成两半的各种形态）|
| `llm_stream_failure_test.dart` | 流式中断不得重复吐原文 / 残留行不丢 / 伪流式也要清 think |

测试中 ConfigService 用 setter 重置（singleton 不能 fresh new）。

> **无单测的 service**（改动时没有安全网，靠手动验证）：`BillingService`、
> `AudioDeviceService`、`AppService`、`OverlayController`、`UpdateService` 的安装脚本部分
> （`update_service_test.dart` 只覆盖版本比较与校验，不覆盖 helper 脚本执行）。

## 隐藏的雷区

- **AppLog dispose 必须取消 _flushTimer** — 否则测试 hang（已修，2026-03-29）
- **UpdateService 下载用 `request.followRedirects = true`** — http.Client 默认不跟随 302（这个 bug 卡过一次）
- **测试连接（testConnectionWith）和真实调用走不同 base URL** — Anthropic 是 `/v1/messages`，OpenAI 兼容是 `/chat/completions`
- **`CloudAccountService` 的公开写方法只能从链外调** — 链内再调会把自己排到自己后面，
  表现是**卡死而不是报错**。规则由 `write_chain_discipline_test.dart` 守，加新写方法时同步加进它的名单
- **`importFromFile` 现在会抛** — 文件读不了 / JSON 坏 / 不是账户导出格式都 rethrow。
  UI 必须接住；早期它吞成 `return 0`，界面报「导入完成，0 条」，把用户指向完全错误的方向
- **`correctTextStream` 有两条形态完全不同的路径** —— SSE 真流式（OpenAI 兼容）
  和「整段一次性 yield」的伪流式（Anthropic / Ollama）。改其中一条务必看另一条：
  `<think>` 剥离、失败回退这些都要两边都做，否则同一个模型开不开打字机结果不一样
- **流式路径里出错不能无脑 `yield input`** —— 打字机是边收边往用户文档里粘的，
  已经吐过内容再补一份原文 = 用户文档里「半段润色 + 完整原文」。
  只有一个字都没吐过时回退才是对的
- **`ChatService.resetForTest()` 必须 await** —— 它要等掉在飞的 `_pendingSave`。
  丢掉那个协程会让写入落到下一个用例的目录里，异常也算在下一个用例头上
  （表现为「随机某条挂、单独跑不复现」）
- **懒加载不要用「布尔完成位」** — `VocabService` 曾在 await **之前**就把 `_packsLoaded` 置 true，
  并发第二次调用立刻返回而数据还没读完。要记就记 Future 本身（`_x ??= _load()`）
