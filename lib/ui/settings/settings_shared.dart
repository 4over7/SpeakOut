import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/config_service.dart';
import '../../services/cloud_account_service.dart';
import '../../models/cloud_account.dart';
import '../../engine/core_engine.dart';
import '../theme.dart';
import '../widgets/settings_widgets.dart';

/// Shared key code → display name mapping
String mapKeyCodeToString(int keyCode) {
  if (keyCode == 63) return "FN";
  if (keyCode == 58) return "Left Option";
  if (keyCode == 61) return "Right Option";
  if (keyCode == 55) return "Left Command";
  if (keyCode == 54) return "Right Command";
  if (keyCode == 56) return "Left Shift";
  if (keyCode == 60) return "Right Shift";
  if (keyCode == 59) return "Left Control";
  if (keyCode == 62) return "Right Control";
  if (keyCode == 49) return "Space";
  if (keyCode == 36) return "Return";
  if (keyCode == 48) return "Tab";
  if (keyCode == 51) return "Delete";
  if (keyCode == 53) return "Escape";
  return "Key $keyCode";
}

/// Build display name for key + modifier combo
String comboKeyName(int keyCode, int modifiers) {
  final parts = <String>[];
  if (modifiers & 0x0008 != 0) parts.add('L.Cmd');
  if (modifiers & 0x0010 != 0) parts.add('R.Cmd');
  if (modifiers & 0x0001 != 0) parts.add('L.Ctrl');
  if (modifiers & 0x2000 != 0) parts.add('R.Ctrl');
  if (modifiers & 0x0020 != 0) parts.add('L.Opt');
  if (modifiers & 0x0040 != 0) parts.add('R.Opt');
  if (modifiers & 0x0002 != 0) parts.add('L.Shift');
  if (modifiers & 0x0004 != 0) parts.add('R.Shift');
  parts.add(mapKeyCodeToString(keyCode));
  return parts.join(' + ');
}

/// Strip the trigger key's own modifier from flags
int stripOwnModifier(int keyCode, int flags) {
  const ownMasks = {58: 0x0020, 61: 0x0040, 56: 0x0002, 60: 0x0004, 55: 0x0008, 54: 0x0010, 59: 0x0001, 62: 0x2000};
  return flags & ~(ownMasks[keyCode] ?? 0);
}

/// Collect all active hotkeys (from enabled features only) as {keyCode: featureName}
Map<int, String> getActiveHotkeys(BuildContext context, {String? excludeFeature}) {
  final config = ConfigService();
  final loc = AppLocalizations.of(context)!;
  final map = <int, String>{};
  if (config.pttKeyCode != 0 && excludeFeature != 'ptt') {
    map[config.pttKeyCode] = loc.pttMode;
  }
  if (config.toggleInputEnabled && config.toggleInputKeyCode != 0 && excludeFeature != 'toggleInput') {
    map[config.toggleInputKeyCode] = loc.toggleModeTip;
  }
  if (config.diaryEnabled && config.diaryKeyCode != 0 && excludeFeature != 'diary') {
    map[config.diaryKeyCode] = loc.diaryMode;
  }
  if (config.toggleDiaryEnabled && config.toggleDiaryKeyCode != 0 && excludeFeature != 'toggleDiary') {
    map[config.toggleDiaryKeyCode] = loc.diaryMode;
  }
  if (config.organizeEnabled && config.organizeKeyCode != 0 && excludeFeature != 'organize') {
    map[config.organizeKeyCode] = loc.organizeEnabled;
  }
  if (config.translateEnabled && config.translateKeyCode != 0 && excludeFeature != 'translate') {
    map[config.translateKeyCode] = loc.quickTranslate;
  }
  if (config.correctionEnabled && config.correctionKeyCode != 0 && excludeFeature != 'correction') {
    map[config.correctionKeyCode] = '纠错反馈';
  }
  if (config.aiReportEnabled && excludeFeature != 'aiReport') {
    for (final c in config.aiReportAllKeyCodes) {
      map[c] = 'AI 一键调试';
    }
  }
  return map;
}

/// Show error dialog
void showSettingsError(BuildContext context, String msg) {
  String cleanMsg = msg.replaceAll(RegExp(r'uri=https?:\/\/[^\s,]+'), '[URL]');
  if (cleanMsg.contains("ClientException") || cleanMsg.contains("SocketException")) {
    cleanMsg = "网络连接失败，请检查网络设置。\n\n详细信息: $cleanMsg";
  }
  if (cleanMsg.length > 300) cleanMsg = "${cleanMsg.substring(0, 300)}...";
  showMacosAlertDialog(
    context: context,
    builder: (_) => MacosAlertDialog(
      appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
      title: const Text("Error"),
      message: Text(cleanMsg),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context),
        child: const Text("OK"),
      ),
    ),
  );
}

/// Show info via engine status
void showSettingsInfo(String msg) {
  CoreEngine().updateStatus('ℹ️ $msg');
}

/// Shared dropdown builder
Widget buildDropdown(BuildContext context, {
  required String value,
  required Map<String, String> items,
  required Function(String?) onChanged,
}) {
  return Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: MacosTheme.of(context).canvasColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: MacosColors.separatorColor),
    ),
    child: MacosPopupButton<String>(
      value: value,
      items: items.entries.map((e) => MacosPopupMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    ),
  );
}

/// Shared key capture tile
Widget buildKeyCaptureTile(BuildContext context, String label, IconData icon, {
  required bool isCapturing,
  required String keyName,
  required VoidCallback onEdit,
  VoidCallback? onClear,
}) {
  final loc = AppLocalizations.of(context)!;
  final displayName = keyName.isEmpty ? loc.notSet : keyName;
  return SettingsTile(
    label: label,
    icon: icon,
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isCapturing ? AppTheme.getAccent(context) : MacosColors.systemGrayColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isCapturing ? loc.pressAnyKey : displayName,
            style: AppTheme.mono(context).copyWith(
              color: isCapturing ? Colors.white : (keyName.isEmpty ? MacosColors.systemGrayColor : null),
            ),
          ),
        ),
        const SizedBox(width: 8),
        MacosIconButton(
          icon: const MacosIcon(CupertinoIcons.pencil),
          onPressed: onEdit,
        ),
        if (onClear != null && keyName.isNotEmpty)
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.trash),
            onPressed: onClear,
          ),
      ],
    ),
  );
}

/// Check if any LLM API key is configured
String resolveLlmApiKey() {
  final llmAccounts = CloudAccountService().getAccountsWithCapability(CloudCapability.llm);
  if (llmAccounts.isNotEmpty) {
    final savedId = ConfigService().selectedLlmAccountId ?? '';
    final effectiveId = llmAccounts.any((a) => a.id == savedId) ? savedId : llmAccounts.first.id;
    final account = CloudAccountService().getAccountById(effectiveId);
    return account?.credentials['api_key'] ?? '';
  }
  return ConfigService().llmApiKey;
}

/// Shared action button for model download/activate/delete
Widget buildActionBtn(BuildContext context, {
  required bool isDownloaded, required bool isLoading, required bool isActive,
  required VoidCallback onDownload, required VoidCallback onDelete, required VoidCallback onActivate,
  double? progress, String? statusText, bool isOffline = false,
  String? modelUrl, VoidCallback? onImport,
}) {
  final loc = AppLocalizations.of(context)!;
  if (isLoading) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MacosColors.systemGrayColor.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getAccent(context)),
            ),
          ),
          const SizedBox(height: 4),
          Text(statusText ?? loc.preparing, style: AppTheme.caption(context)),
        ],
      ),
    );
  }
  if (!isDownloaded) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PushButton(
          controlSize: ControlSize.regular,
          color: AppTheme.getAccent(context),
          onPressed: onDownload,
          child: Text(loc.download, style: const TextStyle(color: Colors.white)),
        ),
        if (onImport != null) ...[
          const SizedBox(width: 6),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: onImport,
            child: Text(loc.importModel),
          ),
        ],
        if (modelUrl != null) ...[
          const SizedBox(width: 4),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.link, size: 16),
            onPressed: () => _launchUrl(modelUrl),
          ),
        ],
      ],
    );
  }
  return Row(
    children: [
      if (isActive)
        Row(children: [
          const Icon(CupertinoIcons.checkmark_alt_circle_fill, color: AppTheme.successColor),
          const SizedBox(width: 4),
          Text(loc.active, style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isOffline
                  ? Colors.orange.withValues(alpha: 0.15)
                  : AppTheme.getAccent(context).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isOffline ? loc.modeOffline : loc.modeStreaming,
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: isOffline ? Colors.orange : AppTheme.getAccent(context),
              ),
            ),
          ),
        ])
      else
        PushButton(
          controlSize: ControlSize.regular,
          color: MacosColors.controlColor.resolveFrom(context),
          onPressed: onActivate,
          child: Text(loc.activate),
        ),
      const SizedBox(width: 12),
      MacosIconButton(
        icon: const MacosIcon(CupertinoIcons.trash, color: AppTheme.errorColor, size: 18),
        onPressed: onDelete,
      ),
    ],
  );
}

void _launchUrl(String url) {
  // Import url_launcher at call site to avoid circular deps
  // This is a workaround — callers can import url_launcher directly
}

/// Shared API item builder
Widget buildApiItem(BuildContext context, String label, IconData icon, String? value, Function(String) onChanged, {bool isSecret = false, String? placeholder}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      MacosTextField(
        placeholder: placeholder ?? label,
        obscureText: isSecret,
        maxLines: 1,
        decoration: BoxDecoration(
          color: AppTheme.getInputBackground(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.getBorder(context)),
        ),
        prefix: Padding(padding: const EdgeInsets.only(left: 8), child: MacosIcon(icon, size: 14)),
        controller: TextEditingController(text: value),
        onChanged: onChanged,
      ),
    ],
  );
}
