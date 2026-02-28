# 模型手动导入功能

**日期**: 2026-02-28
**版本**: v1.3.3

## 背景

部分用户在引导流程中无法成功下载模型（GitHub 访问受限、网络不稳定等）。需要提供备用方案让用户自行下载 `.tar.bz2` 文件后通过界面手动导入。

## 实现方案

### ModelManager 重构

将 `downloadAndExtractModel` 中解压+验证+激活逻辑提取为公共方法：

```dart
Future<String> _extractAndInstallModel(String id, File tarFile, {onStatus, onProgress})
```

两个入口共用：
- `downloadAndExtractModel` → 下载 → `_extractAndInstallModel`
- `importModel` → 复制文件到 Models 目录 → `_extractAndInstallModel`

`importModel` 先将用户选择的文件复制到 App Support/Models 目录（避免沙盒权限问题），再调用公共方法完成解压→tokens 验证→激活。

### 设置页 — 未下载状态 UI

`_buildActionBtn` 新增 `modelUrl` 和 `onImport` 可选参数，未下载状态改为：

```
[下载]  [导入]  🔗
```

- **下载** — 原有逻辑不变
- **导入** — 通过 `MethodChannel('com.SpeakOut/overlay').invokeMethod('pickFile')` 选择文件
- **🔗** — `url_launcher` 打开模型的 GitHub 直链

### 引导页 — 下载失败备用入口

下载失败 UI（原有「重试」+「跳过」）扩展为：

```
[重试]  [导入]  [跳过]
        手动下载 ↗
```

`_importSelectedModel` 方法：选择文件 → importModel → 激活 → 初始化 ASR。

### 原生层 — 文件选择器

`AppDelegate.swift` 新增 `pickFile` 方法：
- `NSOpenPanel` 配置为仅选择文件
- `allowedContentTypes` 过滤 `.bz2`
- 返回文件路径字符串

## 文件变更

| 文件 | 改动 |
|------|------|
| `lib/engine/model_manager.dart` | 提取 `_extractAndInstallModel`，新增 `importModel` |
| `lib/ui/settings_page.dart` | `_buildActionBtn` 增加导入+链接；新增 `_importModel` |
| `lib/ui/onboarding_page.dart` | 下载失败 UI 增加导入+手动下载；新增 `_importSelectedModel` |
| `macos/Runner/AppDelegate.swift` | 新增 `pickFile` (NSOpenPanel) |
| `lib/l10n/app_zh.arb` | +4 i18n 键 |
| `lib/l10n/app_en.arb` | +4 i18n 键 |

## 验证

- `flutter analyze` — 0 错误
- `flutter test` — 134 测试全部通过
- 编译通过，DMG 打包成功
