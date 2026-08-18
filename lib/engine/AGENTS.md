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
  → 模式分发：注入 / 闪念笔记 / 翻译 / AI 梳理
```

## 核心抽象

| 类 | 文件 | 职责 |
|---|---|---|
| `CoreEngine` (singleton) | `core_engine.dart` | 主编排：键盘监听循环、音频管道、ASR 状态机、模式分发、超时/Watchdog |
| `ASRProvider` | `asr_provider.dart` | 抽象基类：`init() / start() / stop() / dispose()` + Stream<ASRResult> |
| `ASRResult` | `asr_result.dart` | 结果载荷 `{text, isFinal, error?}`（错误走 `error` 字段不走异常）|
| `ModelManager` | `model_manager.dart` | 离线模型下载/解压/校验/激活 + 模型注册表 |
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
| Groq | **复用 `openai_asr_provider.dart`** | 云端非流式 | HTTP（OpenAI 兼容，仅 baseUrl 不同）|

`ASRProviderFactory` 里 `case 'openai': case 'groq':` 落到同一实现 —— 加 OpenAI 兼容的新家族时照此扩展，不要新建重复 provider。

## 关键设计决策

### 1. C Ring Buffer 而非 Dart 回调
原生层（`native_lib/`）采集 16kHz PCM 写入 C Ring Buffer，Dart 端轮询读取。**不用跨 isolate 回调** — 那种方式在 macOS 上反复触发 SIGABRT。原生侧实现见 [`native_lib/AGENTS.md`](../../native_lib/AGENTS.md)。

### 2. 错误用 ASRResult.error 字段，不抛异常
云端 ASR 失败时走 `result.error` 字段返回，CoreEngine 收到后在录音浮窗显示 4 秒。**不要 throw**——会让 stop() 卡死。

### 3. stop() 的两层预算：内层必须给外层让路

```
引擎（core_engine）      provider.stop().timeout(stopTimeout)     ← 外层，超时回调返回 **空文本**
  └ provider 内部        等握手 + 等收尾帧 ≤ kAsrFinalFrameWait   ← 内层，超时返回 **已攒到的文本**
```

| 常量 | 值 | 谁用 |
|---|---|---|
| `kAsrStopTimeout` | 6s | 引擎给 `stop()` 的总预算；也是取消路径的短超时 |
| `kAsrFinalFrameWait` | 4s | provider 内部所有等待**加起来**的上限 |

**内层跟外层齐平就是竞速**：外层先触发的话返回空文本，provider 攒下的部分文本一起丢，
用户看到「一个字都没有」。踩过三种形态：写死 5s 而声明 6s（三个 provider）、
阿里云 `stop()` **盲等 500ms** 直接丢掉慢到的最后一句、
握手 2s 与收尾 4s 各自独立计时正好加到 6s。

现在的写法：`Stopwatch` + `remaining()`，两段共用一个预算；等的是**事件**
（Completer / 标志位轮询）而不是固定时长，早到就早返回。
`test/engine/asr_stop_budget_test.dart` 守这条。

> 例外：OpenAI/Groq 是批量上传，`stopTimeout` 单独声明 35s（HTTP 自身 30s），
> 这在类里写明了理由。取消路径不用它 —— 见 `core_engine.dart` 里的注释。

### 3b. initASR 必须串行且只能在 idle 执行，失败必须上抛

`initASR` 在 await `provider.initialize()` **之前**就把 `_asrProvider` 置 null，
所以两次调用重叠时第二次看不到旧 provider，跳过 dispose 直接并发初始化：
后完成的覆盖字段，先完成的**永远不被 dispose**（云端漏 WebSocket / 离线漏 recognizer），
而它的 textStream 还在往浮窗推 —— 两路结果交替出现。

公开的 `initASR` 因此只是一层串行链，实现在 `_initASRUnsafe`。**不要绕过它。**
执行时还必须重新确认录音状态为 `idle`；录音/处理中替换 provider
会把当前 session 静默丢掉。整个切换期间会锁住录音入口，不能只在第一个 await 前查一次。

初始化失败也必须 `rethrow`：只发一条 `EngineStatus.error` 就正常返回的话，
调用方看到的是「成功」，设置页那段 `Init failed -> rollback` 变成死代码，
配置停在一个加载不起来的模型上。`test/engine/asr_init_serialization_test.dart` 守这两条。

### 3c. 录音启动是跨 provider / native 的事务

`provider.start()` 成功但原生麦克风启动失败时，必须回滚 ASR session；
异步启动期间被取消时，原启动任务在 await 返回后负责回滚，不得再打开麦克风。
应用退出时 `dispose()` 必须等待在途 start/stop，再关 provider 和 stream，否则识别收尾或闪念落盘会被截断。

### 4. 默认模型随包内置（v1.10）

打包脚本 `create_styled_dmg.sh` 在 **codesign 之前**把 SenseVoice 注入到
`SpeakOut.app/Contents/Resources/models/<dirFromUrl>/`（只放 `model.int8.onnx` + `tokens.txt`）。

- `ModelManager.bundledModelDir(id)` 由 `Platform.resolvedExecutable` 反推 `Contents/Resources/...` 并 `existsSync` 判定
- **优先级：用户副本 > 内置**。`getActiveModelPath()` 先查 Application Support 里下载/导入的副本，
  都没有才回落到 bundle —— 反过来会让「导入」按钮对内置模型完全失效（导入了却仍在用 bundle 那份）
- `isModelDownloaded()` 对内置模型返回 true（内置即就绪，列表显示「激活」而非「下载」）
- 内置模型**不显示删除按钮**（`buildActionBtn(isBundled:)`）—— bundle 内的文件删不掉，
  显示删除只会让用户点了没反应
- `AppService._initASR()` 回退时也先查内置，避免 activeModelId 失效时白下载一份 bundle 里已有的模型
- 升级用户的冗余副本：`findRedundantBundledCopies()` 检测 + 开发者选项手动清理。
  ⚠️ **不自动删** —— 该目录同时是「导入模型」的落盘位置，用户的自定义模型也在里面，删前必须确认
- onboarding 检测到内置则跳过整个下载步骤（`_activateBundledModel`）
- **模型不入 git**（228MB 会让仓库永久膨胀）：打包时下载到 `build/bundled-models/` 缓存，已 gitignore
- 开发期 `flutter run` 下 bundle 内没有该目录 → 自动回退原下载流程，行为不变
- ⚠️ 注入必须在 codesign 之前，否则签名不覆盖新文件会导致公证失败

### 5. 模型激活失败回滚
设置页经 `AppService` 调用 `CoreEngine.initASR()` 失败时，必须把模型 ID 和引擎实例一起恢复到切换前状态。

模型文件安装本身由 `ModelManager` 做事务保护：先在 staging 解压，并按 Provider 实际需要的
文件组合校验；校验通过后才用 `.old` 备份替换正式目录。读取模型状态时会自动恢复中断安装
留下的有效备份。**不能退化成只检查 tokens 文件**，否则残缺包会覆盖用户原有模型。

### 6. 预分段识别（pre-segmentation）
录音中检测 3 秒停顿 + 累计 ≥30s 后台触发 ASR 解码。`kPauseSegmentThresholdCount=15`、`kPreSegmentMinDurationSec=30.0`（在 `core_engine.dart`）。停止时只需等最后一段，体感快。

### 7. activeHotkeyCode 而非 pttKeyCode
CoreEngine 记录"实际触发录音的键"，而不是固定查 PTT 键——因为可能是闪念笔记键、AI 梳理键、翻译键。Watchdog 检查的是 `activeHotkeyCode`。
只有 keyCode 和 modifiers 都相同才能进入 shared-key 逻辑；Toggle 的二次按下也必须重新校验 modifiers。

### 8. translateOverride 单次覆盖
即时翻译键按下时设 `_translateOverride`，处理完自动清除。即使 AI 润色全局关闭，翻译键也强制启用 LLM。

### 9. 用户可见状态发 code，不直接展示 fallback

Engine 发 `EngineStatus(code, params)`，状态栏、录音浮窗和通知共用
`engine_status_localizer.dart` 的中英文映射。`message` 只是未知 code 的诊断兜底，不是用户文案真源。

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
- ❌ **不要在 `stop()` 里 `Future.delayed(秒级)` 盲等** — 见 §3，等事件不等时长
- ❌ **不要直接调 `_initASRUnsafe`** — 见 §3b，绕过串行链会漏 provider

## 测试

- `test/engine/core_engine_test.dart` — CoreEngine 状态机
- `test/engine/model_full_flow_test.dart` — 模型下载+解压+激活全流程（**真实网络下载**，跑一次约 3GB）。
  > ⚠️ 2026-08-10 更正：此前标注为「CI 偶发因网络抖动失败，可重跑」，**该归因是错的**。
  > 真因是 `setUp` 未调 `ConfigService().init()` —— `_prefs` 为 null 时 `setActiveModelId` 会
  > **静默 no-op**（`await _prefs?.setString(...)`），于是 `getActiveModelPath()` 读回默认模型 id，
  > 查向未下载的目录返回 null，稳定失败 8 个（9 个模型里只有 id 撞上 `kDefaultModelId` 的 SenseVoice 能过）。已修。
  >
  > 修复后**仍会偶发失败**，那才是真的网络抖动（2026-08-10 实测：同一份代码一次 4 失败、
  > 重跑 10/10 全过）。**区分方法**：稳定复现同样数量、同样用例 → 代码 bug，别赖网络；
  > 两次结果不同 → 网络，重跑即可。排查时先跑 `test/services` + `test/engine` 里
  > 除本文件外的其余 11 个文件（约 598 例，不碰网络），全过即可排除代码回归。
  >
  > **2026-08-13 补充**：上面那条「两次结果不同 → 网络」的判据仍然成立，但它曾把一个真缺陷
  > 伪装成网络问题 —— 慢网络下**稳定** -8 且报 `Bad state: Cannot close sink while adding stream`。
  > 真因：Dart 的 test timeout **不取消正在运行的 Future**，用例超时后 `tearDown` 立刻删掉临时目录，
  > 而下载协程还在往里写 → `PathNotFoundException` 击穿 stream sink → 框架崩 → **后续用例级联失败**。
  > 所以「快网络全过 / 慢网络全崩」看着像网络，实为缺乏隔离。已修（下载前补建父目录 + tearDown 容错）。
  > **教训**：网络只该让**个别**用例失败；一旦出现「整批崩塌」或框架级异常，那是隔离问题，不是网络。
  >
  > **按环境裁剪**（弱网必备）：用体积阈值跳过大模型，避免它们超时拖垮整轮 ——
  > ```bash
  > flutter test                                    # 全跑（约 3GB，需良好带宽）
  > MODEL_TEST_MAX_MB=300 flutter test              # 只跑 300MB 以内的模型
  > MODEL_TEST_MAX_MB=1   flutter test test/engine/model_full_flow_test.dart   # 全部跳过，24 秒
  > ```
  > 体积从 `ModelInfo.description` 里的 `~538MB` / `~1.0GB` 解析，不维护硬编码 id 清单
  > （那种清单会随模型增删漂移）。超时也按体积给：≥300MB 用 30 分钟，其余 10 分钟。
- `test/engine/hotkey_matching_test.dart` — 修饰键精确匹配规则
- `test/engine/asr_stop_budget_test.dart` — 上面 §3 的两层预算（含「不得秒级盲等」扫描）
- `test/engine/asr_init_serialization_test.dart` — 上面 §3b 的串行链与 rethrow
- `test/engine/model_import_atomicity_test.dart` — 模型导入完整性、原子替换与中断恢复
- `test/engine/xfyun_wpgs_test.dart` — 讯飞动态修正的 segment 合并（rg 越界不得重复/丢字）
- 新增 Provider 时：mock WebSocket，验证 protocol 序列（run-task → task-started → result-generated → task-finished/task-failed）

## 与外部依赖

- `sherpa-onnx` SDK v1.12.33 — 通过 FFI 调用，原生模型推理
- 各云端 ASR：HTTP/WebSocket，鉴权方式各异（账户在 `lib/services/cloud_account_service.dart`）
