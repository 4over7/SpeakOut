# lib/ffi/ — FFI 层

> Dart ↔ 原生 dylib 的桥接。按平台分发到不同实现（macOS 完整 / Windows / Linux fallback）。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律
- 配套：[../../native_lib/AGENTS.md](../../native_lib/AGENTS.md) — 原生实现（三平台）

## 这层是干什么的

Engine 层需要原生能力：键盘监听、音频采集、文本注入、应用控制、权限探测。
**本层把原生 C API 包装成 Dart 接口**，并吸收平台差异。

> 截屏**不经过本层** —— `core_engine.dart` 直接 `Process.run('screencapture', ...)`；本层只有权限探测。

## 文件清单

| 文件 | 职责 |
|---|---|
| `native_input.dart` | 公共 export 入口 + 平台分发 |
| `native_input_base.dart` | 抽象基类 `NativeInputBase` + **全部 C typedef**（ABI 的 Dart 半边） |
| `native_input_factory.dart` | 按 `Platform.isMacOS / isWindows / isLinux` 创建实现 |
| `native_input_ffi.dart` | 通用 FFI 绑定基类，**三平台共用**；含 ABI 握手与符号绑定 |
| `native_input_linux.dart` | Linux：只提供 dylib 路径，绑定复用上面那个 |
| `native_input_windows.dart` | Windows：同上 |

## 主干概念（改这层之前必须知道的四件事）

### 1. ABI 握手 —— 版本号是签名的函数，不是手写序号

四处必须一致：三个平台的 `SPEAKOUT_NATIVE_ABI_VERSION` + Dart 的
`kExpectedNativeAbiVersion`。**它的值是「导出面指纹的前 6 位十六进制」**，
由 `test/engine/native_batch5_invariants_test.dart` 的指纹锁算出。

指纹覆盖：三平台的**导出函数签名** + **回调 typedef** + Dart 的 **C typedef** +
**symbol → typedef 绑定映射**。改动其中任何一项，指纹变 → 期望版本变 →
四处旧值全部对不上，测试红。

> 为什么不是手写递增：手写靠自觉，而实际发生过「改了 `inject_clipboard_begin`
> 的签名却忘了升版本」—— 那正是这个握手要防的情形（Dart 按 Int32 去调
> 一个还是 void 的旧函数，读到返回寄存器里的残值）。

### 2. 三档符号：核心 / 惰性组 / 可选

| 档 | 绑定时机 | 缺失后果 |
|---|---|---|
| 核心 | `initWithLibrary` 急切绑定 | 失败 rethrow，应用起不来 |
| 惰性组 | 首次使用时整组绑定（音频组 / 设备组 / 权限组 / 剪贴板组 / 梳理组） | 整组能力不可用 |
| 可选 | 惰性组内单独 try，失败置 null | 只有那一个能力降级 |

**放错档会连坐。** 实际发生过两次：日志符号放进核心档，而 Windows/Linux
根本没导出 → 整个 FFI 初始化抛异常；`save_recording_wav`（调试用落盘）
放进音频组急切段 → 缺它会让权限检查、开始录音、读 ring buffer 全部判为未绑定。

判断标准：**这个能力缺了，同组其它能力还能不能用？** 能，就是可选档。

### 3. 失败必须能传回 Dart

原生侧凡是「可能失败、且用户会察觉」的操作，一律返回状态而不是 `void`。
已经这么做的：`inject_text` / `inject_clipboard_begin` / `inject_clipboard_chunk` /
`copy_selection_text` / `press_key`。

> 反例（都真实发生过）：注入失败却报 Ready，用户口述整段话消失还以为是识别没成；
> Cmd+C 没生效却继续读剪贴板，把**上一次的内容**当成选中文字发给 LLM。

异步操作没法用返回值，走**计数 + 对账**：`clipboard_restore_failures()`
由 Dart 在下一次录音 / 剪贴板会话开始时读取比对。

### 4. 跨 isolate 的两条硬规矩

- **音频走轮询，不走回调**：`get_available_audio_samples` + `read_audio_buffer`。
  跨 isolate 回调在 macOS 上反复触发 SIGABRT。
- **回调传字符串必须移交所有权**：`NativeCallable.listener` 是**异步投递** ——
  塞进 isolate 队列就返回，Dart 回调稍后才跑。直接传 `[str UTF8String]` 是悬垂指针。
  native 侧 `strdup`，Dart 侧读完 `nativeFree`（设备变化回调就是这么做的）。

## 导出面（按能力分组，具体签名见 `native_input_base.dart`）

- **ABI**：`native_input_abi_version`
- **键盘**：`start_keyboard_listener`（传 Dart 回调，非轮询）/ `stop_keyboard_listener` / `check_key_pressed`
- **音频采集**：`start_audio_recording` / `stop_audio_recording` / `is_audio_recording` /
  `get_available_audio_samples` + `read_audio_buffer`（轮询）/ `get_audio_level` /
  `get_audio_spectrum` / `save_recording_wav`（可选）
- **音频质量**：`analyze_audio_quality` / `is_likely_telephone_quality`
- **设备**：`get_audio_input_devices` / `get_current_input_device` / `set_input_device` /
  `get_preferred_device_uid` / `set_preferred_device_uid` / `is_device_available`（可选）/
  `is_current_input_bluetooth` / `switch_to_builtin_mic` /
  `start_device_change_listener` / `stop_device_change_listener`
- **文本注入**：`inject_text`（唯一一次性入口，走剪贴板）/
  `inject_clipboard_begin` / `inject_clipboard_chunk` / `inject_clipboard_end`（打字机）/
  `clipboard_restore_failures`（异步还原失败计数）
- **AI 梳理**：`copy_selection_text`（复制并**直接返回文本**）/ `press_key`
- **应用控制**：`activate_app` / `get_frontmost_app_info` / `check_is_terminal_app`
- **权限**：`check_accessibility_permission` / `check_input_monitoring_permission` /
  `check_microphone_permission` / `microphone_permission_status`（三态，不阻塞）/
  `request_microphone_permission`（异步弹框）/ `check_screen_recording_permission` /
  `check_permission_silent`
- **日志 / 内存**：`set_debug_logging`（可选）/ `set_log_directory`（可选）/ `native_free`
- **更新**：`launch_updater`

> **不要**恢复 `copy_selection`（只复制、不返回文本）。它已被删除：
> 「复制」与「读取」拆成两次 FFI 之间有两个窗口会读到别的内容，
> 送进 LLM 的可能是用户剪贴板里的敏感信息。

## 不要做什么

- ❌ **不要在 FFI 层加业务逻辑** — 只做「原生能力 → Dart 接口」，判断放 Engine
- ❌ **不要在 Engine 直接 `dart:ffi`** — 走 `NativeInputFactory.create()`
- ❌ **不要在 stub 里 throw** — 跨平台 fallback 静默安全失败
- ❌ **不要 hardcode dylib 绝对路径** — 走 `Bundle.main.bundlePath`
- ❌ **不要改了 `native_input.m` 不重编 dylib** — 命令见 [`native_lib/AGENTS.md`](../../native_lib/AGENTS.md) §编译
- ❌ **改任何导出签名后不要只改一处版本号** — 见上面「ABI 握手」，跑测试会告诉你新值

## 测试

| 测试 | 证明什么 |
|---|---|
| `test/engine/native_batch5_invariants_test.dart` | 源码级不变量 + **ABI 指纹锁** |
| `test/engine/native_tx_harness_test.dart` | 编译并运行 `native_lib/tests/tx_harness.m`，**真实行为** |
| `test/engine/native_clipboard_session_test.dart` | 剪贴板会话状态 + dylib 新鲜度 |
| `test/engine/clipboard_session_flag_test.dart` | Dart 侧会话计数纪律（AST 判定） |

需要真实 dylib + macOS 权限的部分仍靠手工冒烟，清单见 `docs/release_checklist.md`。
