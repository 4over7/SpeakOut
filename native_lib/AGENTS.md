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
- FFI 入口是 `inject_text`，内部**直接调 `inject_via_clipboard`**（Cmd+V，200ms 后恢复原剪贴板），没有分流判断。
- **v1.5.13 起统一走剪贴板**，替代 CGEvent keyboard（HID 队列异步竞争会丢字）。决策见 ADR-002。
- ⚠️ `inject_via_keyboard`（`native_input.m` 内 `static`）**仍在文件里但零调用点** —— 历史遗留 dead code。
  别照它推断"GUI 应用走 keyboard、其他走剪贴板"，那套分流早就没有了。
- **打字机效果**（Alpha）：流式 LLM + 剪贴板批量注入（`inject_clipboard_begin/chunk/end`），120ms 批量。

### 5. 偏好设备而非系统默认
`set_input_device` 设 `kAudioQueueProperty_CurrentDevice` 用偏好设备，**不改系统默认**（ConfigService.audioInputDeviceId 是 SSoT）。

### 6. NSTask 启动 helper
自动更新 install 时 `launch_updater` 用 NSTask 启动独立 bash 脚本，输出写到 `~/Library/Logs/speakout-updater.log`（不写 /dev/null，否则启动期失败完全看不见）。

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
├── 文本注入（keyboard + clipboard 两套）
├── 应用控制（activate_app / get_frontmost_app_info / press_key / copy_selection）
├── 权限检查（check_screen_recording_permission 等）
├── 自动更新 helper（launch_updater）
└── 录音 WAV 保存（save_recording_wav）
```

## 不要做什么

- ❌ **不要在原生层加业务逻辑** — 这层只暴露原生能力，业务判断放 Engine 层
- ❌ **不要在原生层 NSLog 详细日志** — Dart 端 AppLog 才是 SSoT；原生只记关键启动 + 错误
- ❌ **不要 hardcode 路径**（如录音保存路径）— 通过参数从 Dart 传入
- ❌ **不要忘 -fobjc-arc 编译** — 否则内存管理崩
- ❌ **不要往 ring buffer 写超过容量** — 会覆盖旧数据，确保 buffer 足够大或正确处理回绕

## Linux / Windows 子目录

`native_lib/linux/`（`native_input.c`）和 `native_lib/windows/`（`native_input.cpp`）提供同名 `libnative_input` 实现（多数 stub），各带 `CMakeLists.txt`。CI 三平台编译（Windows 测试目前未全绿，见根 AGENTS.md）。

## 调试技巧

- 启用 verbose：`defaults write com.speakout.speakout verbose_logging -bool true`
- 从终端启动 SpeakOut 捕获 stdout：`/Applications/SpeakOut.app/Contents/MacOS/SpeakOut`
- 分析 dylib 是否真的热加载：`stat -f "%Sm" /Applications/SpeakOut.app/Contents/MacOS/native_lib/libnative_input.dylib` vs 进程启动时间
