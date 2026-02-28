# SpeakOut Version History

## [1.3.0] - 2026-02-28

### 新功能: Toggle 模式

- **单击切换录音** — 新增 Toggle 录音模式：单击开始录音，再次单击结束并自动输出文字。适合走动、站立等不方便长按的场景。
- **双 Toggle 快捷键** — 支持「文本注入」和「闪念笔记」两个独立 Toggle 快捷键，各自独立配置。
- **共用键智能判定** — Toggle 键可与 PTT 键设为同一个键，系统用时间阈值自动区分：按住 < 1 秒释放为 Toggle 模式（录音继续），按住 ≥ 1 秒释放为 PTT 模式（立即停止）。
- **最大录音时长保护** — 可选 1/3/5/10 分钟上限，到时自动停止录音，防止忘记关闭。设为「不限制」则无上限。
- **设置页 UI** — 在「触发按键」下方新增「Toggle 模式」设置组，含快捷键编辑/清除、时长下拉、操作提示。
- **完整 i18n** — 中英文 8 个新增 l10n 键。

### 测试

- **测试体系扩展** — 新增 ~117 个测试用例（总计 134），覆盖 CoreEngine、ChatService、DiaryService、LLM Golden。
- **共享测试基础设施** — 提取 `test/helpers/` (MockPathProvider, FakeASRProvider)、Golden 测试锁定 LLM prompt。
- **新增脚本** — `scripts/test_all.sh` (analyze + test + 覆盖率)、`docs/release_checklist.md`。

## [1.2.28] - 2026-02-27

### 国际化 (i18n)

- **引导页全量 l10n** — 提取 ~40 个硬编码中文字符串到 ARB 文件，覆盖欢迎、权限、模型选择、下载、完成全部 5 个步骤。英文系统全英文，中文系统全中文，不再混杂。
- **设置页模型列表 l10n** — 流式模型和离线模型的名称/描述从 `model.name` 改为 `_localizedModelName()` / `_localizedModelDesc()`，中文环境正确显示中文。
- **新增 ~30 个 l10n 键** — 包含参数化字符串 (`onboardingBrowseModels(count)`, `onboardingDownloading(name)`, 下载百分比等)。
- **修正 ARB 模型大小描述** — Zipformer ~85MB→~490MB, Paraformer ~230MB→~1GB，与实际下载一致。

### 下载可靠性

- **数据流超时保护** — `_downloadWithResume` 添加 30 秒无活动超时 (`stream.timeout`)，防止 GitHub 传输卡住时 UI 永远停在"下载中"。超时后自动重试（最多 5 次，间隔递增）。

### 构建与分发

- **DMG 代码签名** — `create_styled_dmg.sh` 加入 Apple Development 证书签名流程（dylib 先签、app bundle 后签），分发给他人后权限可跨重装保留。

## [1.2.27] - 2026-02-26

### 架构重构: 语音输入管道

- **CoreEngine 录音状态机** — 用 `RecordingState { idle, starting, recording, stopping, processing }` 枚举替换 5 个布尔标记 (`_isRecording`, `_isStopping`, `_isDiaryMode`, `_audioStarted` 部分)，消除非法状态组合。
- **RecordingMode 参数化** — `startRecording({required RecordingMode mode})` 替代先设标记再调用的模式，PTT 和日记模式统一入口。
- **提取 OverlayController 单例** — 新增 `lib/services/overlay_controller.dart`，统一 overlay MethodChannel 调用（原散布在 CoreEngine + main.dart 两处），消除双重更新竞态。
- **统一边沿检测** — 提取 `_handleModeKey()` 方法，PTT 和日记的按键处理共用同一逻辑。
- **消除硬编码延迟** — 移除 `stopRecording()` 中多余的 10ms/200ms `Future.delayed`，provider 已内含尾部处理。

### 代码清理

- **删除调试残留** — 移除 `_audioDumpSink`、`_audioBuffer`、`_modelPath`、`_startTime`、`_isInit` 等从未使用或仅调试用的字段。
- **修复 144 个 flutter analyze 问题** — 从 144 issues 降到 0：
  - 移除 20+ 个 unused import (`dart:io`, `dart:convert`, `dart:typed_data`, `shared_preferences`, `crypto` 等)
  - 移除 10+ 个 unused field (`_heartbeatInterval`, `_startCompleter`, `_lastBluetoothDeviceName`, `_checkPermission` 等)
  - `withOpacity()` → `withValues(alpha:)` 全局替换 (28 处，适配 Flutter 3.33+)
  - `print()` → `debugPrint()` 全局替换 (40+ 处)
  - 修复 `curly_braces_in_flow_control_structures` (10+ 处)
  - 修复 `unnecessary_string_interpolations`、`prefer_interpolation_to_compose_strings`
  - 添加 `path_provider_platform_interface` 和 `plugin_platform_interface` 到 dev_dependencies
- **CoreEngine 瘦身** — 从 ~800 行降到 ~700 行，删除 ~115 行死代码。

### 测试

- 全部 17 个测试通过，无需修改测试用例（重构未改变 ASRProvider 接口和 Service 层 API）。

## [1.2.26] - 2026-02-26

### 安全修复 (P0)

- **Gateway: 移除 CORS 全开放** — 不再设置 `Access-Control-Allow-Origin: *`，桌面客户端不需要 CORS。
- **Gateway: 注释 Stripe Webhook** — 未完成的支付模块暂时禁用，避免无签名验证的端点暴露。
- **Gateway: 注释 /token 路由** — 当前客户端本地生成 Token，Gateway 端占位代码暂时禁用。
- **Gateway: 充值码改用 `crypto.getRandomValues()`** — 替换不安全的 `Math.random()`。
- **Gateway: /redeem TOCTOU 缓解** — 先标记卡密已用再增加余额，防止并发双充。
- **Gateway: /admin/generate 输入验证** — 增加 amount/count/prefix 类型校验，count 上限 100。
- **Gateway: /report 类型校验** — `total_seconds` 增加 `typeof` 检查。

### 内存与线程安全 (P1)

- **native_input.m: 修复 `va_list` 双重消费** — 使用 `va_copy` 创建副本，消除未定义行为。
- **native_input.m: 修复 `CFStringRef` 泄漏** — `getDeviceStringProperty` 使用 `__bridge_transfer` 正确转移所有权给 ARC。
- **native_input.m: Ring Buffer 游标改用 `_Atomic`** — 替换 `volatile`，使用 `memory_order_acquire/release` 保证正确的 acquire-release 语义。
- **native_input.m: CGEventTap 改用 `kCGEventTapOptionListenOnly`** — 仅监听不修改事件，降低权限需求。
- **native_input.m: CGEvent 创建增加 NULL 检查** — `inject_via_keyboard` 和 `inject_via_clipboard` 中防止 NULL 解引用。
- **native_input.m: `deviceChangeCallback` 竞态修复** — 本地拷贝回调指针，避免 CoreAudio 线程与主线程之间的 TOCTOU。

### Engine 层修复 (P1-P2)

- **CoreEngine: `stopRecording` 防重入** — 入口检查 `_isStopping`，防止 watchdog 和按键释放并发触发。
- **CoreEngine: 新增 `dispose()` 方法** — 关闭所有 StreamController、释放 NativeCallable、free `_pollBuffer` 原生内存。
- **CoreEngine: 同步日志改异步** — `writeAsStringSync` → `writeAsString().ignore()`，不再阻塞音频处理热路径。
- **CoreEngine: 清理 AGC 死代码** — 移除无效的 `rawPeak` 计算循环和 `dynamicGain = 1.0` 常量，以及未使用的 `_lastAppliedGain` 字段。
- **AliyunProvider: Token 刷新逻辑** — 基于 `_tokenExpireTime` 在过期前 1 小时自动刷新，不再永不刷新。
- **AliyunProvider: `_pendingBuffer` 上限** — 最多缓存 200 个音频块（~10 秒），防止握手卡住时 OOM。
- **AliyunProvider: `dispose()` 设置 `_isReady = false`** — 防止 dispose 后仍被调用。
- **AliyunProvider: 清理空心跳 Timer** — 移除空操作的定时器，WebSocket 协议层自动处理 ping/pong。
- **AliyunProvider: JSON 解析错误不再静默吞掉** — 输出日志便于调试。
- **SherpaProvider: `dispose()` 关闭 `_textController`** — 防止 StreamController 泄漏。
- **SherpaProvider: `_recognizer.free()`** — 正确释放 FFI 对象的原生内存。

### Service 层修复 (P1-P2)

- **LLMService: 修复 HTTP Client 泄漏** — 使用共享的 `_defaultClient` 实例替代每次创建新 Client。
- **ConfigService: `init()` 并发保护** — 使用 `Completer` 防止多次并发初始化。
- **ChatService: 写入序列化** — `_scheduleSave()` 确保 `_saveHistory` 顺序执行，防止并发文件写入竞态。
- **ChatService: 截断后通知 UI** — `_saveHistory` 截断消息后发送 stream 事件。
- **ModelManager: 下载 sink 异常安全** — `try-finally` 确保网络中断时正确关闭 `IOSink` 和 `http.Client`。
- **ModelManager: `firstWhere` → `firstOrNull`** — 无效 ID 不再抛 StateError，改为安全返回。

### UI 修复 (P1-P3)

- **SettingsPage: 修复 `TextEditingController` 在 build 中创建** — AI Prompt 输入框改用 `initState` 中创建的 `_aiPromptController`，解决光标重置和内存泄漏。
- **SettingsPage: 移除双层 `SingleChildScrollView`** — 删除复制粘贴产生的多余嵌套。
- **SettingsPage: `dispose()` 释放所有 Controller** — 补齐 `_akIdController`、`_akSecretController`、`_appKeyController`、`_aiPromptController` 的释放。
- **SettingsPage: 保存成功提示改用 SnackBar** — 不再用 `_showError` 显示成功消息。
- **main.dart: Stream subscription 生命周期管理** — 5 个 subscription 存储为字段，`dispose()` 中统一 cancel。
- **main.dart: 波形数组长度 5→7** — 与 UI 渲染的 7 个 bar 一致，消除模运算导致的视觉重复。
- **ChatPage: 新增 `dispose()`** — 释放 `_textCtrl` 和 `_scrollCtrl`。

### 代码清理

- **删除死代码 `RecordingOverlay`** — 已被原生覆盖层替代，移除文件和 import。
- **`offline_debug.dart` 移到 `tools/`** — 不属于测试，移出 `test/` 目录。
- **`run_tests.sh` 修复** — 使用 `set -e` + `flutter test` 全量运行，替换引用不存在文件的旧命令。
- **SettingsPage: 移除重复注释** — `// Model State` 去重。

### 文档

- **新增 `CLAUDE.md`** — 项目指引文件，包含构建命令、架构设计、关键模块路径。
- **新增代码评审报告** — `docs/wiki/code_review_2026_02_26.md`，45 个问题的完整审查记录。

## [1.2.21] - 2026-01-31

### FTUE (首次使用体验) 修复

- **新增 Onboarding 引导流程**：新用户首次启动时展示权限授权和模型下载的引导页面。
- **修复权限检测类型错误**：`native_input.dart` 中 `checkPermission()` 错误地将 `bool` 与 `int` 比较 (`result == 1`)，导致权限检测永远返回 false。
- **修复键盘监听器未启动**：`CoreEngine.init()` 使用 `_isInit` 作为守卫条件，但 `initASR()` 也设置了该标志，导致 onboarding 后键盘监听器无法启动。现改为检查 `_isListenerRunning`。
- **修复模型下载进度显示**：解决提取阶段显示 `-100%` 的问题，现显示"解压中..."。
- **移除静默标点模型下载**：避免用户混淆 Zipformer 和标点模型的下载状态。
- **新增权限自动刷新**：HomePage 实现 `WidgetsBindingObserver`，从系统设置返回后自动重新检测权限状态。
- **修复 dylib 路径解析**：Release 版本中添加 `flutter_assets` 路径检测，确保原生库正确加载。

### 开发工具

- **新增数据清理脚本**：`scripts/clear_data.sh` 用于完整清理 FTUE 测试数据。
- **清理遗留 MCP 文件**：删除不再使用的 `add_server_dialog.dart`。

## [1.2.20] - 2026-01-30

- **确认修复 ASR 幻觉重复问题**：通过系统性诊断确认问题根源在 Native 库编译/打包环节，重新编译 `libnative_input.dylib` 并重新打包后，语音识别重复问题（如"测测测试"）已彻底消除。
- **诊断方法论**：本次修复采用了"证据先行"的调试方法 —— 先分析 `/tmp/audio_dump.pcm` 确认音频采集层无重复，再排查 ASR 逻辑，最终定位到 Native 库需要重新编译。

## [1.2.19] - 2026-01-26

- **修复底层音频缓冲区竞争 (Native Buffer Decoupling)**：重大底层重构。针对用户反馈的“幻觉重复”，识别出原生 AudioQueue 缓冲区在被 Dart 读取前可能已被系统复写。
- **内存安全异步拷贝**：底层 C 代码现在会立即申请独立内存并拷贝采样数据，彻底解决了 Native 与 Dart 之间的时序竞争。
- **后台音频采集**：将音频采集移出 UI 主线程，使用独立的系统后台线程处理，确保在高负载（如渲染 UI）时依然能维持 100% 连续的声谱信号，从根源消除断点导致的 ASR 幻觉。

## [1.2.18] - 2026-01-26

- **关闭所有数字增益处理 (Raw Signal Bypass)**：按照用户提议进行极限测试，彻底关闭了软件层面的所有自动增益（AGC）和平滑逻辑。ASR 引擎现在直接接收 1.0x 的原始麦克风信号，用于排查是否为增益计算本身导致了幻觉重复。

## [1.2.17] - 2026-01-26

- **采样级增益插值 (Sample-level Interpolation)**：针对用户反馈的“音频截断”感，将增益调整优化为采样点级别的线性插值。现在 100ms 分块之间的音量过渡是绝对平滑的，消除了所有可能导致 ASR 误判的波形突变。

## [1.2.16] - 2026-01-26

- **彻底移除后置去重**：完全删除了输出端的文本去重逻辑，确保 100% 还原 ASR 原始输出。
- **平滑 AGC 增益**：引入指数移动平均（EMA）平滑音量增益，消除由于瞬时增益大幅跳变导致的 ASR 信号失真和幻觉重复。

## [1.2.15] - 2026-01-26

- **深度逻辑审计推倒重排**：优化去重顺序，优先处理单字幻觉，后处理词组重复。
- **AGC 噪声门控**：防止在安静环境下过度放大底噪导致的 ASR 幻觉（修复“测测试三”类重复）。
- **代码除垢**：清理了 `CoreEngine` 中多处冗余的清理逻辑。

## [1.2.14] - 2026-01-26

- 移除输出端硬编码的去重逻辑，优先通过 AGC (自动增益控制) 预防 ASR 幻觉。
- 保留自然的重复表达支持。

## [1.2.13] - 2026-01-26 - 🛡️ 爆音预防与去重双重保护 (Advanced Prevention & Protection)

### 🚀 核心改进 (True Prevention)

- **动态增益控制 (Adaptive Gain Control)**：
  - **事前预防**：实现了动态音频增益逻辑。每 100ms 自动检测输入音量，如果原始声音已经足够强，则自动降低增益至 1.0x（无放大），严防数字削波（Clipping）。
  - 字幕重复现象最根本的诱因——“爆音失真”——在音频进入 ASR 引擎前就被物理阻断了。

- **去重逻辑优化**：
  - 维持 v1.2.12 的智能去重逻辑作为“事后”第二道防线，双重保险确保护正常文字上屏。

---

## v1.2.12 (2026-01-26) - 🛡️ 去重逻辑精度优化 (Deduplication Refinement)

### 🚀 算法优化 (Algorithm Polish)

- **智能去重 (Smart Clean-up)**：
  - 优化了 `_deduplicateFinal` 算法，解决了“误杀”问题。
  - **保护数字**：现在不会误将 `100` 识别为 `10`，确保金额和电话号码的准确性。
  - **保护叠词**：单字重复 2 次（如“看看”、“妈妈”）将被保留，符合中文表达习惯；只有重复 3 次及以上才判定为故障并去重。
  - **短语纠错**：依然精准识别并消除如“原因原因”这类 2-4 字的词组重复点。

---

## v1.2.11 (2026-01-25) - 🛡️ 语音识别稳定性增强 (ASR Stability Fix)

### 🚀 核心修复 (Internal Logic Fixes)

- **消除重复字 (Deduplication)**：
  - 激活了原本处于休eting状态的 `_deduplicateFinal` 逻辑。
  - 现在无论是实时显示还是最终上屏，都会自动过滤由引擎引起的连续字/词重复。

- **音频增益优化 (Gain Optimization)**：
  - 将强制数字增益从 8.0x 调低至 **3.0x**。
  - **证据发现**：8倍增益在灵敏度高的麦克风上会导致严重的“削波失真”，从而误导 ASR 引擎产生重复幻觉。调低后可显著提升在大音量下的识别准确度。

- **流处理加固**：
  - 确保实时文字流（Partial Stream）也经过了去重处理，提升悬浮窗显示的观感。

---

## v1.2.9 (2026-01-25) - 🔧 模型下载稳定性修复 (Model Download Stability)

### 🐛 关键修复 (Critical Fixes)

- **App 沙盒兼容**：
  - 修复了 `bzip2 -t` 完整性校验在 macOS 沙盒环境下失效的问题。
  - 现在依赖 `tar -xf` 解压成功作为完整性验证，兼容性更强。

- **断点续传优化**：
  - 新增 **Content-Range 验证**：校验服务器返回的数据起始位置与请求匹配，防止 CDN 返回错位数据导致文件损坏。
  - 修复 **416 错误处理**：使用 HEAD 请求二次验证文件完整性，不再依赖不可靠的响应头。

- **解压流程加固**：
  - macOS 使用原生 `tar` 命令解压，避免 Dart `archive` 包的内存限制问题。
  - 解压后自动执行 `chmod 755` 修复权限。
  - 使用原生 `find` 命令搜索关键文件，绕过 Dart 文件系统遍历的兼容性问题。

### 📊 技术细节

## v1.2.10 (2026-01-25) - 🔧 界面显示修复 (UI Display Fix)

### 🐛 体验修复

- **实时转写架构重构**：
  - 修复了切换模型后，悬浮窗和主界面无法显示实时文字的问题。
  - 重构 `CoreEngine`，引入持久的 `PartialResult` 中转流，确保 UI 始终监听正确的事件源。
  - 彻底解决了因引擎实例销毁重建导致的 UI 监听失效问题。

### 🐞 其他

- 移除了 v1.2.9 中受 macOS 沙盒限制的 bzip2 校验代码。

## v1.1.0 (2026-01-11) - 💳 Commercialization & UI Polish

The first commercial-ready release with Hybrid Payment System support.

- **Payment System (Hybrid)**:
  - **Pro License**: Support for CD-Key redemption (`/redeem`) and Stripe Webhooks.
  - **Flexible Top-up**: Integrated "Buy Credits" link and manual code entry.
  - **Account Tab**: Dedicated settings page for license management.
- **UI/UX Refactor**:
  - **Settings Redesign**: Moved "Account" to a primary tab; optimized layout for better readability.
  - **Visuals**: Updated App Icon to 160px rounded rectangle; standardized README headers.
- **Documentation**:
  - **Bilingual Architecture**: Added Mermaid diagrams to both English and Chinese README sections.
  - **Icons**: Enhanced Chinese product introduction with visual emojis.

## v1.0.0 (2026-01-11) - 🚀 Initial Open Source Release

The first public stable release of SpeakOut.

- **Open Source**: Complete code release under MIT License.
- **Key Features**:
  - **Tri-Force Engine**: Offline ASR (Sherpa) + Flash Notes (Diary) + MCP Agents.
  - **Privacy First**: Local-only processing by default.
  - **Extension System**: Full support for Model Context Protocol (MCP) to extend capabilities.
- **Documentation**: Comprehensive README (EN/ZH) and Architecture Diagrams.

---

## Beta Phase History (Archives)

### v3.5.18.43 (2026-01-10) - 💎 体验打磨 (Experience Polish)

### 🐛 关键修复 (Critical Fix)

- **Sandbox 持久化修复 (Persistence Fix)**:
  - 修复了 macOS 沙盒环境下，聊天记录和日志无法写入 `~/Documents` 的问题。
  - 现在数据正确存储于 App 的沙盒容器中 (`Library/Containers/...`)。
- **历史记录清理 (Clear History)**:
  - Chat 界面新增 **垃圾桶** 按钮，支持一键清空当前对话列表（带确认保护）。
  - 该操作仅清理 UI 显示，**不会删除** 已经归档的闪念笔记文件。

### ⚡️ 体验优化 (UX)

- **全局错误通知 (Global Error Banner)**:
  - 实现了顶层通知系统。任何文件保存失败或系统错误都会以红色横幅形式在顶部弹出。
- **关于页面自动化**:
  - 版本号现在自动同步，不再需要手动更新文档。

---

### v3.5.18.35 (2026-01-10) - 🤖 智能代理 (Agentic MCP)

### 🚀 核心功能 (Core Features)

- **MCP 代理集成 (Agentic MCP Integration)**:
  - SpeakOut 现在支持 **Model Context Protocol (MCP)**，可以动态连接外部工具（Skills）。
  - **动态发现**: 只需配置 MCP Server，App 会自动学习其能力并在合适时调用。
  - **设置指南**: 移除了硬编码的 Demo，现在可以通过设置页的指南手动添加自定义 MCP（如日历集成）。

- **双重持久化 (Dual Persistence)**:
  - 您的语音输入现在会**并行处理**：
    1. 立即保存为 **闪念笔记** (Diary)。
    2. 同时发送给 **Agent 大脑** 分析意图。
  - 确保数据绝对安全，不会因为 AI 分析失败而丢失原始想法。

### 🛡️ 安全增强 (Security)

- **人机交互确认 (HITL Confirmation)**:
  - 为了防止 AI 误操作，Agent 执行任何命令前都会弹出 **"执行 Agent 命令?"** 确认框。
  - 只有在您点击 **允许** 后，操作才会真正执行。

### ⚙️ 架构升级 (Architecture)

- **并行调用链**: 重构了核心引擎，实现了 ASR 结果的非阻塞分发。
- **独立路由模型**: 可以在设置中为 Agent Router 单独指定模型（如 `gpt-4o-mini`），与文本校正模型解耦。

---

## v3.5.18.29 (2026-01-09) - 📝 闪念笔记 (Flash Note)

### ✨ 新功能 (New Features)

- **闪念笔记 (Flash Note)**:
  - **独立记录模式**: 这是一个区别于普通语音输入的全新功能。按住独立的快捷键（默认为 **Right Option**），即可快速记录当下的想法。
  - **自动归档**: 您的笔记不再是一次性的，而是会作为文本自动**追加保存**到您指定的文件夹中。
  - **每日归档**: 系统会按天自动创建文件（如 `2024-01-09.md`），将一天的想法有条理地组织在一起。

### 🎨 体验优化 (UX Improvements)

- **原生文件夹管理 (Native Directory)**:
  - 笔记存储路径的选择现在调用 **macOS 原生文件选择器**。
  - 您可以直接在选择器窗口中**新建文件夹**，操作习惯与 Finder 完全一致。
- **独立的设置空间**:
  - 为了不干扰原有功能，我们将笔记设置移至了独立的 **"闪念笔记"** 标签页，界面更加清爽。

---

## v3.5.18.15 (2026-01-08) - ℹ️ 版本号显示 (Version Info)

- **关于界面 (About Info)**:
  - 在 **设置 -> 通用** 页面的最底部增加了版本号显示 (例如: `SpeakOut v3.5.4+1006`)。
  - 方便您确认当前运行的是否为最新版本。

---

## v3.5.18.14 (2026-01-08) - 🐛 截断Bug修复 (Truncation fix)

- **多句累积修复 (Multi-sentence Accumulation)**:
  - 修复了当语音较长时，阿里云返回多个句子结果 (Completed Events)，但程序只记录了最后一句导致前面内容丢失的问题。
  - 现在程序会自动累积所有已完成的句子，确保长语音记录完整。
- **停止保护 (Stop Safety)**:
  - 增强了停止录音时的鲁棒性，确保在握手未完成前不会强制关闭连接，防止短语音丢失。

---

## v3.5.18.13 (2026-01-08) - ⚡️ 零延迟握手 (Zero Latency Handshake)

- **音频缓冲机制 (Audio Buffering)**:
  - 为了防止等待云端握手时丢失开头的语音，我们实现了一个内存缓冲区。
  - 现在：按下按键 -> **立刻开始录音** (无需等待网络) -> 录音暂存 -> 等握手成功后自动补发。
  - 效果：彻底消除了说话被掐头的问题，同时保证了与阿里云的完美兼容。

---

## v3.5.18.12 (2026-01-08) - 🐛 云端握手修复 (Cloud Handshake Fix)

- **阿里云网关错误修复 (Gateway Error Fix)**:
  - 修复了 `MESSAGE_INVALID` 错误。之前是因为在服务器尚未准备好时就发送了音频数据。
  - 现在会等待服务器返回 `TranscriptionStarted` 信号后才开始传输音频，彻底解决握手失败问题。
- **标点确认**:
  - 确认阿里云配置中 `enable_punctuation_prediction` 已开启 (True)。

---

## v3.5.18.11 (2026-01-08) - ☁️ 云端引擎优化 (Cloud Optimization)

- **智能标点策略 (Smart Punctuation Strategy)**:
  - 当切换到 **阿里云 (Cloud)** 引擎时，会自动禁用本地标点模型，避免“双重标点”问题。
  - **AI 纠错** 保持开启，继续为您提供语义润色和去口语化服务。

---

## v3.5.18.10 (2026-01-08) - 🎨 极简首页 (Minimalist Home)

- **视觉重构 (Visual Refactor)**:
  - 首页主视觉由显示技术参数的“就绪状态”改为大号品牌名 **"子曰"**。
  - **动态状态栏**: 只有在出错或初始化时才显示技术状态。正常情况下，仅显示简洁的 **"按住 {Key} 键开始说话"**。

---

## v3.5.18.9 (2026-01-08) - U 品牌回归 (Branding Restore)

- **应用标题 (App Title)**:
  - 找回了消失的中文名 “子曰”。
  - 现在标题栏统一显示为 **"子曰 · SpeakOut"** (中文环境) 或 **"SpeakOut · 子曰"** (英文环境)。

---

## v3.5.18.8 (2026-01-08) - ✨ 代码优化 (Code Optimization)

- **提示词语法重构 (Refactor Prompt to Triple Quotes)**:
  - 将 `AppConstants.dart` 中的多行字符串拼接改为 Dart 标准的 `"""` 三引号语法，提高可读性和维护性。

---

## v3.5.18.7 (2026-01-08) - 🧠 提示词更新 (Default Prompt Update)

- **默认 AI 提示词 (Default AI Prompt)**:
  - 更新了系统内置的默认提示词，去除了“英文缩写修正”规则，专注于语气词保留和语义标点。
  - 新规则现在作为“恢复默认”时的基准。

---

## v3.5.18.6 (2026-01-08) - 🐛 设置页修复 (Settings Fix)

- **AI 设置重构 (Refactored AI Settings)**:
  - 恢复了 **AI 提示词 (Correction Prompt)** 的编辑框，现在可以直接在界面修改指令。
  - 隐藏了 **API 配置** (Key/URL)，勾选 "Use Custom API" 后才会显示，界面更加整洁。

---

## v3.5.18.5 (2026-01-08) - 🧠 智能标点架构 (Smart Punctuation)

- **AI 主导，本地兜底 (AI-First Punctuation)**:
  - **Prompt**: 明确要求 AI “通过理解语义，在适当的情况下增加标点符号”。
  - **Fallback**: 代码会自动检测 AI 的输出。如果 AI 忘记加标点（句号/问号等），**本地模型会自动补位**。如果 AI 已经加了，本地模型则**静默**，避免重复。
  - **效果**: 既能利用大模型的高级语义断句，又保证了格式的绝对规范。

---

## v3.5.18.4 (2026-01-08) - 🐛 标点逻辑修复 (Punctuation Logic Fix)

- **标点兜底 (Force Punctuation)**:
  - 修复了当 AI 纠错修改过文本时，本地标点模型被错误的跳过的问题。
  - 现在：无论 AI 是否修改了内容，只要最终结果缺乏标点，本地模型就会进行补充。

---

## v3.5.18.3 (2026-01-08) - U 界面微调 (UI Tweak)

- **设置入口 (Settings Entry)**:
  - 加大了主页右上角的设置齿轮图标 (28 -> **36**)。
  - 增加了边缘间距 (10 -> **16**)，使其更易点击且视觉更平衡。

---

## v3.5.18 (2026-01-08) - 🐛 尾音截断修复 (Tail Truncation Fix)

### 🧠 智能纠错 (AI Correction)

- **提示词温和化 (Conservative Prompt)**:
  - 调整了 AI 纠错的指令，从“删除口水词”改为“仅删除口吃”。
  - **明确保护**: 强制要求保留句末的语气词（如“看看吧”、“呢”、“啊”），避免 AI 误伤自然口语。
  - **缩写**: 保留了如 `'a p'` -> `'APP'` 的有用纠错。

### 🔊 音频稳定性

- **增益增强 (Signal Boost)**: 将软件数字增益从 5.0x 提升至 **8.0x** (+18dB)。
  - **原因**: 离线分析显示部分录音 RMS 能量仅 0.02 (极低)，导致 ASR 引擎难以捕捉尾音或将音识别错误。
- **解码缓冲清空 (Flush Decoder)**: 将注入的静音填充从 0.5s 增加至 **0.8s**。
  - **原因**: 确保强制将解码器缓冲区内残留的最后几个字推出来。
- **停止延迟优化**: 将录音停止后的缓冲等待时间 (Stop Delay) 从 200ms 增加至 **500ms**。
  - **原因**: 200ms 的窗口对于语速较快的情况过于激进，导致部分尾音（如"一下"的"下"）还在系统缓冲区未被处理就被截断。
  - **效果**: 确保所有语音数据都能完整传输给识别引擎。

### 🩺 诊断增强

- **音频转储恢复**: 恢复了 `/tmp/audio_dump.pcm` 原始音频保存功能。
  - 方便在出现识别问题时，通过分析原始音频判断是麦克风收音问题还是引擎识别问题。

---

## v3.5.17 (2026-01-08) - 💎 体验打磨完成版 (Experience Polish Final)

### 🎨 视觉与交互 (Visual & Interaction)

- **波形动画复刻 (Waveform Match)**:
  - 彻底重写了主界面麦克风的波形动画，现在与系统悬浮窗**完全一致**。
  - **细节**: 7 条波形条，80ms 刷新率，真随机高度 (8-48px)，采用 `Curves.easeInOut` 平滑过渡。

- **布局坚如磐石 (Layout Stability)**:
  - **重构**: 废弃了依赖内容尺寸的 `Center` 布局，改用 `LayoutBuilder` + `Stack` 实现像素级绝对定位。
  - **效果**: 无论状态文字如何变化（变长、换行、消失），麦克风图标都保持**纹丝不动**。

- **视觉减负**:
  - 移除了录音状态下文字变红的逻辑，保持界面清爽一致。

### 🧠 智能纠错 (AI Correction)

- **配置修复**:
  - 修复了 `AppConstants` 默认值未生效导致 "API Key MISSING" 的问题。
  - **关键修复**: 将 `assets/llm_config.json` 正确添加到 `pubspec.yaml` 资源列表中，确保配置文件被打包。
  - **效果**: AI 纠错功能现已正常工作，自动去除口水词（如"呃"、"那个"）。

---

## v3.5.6 (2026-01-08) - 🎤 实时显示修复 (Real-time Display Fix)

### ✨ 功能恢复

- **边说边出字**: 恢复实时显示部分识别结果功能。
- 新增 `partialTextStream` getter，转发 ASR Provider 的实时结果流。
- UI 现在同时订阅最终结果和部分结果，实现真正的"边说边出"。

---

## v3.5.5 (2026-01-08) - 🖼️ 悬浮窗修复 (Overlay Fix)

### 🐛 Bug 修复

- **悬浮窗可见性**: 修复悬浮窗在录音结束后立即消失的问题。
- 现在悬浮窗会在有文字时保持显示，即使录音已结束。

---

## v3.5.4 (2026-01-08) - 📊 UI 显示修复 (UI Display Fix)

### 🐛 Bug 修复

- **主界面文字显示**: 添加 `resultStream` 订阅，识别结果现在会显示在主界面。
- **悬浮窗文字显示**: 将识别结果绑定到悬浮窗的 `statusText`。
- 清理冗余诊断日志，移除 `Data Received` 每帧日志。

---

## v3.5.3 (2026-01-08) - 🔧 ASR 启动修复 (ASR Start Fix)

### 🐛 关键 Bug 修复

- **恢复 `_asrProvider.start()` 调用**: 重构时遗漏，导致 Sherpa 内部 stream 为 null，所有音频数据被丢弃。
- 这是 v3.5.0 "No Speech" 问题的根本原因。

---

## v3.5.2 (2026-01-08) - 🩺 诊断日志 (Diagnostic Logging)

### 🩺 诊断

- 添加 `Data Received: XXX bytes` 入口日志，用于验证音频数据流。

---

## v3.5.1 (2026-01-08) - 🔓 权限修复 (Permission Fix)

### 🐛 关键 Bug 修复

- **移除 `permission_handler` 插件**: 该插件在 macOS Release/沙盒模式下无限阻塞。
- 改用 `record` 插件原生的 `hasPermission()` 方法。
- 修复 PTT 按键无响应问题。

---

## v3.5.0 (2026-01-07) - 🛠️ 核心重构 (Core Refactor)

### 🔊 音频核心重写 (Audio Engine Rewrite)

本次更新**彻底重写**了音频采集层，以最严谨的逻辑解决“无声”、“麦克风不可用”和“识别率低”的问题。

- **原生 16000Hz 采集**:
  - 移除了所有中间层的“降采样”算法，改为直接向底层系统申请 16k 音频。
  - **优势**: 消除数字信号处理带来的杂音和精度损失，降低 CPU 占用。
  - **兼容性**: 完美适配 Sherpa 语音引擎的要求。

- **权限卫士 (Permission Guard)**:
  - 引入了严格的“安检机制”。在录音启动前 0.1 秒，必须通过系统级权限验证。
  - 彻底杜绝了“UI 再转但后台没权限”的假死状态。

- **纯净数字增益 (Clean Digital Gain)**:
  - 移除了不可靠的 VPIO 硬件开关。
  - 采用 **5.0x 软件线性增益**。无论麦克风硬件音量多小，都保证有足够的电平供给识别引擎。

- **总结**: 这是一个“返璞归真”的版本。不做花哨的硬件处理，只做最扎实的数据传输。

## v3.4.22 (2026-01-07) - 🎙️ 终极稳定版 (Ultimate Stable)

### 🚀 稳定性重构 (Refactoring)

- **核心路线修正**:
  - 我们放弃了在您设备上不稳定的 VPIO 硬件增益模式（导致“麦克风不可用”的元凶）。
  - 回归到 **标准音频采集** + **软件智能增益** 的组合。
  - **数字增益**: 无论原始声音多小，软件内核直接将其放大 5 倍，确保识别引擎听得清清楚楚。
- **总结**: 这是一个“兼容性”和“效果”的终极平衡版本。

## v3.4.21 (2026-01-07) - 🎙️ 完美重生 (The Resurrection)

### 🚀 最终修复 (Final Fix)

- **VPIO 全面回归**:
  - 既然权限问题已解决，我们**重新启用**了所有高级音频特性。
  - **自动增益 (AGC)**: 解决“声音太小不识别”的问题。
  - **回声消除 (AEC)**: 解决“听到自己声音”的问题。
  - **降噪 (NS)**: 提供纯净的语音流。
- **48k 原生采样**: 恢复高品质音频采集，并由内核进行高质量降采样。
- **总结**: 这应该是本次调试的终点。权限正常 + 增益正常 = 完美识别。

## v3.4.20 (2026-01-07) - 🎙️ 音频文件转储 (Dump Audio)

### 🩺 诊断 (Diagnostics)

- **音频文件导出**:
  - 我们确认数据流已经通畅（不再是静音全0），但音量极低。
  - 此版本会将麦克风听到的原始声音保存到 `/tmp/audio_dump.pcm`。
  - 请运行录音一次，然后我们可以分析这个文件，看看是麦克风增益问题还是只有电流底噪。

## v3.4.18 (2026-01-07) - 🎙️ 深度数据流检测 (Data Flow Inspection)

### 🩺 诊断 (Diagnostics)

- **"全零" 数据预警**:
  - 新增了对音频数据流内容的深度检测。
  - 如果应用检测到收到的数据包全都是 `0x00` (绝对静音)，会发出明确的警告日志。这通常意味着 macOS 的隐私权限虽然表面允许，但底层仍处于被系统静音 (Muted) 的状态。
- **环境重置**:
  - 此版本建议配合 `tccutil reset Microphone com.speakout.speakout` 命令使用，以彻底重置系统的 TCC 权限状态。

## v3.4.17 (2026-01-07) - 🎙️ 录音权限修复 (Entitlement Fix)

### 🩺 根源修复 (Root Cause Fixed)

- **缺失的权限标识**:
  - 我们发现了导致“有动画无文字”的终极原因：Release 版本中缺失了 `com.apple.security.device.audio-input` 关键权限标识。
  - 这导致 macOS 系统虽然弹窗询问了权限，但随后默默地**屏蔽**了实际的音频数据流（Input Muted）。
  - **修复**: 已补全该权限标识，这是彻底解决“静默录音”问题的核心。
- **配置保持**: 暂时继续保持 16k 标准模式，待确认数据通畅后再逐步开放 VPIO 高级功能。

## v3.4.16 (2026-01-07) - 🎙️ 缓存失效与设备重置 (Cache Invalidation)

### 🛠 修复 (Fixes)

- **设备缓存清理**:
  - 当录音设备启动失败时，**立即失效** 之前的缓存设备 ID。
  - 强制以 `null` (系统默认设备) 重新发起录音请求。
  - 这专门修复了当用户拔掉外接麦克风后，App 仍然死守着旧设备 ID 导致无法录音的问题。

## v3.4.15 (2026-01-07) - 🎙️ 核心回退与流诊断 (Stream Diagnostics)

### 🛠 调试模式 (Safe Mode)

- **强制 16k 基线**:
  - 为了排查 48k 采样率可能导致的静默问题，此版本强制回退到 **16000Hz** 采样率。
  - 关闭所有高级音频处理 (VPIO, AutoGain, NoiseSuppress)，以最原始的方式请求音频流。
- **流状态监控**:
  - 增加了对音频数据包的实时监控，如果内核在 5 秒内未收到任何音频数据，会明确记录日志。

## v3.4.14 (2026-01-07) - 🎙️ 音频诊断版本 (Audio Diagnostics)

### 🩺 诊断 (Diagnostics)

- **RMS 能量检测**:
  - 内核增加了实时音频能量 (RMS) 检测与日志记录。
  - 用于判断麦克风是否在采集真实声音，还是被系统静音。
  - 这是为了排查“有波形动画但无文字结果”问题的关键调试版本。

## v3.4.13 (2026-01-07) - 🎙️ 标准核心模式 (Standard CoreAudio)

### 🛠 紧急修复 (Hotfix)

- **禁用 VPIO (Disable VPIO)**:
  - 为了兼容更多种类的外接麦克风（特别是部分 USB 麦克风和虚拟声卡），我们默认**即用标准的 CoreAudio** 模式，不再强制开启回声消除 (VPIO)。
  - 此举虽然牺牲了部分降噪能力，但极大提升了设备兼容性，彻底解决了“有录音动画但转文字为空”的静默问题。
- **48k 原生处理**: 依然保持 48kHz 的原生采样请求，手动进行降采样，确保底层稳定性。

## v3.4.12 (2026-01-07) - 🎙️ 智能灾备机制 (Smart Fallback)

### 🛠 修复 (Fixes)

- **USB 麦克风热插拔保护**:
  - 修复了当指定的外接麦克风（如 USB 麦克风）ID 发生变化或不可用时，App 直接报错退出的问题。
  - **自动回退 (Auto Fallback)**: 现在，如果指定的麦克风打开失败，系统会无缝（< 50ms）切换回 **系统默认麦克风** 并继续录音，确保录音操作不中断。
- **诊断增强**: 增加了更详细的设备连接错误日志，方便排查硬件兼容性问题。

## v3.4.11 (2026-01-07) - 🎙️ 终极兼容性修复 (Ultimate Compatibility Fix)

### 🛠 修复 (Fixes)

- **VPIO 48k 原生采样**:
  - 强制请求 **48000Hz** 音频流（macOS 声卡的原生频率），配合 VPIO 模式确保在所有 Mac 设备（包括 Intel/M1/M2/M3）上都能稳定采集数据。
  - 解决了部分设备因 VPIO 拒绝 16k 请求而导致的 "Error 1852797029" 或 **静默录音** 问题。
  - **手动降采样 (Manual Downsampling)**: 实现高效的 3:1 降采样算法 (48k -> 16k)，确保识别引擎获得标准音频数据。
- **设备记忆恢复 (Smart Device Cache)**:
  - 恢复了对用户指定麦克风的记忆功能。如果“系统默认”设备不可用（如被虚拟声卡劫持），App 会智能切换回您上次选择的 **内置麦克风**。

## v3.4.10 (2026-01-07) - 🎙️ 音频引擎重构：极致稳定与极速响应 (Audio Engine Overhaul)

本次更新彻底重构了底层音频架构，解决了所有已知的稳定性和延迟痛点。

### 🚀 极致性能 (Performance)

- **0 延迟启动 (Parallel Startup)**:
  - 彻底重写 `startRecording` 逻辑，**并行启动** UI 悬浮窗与麦克风引擎。
  - 消除了约 200ms 的串行等待时间，确保**按下即录**，彻底解决“首字丢失” (Head Truncation) 问题。
- **200ms 智能收尾**:
  - 将录音停止后的 "Tail Delay" 从 600ms 精确缩减至 **200ms**。
  - 既能完美覆盖硬件缓冲区延迟（防止吞尾字），又保证了极佳的跟手感。

### 🛡️ 磐石稳定 (Rock-Solid Stability)

- **VPIO 语音处理模式 (Voice Processing IO)**:
  - 废弃了不稳定的手动重采样方案，全面启用 macOS 原生 **VPIO** 模式 (与 Zoom/WeChat 同款)。
  - **彻底修复** "Error 1852797029" (麦克风失效) 问题，利用系统级回声消除与降噪算法，保证全天候稳定运行。
- **互斥锁保护 (Mutex Safety)**:
  - 引入 `_isStopping` 原子锁机制。
  - 智能识别并忽略毫秒级的极速连按冲突，**彻底杜绝** 因快速操作导致的 App 崩溃或死锁。

### ✨ 其他改进

- **默认 AI 纠错**: AI 智能纠错现在默认开启，并配合本地标点模型作为双重保障。
- **默认设备直连**: 为了追求极致速度，默认优先使用系统设定麦克风，跳过耗时的设备枚举过程。

## [v3.4.0] - 2026-01-07

### ✨ UI 重构 (Visual Redesign)

- **全新薄荷绿主题**：采用 `#2ECC71` 作为主色调，界面更清新现代。
- **扁平化首页**：移除发光特效，采用原生风格的扁平化麦克风按钮。
- **悬浮窗重设计**：原生 Swift 实现的全局悬浮窗，采用磨砂玻璃药丸设计，移除红点，优化音波动画。
- **一致性优化**：统一 Light/Dark 模式下的布局和配色，严格遵循 macOS 原生设计规范。

### 🚀 核心优化 (Core Engine)

- **音频稳定性增强**：重构设备选择逻辑，强制刷新设备 ID，解决因设备 ID 变更导致的录音卡死问题。
- **智能纠错升级**：优化 LLM Prompt，专门针对 "APP" 等英文缩写进行纠错增强，解决字母被拆分的问题。
- **性能优化**：通过原生代码实现悬浮窗，大幅降低内存占用。

## v3.3.0 - 2026-01-06 (UI/UX Redesign)

- **Visual Refresh**: 全新 "SpeakOut · 子曰" 视觉语言。
  - **Teal Theme**: 采用青色 (Teal) 作为品牌主色，寓意沉稳文雅。
  - **Breathing Mic**: 首页新增呼吸光效麦克风，录音状态更直观。
  - **Card Layout**: 设置页采用 macOS 系统级卡片式布局，分组更清晰。
- **Dark Mode**: 深度优化的深色模式体验。
- **UX**: 优化了 API Key 隐藏/显示、模型状态指示等交互细节。

## v3.2.0 (2026-01-06) - 国际化支持 (Internationalization)

- **多语言架构 (Multi-language)**: 全面支持英文 (English) 与简体中文界面。
- **动态切换**: 设置中增加了语言切换选项 (跟随系统/中文/英文)，即时生效。
- **本地化优化**: 针对不同语言环境优化了提示文案与状态显示。

## v3.1.6 (2026-01-06) - AI 提示词精简 (Prompt Refinement)

- **中文提示词 (Chinese Prompt)**: 将 AI 纠错的默认 System Prompt 重写为全中文，去除具体案例，增强同音字纠错的通用性。
- **配置优化 (UI Polish)**:
  - 默认未修改的 API 参数现在显示为空白，占位符 (Placeholder) 显示系统默认值，区分更直观。
  - 修复了空 API Key 会覆盖系统默认配置的 Bug。
- **语音引擎优化**:
  - 遇到录音设备失效（Silent/Error）时，明确显示 "🔇 未检测到语音" 提示，避免误导。
  - 增加了录音重启的稳定延时，解决偶发的音频设备死锁问题。

## v3.1.5 (2026-01-06)

- **同音字修复 (Homophone Fix)**: 针对 "统一字" -> "同音字" 等特定 ASR 错误进行了 Prompt 进行定向优化。

## v3.1.4 (2026-01-06)

- **UI 交互重构**: 实现了 "Placeholder as Default" 模式，未配置的项显示为空，清晰展示底层默认值。

## v3.1.3 (2026-01-06)

- **静音检测 (Silence Detection)**: 修复了麦克风失效导致录入空音频时，UI 仍显示成功勾选的 Bug。
- **稳定性**: 增加了音频回退重试的延时 (500ms)，防止底层死锁。

## v3.1.2 (2026-01-06)

- **配置修复**: 修复了空字符串会覆盖默认配置文件的 Bug。
- **Prompt 升级**: 初步增加了同音字纠错指令。

## v3.1.1 (2026-01-06)

- **配置文件支持**: 新增 `assets/llm_config.json` 支持，允许通过文件预设 API Key。
- **阿里云适配**: 深度适配阿里云百炼 (Qwen) 模型参数。

## v3.1.0 (2026-01-06) - AI 纠错 Beta (Intelligent Correction)

- **核心功能**: 首个集成 AI 纠错的版本，支持 OpenAI 兼容接口。
- **UI**: 新增 AI 纠错开关及配置面板。
- **音频**: 实施了第二轮录音死锁保护 (Recorder Reset)。

## v3.0.2 (2026-01-06) - 体验打磨与安全增强 (Experience Polish & Security)

### 🚀 自动化与安全 (Automation & Security)

- **智能安装 (Smart Install)**:
  - 新增自动化安装脚本 `scripts/install.sh`。
  - 自动检测并关闭正在运行的 App，实现一键编译并覆盖安装到 `/Applications`，开发体验极大飞跃。
- **配置安全 (Secure Config)**:
  - 将敏感的阿里云 API Key 移出代码库，改为从 `assets/aliyun_config.json` 读取。
  - 默认加载本地配置文件，支持 Git 忽略，彻底解决开源泄密风险。

### ⚡️ 体验优化 (UX Improvements)

- **错误显性化 (Foreground Error Overlay)**:
  - 当云端识别出错（如断网、Key 无效）时，悬浮窗现在会显示醒目的红色 ❌ 错误提示，而不是静默失败。
- **引擎选择优化 (Engine Selection)**:
  - 设置页面的引擎选择从“开关”改为更直观的 **垂直单选组 (Radio Group)**，明确区分“配置”与“激活”状态。
- **标点优化 (Smart Punctuation)**:
  - 当使用阿里云引擎（自带高精度标点）时，自动跳过本地标点模型，避免双重标点和不必要的 CPU 消耗。

### 🐛 关键修复 (Critical Fixes)

- **初始化竞争 (Init Race Condition)**:
  - 修复了切换引擎设置后，因初始化标志位未重置导致的引擎加载失败（表现为录音无反应）的问题。
- **文字丢失 (Empty Result Fix)**:
  - 修复了云端引擎在停止那一刻可能不返回最后一段文字的 Bug，强制从缓存中捕获最终结果。

---

## v3.0.0 (2026-01-05) - 混合云架构里程碑 (Hybrid Cloud Milestone)

### 🚀 重大更新 (Major Updates)

- **混合云引擎架构 (Hybrid Engine Architecture)**:
  - **双引擎支持**: 可以在“本地离线 (Privacy)”和“云端在线 (Accuracy)”模式间无缝切换。
  - **阿里云集成 (Aliyun Cloud)**: 引入阿里云智能语音服务 (NUI WebSocket)，提供超高精度的在线识别能力。
  - **架构重构**: 重写了核心音频流水线 (CoreEngine)，支持动态插拔不同的 ASR 提供商。

### ✨ 新功能 (New Features)

- **云端配置 (Cloud Config)**: 设置页新增阿里云 API Key 配置入口，支持用户自带 Key (BYOK)。
- **实时流式识别**: 实现了 WebSocket 音频流式上传，延迟极低。

### 🛠 修复与优化 (Fixes & Polish)

- **Settings UI**: 重新设计了设置页面布局，新增“引擎模式”切换开关。
- **稳定性**: 修复了多处因引擎切换导致的初始化状态竞争问题。
- **国际化**: 修正了部分英文提示，全面回归中文界面。

---

## v2.44.6 (2026-01-05) - 极速启动优化 (Instant Start)

- **优化音频延迟 (Audio Startup Latency)**:
  - 移除了每次按下快捷键时重复扫描所有音频硬件的耗时操作 (由 ~1.8秒 降至 <0.1秒)。
  - 实现了输入设备缓存机制 (`InputDevice Cache`)，仅在应用启动或设置变更时刷新设备列表。
  - 现在按下快捷键后，悬浮窗和录音几乎是**瞬时响应**。

## v2.44.5 (2026-01-05) - 录音死锁修复 (Audio Deadlock Fix)

- **修复空闲停止死锁 (Fix Stop on Idle Recorder)**:
  - 解决了当录音启动尚未完成（例如正在检查权限）时，立刻停止录音会导致 `AudioRecorder.stop()` 挂起，进而导致整个 App 界面卡死的严重 Bug。
  - 引入了 `_audioStarted` 状态原子锁，确保只有在录音流真正建立后，才允许调用停止指令。

## v2.44.4 (2026-01-05) - 悬浮窗卡死修复 (Overlay Freeze Hotfix)

- **修复按键释放卡死 (Fix Overlay Freeze on Release)**:
  - 解决了当用户快速按下并释放 Option 键（未说话）时，悬浮窗未能正确关闭导致的界面卡死问题。
  - 增加了录音状态的原子性检查，防止在停止录音后仍继续执行初始化逻辑。

## v2.44.3 (2026-01-05) - 紧急修复 (Hotfix)

- **修复启动崩溃 (Crash on Launch Fix)**:
  - 修复了 Release 模式下因缺少 `app_icon.png` 资源导致的闪退/白屏问题。
  - 修正了 `native_lib` 在 App Bundle 环境下的路径加载逻辑，确保持久化兼容性。
  - 恢复了 DMG 安装包的标准样式 (大图标、居中布局、拖拽安装)。

## v2.44.2 (2026-01-05) - 关键修复 (Silence Padding Fix)

- **修复录音截断 (Truncation Fix)**:
  - 核心引擎现会在处理结束前自动注入 0.5 秒静音帧。
  - 这强制解码器必须处理完缓冲区里最后的几个字，彻底解决了“说话太快被吞字”的问题。

## v2.44.1 (2026-01-05) - 调试工具热修复 (Debug Hotfix)

- **修复**: 修正了离线 ASR 对比工具的配置错误，现在可以正确生成对比日志了。
- **升级**: 将最低系统要求提升至 **macOS 11.0 (Big Sur)**，以消除底层依赖警告并提升稳定性。

## v2.44 (2026-01-05) - 界面与体验优化 (UI & UX Polish)

### ⚡️ 体验优化 (UX)

- **界面微调 (UI Polish)**:
  - 加大了主界面设置图标 (Icon Size) 方便点击。
  - **设置页重构**: 将 "快捷键" 标签改为 "通用" (General)，并将 **音频输入设备** 选项移至此处，归类更合理。
  - **精简列表**: 移除了冗余的语音模型，仅保留推荐的双语模型。

---

## v2.43 (2026-01-05) - 增强稳定性 (Enhanced Stability)

### 🛡️ 修复与保护 (Fixes & Protection)

- **智能麦克风回退 (Fallback Protection)**:
  - 修复了指定麦克风不可用时导致的 App 崩溃 (Error 1852797029)。
  - 现在会自动无缝切换回系统默认麦克风，并给出明确提示。

### ⚡️ 体验优化 (UX)

- **悬浮窗状态显示 (Overlay Status)**:
  - 重新设计了录音悬浮窗 (加大尺寸)，现在会明确显示当前使用的麦克风名称 (如 "MacBook Pro Mic")。
  - 让你时刻确信正在使用正确的设备录音。

---

## v2.42 (2026-01-05) - 音频输入管理方案 (Audio Input Solution)

### ✨ 新增功能 (New Features)

- **音频输入设备选择 (Audio Input Selection)**:
  - 在设置中新增"音频输入设备"选项，允许用户强制指定录音麦克风。
  - 彻底解决了蓝牙耳机 (HFP) 音质差的问题，推荐手动选择 MacBook 内置麦克风。
  - 录音状态栏智能提示当前使用的麦克风名称（仅在非默认设备时显示）。

### 🛠 修复 (Fixes)

- **CoreEngine 稳定性**: 修复了核心引擎类结构导致的潜在崩溃问题。
- **音频采样率**: 强制统一使用 16kHz/16-bit 采样率，提高识别兼容性。

---

## v2.41 (2026-01-04) - 重构里程碑 (Refactoring Masterpiece)

### 🏗️ 架构与稳定性 (Refactoring & Stability)

- **架构升级**：引入 `AppService` 和 `ConfigService`，实现更稳健的状态管理和启动逻辑。
- **UI 重设计**：设置页面全面采用 macOS 原生风格（扁平化设计，优化的间距）。
- **初始化修复**：解决 "Initialize sherpa-onnx first" 报错，强制执行严格的初始化顺序 (ASR -> 标点)。
- **按键修复**：修复自定义快捷键失效问题，确保原生键盘监听器在 App 启动时立即运行。
- **自愈机制**：增加标点模型自修复机制（检测到损坏自动删除）。
- **模型管理**：在设置页面恢复标点模型的手动管理功能（下载/删除）。

---

## v2.40 (2026-01-04)

### ✨ 新功能

- **标点符号恢复 (Beta)**：集成 `sherpa-onnx` 离线标点模型，让语音转文字更自然通顺。
- **系统主题自适应**：应用现在会自动跟随 macOS 系统外观（深色/浅色模式）。

### 🐞 修复

- **闪退修复**：修复了标点模型初始化时因路径判定错误导致的 App 崩溃问题。
- **DMG 安装包**：修复了安装包样式丢失无法显示背景和图标布局的问题。

### ⚡️ 改进

- **UI 体验升级**：
  - 加大了默认窗口尺寸 (800x600)，解决内容显示不全的问题。
  - **设置与模型合并**：使用紧凑的顶部标签页设计。

---

## v2.39 (2026-01-04)

### 修复

- **录音截断修复**：在 `_audioRecorder.stop()` **之前** 等待 500ms，让最后的音频数据有时间被处理。

### 改进

- **设置页面 UI 重构**：移除 Sidebar 依赖，改用顶部导航，适配小窗口。

---

## v2.38 (2026-01-04)

### 新功能

- **原生按键捕获**：支持直接捕获 FN 等特殊修饰键作为 PTT 热键。
- **主界面设置按钮**：右上角添加直达设置的入口。

---

## v2.37 (2026-01-04)

### 改进

- **录音解码优化**：改进 pre/post decode 策略，利用 `inputFinished` 信号减少丢字。
- **图标微调**：声波使用更深颜色增加对比度。

---

## v2.36 (2026-01-04)

### 🧹 整理与优化

- **项目结构清理**：移除根目录冗余文件，规范化工程结构。
- **动态文案**：UI 中的按键提示文案现在会根据实际设置动态变化 (如从 "Left Option" 变为 "Fn")。

---

## v2.35 (2026-01-04)

### 改进

- **最终图标设计**：青绿色气泡+声波设计，全尺寸图标更新。

---

## v2.34 (2026-01-04)

### 改进

- **图标迭代**：尝试新的配色方案 (Teal v2)。

---

## v2.33 (2026-01-04)

### 改进

- **提高快捷键优先级**：将事件捕获级别从 `kCGSessionEventTap` 改为 `kCGHIDEventTap`
  - HID 级别的优先级最高，可以在系统快捷键处理之前拦截按键
  - 这应该允许 FN 键被正确捕获，而不会触发系统输入法切换

---

## v2.32 (2026-01-04)

### 修复

- **修复最后几个字丢失**：停止录音后添加 200ms 延迟 + 最多 50 次解码循环
- **波形动画**：悬浮提示改为 5 个动态蓝色波形条 + 红色圆点脉冲

---

## v2.31 (2026-01-04)

### 新功能

- **系统级录音悬浮提示**：录音时在屏幕显示红点脉冲动画
  - 在所有应用上层显示，即使 SpeakOut 窗口不在前台
  - 红色圆点 + 脉冲动画 + "正在录音..." 文字
  - 使用 MethodChannel 与 Flutter 通信

---

## v2.30 (2026-01-04)

### 修复

- **修复快捷键无法触发录音**：Flutter 使用 USB HID 码，macOS 使用 CGKeyCode，两者不兼容
  - 添加 `_getCGKeyCode()` 函数正确映射修饰键（Left Option=58, FN=63 等）
- **改进 FN 键检测**：使用状态跟踪替代单纯 flags 检测，解决某些键盘型号的兼容问题

---

## v2.29 (2026-01-04)

### 新功能

- **FN 键支持**：现在可以将 FN 键设置为 PTT 快捷键
- 在 `native_input.m` 中添加 keyCode=63 检测，使用 `kCGEventFlagMaskSecondaryFn` 标志位

---

## v2.28 (2026-01-04)

### 新功能

- **Design B UI 重构**：Settings 页面改为双栏布局（左侧边栏导航，右侧内容区）
- **录音悬浮提示**：按住快捷键时屏幕底部显示波形动画提示
- **中文界面**：首页和设置页面全部改为中文
- **模型激活状态显示**：用 ✓ 绿色标记和"使用中"标签标识当前模型

### 改进

- 首页麦克风图标录音时变红，提供视觉反馈
- 状态文字改为中文（"正在录音..."、"处理中..."）

---

## v2.27 (2026-01-04)

### 新功能

- **下载进度显示**：下载模型时显示实时百分比和进度条

### 改进

- 使用流式 HTTP 下载，边下载边更新进度

---

## v2.26 (2026-01-04)

### 新功能

- **自定义快捷键**：Settings 页面支持自定义 PTT 按键
- 配置持久化存储，重启后仍然生效

---

## v2.25 (2026-01-04)

### 新功能

- **音频日志 + 离线 ASR 对比**：录音时保存原始音频到 `/tmp/`
- 停止录音后运行离线 ASR 并在日志中对比结果

### 改进

- 日志格式优化，显示 STREAMING vs OFFLINE 对比

---

## v2.24 (2026-01-04)

### 修复

- **方案3：稳定前缀提交**：实现 Stable Prefix Commit 算法
- **最终去重**：正则表达式移除连续重复字符/词组

### 改进

- 使用 `_longestCommonPrefix()` 追踪稳定前缀
- 连续3次 LCP 相同时锁定为 committed

---

## v2.23 (2026-01-04)

### 修复

- **方案1：Partial Replace + Final Commit**
- UI 实时更新假设，只在松开按键时注入最终结果

---

## v2.22 (2026-01-04)

### 修复

- 实时解码 + 简单去重

### 改进

- 添加 `_deduplicateText()` 函数移除重复字词

---

## v2.21 (2026-01-04)

### 修复

- 启用 Sherpa-ONNX endpoint 检测
- 配置 `rule1MinTrailingSilence`、`rule2MinTrailingSilence`

---

## v2.20 (2026-01-04)

### 修复

- 修复 ASR 输出重复问题初步尝试
- 添加实时 decode 调用

---

## v2.19 及更早版本

- **核心功能**：ASR 引擎集成、PTT 监听、文字注入、模型管理。
