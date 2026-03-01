# Windows 真机测试指南

## 环境准备

### 1. 安装 Flutter SDK

```powershell
# 方式一：官方安装器 (推荐)
# 下载 https://docs.flutter.dev/get-started/install/windows/desktop

# 方式二：Chocolatey
choco install flutter

# 验证
flutter doctor
```

### 2. 安装 Visual Studio 2022

`flutter doctor` 会检查。需要安装以下工作负载：
- **使用 C++ 的桌面开发** (Desktop development with C++)
- 确保包含 MSVC v143 编译器 和 Windows 10/11 SDK

### 3. 安装 Git

```powershell
choco install git
# 或从 https://git-scm.com/download/win 安装
```

## 构建步骤

### 1. 克隆项目

```powershell
git clone https://github.com/4over7/SpeakOut.git
cd SpeakOut
```

### 2. 安装 Flutter 依赖

```powershell
flutter pub get
```

### 3. 编译原生库

```powershell
cd native_lib\windows
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
cd ..\..\..
```

编译完成后 `native_lib/native_input.dll` 应该存在。

### 4. 开发模式运行

```powershell
flutter run -d windows
```

### 5. Release 构建

```powershell
flutter build windows --release
```

输出在 `build\windows\x64\runner\Release\`，`native_input.dll` 会被自动拷贝到 exe 同级目录。

## 测试清单

### 基础功能

- [ ] 应用启动，显示 Fluent UI 首页
- [ ] 语音引擎初始化（Sherpa 模型下载/加载）
- [ ] 系统托盘图标显示

### 键盘监听

- [ ] PTT（按住说话）模式：按住快捷键 → 录音 → 松开 → 停止
- [ ] Toggle 模式：单击开始 → 单击停止
- [ ] 全局热键在其他应用窗口下仍有效

### 语音识别

- [ ] 麦克风权限正常获取
- [ ] 实时 partial 结果显示
- [ ] 最终识别结果正确
- [ ] 长句识别稳定

### 文本注入

- [ ] 识别结果正确注入到活动窗口
- [ ] 在记事本、浏览器、VS Code 等应用中测试
- [ ] 中文字符正确输入
- [ ] 标点符号正确

### 设置

- [ ] 快捷键更改生效
- [ ] ASR 引擎切换
- [ ] AI 纠错开关
- [ ] 语言切换（中/英/跟随系统）

### 音频设备

- [ ] 切换麦克风设备
- [ ] 蓝牙耳机连接/断开处理
- [ ] 设备热插拔检测

## Sherpa 模型

首次启动会自动下载 Sherpa-ONNX 模型。如果 GitHub 下载慢，可以手动导入：

1. 在设置页面找到模型管理
2. 点击「导入」按钮
3. 选择预先下载的 `.tar.bz2` 模型文件

## 常见问题

### `native_input.dll` 找不到

确保先执行了第 3 步编译原生库。开发模式下 DLL 路径查找顺序：
1. exe 同级目录
2. `native_lib/` 子目录
3. 当前工作目录 `/native_lib/`

### 缺少 Visual Studio 组件

```powershell
flutter doctor --verbose
```

检查输出中 Visual Studio 相关的提示。

### 键盘 Hook 无反应

Windows 的 `SetWindowsHookEx(WH_KEYBOARD_LL)` 需要消息循环。如果快捷键无效，检查是否有杀毒软件拦截。

### WASAPI 音频初始化失败

确保至少有一个可用的麦克风设备。在 Windows 设置 → 声音 → 输入 中确认。
