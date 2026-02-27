# 引导页 i18n 全量修复 + 下载超时保护 (2026-02-27)

## 问题

1. **中英文混杂** — 系统语言为英文时，引导页大量中文硬编码字符串未走 l10n 系统；设置页模型列表同样直接用 `model.name` / `model.description`（英文原始值），中文模式下显示英文。
2. **下载卡死** — `_downloadWithResume` 对连接阶段有 60s 超时，但 `await for (chunk in stream)` 数据流阶段无超时。GitHub Releases 在国内连接成功但传输极慢时，UI 永远停在"下载中"无法恢复。
3. **DMG 未签名** — `create_styled_dmg.sh` 无代码签名步骤，分发给他人后每次重装都需重新授权权限。

## 修复

### 1. 引导页 i18n (`lib/ui/onboarding_page.dart`)

**新增 `_l10n` getter**：
```dart
AppLocalizations get _l10n => AppLocalizations.of(context)!;
```

**替换全部 ~40 个硬编码字符串**，涵盖 5 个步骤：

| 步骤 | 示例硬编码 | 替换为 |
|------|-----------|--------|
| 欢迎 | `"欢迎使用子曰"` | `_l10n.onboardingWelcome` |
| 权限 | `"输入监控"`, `"授权"`, `"刷新状态"` | `_l10n.permInputMonitoring`, `_l10n.permGrant`, `_l10n.permRefreshStatus` |
| 模型选择 | `"自定义选择"`, `"返回"`, `"继续"` | `_l10n.onboardingCustomSelect`, `_l10n.onboardingBack`, `_l10n.onboardingContinue` |
| 下载 | `"准备下载..."`, `"下载标点模型..."`, `"下载完成!"` | `_l10n.onboardingPreparing`, `_l10n.onboardingDownloadPunct`, `_l10n.onboardingDownloadDone` |
| 完成 | `"设置完成!"`, `"按住说话"`, `"开始使用"` | `_l10n.onboardingDoneTitle`, `_l10n.onboardingHoldToSpeak`, `_l10n.onboardingBegin` |

**下载页模型名** — `selectedModel?.name` → `_localizedModelName(selectedModel, _l10n)`

### 2. 设置页模型 l10n (`lib/ui/settings_page.dart`)

新增 `_localizedModelName()` / `_localizedModelDesc()` 方法，通过 `model.id` switch 到对应 l10n 键：

```dart
String _localizedModelName(ModelInfo model, AppLocalizations loc) {
  switch (model.id) {
    case 'zipformer_bi_2023_02_20': return loc.modelZipformerName;
    case 'sensevoice_zh_en_int8': return loc.modelSenseVoiceName;
    // ... 共 8 个模型
  }
}
```

流式模型和离线模型列表中 `label: m.name` → `label: _localizedModelName(m, loc)`。

### 3. ARB 文件变更

**`app_en.arb`** — 新增 ~30 键，包含参数化：
- `onboardingBrowseModels`: `"Browse all {count} models, including dialects and large models"`
- `onboardingDownloading`: `"Downloading {name}"`
- `onboardingDownloadPunctPercent`: `"Downloading punctuation model... {percent}%"`

**`app_zh.arb`** — 对应中文翻译。

**修正模型大小描述**：Zipformer ~85MB→~490MB, Paraformer ~230MB→~1GB。

### 4. 下载超时 (`lib/engine/model_manager.dart`)

```dart
await for (final chunk in streamedResponse.stream.timeout(
  const Duration(seconds: 30),
  onTimeout: (sink) {
    sink.addError(Exception("数据传输超时 (30s 无数据)"));
    sink.close();
  },
)) { ... }
```

超时触发 Exception → catch 块捕获 → 进入重试循环（最多 5 次，间隔 2/4/6/8/10 秒）。

### 5. DMG 签名 (`scripts/create_styled_dmg.sh`)

在 staging 阶段打包进 DMG 之前签名：
```bash
codesign -f -s "$SIGN_IDENTITY" ".../libnative_input.dylib"
codesign -f --deep -s "$SIGN_IDENTITY" ".../SpeakOut.app"
```

## 注意事项

- `model_manager.dart` 中的 `ModelInfo.name` / `.description` 保留英文作为 fallback，UI 层通过 switch(model.id) 映射到 l10n
- 模型 ID 注意区分：流式模型用 `zipformer_bi_2023_02_20` / `paraformer_bi_zh_en`（非 `zipformer_bilingual`）
- Apple Development 证书签名的 app 在他人机器需 `xattr -cr` 解除隔离，但签名身份稳定可保留权限
