# lib/ffi/ — FFI 层

> Dart ↔ 原生 dylib 的桥接。按平台分发到不同实现（macOS C / Windows / Linux fallback）。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md) 三层架构铁律
- 配套：[../../native_lib/AGENTS.md](../../native_lib/AGENTS.md) — macOS 原生层（Objective-C 实现）

## 这层是干什么的

Engine 层（特别是 CoreEngine）需要原生能力：键盘事件监听（CGEventTap）、音频采集（AudioQueue）、文本注入（Accessibility / 剪贴板）、屏幕截图、应用激活等。**FFI 层把这些原生 C API 包装成 Dart 调用**。

## 文件清单

| 文件 | 行 | 职责 |
|---|---|---|
| `native_input.dart` | 65 | 公共 export 入口 + 平台分发 |
| `native_input_base.dart` | 207 | 抽象基类 `NativeInputBase`，定义所有原生能力的接口 |
| `native_input_factory.dart` | 14 | 按 `Platform.isMacOS / isWindows / isLinux` 创建实现 |
| `native_input_ffi.dart` | 682 | **macOS 实现** — 调 `libnative_input.dylib` |
| `native_input_linux.dart` | 57 | Linux fallback（多数能力 stub）|
| `native_input_windows.dart` | 56 | Windows fallback（多数能力 stub） |

## 关键设计决策

### 1. Base 抽象 + 工厂分发
`NativeInputBase` 是抽象类，三平台各有实现。Engine 层只 depend on Base，不知道具体平台。新增能力先在 Base 加抽象方法，再补三平台实现（macOS 必须实现，其他可 stub）。

### 2. 命名约定
原生函数 `snake_case`（如 `inject_via_clipboard`），Dart 包装 `camelCase`（如 `injectViaClipboard`）。**Dart 端不暴露 `Pointer<NativeFunction>`，只暴露语义方法**。

### 3. 不用回调
跨 isolate 回调容易触发 SIGABRT。用 **C Ring Buffer 轮询**（音频）或 **方法返回值**（键事件）。详见 `native_lib/AGENTS.md`。

### 4. dylib 路径
运行时通过 `Bundle.main.bundlePath + "/Contents/MacOS/native_lib/libnative_input.dylib"` 加载。**不能 hardcode 绝对路径**——会破坏跨设备运行。

### 5. 平台 fallback 策略
- macOS：完整实现（核心战场）
- Linux / Windows：能跑就跑，跑不了 stub 返回安全默认值（`false` / 空 string / 不抛）。**不阻塞主流程启动**

## 不要做什么

- ❌ **不要在 FFI 层加业务逻辑** — 这层只做"原生能力 → Dart 接口"，业务判断放 Engine 层
- ❌ **不要直接 `dart:ffi` 在 Engine 调用** — 走 `NativeInputFactory.create()` 拿实例
- ❌ **不要在 stub 实现里 throw** — 跨平台 fallback 要 silent 安全失败
- ❌ **修改 `native_input.m` 后必须重新编译 dylib**（命令见 CLAUDE.md「编译命令」），否则旧 dylib 会被加载

## 关键 FFI 函数

主要分组（具体见 `native_input_ffi.dart`）：

- **键盘**：`init_listener / start_listener / stop_listener / poll_event`
- **音频**：`start_audio_recording / stop_audio_recording / get_audio_chunk / get_audio_level / save_recording_wav`
- **设备**：`list_audio_devices / set_input_device`
- **文本注入**：`inject_via_keyboard / inject_via_clipboard / inject_clipboard_begin/chunk/end`
- **应用控制**：`activate_app / get_frontmost_app_info / press_key / copy_selection`
- **截屏**：`capture_screen` (AI 调试用)
- **更新**：`launch_updater`（启动 helper bash 脚本）

## 测试

FFI 层难以单元测试（要真实 dylib + macOS 权限）。集成测试在 `test/integration_test.dart`。本地手工冒烟为主。
