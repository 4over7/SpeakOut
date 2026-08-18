# native_lib/ — 原生 C/Objective-C 层（macOS）

> macOS 原生能力实现：CGEventTap 键盘监听、AudioQueue 音频采集、Accessibility 文本注入、剪贴板注入、应用激活、权限检查。**单一大文件 `native_input.m`**（近 1800 行，按段分组）+ Linux/Windows 子目录的同名实现。
>
> ⚠️ **本层没有截屏能力** —— 只有权限探测 `check_screen_recording_permission`，且它已无业务调用（详见设计决策 8）。

## 必读

- 上游：[../AGENTS.md](../AGENTS.md)
- 配套：[`../lib/ffi/AGENTS.md`](../lib/ffi/AGENTS.md) — Dart 端 FFI 包装

## 编译

修改 `native_input.m` 后**必须重新编译 dylib**：

```bash
cd native_lib && clang -dynamiclib \
  -framework Cocoa -framework Carbon \
  -framework AVFoundation -framework AudioToolbox -framework CoreAudio \
  -framework Accelerate \
  -o libnative_input.dylib native_input.m -fobjc-arc
```

之后 `flutter build macos` 会把新 dylib 拷进 .app bundle。

## 关键设计决策

### 1. Ring Buffer 而非回调
AudioQueue 回调里写入 C 静态 ring buffer（16kHz mono PCM），Dart 端 FFI 轮询 `get_available_audio_samples` + `read_audio_buffer` 取走。**不用 Dart 回调**——跨 isolate 触发 SIGABRT。

### 2. 录音独立 startPos
`save_recording_wav` 用 `recordingStartPos` 记录录音开始位置，**不用 `ringReadPos`**——后者会被 ASR 流式消费追到 `ringWritePos`，导致 save 出来只剩最后一个 chunk（v1.8.5 之前的 0.2s 残尾 bug）。

### 3. Globe/Fn 键映射
macOS 26 上 Globe 键 keyCode 179 + 标准 Fn 63 双重事件，要映射并抑制重复。

### 4. 文本注入只剩剪贴板一条路
- FFI 入口是 `inject_text`，内部走 `inject_via_clipboard`（写剪贴板 → Cmd+V → 延迟还原）。
- **v1.5.13 起统一走剪贴板**，替代 CGEvent keyboard（HID 队列异步竞争会丢字）。决策见 ADR-002。
- ⚠️ `inject_via_keyboard`（`static`）**仍在文件里但零调用点** —— 历史遗留 dead code。
  别照它推断"GUI 应用走 keyboard、其他走剪贴板"，那套分流早就没有了。
- **打字机效果**：流式 LLM + 剪贴板批量注入（`inject_clipboard_begin/chunk/end`）。

### 4b. 剪贴板事务协调器 ⭐ 改注入前必读

一次性注入、流式注入、AI 梳理的 Cmd+C **共用同一套事务状态**，绝不能各留一套。
（曾经是两套，靠 Dart 侧会话计数推断二者不交错 —— 那个计数管不到普通 `inject()`，
更管不到 native 侧的延迟还原窗口，结果是用户原剪贴板被永久覆盖。）

**状态**（全部由 `clipTxMutex` 保护）：

| 状态 | 含义 |
|---|---|
| `_txActive` / `_txOriginal` / `_txOriginalValid` | 事务是否开启、事务开始前的剪贴板快照、快照可不可信 |
| `_txExpectedChangeCount` / `_txToken` | 所有权判据：只有我们动过的话 changeCount 该是多少；私有 type 里的一次性 token |
| `_txGeneration` | 每次我们改动剪贴板 +1，只有最后一代负责收尾 |
| `_txHoldDepth` | 流式会话深度，>0 时挂起还原 |
| `_txRestorePending` | 还原重试进行中，期间**拒绝开新事务** |

**四条不变量**（违反任何一条都曾造成用户数据丢失）：

1. **快照只在事务开启时拍一次**，且必须与 `changeCount` 同版本（读 → 拍 → 再读，一致才认）。
2. **所有权判据三条齐全**：`changeCount` 相符 + 恰好一个 item + token 匹配。
   `changeCount` 是 Apple 文档里的正规机制，token 只是辅助（general pasteboard
   对所有进程可读，token 能被原样重放）。**不要拿 token 取代 changeCount。**
3. **动剪贴板之前先判所有权**，不是我们的就重拍快照 —— 只在收尾时判是不够的。
4. **失败必须能被感知**：同步失败走返回值，异步还原失败走 `clipboard_restore_failures()` 计数。

**返回值语义**：`tx_paste_locked` 返回 `0` **严格表示「剪贴板一个字都没动过」**。
越过 `clearContents` 之后的任何失败都必须返回非零代次，否则调用方会以为无需收尾，
直接销毁快照 → 剪贴板永久为空。

> 完整事故史与每条不变量的来由：
> [`docs/debug-log/2026-08-16-paste-yields-previous-recognition.md`](../docs/debug-log/2026-08-16-paste-yields-previous-recognition.md)

### 4c. AI 梳理的复制必须原子

`copy_selection_text` 把「发 Cmd+C → 等变化 → 读文本」收进**一次调用**，
并把读取锁死在归因到的那一版。拆成两次 FFI 的话，中间两个窗口会读到别的内容 ——
送进 LLM 的可能是用户剪贴板里的敏感信息。

⚠️ **已知限制**：`changeCount` 变化**证明不了**那次变化来自我们的 Cmd+C。
要确定性来源只能走 Accessibility 的 `AXSelectedText`，尚未实现。

### 5. 偏好设备而非系统默认
`set_input_device` 设 `kAudioQueueProperty_CurrentDevice` 用偏好设备，**不改系统默认**（ConfigService.audioInputDeviceId 是 SSoT）。

### 6. NSTask 启动 helper
自动更新 install 时 `launch_updater` 用 NSTask 启动独立 bash 脚本，输出写到 `~/Library/Logs/speakout-updater.log`（不写 /dev/null，否则启动期失败完全看不见）。它必须返回启动状态；Dart 只在成功后退出主程序。

### 7. CGEventTap 权限
需要 **Input Monitoring** 权限。未授权时 `start_keyboard_listener` 直接返回 0，不尝试启动（避免后续失败消息覆盖正确的"未授权"提示）。

### 8. 屏幕录制：只剩权限探测函数
本层有 `check_screen_recording_permission`，但**已无业务调用**。
唯一用到截屏的「AI 一键调试」功能在 v1.10 整体移除，连带屏幕录制权限项也从设置页删掉了。
函数保留（删它要重编 dylib，收益不成比例），新代码不要以为这里还有截屏能力。

## 文件结构（按段分组）

```
native_input.m
├── Imports & forward declarations
├── Ring buffer 全局状态（ringBuffer / ringWritePos / ringReadPos / recordingStartPos）
├── 键盘监听（CGEventTap callback + start_keyboard_listener / stop_keyboard_listener）
├── 音频采集（AudioQueue callback + start/stop_audio_recording
│              + get_available_audio_samples / read_audio_buffer / get_audio_level / get_audio_spectrum）
├── 设备枚举（AudioObjectGetPropertyData + start/stop_device_change_listener）
├── 剪贴板事务协调器（tx_* 系列 + snapshot_pasteboard，见 §4b）
├── 文本注入（inject_text / inject_clipboard_begin|chunk|end；keyboard 那套是 dead code）
├── 应用控制（activate_app / get_frontmost_app_info / press_key / copy_selection_text）
├── 权限检查（check_screen_recording_permission 等）
├── 自动更新 helper（launch_updater）
├── 录音 WAV 保存（save_recording_wav）
└── ABI 版本（native_input_abi_version，见 lib/ffi/AGENTS.md §ABI 握手）
```

`native_lib/tests/tx_harness.m` —— 剪贴板事务的**可执行**交错测试，
直接 `#include` 本文件拿到 static 函数。两条安全前提：用 `pasteboardWithUniqueName`
（不碰用户剪贴板）、宏掉 `CGEventPost`（不发真按键）。由
`test/engine/native_tx_harness_test.dart` 编译并运行。

其他需要验证 native 内部状态转换的窄场景也使用独立可执行宿主，放在 `native_lib/tests/`，
由 `test/engine/` 中的 Dart 测试负责编译运行；不要用源码文本断言代替行为测试。

## 不要做什么

- ❌ **不要在原生层加业务逻辑** — 这层只暴露原生能力，业务判断放 Engine 层
- ❌ **不要在原生层 NSLog 详细日志** — Dart 端 AppLog 才是 SSoT；原生只记关键启动 + 错误
- ❌ **不要 hardcode 路径**（如录音保存路径）— 通过参数从 Dart 传入
- ❌ **不要忘 -fobjc-arc 编译** — 否则内存管理崩
- ❌ **不要往 ring buffer 写超过容量** — 会覆盖旧数据，确保 buffer 足够大或正确处理回绕
- ❌ **不要在 CGEventTap 回调里做同步 I/O** — 回调有系统时限，超时会被系统禁用整个 tap；
  用 `log_from_tap`（无锁环形缓冲，后台排空），不要用 `log_to_file`
- ❌ **不要把回调里的 `[str UTF8String]` 直接交给 `NativeCallable.listener`** —
  它是异步投递，那是悬垂指针；`strdup` 后由 Dart `nativeFree`
- ❌ **不要改导出签名却不升 ABI 版本** — 四处必须同步，见 [`lib/ffi/AGENTS.md`](../lib/ffi/AGENTS.md)

## Linux / Windows 子目录

`native_lib/linux/`（`native_input.c`）和 `native_lib/windows/`（`native_input.cpp`）提供同名
`libnative_input` 实现（多数 stub），各带 `CMakeLists.txt`。CI 三平台编译
（Windows 测试目前未全绿，见根 AGENTS.md）。

**两条跨平台纪律**：

- **回调 typedef 必须与 Dart 侧参数完全一致**（`KeyCallback` 三个参数）。
  少一个不会编译报错，运行时读到的是栈上残值 —— 组合键判定随机命中。
  指纹锁会检查这一致性。
- **不导出的符号在 Dart 侧必须是「可选档」**，见 [`lib/ffi/AGENTS.md`](../lib/ffi/AGENTS.md) §三档符号。
  放错档会让整组能力、甚至整个 FFI 初始化在这两个平台上失败。

## 调试技巧

- 启用 verbose：`defaults write com.speakout.speakout verbose_logging -bool true`
- 从终端启动 SpeakOut 捕获 stdout：`/Applications/SpeakOut.app/Contents/MacOS/SpeakOut`
- 分析 dylib 是否真的热加载：`stat -f "%Sm" /Applications/SpeakOut.app/Contents/MacOS/native_lib/libnative_input.dylib` vs 进程启动时间
