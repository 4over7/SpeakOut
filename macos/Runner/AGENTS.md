# macos/Runner/ — macOS 平台集成

> Flutter 标准 macOS Runner + SpeakOut 自定义：AppDelegate（含录音浮窗 + Method Channel）、entitlements、Info.plist 权限声明。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md)
- 配套：[`../../native_lib/AGENTS.md`](../../native_lib/AGENTS.md) — 原生能力实现

## 文件清单

| 文件 | 职责 |
|---|---|
| `AppDelegate.swift` | **自定义重点**：MethodChannel `com.SpeakOut/overlay`（show/update/hide 录音浮窗 + pickDirectory/pickFile）+ 应用生命周期（保留 tray + Dock 重激活） |
| `MainFlutterWindow.swift` | Flutter window 标准包装，最小代码 |
| `Info.plist` | Bundle ID / 权限声明（`NSAccessibilityUsageDescription` / `NSMicrophoneUsageDescription` / `NSScreenCaptureUsageDescription` 等） |
| `DebugProfile.entitlements` / `Release.entitlements` | 调试 / 发布 entitlements（`com.apple.security.cs.disable-library-validation` 允许加载 dylib） |
| `AppStore.entitlements` | App Store 沙盒 entitlements（沙盒=true）|
| `Configs/`, `Base.lproj/`, `Resources/`, `Assets.xcassets/` | 标准 Xcode 资源目录（图标 / Info.plist 配置文件） |

## 关键设计决策

### 1. 录音浮窗在 Native 端而非 Flutter
浮窗用 `NSPanel`（borderless + nonactivatingPanel，不抢焦点），波形动画用 NSView + 定时器。**为什么不用 Flutter**：Flutter 主窗口被关闭后无 Flutter 渲染上下文，浮窗无法显示。NSPanel 独立于主窗口，Flutter 关了照常工作。

通信：Flutter 端 `OverlayController.show/update/hide` → MethodChannel → AppDelegate 的 handler。

### 2. Tray 模式（applicationShouldTerminateAfterLastWindowClosed = false）
关闭主窗口不退出，进 system tray。让用户始终能用快捷键。

**配套必须实现 `applicationShouldHandleReopen`**——否则用户点 Dock 图标无反应（v1.8.6 修复，commit `c2c45a7`）。

### 3. 实时音频电平驱动浮窗动画
AppDelegate `loadAudioLevelFunction()` 用 `dlopen` + `dlsym` 拿到原生 `get_audio_level` 函数指针，定时器 80ms 调用一次，把 0~1 电平驱动波形 bar 高度。**不通过 MethodChannel 传电平** —— 跨 isolate 60Hz 调用太重。

### 4. Mode-aware 浮窗配色
浮窗模式 `streaming / offline / diary / organize` 各自一种颜色（accent / 紫 / 蓝绿）。模式由 Flutter 端 `OverlayController` 通过 channel 传入。

### 5. 多屏幕动态定位
浮窗位置基于**鼠标当前屏幕**计算（`NSEvent.mouseLocation` + `NSScreen.screens`），不固定主屏。多显示器场景体验自然。

### 6. 文件选择走 Native NSOpenPanel
`pickDirectory` / `pickFile` 用 NSOpenPanel 而不是 Flutter file_picker 包。原因：NSOpenPanel 触发 macOS 沙盒授权弹窗，**让用户主动选目录后获得读写权限**——闪念笔记目录授权、模型导入文件读取都依赖此。

## 不要做什么

- ❌ **不要在 AppDelegate 里写业务逻辑** — 这层是 native ↔ Flutter 桥接，业务在 Dart 端
- ❌ **不要硬编码 Bundle ID** — 走 Info.plist 的占位符 + Flutter / Xcode 配置
- ❌ **不要在 entitlements 里乱加权限** — 每加一项 macOS 都会要求用户授权，影响首次体验。**只加真正需要的**
- ❌ **不要禁用 hardened runtime**（`com.apple.security.cs.allow-unsigned-executable-memory`）— 无法通过 Apple 公证
- ❌ **不要在 NSPanel 里用 Flutter widget** — NSPanel 是 AppKit，Flutter widget 渲染需要 FlutterViewController + 完整窗口

## 编译 + 签名

`flutter build macos --release` 自动调 Xcode build。签名脚本在 `scripts/create_styled_dmg.sh`：
- 递归签所有 framework / dylib（`--timestamp --options runtime`）
- 最后签 app bundle
- 公证（`xcrun notarytool submit ... --keychain-profile notarytool`）
- Stapler（`xcrun stapler staple`）

## 调试

- 浮窗不显示：在 AppDelegate 加 `NSLog("[Overlay] ...")`，从终端启动 SpeakOut 看输出
- 权限弹窗不弹：检查 Info.plist 的 `NS*UsageDescription` 字符串是否齐全（macOS 要求每种权限有 description 才能弹窗）
- entitlements 配错：`codesign -d --entitlements - /Applications/SpeakOut.app` 看实际 entitlements
