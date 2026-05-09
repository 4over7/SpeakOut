# lib/services/ — Service 层

> 业务服务层。配置 / LLM 调用 / 笔记 / 聊天历史 / 音频设备 / 云账户 / 计费 / 自动更新。**全部 singleton**，UI 层 + Engine 层都依赖这层。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律
- Engine 协作：Engine 调 ConfigService 读配置、调 LLMService 做润色

## 这层是干什么的

把"业务规则 + 持久化 + 副作用"从 Engine 和 UI 隔离出来。每个服务有清晰职责，singleton 模式，全局可用。

## 服务全清单（14 个）

| Service | 文件 | 行数 | 职责 |
|---|---|---|---|
| **`ConfigService`** | `config_service.dart` | 569 | **唯一**配置读写入口（包装 SharedPreferences），所有偏好/凭证/状态都过它 |
| **`LLMService`** | `llm_service.dart` | 700 | **唯一** LLM 调用入口，支持 OpenAI/Anthropic/Ollama 三种 API 格式 + 流式 + 翻译 + 梳理 |
| `AppService` | `app_service.dart` | 178 | 应用生命周期总控：启动时调 init()，关闭时 dispose() 全部子服务 |
| `CloudAccountService` | `cloud_account_service.dart` | 255 | 云账户 CRUD（多账户管理 + 凭证安全存储） |
| `AudioDeviceService` | `audio_device_service.dart` | 298 | 麦克风设备枚举、用户偏好、蓝牙检测、设备变化 Stream |
| `UpdateService` | `update_service.dart` | 499 | 检查更新、下载 DMG（带断点续传）、Helper 脚本启动安装 |
| `ChatService` | `chat_service.dart` | 150 | 聊天历史持久化（JSON 文件）、metadata（如 ASR 原文）|
| `BillingService` | `billing_service.dart` | 225 | Cloudflare Workers Gateway 通信：许可证验证、Token 生成、额度计费 |
| `AudioDeviceService` | `audio_device_service.dart` | 298 | 设备列表、首选设备、蓝牙检测 |
| `CorrectionService` | `correction_service.dart` | 217 | 纠错反馈：LLM 提取词级差异 → 自动追加用户词典 |
| `VocabService` | `vocab_service.dart` | 184 | 行业词典 + 个人词库 → 注入 LLM prompt 的 `<vocab_hints>` |
| `DiaryService` | `diary_service.dart` | 48 | 闪念笔记 Markdown 文件按天追加 |
| `OverlayController` | `overlay_controller.dart` | 77 | 录音浮窗 MethodChannel（show/update/hide → AppDelegate）|
| `NotificationService` | `notification_service.dart` | 66 | macOS 系统通知（应用内 + 横幅消息）|
| `ConfigBackupService` | `config_backup_service.dart` | 140 | 配置导入/导出（JSON 文件，含云账户凭证）|

## 关键设计决策

### 1. 全局 singleton + 显式 init/dispose
所有 service 都是 `factory ServiceName() => _instance` 模式。`AppService` 在启动时统一 `init()`，关闭时 `dispose()` 关闭 stream / 取消 timer / 关闭文件句柄（防内存泄漏，2026-03-29 集中修过一轮）。

### 2. ConfigService 是配置唯一入口
**禁止**任何模块直接 `SharedPreferences.getInstance()`。所有 getter 都走 `ConfigService()`，所有 setter 都走 `ConfigService().setXxx()`。原因：
- 默认值集中管理（`AppConstants.kDefaultXxx`）
- 写入有时需要触发副作用（如改音频设备 → 通知 AudioDeviceService 重启）
- 测试时 mock 一个 service 比 mock 整个 SharedPreferences 容易

### 3. LLMService 三种 API 格式
- OpenAI 兼容（绝大多数：DeepSeek/阿里云/Groq/智谱/Kimi/MiniMax/Doubao 等）
- Anthropic（Claude）
- Ollama（本地）
- 入口分流在 `correctText()` / `correctTextStream()`，按 `provider.llmApiFormat` 决定走哪条
- 模型特定参数（如 V4 thinking off）通过 `_applyModelSpecificParams()` helper 注入

### 4. 流式 stream 在 dispose() 时必须关
所有 service 用 `StreamController` 暴露状态变化。`dispose()` 不关 stream → 内存泄漏 + 单元测试 hang。

### 5. 云账户凭证迁移
`flutter.cloud_cred_secure_migrated` 标记凭证已从明文迁移到 keychain（2026-03-17 引入）。新账户直接进 keychain。**不要再写明文凭证到 SharedPreferences**。

### 6. ChatService metadata 字段扩展
聊天气泡可携带 `metadata` map，用于 dictation 气泡折叠展开 ASR 原文（v1.6.x 起）。新增类似功能时复用此字段，**不要扩 message 主表 schema**。

## 数据流

```
UI 触发动作（如「保存设置」）
  → ConfigService.setXxx()
  → SharedPreferences 持久化
  → 必要时 broadcast 到订阅者（如 AudioDeviceService.deviceChanges）

CoreEngine 录音结束
  → 调 LLMService.correctText(rawAsr, vocabHints: VocabService.getHints())
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

- `test/services/llm_service_test.dart` — Golden + 流式协议 + 三种 API 格式
- `test/services/config_service_test.dart` — 默认值 + setter 行为
- `test/services/correction_service_test.dart` — 词级 diff 提取
- `test/services/diary_service_test.dart` — Markdown 追加
- 测试中 ConfigService 用 setter 重置（singleton 不能 fresh new）

## 隐藏的雷区

- **AppLog dispose 必须取消 _flushTimer** — 否则测试 hang（已修，2026-03-29）
- **UpdateService 下载用 `request.followRedirects = true`** — http.Client 默认不跟随 302（这个 bug 卡过一次）
- **测试连接（testConnectionWith）和真实调用走不同 base URL** — Anthropic 是 `/v1/messages`，OpenAI 兼容是 `/chat/completions`
