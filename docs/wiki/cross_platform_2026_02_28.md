# SpeakOut 跨平台扩展方案（务实版）

**日期**: 2026-02-28

## 实施进度

### Phase 0: Dart 层最小改动 — ✅ 已完成
- `audio_device_service.dart`: `NativeInput` → `NativeInputBase`
- `native_input_factory.dart`: 新增工厂方法
- `core_engine.dart`: 使用工厂方法 + 修类型
- `config_service.dart`: 条件化 `MacOsOptions`
- 验证: 0 errors, 134 tests passed

### Phase 1: Windows — ✅ Dart 层已完成，C++ 待目标平台编译验证
- `native_input_ffi.dart`: ★ 提取 FFI 共用基类（消除 ~400 行重复）
- `native_input.dart`: 精简为仅 macOS 路径查找（~60 行）
- `native_input_windows.dart`: Windows FFI 绑定（~60 行）
- `native_lib/windows/native_input.cpp`: Win32 API 实现（~550 行）
- `native_lib/windows/CMakeLists.txt`: 编译配置
- `main.dart`: 平台入口分发
- `lib/ui/windows/`: 4 个 fluent_ui 页面
- `overlay_controller.dart`: 非 macOS 平台 no-op
- `pubspec.yaml`: 添加 `fluent_ui: ^4.9.0`
- 验证: 0 errors, 134 tests passed

### Phase 2: Linux — 待实施
### Phase 3: 鸿蒙 — 独立项目

## 核心发现

`NativeInputBase` 已经是完整的 21 方法抽象接口，且只在 3 个文件中使用。不需要拆成 6 个新接口、不需要 Platform Abstraction Layer、不需要 Controller mixin。

## 方案

各平台的 C/C++ 原生库导出**相同的 21 个函数签名**，Dart FFI 层用工厂方法按平台加载不同的动态库。UI 各平台独立实现（macOS: macos_ui, Windows: fluent_ui, Linux: Material+adwaita）。

## 阶段

- **Phase 0** (1-2 天): Dart 层 4 个微调（工厂方法 + 类型修复 + 条件化 SecureStorage）
- **Phase 1** (4-6 周): Windows 原生库 `native_input.cpp` (Win32 API) + Windows UI (fluent_ui)
- **Phase 2** (3-4 周): Linux 原生库 `native_input.c` (X11/PulseAudio) + Linux UI (Material)
- **Phase 3**: 鸿蒙 ArkTS 独立仓库

详细方案见计划文件 `/Users/leon/.claude/plans/nifty-painting-rossum.md`。
