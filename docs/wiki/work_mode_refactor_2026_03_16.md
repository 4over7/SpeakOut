# 工作模式合并方案 — 设计文档

> 日期: 2026-03-16
> 目标: 将"语音模型"和"AI 润色"两个设置 tab 合并为一个"工作模式" tab

## 背景

当前设置页有两个独立 tab 配置"云端服务"：
- **语音模型 tab** — 选 Sherpa 离线 or 阿里云云端 ASR
- **AI 润色 tab** — 选 LLM 提供方 (DashScope/OpenAI/Claude/Ollama)

用户困惑：概念边界模糊，都是"用 AI 把语音变成准确文字"，两处都配 API key。

## 三种工作模式

| 模式 | ASR | 后处理 | 需要的 Key | 内部映射 |
|------|-----|--------|-----------|---------|
| **纯离线** | Sherpa 本地 | Vocab 替换(可选) | 无 | `asrEngineType='sherpa'`, `aiCorrectionEnabled=false` |
| **智能模式(推荐)** | Sherpa 本地 | LLM 纠错 + Vocab | LLM API key | `asrEngineType='sherpa'`, `aiCorrectionEnabled=true` |
| **云端识别** | 阿里云 | 直接输出 | 阿里云 3 个 key | `asrEngineType='aliyun'`, `aiCorrectionEnabled=false` |

## Tab 结构: 6→5

| 之前 | 之后 |
|------|------|
| 通用 | 通用 |
| 语音模型 | **工作模式** (合并) |
| 触发方式 | 触发方式 |
| 闪念笔记 | 闪念笔记 |
| AI 润色 | *(合并到工作模式)* |
| 关于 | 关于 |

## UI 布局

```
┌────────────────────────────────────────────┐
│ [选择工作模式]                               │
│                                             │
│ ○ 纯离线模式     🔒                         │
│   本地识别，完全离线，保护隐私                 │
│                                             │
│ ● 智能模式（推荐） ✨                        │
│   本地识别 + AI 润色，准确度最高              │
│                                             │
│ ○ 云端识别模式    ☁️                         │
│   阿里云高精度识别                            │
├────────────────────────────────────────────┤
│ [模式特定配置 — 根据选中模式动态显示]          │
│  智能模式: LLM 提供方、API Key、Model 等     │
│  云端模式: 阿里云 AccessKey 等               │
│  纯离线: 提示文字                            │
├────────────────────────────────────────────┤
│ ▸ 高级设置 (折叠)                            │
│   - 语音模型管理 (离线/智能模式)              │
│   - System Prompt (智能模式)                 │
│   - 专业词汇词典 (离线/智能模式)              │
│   - 打字机效果 (智能模式, Alpha)              │
├────────────────────────────────────────────┤
│ [底部固定保存栏 — 仅智能模式 + cloud LLM]     │
└────────────────────────────────────────────┘
```

## 实施步骤

### Phase A: 数据层 — ConfigService

**文件:** `lib/services/config_service.dart`

1. 新增 `workMode` getter/setter:
```dart
String get workMode => _prefs?.getString('work_mode') ?? _inferWorkMode();

Future<void> setWorkMode(String mode) async {
  await _prefs?.setString('work_mode', mode);
  switch (mode) {
    case 'offline':
      await setAsrEngineType('sherpa');
      await setAiCorrectionEnabled(false);
    case 'smart':
      await setAsrEngineType('sherpa');
      await setAiCorrectionEnabled(true);
    case 'cloud':
      await setAsrEngineType('aliyun');
      await setAiCorrectionEnabled(false);
  }
}

String _inferWorkMode() {
  if (asrEngineType == 'aliyun') return 'cloud';
  if (aiCorrectionEnabled) return 'smart';
  return 'offline';
}
```

2. 新增 `migrateToWorkMode()`:
```dart
Future<void> migrateToWorkMode() async {
  if (_prefs?.containsKey('work_mode') ?? false) return;
  await _prefs?.setString('work_mode', _inferWorkMode());
}
```

3. 保留旧的 `asrEngineType` 和 `aiCorrectionEnabled` getter/setter 不删除 — CoreEngine 仍然读取它们

### Phase B: 国际化

**文件:** `lib/l10n/app_zh.arb`, `lib/l10n/app_en.arb`

新增 key:
- `tabWorkMode` / "工作模式" / "Work Mode"
- `workModeOffline` / "纯离线模式" / "Offline Mode"
- `workModeOfflineDesc` / 描述
- `workModeSmart` / "智能模式（推荐）" / "Smart Mode (Recommended)"
- `workModeSmartDesc` / 描述
- `workModeCloud` / "云端识别模式" / "Cloud Recognition"
- `workModeCloudDesc` / 描述
- `workModeAdvanced` / "高级设置" / "Advanced Settings"

运行 `flutter gen-l10n`

### Phase C: UI 重构 — settings_page.dart

**核心改动:**

1. **Sidebar**: 删除 AI 润色项，语音模型改名为工作模式
   - 6 个 SidebarItem → 5 个
   - index 映射: 0通用, 1工作模式, 2触发, 3闪念, 4关于

2. **新增 `_buildWorkModeView()`**: 替代 `_buildModelsView()` + `_buildAiPolishView()`
   - 顶部: 三选一 Radio 卡片
   - 中部: 模式特定配置（复用现有 helper）
   - 底部: 高级设置折叠 + LLM 保存栏

3. **模式切换逻辑 `_switchWorkMode()`**:
   - 调用 `ConfigService().setWorkMode()`
   - 按需重初始化 ASR 引擎
   - 刷新 UI 状态

4. **复用的现有 helper**:
   - `_buildCloudPresetSection()` → 智能模式 LLM 配置
   - `_buildApiItem()` / `_buildApiItemWithController()` → API 字段
   - `_buildActionBtn()` → 模型下载按钮
   - `VocabSettingsView` → 词典设置
   - `_flushLlmControllers()` / `_syncLlmControllers()` → LLM 配置同步

5. **删除旧方法**: `_buildModelsView()`, `_buildAiPolishView()`

### Phase D: 启动迁移

在 app 启动时（ConfigService.init() 之后）调用 `migrateToWorkMode()`，确保旧用户配置自动迁移。

### Phase E: 测试

**单元测试** (`test/services/config_service_test.dart`):
- workMode 默认推断: sherpa+AI off → offline
- workMode 默认推断: sherpa+AI on → smart
- workMode 默认推断: aliyun → cloud
- setWorkMode 同步底层配置
- migrateToWorkMode 幂等性

**手动冒烟测试**:
- [ ] 新安装用户: 默认纯离线模式
- [ ] 旧用户升级: 配置自动迁移到对应模式
- [ ] 切换模式: LLM/阿里云配置区域正确显示/隐藏
- [ ] 高级设置展开: 模型管理和词典正常
- [ ] 智能模式录音: ASR → LLM 润色 → 输出
- [ ] 云端模式录音: 阿里云 ASR → 输出
- [ ] 纯离线模式录音: Sherpa → 直接输出

## 设计决策

### 为什么不改 CoreEngine？
CoreEngine 仍然读取 `asrEngineType` 和 `aiCorrectionEnabled`。workMode 是 UI 层抽象，通过 `setWorkMode()` 同步到底层配置。这样引擎层零风险。

### 为什么隐藏"阿里云 ASR + LLM 润色"组合？
阿里云 ASR 精度已很高，额外过 LLM 是浪费成本。三种模式覆盖了 99% 的实际使用场景。

### Vocab 词典放在哪？
高级设置折叠区域，离线和智能模式下都可见。离线模式用精确替换，智能模式注入 LLM prompt。

### 底部保存栏何时显示？
仅智能模式 + Cloud LLM 时显示（因为需要保存 API key 等敏感配置）。Ollama 本地 LLM 不需要保存栏。
