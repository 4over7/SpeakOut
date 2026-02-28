# 设置页分类重组 (2026-02-28)

## 背景

v1.3.0 新增 Toggle 模式后，通用 tab 变得过于臃肿（6 个分组），而闪念笔记 tab 仅有 3 项设置。需要重新分类。

## 改动

### Tab 结构变更

| Tab | 改前 | 改后 |
|-----|------|------|
| 1 通用 | 语言 + 音频 + PTT + Toggle + ASR 去重 + AI 纠错 | 语言 + 音频 + AI 纠错 |
| 2 语音模型 | 不变 | 不变 |
| 3 闪念笔记 → **触发方式** | 启用 + 热键 + 保存目录 | 文本注入 + 闪念笔记 + 录音保护 |
| 4 关于 | 不变 | 不变 |

### Tab 3「触发方式」详细布局

```
┌─ 文本注入 ────────────────────────────────┐
│ 长按说话 (PTT)     [Left Option] ✏️       │
│ 单击切换 (Toggle)  [未设置]  ✏️  🗑️       │
└────────────────────────────────────────────┘

┌─ 闪念笔记 ────────────────────────────────┐
│ ☑ 启用                                    │
│ 长按说话 (PTT)     [Right Option] ✏️      │
│ 单击切换 (Toggle)  [未设置]  ✏️  🗑️       │
│ 保存目录           [SpeakOut_Notes] 📂    │
└────────────────────────────────────────────┘

┌─ 录音保护 ────────────────────────────────┐
│ 最大录音时长       [不限制 ▾]              │
│ ASR 去重           [☑]                    │
│ ⓘ 单击切换提示文字                         │
└────────────────────────────────────────────┘
```

## 代码变更

### 文件清单

| 文件 | 改动 |
|------|------|
| `lib/l10n/app_zh.arb` | +5 键 / -3 键 |
| `lib/l10n/app_en.arb` | +5 键 / -3 键 |
| `lib/l10n/generated/app_localizations*.dart` | 自动生成 |
| `lib/ui/settings_page.dart` | 重组 tab 内容，提取辅助方法 |

### i18n 键变更

新增:
- `tabTrigger`: "触发方式" / "Triggers"
- `pttMode`: "长按说话 (PTT)" / "Hold to Speak (PTT)"
- `toggleModeTip`: "单击切换 (Toggle)" / "Tap to Toggle"
- `textInjection`: "文本注入" / "Text Input"
- `recordingProtection`: "录音保护" / "Recording Protection"

移除:
- `toggleMode` → 被 `tabTrigger` 替代
- `toggleInput` → 被 `textInjection` 替代
- `toggleDiary` → 直接复用 `diaryMode`

### 代码重构

提取 `_buildKeyCaptureTile()` 辅助方法，统一 5 处快捷键编辑 UI 的重复代码：
- 文本注入 PTT
- 文本注入 Toggle
- 闪念笔记 PTT
- 闪念笔记 Toggle
- （原通用 tab 的 PTT 也已移入）

## 验证

- `flutter analyze` — 0 error
- `flutter test` — 134 tests passed
- 编译安装测试通过
