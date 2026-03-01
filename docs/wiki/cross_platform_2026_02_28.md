# SpeakOut 跨平台扩展方案（务实版）

**日期**: 2026-02-28

## 实施进度

### Phase 0: Dart 层最小改动 — ✅ 已完成
- `audio_device_service.dart`: `NativeInput` → `NativeInputBase`
- `native_input_factory.dart`: 新增工厂方法
- `core_engine.dart`: 使用工厂方法 + 修类型
- `config_service.dart`: 条件化 `MacOsOptions`
- 验证: 0 errors, 134 tests passed

### Phase 1: Windows — ✅ 已完成 (Dart + C++ + CI 全绿)
- `native_input_ffi.dart`: ★ 提取 FFI 共用基类（消除 ~400 行重复）
- `native_input.dart`: 精简为仅 macOS 路径查找（~60 行）
- `native_input_windows.dart`: Windows FFI 绑定（~60 行）
- `native_lib/windows/native_input.cpp`: Win32 C++ 实现（~550 行）
  - 键盘: `SetWindowsHookEx(WH_KEYBOARD_LL)` + 消息循环线程
  - 文本注入: `SendInput(KEYEVENTF_UNICODE)`
  - 音频: WASAPI `IAudioClient` + Ring Buffer (16kHz mono 16-bit PCM)
  - 设备: `IMMDeviceEnumerator` 枚举，JSON 格式输出
  - 权限: 全部返回 1（Windows 无需特殊权限）
- `native_lib/windows/CMakeLists.txt`: MSVC 编译配置
- `windows/`: Flutter Windows runner 平台文件
- `main.dart`: 平台入口分发
- `lib/ui/windows/`: 4 个 fluent_ui 页面 (app/home/settings/chat)
- `overlay_controller.dart`: 非 macOS 平台 no-op
- `pubspec.yaml`: 添加 `fluent_ui: ^4.9.0`
- **CI 验证**: GitHub Actions 三平台全绿 — 静态分析 + 134 测试 + MSVC 编译 + Flutter 构建

### Phase 1 CI 调试记录
1. **测试: TOKENS.txt 大小写** — macOS (HFS+) 和 Windows (NTFS) 大小写不敏感，Linux (ext4) 大小写敏感 → 按 `Platform.isLinux` 条件判断
2. **测试: Golden prompt 行尾** — Git 在 Windows 上将 .txt 文件行尾转为 CRLF → 加 `.replaceAll('\r\n', '\n')` 统一
3. **C++ 编译: COM 风格** — MSVC 编译为 C++，不支持 C 风格 `lpVtbl` 调用和 C11 `<stdatomic.h>` → 改用 C++ COM 直接调用 + `std::atomic`
4. **Flutter 构建: 缺少 runner** — 需要 `flutter create --platforms=windows` 生成 `windows/` 目录

### Phase 2: Linux — ✅ 已完成
- `native_lib/linux/native_input.c`: Linux C 实现 (~350 行)
  - 键盘: evdev `/dev/input/eventN` + `select()` 轮询
  - 文本注入: `xdotool` (X11) / `wtype`/`ydotool` (Wayland)
  - 音频: PulseAudio `pa_simple` API (16kHz mono 16-bit PCM, 20ms chunks)
  - Ring Buffer: pthread_mutex 保护
  - 设备: `pactl` 命令行工具
- `native_lib/linux/CMakeLists.txt`: gcc 编译配置 (libpulse, pthread)
- `lib/ffi/native_input_linux.dart`: Linux FFI 绑定 (NativeInputFFI 子类)
- `lib/ui/linux/`: 4 个 Material Design 3 页面 (app/home/settings/chat)
- `linux/`: Flutter Linux runner 平台文件
- `main.dart` + `native_input_factory.dart`: 添加 Linux 分发
- CI: Linux job 增加原生库 CMake 编译 + `flutter build linux`
- 验证: 0 errors, 134 tests passed

### Phase 3: 鸿蒙 — 独立项目

## 核心发现

`NativeInputBase` 已经是完整的 21 方法抽象接口，且只在 3 个文件中使用。不需要拆成 6 个新接口、不需要 Platform Abstraction Layer、不需要 Controller mixin。

## 方案

各平台的 C/C++ 原生库导出**相同的 21 个函数签名**，Dart FFI 层用工厂方法按平台加载不同的动态库。UI 各平台独立实现（macOS: macos_ui, Windows: fluent_ui, Linux: Material+adwaita）。

## 阶段

- **Phase 0** (1-2 天): Dart 层 4 个微调（工厂方法 + 类型修复 + 条件化 SecureStorage） — ✅
- **Phase 1** (4-6 周): Windows 原生库 + UI + CI — ✅
- **Phase 2** (3-4 周): Linux 原生库 `native_input.c` (X11/PulseAudio) + Linux UI (Material)
- **Phase 3**: 鸿蒙 ArkTS 独立仓库

## GitHub Actions CI

```yaml
# .github/workflows/ci.yml
# 三平台并行: macOS + Windows + Linux
# 触发: push/PR to main
# 同分支新 push 自动取消旧运行

macOS:  分析 → 测试 → clang 编译 dylib → flutter build macos
Windows: 分析 → 测试 → CMake/MSVC 编译 dll → flutter build windows
Linux:  分析 → 测试 → CMake/gcc 编译 so → flutter build linux
```

详细方案见计划文件 `/Users/leon/.claude/plans/nifty-painting-rossum.md`。
