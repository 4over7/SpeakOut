# Toggle 模式实现 (2026-02-28)

## 背景

用户反馈长时间说话时一直按住按键不方便（走来走去的场景）。新增 Toggle（单击切换）模式：单击开始录音，再次单击结束录音并自动输入文字。

## 设计决策

### 共用键 vs 独立键

Toggle 使用独立快捷键，但允许与 PTT 共用同一个键。共用时用时间阈值区分：
- 按下后 < 1s 释放 → Toggle（单击切换，录音继续）
- 按下后 ≥ 1s 释放 → PTT（长按说话，释放停止）

阈值固定为 `AppConstants.kToggleThresholdMs = 1000`。

### 双 Toggle 键

两个 Toggle 快捷键独立配置：
- **Toggle 文本注入** — 对应 `RecordingMode.ptt`
- **Toggle 闪念笔记** — 对应 `RecordingMode.diary`

### 最大录音时长

可选保护机制，防止忘记关闭。设为 0 表示不限时。可选值：1/3/5/10 分钟。

## 文件变更

| 文件 | 改动 |
|------|------|
| `lib/config/app_constants.dart` | +6 常量：默认键码/键名、最大时长、阈值 |
| `lib/services/config_service.dart` | +30 行：Toggle Input/Diary getter/setter/clear、toggleMaxDuration |
| `lib/engine/core_engine.dart` | +146 行：Toggle 状态机、共用键判定、最大时长定时器 |
| `lib/ui/settings_page.dart` | +164 行：Toggle 设置 UI（快捷键编辑/清除、时长下拉、提示） |
| `lib/l10n/app_zh.arb` + `app_en.arb` | +8 个 i18n 键 |

## 核心逻辑：`_handleKey()` 优先级

```
1. Toggle 正在录音 + Toggle 键 keyDown → stopRecording()
2. 共用键（Toggle 键 == PTT/Diary 键）→ _handleSharedKey()
3. 独立 Toggle 键 → _handleToggleKey()
4. 纯 PTT/Diary 键 → _handleModeKey()（不变）
```

### `_handleSharedKey()` 时间阈值

```
keyDown → 立即 startRecording()，记录 _keyDownTime
keyUp   → holdMs = now - _keyDownTime
           < 1000ms → Toggle（录音继续，启动 maxTimer）
           ≥ 1000ms → PTT（stopRecording）
```

关键点：
- 录音零延迟启动（keyDown 即开始），不等释放后再判断
- Toggle 模式取消看门狗（`!_isToggleMode` 条件）
- Toggle 模式启动最大时长定时器

### `_handleToggleKey()` 独立键

仅响应 keyDown。idle → start，recording → stop（在 `_handleKey` 开头处理）。

## 状态管理

新增字段：
```dart
bool _isToggleMode = false;        // 当前录音是否为 Toggle 触发
Timer? _toggleMaxTimer;            // 最大录音时长定时器
DateTime? _keyDownTime;            // 共用键按下时间戳
```

清理点：
- `stopRecording()` 开头
- `_cleanupRecordingState()`
- `dispose()`

## 配置存储

| SharedPreferences Key | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `toggle_input_key_code` | int | 0 | 0 = 禁用 |
| `toggle_input_key_name` | String | "" | 显示名称 |
| `toggle_diary_key_code` | int | 0 | 0 = 禁用 |
| `toggle_diary_key_name` | String | "" | 显示名称 |
| `toggle_max_duration` | int | 0 | 秒，0 = 不限时 |

## 设置页 UI

在「触发按键 (PTT)」下方新增「Toggle 模式」设置组：
- 文本注入快捷键：显示键名 / 编辑 ✏️ / 清除 🗑️
- 闪念笔记快捷键：同上
- 最大录音时长：MacosPopupButton 下拉
- 提示信息：ⓘ 图标 + 说明文字

## 测试验证

- `flutter analyze` — 0 issues
- `flutter test` — 134 tests passed
- 手动场景覆盖：纯 PTT / 独立 Toggle / 共用键短按 / 共用键长按 / 最大时长保护

## FN/Globe 键双事件去重 (v1.3.2)

macOS 26+ 的 FN/Globe 键同时产生两种事件：
- `FlagsChanged` (keyCode=63) — 传统修饰键事件
- `KeyDown/KeyUp` (keyCode=179) — macOS 26 新增

**问题**：到达顺序不固定。若 FlagsChanged 先到并启动 Toggle 录音，随后到达的 KeyDown 179 会被 Toggle stop 逻辑误判为"第二次点击"而立即停止。

**修复**：原生层双向时间戳去重 (`native_input.m`)：
- `lastGlobe179Time` — 179 事件记录时间戳，100ms 内到达的 63 被抑制
- `lastFn63Time` — 63 事件记录时间戳，100ms 内到达的 179 被抑制
- 先到者赢，后到者静默丢弃

Dart 层额外守卫 (`core_engine.dart`):
- Toggle 模式下，`_handleKey` 第 4 步 PTT/diary keyUp 被 `_isToggleMode && !isDown` 拦截
