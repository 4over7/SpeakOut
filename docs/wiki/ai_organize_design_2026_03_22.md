# AI 梳理（Organize）功能设计方案

> 日期: 2026-03-22
> 状态: 方案设计，待确认

---

## 一、功能定义

**AI 梳理**：对用户选中的任意文字进行深度重组——理清逻辑、专业化表达、去除冗余——但不改变原意。

与现有"润色"的区别：

| | 润色（现有） | 梳理（新） |
|--|--|--|
| 目的 | 修 ASR 错别字、去语气词 | 重组逻辑结构、专业化表达 |
| 改动幅度 | 字词级 | 段落级，可能重排整段 |
| 触发方式 | 自动（每次语音输入后） | 手动（快捷键） |
| 输入来源 | 仅 SpeakOut 语音输入 | 任何 app 中选中的文字 |
| 速度要求 | <1s | 可以 3-5s |

---

## 二、交互流程

```
用户在任何 app 选中一段文字
  → 按梳理快捷键（默认：无，用户自行设置）
  → 悬浮窗显示「梳理中...」（青色/蓝绿色调，区分录音悬浮窗）
  → 后台：Cmd+C 获取选中文字 → LLM 梳理 → 光标移到选区末尾 → 换行 → 粘贴结果
  → 悬浮窗显示「✓ 已完成」后自动消失
```

**输出方式：追加在下一行**（不替换原文）
- 原文保留，用户可对比、取舍
- 不可逆操作风险为零

异常情况：
- **未选中文字**（剪贴板为空或无变化）→ 悬浮窗显示「未检测到选中文字」，2s 后消失
- **LLM 超时/失败** → 悬浮窗显示错误信息，原文不受影响
- **快捷键冲突** → 沿用现有冲突检测机制

---

## 三、设置 Tab

新增设置页 Tab「AI 梳理」，插入索引 3（闪念笔记之前）。

**Tab 结构调整**：
```
通用(0) | 工作模式(1) | 触发方式(2) | AI梳理(3) | 闪念笔记(4) | 云服务账户(5) | 关于(6)
```

**Tab 内容**：

```
┌─────────────────────────────────────────┐
│ AI 梳理                                  │
│                                         │
│ ┌─ 基本设置 ────────────────────────────┐ │
│ │ 启用 AI 梳理          [开关]          │ │
│ │ 快捷键               Cmd+Shift+L [编辑]│ │
│ └───────────────────────────────────────┘ │
│                                         │
│ ┌─ 功能说明 ────────────────────────────┐ │
│ │ 💡 选中任意文字后按快捷键，AI 将：     │ │
│ │   · 提取核心观点，按逻辑重新组织       │ │
│ │   · 用清晰专业的语言重新表达           │ │
│ │   · 保留原文含义，不添加不删减         │ │
│ │   · 未完成的想法会标注而非补全         │ │
│ └───────────────────────────────────────┘ │
│                                         │
│ ┌─ 梳理指令 ────────────────────────────┐ │
│ │ [多行文本框 — 可自定义 System Prompt]  │ │
│ │                        [恢复默认]     │ │
│ └───────────────────────────────────────┘ │
│                                         │
│ ┌─ LLM 服务 ───────────────────────────┐ │
│ │ ⓘ 使用「工作模式」中配置的 LLM 服务商  │ │
│ │                   [前往配置 →]        │ │
│ └───────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**设计决策**：
- LLM 配置复用工作模式 tab 中已配置的服务商/模型，不单独配置（避免用户维护两套 LLM 凭证）
- 快捷键默认不设置（值为 0），需用户主动配置，避免快捷键冲突
- 梳理指令（System Prompt）独立于润色 prompt，可单独自定义

---

## 四、技术实现

### 4.1 改动清单

| 层级 | 文件 | 改动 |
|------|------|------|
| **常量** | `lib/config/app_constants.dart` | 新增默认 prompt、超时常量 |
| **配置** | `lib/services/config_service.dart` | 新增 organize 相关配置项 |
| **原生** | `native_lib/native_input.m` | 新增 `copy_selection()` 函数 |
| **FFI** | `lib/ffi/native_input.dart` + `native_input_ffi.dart` | 绑定 `copy_selection` |
| **引擎** | `lib/engine/core_engine.dart` | `_handleKey` 增加梳理快捷键分支 |
| **LLM** | `lib/services/llm_service.dart` | 新增 `organizeText()` 方法 |
| **悬浮窗** | `lib/services/overlay_controller.dart` | 支持 `organizeMode` 显示 |
| **原生UI** | `macos/Runner/AppDelegate.swift` | 悬浮窗新配色（梳理=蓝绿） |
| **设置UI** | `lib/ui/settings_page.dart` | 新增 tab + `_buildOrganizeView()` |
| **i18n** | `lib/l10n/app_zh.arb` + `app_en.arb` | 新增 i18n key |

### 4.2 ConfigService 新增配置

```dart
// --- AI 梳理 ---
bool get organizeEnabled => _prefs?.getBool('organize_enabled') ?? false;
int get organizeKeyCode => _prefs?.getInt('organize_key_code') ?? 0; // 0=未设置
int get organizeModifiers => _prefs?.getInt('organize_modifiers') ?? 0;
String get organizeKeyName => _prefs?.getString('organize_key_name') ?? '';
String get organizePrompt => _prefs?.getString('organize_prompt') ?? AppConstants.kDefaultOrganizePrompt;

Future<void> setOrganizeEnabled(bool v) async => await _prefs?.setBool('organize_enabled', v);
Future<void> setOrganizeKey(int code, String name, {int modifiers = 0}) async { ... }
Future<void> clearOrganizeKey() async { ... }
Future<void> setOrganizePrompt(String v) async => await _prefs?.setString('organize_prompt', v);
```

### 4.3 AppConstants 新增

```dart
// AI 梳理
static const Duration kOrganizeTimeout = Duration(seconds: 15);
static const String kDefaultOrganizePrompt = '''你是一位专业的文字编辑。用户会给你一段口语化、可能杂乱无章的文字。请：

1. 提取所有核心观点和信息
2. 按逻辑关系重新组织结构
3. 用清晰、专业的书面语重新表达
4. 严格保留原文的含义和立场，不添加、不删减内容
5. 如果有未完成或不完整的想法，用「[待补充: ...]」标注，不要替用户补全

直接输出整理后的文字，不要输出任何解释或前缀。''';
```

### 4.4 native_input.m 新增

```c
/// 模拟任意按键（用于 → 取消选区、Return 换行等）
void press_key(int keyCode, int modifierFlags) {
    @autoreleasepool {
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventRef keyDown = CGEventCreateKeyboardEvent(source, (CGKeyCode)keyCode, true);
        CGEventRef keyUp   = CGEventCreateKeyboardEvent(source, (CGKeyCode)keyCode, false);
        if (modifierFlags) {
            CGEventSetFlags(keyDown, (CGEventFlags)modifierFlags);
            CGEventSetFlags(keyUp,   (CGEventFlags)modifierFlags);
        }
        CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
        CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
        CFRelease(keyDown);
        CFRelease(keyUp);
        CFRelease(source);
    }
}

/// 模拟 Cmd+C 复制选中文字到剪贴板
void copy_selection(void) {
    @autoreleasepool {
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 8, true);  // 8 = 'c'
        CGEventRef keyUp   = CGEventCreateKeyboardEvent(source, 8, false);
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventSetFlags(keyUp,   kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
        CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
        CFRelease(keyDown);
        CFRelease(keyUp);
        CFRelease(source);
        usleep(100000); // 100ms 等待剪贴板更新
    }
}
```

### 4.5 CoreEngine `_handleKey` 新增分支

在现有 step 3（独立 toggle keys）之后、step 4（纯 PTT/diary）之前插入：

```dart
// 5. AI 梳理快捷键（仅 keyDown，不涉及录音状态机）
final organizeCode = config.organizeKeyCode;
if (isDown && config.organizeEnabled && organizeCode != 0 &&
    matchKey(organizeCode, config.organizeModifiers)) {
  // 不进入录音状态机，直接触发文本处理
  _handleOrganize();
  return;
}
```

### 4.6 CoreEngine `_handleOrganize()` 核心流程

```dart
Future<void> _handleOrganize() async {
  if (_isOrganizing) return; // 防重入
  _isOrganizing = true;
  _log("[Organize] 开始梳理");

  try {
    // 1. 保存剪贴板 + 模拟 Cmd+C
    _nativeInput.injectClipboardBegin(); // 保存原剪贴板
    _nativeInput.copySelection();        // 模拟 Cmd+C
    await Future.delayed(const Duration(milliseconds: 150)); // 等剪贴板更新

    // 2. 读取剪贴板内容
    final clipData = await Clipboard.getData('text/plain');
    final selectedText = clipData?.text?.trim() ?? '';
    if (selectedText.isEmpty) {
      _log("[Organize] 未检测到选中文字");
      _overlay.showThenClear("未检测到选中文字", const Duration(seconds: 2));
      _nativeInput.injectClipboardEnd(); // 恢复剪贴板
      return;
    }
    _log("[Organize] 获取到 ${selectedText.length} 字");

    // 3. 显示悬浮窗
    _overlay.recordingMode = "organize";
    _overlay.updateText("梳理中...");
    await _overlay.show();

    // 4. 调用 LLM
    final result = await LLMService().organizeText(selectedText)
        .timeout(AppConstants.kOrganizeTimeout);

    if (result.isEmpty) {
      _overlay.showThenClear("梳理失败", const Duration(seconds: 2));
      _nativeInput.injectClipboardEnd();
      return;
    }

    // 5. 光标移到选区末尾 + 换行 + 粘贴结果（不替换原文）
    _nativeInput.pressKey(124, 0); // → 键，取消选区，光标到末尾
    await Future.delayed(const Duration(milliseconds: 50));
    _nativeInput.pressKey(36, 0);  // Return 键，换行
    await Future.delayed(const Duration(milliseconds: 50));
    _nativeInput.injectClipboardChunk('\n$result'); // 粘贴梳理结果
    await Future.delayed(const Duration(milliseconds: 100));
    _nativeInput.injectClipboardEnd(); // 恢复原剪贴板

    _overlay.showThenClear("✓", const Duration(seconds: 1));
    _log("[Organize] 完成，输出 ${result.length} 字");
  } catch (e) {
    _log("[Organize] 错误: $e");
    _overlay.showThenClear("梳理失败", const Duration(seconds: 3));
    _nativeInput.injectClipboardEnd(); // 确保恢复剪贴板
  } finally {
    _isOrganizing = false;
    await _overlay.hide();
  }
}
```

### 4.7 LLMService 新增方法

```dart
/// AI 梳理：深度重组文字结构（非流式，一次性返回）
Future<String> organizeText(String input) async {
  final prompt = ConfigService().organizePrompt;
  // 复用现有 _resolveLlmConfig() 获取 LLM 配置
  // 复用现有 _callLlmApi() 发送请求
  // 但使用 organizePrompt 而非 aiCorrectionPrompt
  ...
}
```

不做流式（打字机效果），因为梳理是"替换选中文字"，必须一次性完整替换，逐字替换会导致选区丢失。

### 4.8 悬浮窗配色

| 模式 | 颜色 | 用途 |
|------|------|------|
| ptt | 绿色→蓝色（流式） | 语音输入 |
| diary | 紫色 | 闪念笔记 |
| **organize** | **蓝绿色 (#1ABC9C)** | **AI 梳理** |

AppDelegate.swift 中新增 `organizeColor`，当 `recordingMode == "organize"` 时使用。

### 4.9 设置页 Tab 索引调整

```
通用(0) | 工作模式(1) | 触发方式(2) | AI梳理(3) | 闪念笔记(4) | 云服务账户(5) | 关于(6)
```

需要更新所有硬编码的 tab 索引引用：
- `_selectedIndex = 4` (跳转到云服务账户) → `_selectedIndex = 5`
- `MacosTabController(length: 6)` → `length: 7`
- 侧边栏 items 数组插入新项
- `IndexedStack` children 插入 `_buildOrganizeView(loc)`

### 4.10 i18n 新增 Key

```json
// app_zh.arb
"tabOrganize": "AI 梳理",
"organizeEnabled": "启用 AI 梳理",
"organizeHotkey": "梳理快捷键",
"organizeHotkeyHint": "选中文字后按此快捷键触发",
"organizePrompt": "梳理指令",
"organizeResetDefault": "恢复默认",
"organizeDesc": "选中任意文字后按快捷键，AI 将提取核心观点、重组逻辑结构、专业化表达，但不改变原意。",
"organizeNoText": "未检测到选中文字",
"organizeFailed": "梳理失败",
"organizeDone": "梳理完成",
"organizeLlmHint": "使用「工作模式」中配置的 LLM 服务商",
"organizeGoConfig": "前往配置 →"
```

---

## 五、边界情况

| 场景 | 处理 |
|------|------|
| 未选中文字 | 悬浮窗提示，不执行 |
| 选中文字超长（>5000字） | 截断并提示，或直接交给 LLM（受 max_tokens 限制） |
| 正在录音时按梳理键 | 忽略（_isOrganizing guard + 录音状态检查） |
| 正在梳理时再按梳理键 | 忽略（_isOrganizing guard） |
| LLM 未配置 | 悬浮窗提示「请先配置 LLM 服务」 |
| LLM 超时 | 15s 超时，悬浮窗显示失败，不替换原文 |
| 目标 app 为只读区域 | 换行和粘贴会被忽略，无副作用 |
| 梳理快捷键与其他快捷键冲突 | 沿用现有冲突检测逻辑，设置时警告 |

---

## 六、实现优先级

1. **P0**: ConfigService + AppConstants + native `copy_selection()` + FFI 绑定
2. **P1**: CoreEngine `_handleOrganize()` + LLMService `organizeText()`
3. **P2**: 悬浮窗 organize 模式 + AppDelegate 配色
4. **P3**: 设置页 tab + i18n
5. **P4**: 测试

---

## 七、测试计划

### 单元测试
- `organizeText()` prompt 构建正确性（Golden 测试）
- ConfigService organize 配置读写
- CoreEngine organize 快捷键匹配

### 手动测试
- [ ] 在 TextEdit 选中文字 → 快捷键 → 验证替换结果
- [ ] 在 WeChat 选中文字 → 快捷键 → 验证替换结果
- [ ] 未选中文字 → 快捷键 → 验证提示
- [ ] 正在录音时按梳理键 → 验证忽略
- [ ] LLM 未配置时按梳理键 → 验证提示
- [ ] 悬浮窗颜色为蓝绿色，非绿色/紫色
