# lib/engine/ — Engine 层

> 核心编排 + ASR Provider 抽象 + 模型管理。不依赖 Flutter UI，可独立单元测试。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律
- 协作：调 Service 层（ConfigService 读配置、LLMService 做润色）

## 这层是干什么的

把"按住快捷键说话 → 文字注入 App"这条核心链路串起来：

```
快捷键事件 (FFI)
  → CoreEngine 编排
  → ASR Provider 选型 (sherpa 离线 / 阿里云/火山/讯飞/腾讯/OpenAI/Groq 云端)
  → 文本流回吐 → LLM 润色（可选）
  → 模式分发：注入 / 闪念笔记 / 翻译 / AI 梳理 / AI 调试
```

## 核心抽象

| 类 | 文件 | 职责 |
|---|---|---|
| `CoreEngine` (singleton) | `core_engine.dart` (1679) | 主编排：键盘监听循环、音频管道、ASR 状态机、模式分发、超时/Watchdog |
| `ASRProvider` | `asr_provider.dart` | 抽象基类：`init() / start() / stop() / dispose()` + Stream<ASRResult> |
| `ASRResult` | `asr_result.dart` | 结果载荷 `{text, isFinal, error?}`（错误走 `error` 字段不走异常）|
| `ModelManager` | `model_manager.dart` (817) | 离线模型下载/解压/校验/激活 + 注册表（9 可见 + 8 隐藏）|
| `ASRProviderFactory` | `providers/asr_provider_factory.dart` | 按工作模式 + 账户配置选 Provider |

## ASR Provider 实现矩阵

| Provider | 文件 | 类型 | 协议 |
|---|---|---|---|
| Sherpa 离线（流式 + 非流式） | `sherpa_provider.dart` + `offline_sherpa_provider.dart` | 离线 | sherpa-onnx FFI |
| 阿里云百炼 (DashScope) | `dashscope_asr_provider.dart` | 云端实时 | WebSocket |
| 阿里云 NLS（旧版） | `aliyun_provider.dart` + `aliyun_token_service.dart` | 云端实时 | WebSocket + Token |
| 火山引擎 | `volcengine_asr_provider.dart` | 云端实时 | WebSocket |
| 讯飞 | `xfyun_asr_provider.dart` | 云端实时 | WebSocket |
| 腾讯云 | `tencent_asr_provider.dart` | 云端实时 | WebSocket |
| OpenAI | `openai_asr_provider.dart` | 云端非流式 | HTTP |

## 关键设计决策

### 1. C Ring Buffer 而非 Dart 回调
原生层（`native_lib/`）采集 16kHz PCM 写入 C Ring Buffer，Dart 端轮询读取。**不用跨 isolate 回调** — 那种方式在 macOS 上反复触发 SIGABRT。详见 CLAUDE.md「FFI 音频采集」。

### 2. 错误用 ASRResult.error 字段，不抛异常
云端 ASR 失败时走 `result.error` 字段返回，CoreEngine 收到后在录音浮窗显示 4 秒。**不要 throw**——会让 stop() 卡死。

### 3. Provider 抽象 stop() 必须可超时
CoreEngine 调 ASR `stop()` 时设 6 秒超时（云端识别需要 wait task-finished）。Provider 实现里发 `finish-task` 后等 flag，最多 4s。

### 4. 模型激活失败回滚
`ModelManager.initASR()` 抛异常时 CoreEngine 回滚到之前的模型 ID（防止用户卡在"无可用模型"状态）。

### 5. 预分段识别（pre-segmentation）
录音中检测 3 秒停顿 + 累计 ≥30s 后台触发 ASR 解码。`kPauseSegmentThresholdCount=15`、`kPreSegmentMinDurationSec=30.0`（在 `core_engine.dart`）。停止时只需等最后一段，体感快。

### 6. activeHotkeyCode 而非 pttKeyCode
CoreEngine 记录"实际触发录音的键"，而不是固定查 PTT 键——因为可能是闪念笔记键、AI 梳理键、翻译键、调试键。Watchdog 检查的是 `activeHotkeyCode`。

### 7. translateOverride 单次覆盖
即时翻译键按下时设 `_translateOverride`，处理完自动清除。即使 AI 润色全局关闭，翻译键也强制启用 LLM。

## 数据流（细节）

```
[原生 dylib]
  CGEventTap callback → 写键事件到 dart 端
  AudioQueue callback → 写 16kHz PCM 到 C ring buffer

[CoreEngine]
  事件循环（Timer 16ms tick）
  ├─ 读键事件 → 状态机：idle → recording → processing → idle
  ├─ 读音频 chunk → VAD/AGC → 喂给 ASRProvider.feedAudio()
  └─ 收到 ASRResult.text → typewriter 模式实时注入 / 完整模式停止后注入

[ASRProvider]（抽象）
  实现各家协议：WebSocket 连接、send chunks、解析 partial/final result
  yield ASRResult through Stream

[处理后端]
  LLMService.correctText（可选）
  → CoreEngine 决定输出位置：active App 注入 / 笔记文件 append / 聊天历史
```

## 不要做什么

- ❌ **不要 `import 'package:flutter/...'`** — Engine 层无 UI 依赖，否则单元测试无法跑
- ❌ **不要在 ASR Provider 里 throw** — 错误用 `ASRResult.error` 字段
- ❌ **不要绕过 ModelManager 自己读模型路径** — 路径管理 + 激活回滚都在 ModelManager 内
- ❌ **不要在主循环里做长任务（>16ms）** — 阻塞键事件处理
- ❌ **不要直接读 SharedPreferences** — 走 `ConfigService()`
- ❌ **不要复用过期 ASRProvider 实例** — 切换工作模式必须 `dispose()` 旧的、new 新的

## 测试

- `test/engine/core_engine_test.dart` — CoreEngine 状态机
- `test/engine/model_full_flow_test.dart` — 模型下载+解压+激活全流程（**真实网络下载**，CI 偶发因网络抖动失败，可重跑）
- `test/engine/hotkey_matching_test.dart` — 修饰键精确匹配规则（30 个用例）
- 新增 Provider 时：mock WebSocket，验证 protocol 序列（run-task → task-started → result-generated → task-finished/task-failed）

## 与外部依赖

- `sherpa-onnx` SDK v1.12.33 — 通过 FFI 调用，原生模型推理
- 各云端 ASR：HTTP/WebSocket，鉴权方式各异（账户在 `lib/services/cloud_account_service.dart`）
