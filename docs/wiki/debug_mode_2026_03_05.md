# 调试模式与日志开关

**日期**：2026-03-05
**Commit**：674022d

---

## 背景

原代码中存在 85 处 `debugPrint` 调用和 C 层 `log_to_file()` 始终写文件，在 release 包中造成不必要的性能开销，且日志文件无限增长（实测达 17MB+）。需要一个统一的开关：开发者测试时打开，正式发布永远关闭。

---

## 设计

```
AppConstants.kVerboseLogging = false   ← 代码层默认，永不提交为 true
        ↓
ConfigService.verboseLogging           ← 运行时存 SharedPreferences
        ↓
AppLog.enabled                         ← Dart 日志开关
AppService.applyVerboseLogging()       ← 同步到 C 层
        ↓
set_debug_logging(1/0)                 ← C 层原子变量，控制 log_to_file()
set_log_directory(path)                ← C 层日志目录（默认 ~/Downloads）
```

---

## 新增文件

### `lib/config/app_log.dart`

统一日志工具，替代所有 `debugPrint`：

```dart
AppLog.d('[MyService] something happened');
```

`AppLog.enabled` 为 `false` 时调用完全无开销（直接 return）。

---

## 修改文件

| 文件 | 改动 |
|------|------|
| `lib/config/app_constants.dart` | 新增 `kVerboseLogging = false` |
| `lib/config/app_log.dart` | 新增，统一日志入口 |
| `lib/services/config_service.dart` | 新增 `verboseLogging` / `logDirectory` 存取 |
| `lib/services/app_service.dart` | 新增 `applyVerboseLogging()`，启动时同步开关 |
| `lib/engine/core_engine.dart` | 暴露 `nativeInput` getter |
| `lib/ffi/native_input_base.dart` | 新增 `setDebugLogging()` / `setLogDirectory()` 抽象方法 |
| `lib/ffi/native_input_ffi.dart` | 对应 FFI 绑定实现 |
| `lib/ui/settings_page.dart` | 新增"开发者"区块 UI |
| `native_lib/native_input.m` | `log_to_file()` 受原子变量控制；新增 `set_log_directory()` |
| 18 个 Dart 文件 | `debugPrint` → `AppLog.d` 批量替换 |

---

## 设置页 UI

设置页 → 通用 → 最底部新增"开发者"区块：

- **详细日志**（MacosSwitch）：打开后 Dart + C 层日志全部生效
- **日志输出目录**：文件夹选择器，默认 `~/Downloads`，可改可重置；日志文件名固定为 `speakout_native.log`

切换开关后立即生效，无需重启。

---

## 发布默认行为

新用户安装后：
- 无任何 Dart 日志输出
- 不生成 `speakout_native.log` 文件
- `AppConstants.kVerboseLogging = false` 是代码层保障，即使 SharedPreferences 损坏也不会误开
