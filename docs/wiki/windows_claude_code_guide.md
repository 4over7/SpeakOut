# Windows Claude Code 开发指南

## 项目概况

**子曰 SpeakOut** — 跨平台离线优先 AI 语音输入系统。Flutter/Dart + 原生 C/C++ (FFI)。
仓库: `https://github.com/4over7/SpeakOut.git`

## 第一步：环境准备

### 1. 克隆项目

```powershell
git clone https://github.com/4over7/SpeakOut.git
cd SpeakOut
```

### 2. 安装 Flutter SDK

```powershell
# 如果还没装
winget install Flutter.Flutter
# 或从 https://docs.flutter.dev/get-started/install/windows/desktop 下载

# 验证
flutter doctor
```

### 3. 安装 Visual Studio 2022

`flutter doctor` 会检查。需要安装以下工作负载：
- **使用 C++ 的桌面开发** (Desktop development with C++)
- 确保包含 MSVC v143 编译器 和 Windows 10/11 SDK

### 4. 安装依赖

```powershell
flutter pub get
```

### 5. 编译原生库

```powershell
cd native_lib\windows
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
cd ..\..\..
```

编译完成后 `native_lib/native_input.dll` 应该存在。

### 6. 验证环境

```powershell
flutter analyze    # 应该 0 errors
flutter test       # 应该全部通过
```

### 7. 运行

```powershell
flutter run -d windows
```

---

## 项目架构速览

```
lib/
├── engine/          # 核心引擎：CoreEngine, ASR Provider, ModelManager
├── ffi/             # FFI 层：NativeInputBase (抽象) → NativeInputFFI (共用) → NativeInputWindows
├── services/        # 业务服务：ConfigService, AppService, LLMService, AudioDeviceService
├── ui/
│   ├── windows/     # ← Windows UI (fluent_ui) — 你主要改这里
│   │   ├── windows_app.dart         # 入口 Widget
│   │   ├── windows_onboarding.dart  # 首次引导（模型下载）
│   │   ├── windows_home.dart        # 主页
│   │   ├── windows_settings.dart    # 设置
│   │   └── windows_chat.dart        # 聊天
│   ├── linux/       # Linux UI (Material)
│   ├── chat/        # macOS 聊天页
│   ├── onboarding_page.dart   # macOS 引导页
│   └── settings_page.dart     # macOS 设置页
├── config/          # 常量定义
├── l10n/            # 国际化 (中/英)
└── main.dart        # 平台分发入口
native_lib/
├── native_input.m              # macOS 原生 (Objective-C)
└── windows/
    ├── native_input.cpp        # Windows 原生 (C++, Win32 API)
    └── CMakeLists.txt
```

### 核心数据流

```
快捷键触发 → native_input.cpp (WH_KEYBOARD_LL hook)
  → Ring Buffer 采集 16kHz PCM 音频 (WASAPI)
  → CoreEngine FFI 轮询 → VAD/AGC 处理
  → ASR (Sherpa-ONNX 离线 / 阿里云)
  → LLM 纠错 (可选)
  → 文本注入 (SendInput + KEYEVENTF_UNICODE)
```

### 关键文件

| 文件 | 说明 |
|------|------|
| `native_lib/windows/native_input.cpp` | Windows 原生库：键盘 Hook + WASAPI 音频 + SendInput |
| `lib/ffi/native_input_windows.dart` | Windows FFI 绑定 |
| `lib/ffi/native_input_ffi.dart` | 共用 FFI 基类（21 个 C 函数绑定） |
| `lib/engine/core_engine.dart` | 主编排器 |
| `lib/services/app_service.dart` | 应用初始化流程 |
| `lib/ui/windows/windows_app.dart` | Windows 入口（检查 isFirstLaunch → 引导/主页） |

---

## 当前已知问题（需要调试）

### 1. 键盘监听启动失败

启动后闪现「❌ 键盘监听失败（请检查权限）」。

- 对应代码：`lib/services/app_service.dart` 的 `_initEngine()`
- 底层：`native_input.cpp` 的 `start_keyboard_listener()` → `SetWindowsHookEx(WH_KEYBOARD_LL)`
- 可能原因：Hook 需要消息循环线程，检查 C++ 端线程是否正确启动

### 2. 首次引导流程刚添加

刚加了 `windows_onboarding.dart`，首次启动应显示引导页引导用户下载 Sherpa 模型。
如果引导页不出现或有问题，检查 `windows_app.dart` 中的 `isFirstLaunch` 逻辑。

---

## 开发规范

- 直接在 **main** 分支开发，改完 push
- macOS 开发者会 pull 同步，确保改动不破坏 macOS 端
- Windows UI 用 **fluent_ui** 包（Windows 11 风格）
- 提交信息用中文描述，格式：`fix: 描述` / `feat: 描述`
- 修改后先 `flutter analyze` 确认 0 errors

## 常用命令

```powershell
flutter analyze              # 静态分析
flutter test                 # 运行测试
flutter run -d windows       # 开发模式运行
flutter build windows --release  # Release 构建
```
