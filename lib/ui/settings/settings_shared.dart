import 'dart:async';
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

/// 捕获一个热键按键（支持组合键）
///
/// 核心策略：由于按组合键时用户总是先按修饰键再按主键，
/// 直接捕获第一个 keyDown 事件会错把修饰键单独记成热键。
///
/// 解决：
/// - 第一个事件是**非修饰键**（例如 K、F1、Space）→ 立即提交（可能带 modifier flag）
/// - 第一个事件是**修饰键**（Cmd/Option/Shift/Ctrl）→ 延迟 400ms；
///   - 400ms 内有后续非修饰键 → 提交后者（组合键）
///   - 400ms 内无后续 → 提交这个裸修饰键
///
/// Fn（keyCode 63）不在 `ownModifierMask` 中，视为普通键立即提交。
class HotkeyCapturer {
  final Stream<(int, int)> keyStream;
  final void Function(int keyCode, int modifierFlags) onCaptured;
  final VoidCallback onTimeout;
  final Duration timeout;
  final Duration modifierDebounce;

  StreamSubscription<(int, int)>? _sub;
  Timer? _debounceTimer;
  Timer? _timeoutTimer;
  (int, int)? _pendingModifier;
  bool _completed = false;

  HotkeyCapturer({
    required this.keyStream,
    required this.onCaptured,
    required this.onTimeout,
    this.timeout = const Duration(seconds: 15),
    this.modifierDebounce = const Duration(milliseconds: 400),
  });

  void start() {
    _sub = keyStream.listen(_handle);
    _timeoutTimer = Timer(timeout, () {
      if (!_completed) {
        _completed = true;
        _cleanup();
        onTimeout();
      }
    });
  }

  void _handle((int, int) event) {
    if (_completed) return;
    final (keyCode, mods) = event;
    final isModifier = CoreEngine.ownModifierMask(keyCode) != 0;

    if (!isModifier) {
      // 非修饰键 → 立即提交（即使之前有 pending modifier，非修饰键的事件已经包含正确的 modifier flags）
      _complete(keyCode, mods);
      return;
    }

    // 修饰键 → 暂存，等待后续非修饰键
    _pendingModifier = (keyCode, mods);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(modifierDebounce, () {
      if (!_completed && _pendingModifier != null) {
        final (kc, mf) = _pendingModifier!;
        _complete(kc, mf);
      }
    });
  }

  void _complete(int keyCode, int mods) {
    _completed = true;
    _cleanup();
    onCaptured(keyCode, mods);
  }

  void _cleanup() {
    _sub?.cancel();
    _sub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _pendingModifier = null;
  }

  /// 外部主动取消（例如用户点了别处）
  void cancel() {
    if (_completed) return;
    _completed = true;
    _cleanup();
  }
}

/// Shared key code → display name mapping
String mapKeyCodeToString(int keyCode) {
  // Modifier keys
  if (keyCode == 63) return "FN";
  if (keyCode == 58) return "Left Option";
  if (keyCode == 61) return "Right Option";
  if (keyCode == 55) return "Left Command";
  if (keyCode == 54) return "Right Command";
  if (keyCode == 56) return "Left Shift";
  if (keyCode == 60) return "Right Shift";
  if (keyCode == 59) return "Left Control";
  if (keyCode == 62) return "Right Control";
  // Whitespace / control
  if (keyCode == 49) return "Space";
  if (keyCode == 36) return "Return";
  if (keyCode == 48) return "Tab";
  if (keyCode == 51) return "Delete";
  if (keyCode == 53) return "Escape";
  if (keyCode == 117) return "Forward Delete";
  // Arrow keys
  if (keyCode == 123) return "←";
  if (keyCode == 124) return "→";
  if (keyCode == 125) return "↓";
  if (keyCode == 126) return "↑";
  // Navigation
  if (keyCode == 114) return "Help";
  if (keyCode == 115) return "Home";
  if (keyCode == 116) return "Page Up";
  if (keyCode == 119) return "End";
  if (keyCode == 121) return "Page Down";
  // Function keys F1-F20
  const fnKeys = {122:'F1', 120:'F2', 99:'F3', 118:'F4', 96:'F5', 97:'F6',
    98:'F7', 100:'F8', 101:'F9', 109:'F10', 103:'F11', 111:'F12',
    105:'F13', 107:'F14', 113:'F15', 106:'F16', 64:'F17', 79:'F18',
    80:'F19', 90:'F20'};
  if (fnKeys.containsKey(keyCode)) return fnKeys[keyCode]!;
  // Letters (US QWERTY layout)
  const letters = {0:'A', 11:'B', 8:'C', 2:'D', 14:'E', 3:'F', 5:'G', 4:'H',
    34:'I', 38:'J', 40:'K', 37:'L', 46:'M', 45:'N', 31:'O', 35:'P',
    12:'Q', 15:'R', 1:'S', 17:'T', 32:'U', 9:'V', 13:'W', 7:'X', 16:'Y', 6:'Z'};
  if (letters.containsKey(keyCode)) return letters[keyCode]!;
  // Digits (top row, not numpad)
  const digits = {29:'0', 18:'1', 19:'2', 20:'3', 21:'4', 23:'5',
    22:'6', 26:'7', 28:'8', 25:'9'};
  if (digits.containsKey(keyCode)) return digits[keyCode]!;
  // Numpad
  const numpad = {82:'Keypad 0', 83:'Keypad 1', 84:'Keypad 2', 85:'Keypad 3',
    86:'Keypad 4', 87:'Keypad 5', 88:'Keypad 6', 89:'Keypad 7',
    91:'Keypad 8', 92:'Keypad 9', 65:'Keypad .', 67:'Keypad *',
    69:'Keypad +', 71:'Keypad Clear', 75:'Keypad /', 76:'Keypad Enter',
    78:'Keypad -', 81:'Keypad ='};
  if (numpad.containsKey(keyCode)) return numpad[keyCode]!;
  // Punctuation
  const punct = {27:'-', 24:'=', 33:'[', 30:']', 41:';', 39:'\'',
    43:',', 47:'.', 44:'/', 42:'\\', 50:'`'};
  if (punct.containsKey(keyCode)) return punct[keyCode]!;
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

/// 统一的热键徽章：点击进入捕获态，未设置/已捕获时无删除按钮，
/// 已设置时旁边带一个小 × 按钮可清除当前键
///
/// 用户场景：忘记自己设的是什么键；某个功能暂时不想用某个热键
Widget hotkeyBadge(
  BuildContext context,
  String keyName, {
  bool isCapturing = false,
  VoidCallback? onTap,
  VoidCallback? onClear,
}) {
  final loc = AppLocalizations.of(context)!;
  final display = isCapturing
      ? loc.pressAnyKey
      : (keyName.isEmpty ? loc.notSet : keyName);
  final badge = GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCapturing
            ? AppTheme.getAccent(context)
            : MacosColors.systemGrayColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        display,
        style: AppTheme.mono(context).copyWith(
          fontSize: 11,
          color: isCapturing
              ? Colors.white
              : (keyName.isEmpty ? MacosColors.systemGrayColor : null),
        ),
      ),
    ),
  );
  // 只在已设置且提供了 onClear 时显示删除按钮
  if (onClear != null && keyName.isNotEmpty && !isCapturing) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 4),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onClear,
            child: Tooltip(
              message: '清除快捷键',
              child: Icon(CupertinoIcons.clear_circled,
                  size: 14, color: MacosColors.systemGrayColor),
            ),
          ),
        ),
      ],
    );
  }
  return badge;
}

/// Hotkey identity: (keyCode, modifiers)
typedef HotkeyId = (int keyCode, int modifiers);

/// Check if a new hotkey conflicts with any active hotkey.
/// Returns the conflicting feature name, or null if no conflict.
///
/// Mirrors runtime `_modifiersMatch` semantics (exact match for non-zero modifiers):
/// - requiredFlags == 0 (bare key) matches ANY modifier combo at runtime,
///   so bare keys conflict with everything on the same keyCode.
/// - requiredFlags != 0 requires EXACT modifier match at runtime,
///   so Cmd+K and Option+K are independent; Cmd+K and Cmd+Shift+K are also independent.
String? findHotkeyConflict(Map<HotkeyId, String> activeKeys, HotkeyId candidate) {
  for (final entry in activeKeys.entries) {
    final (existingKey, existingMods) = entry.key;
    final (candidateKey, candidateMods) = candidate;
    if (existingKey != candidateKey) continue;
    // Same keyCode — check modifier overlap per runtime semantics:
    // Bare key (0) overlaps with everything; non-zero only conflicts on exact match.
    if (existingMods == candidateMods || existingMods == 0 || candidateMods == 0) {
      return entry.value;
    }
  }
  return null;
}

/// Collect all active hotkeys as {(keyCode, modifiers): featureName}
Map<HotkeyId, String> getActiveHotkeys(BuildContext context, {String? excludeFeature}) {
  final config = ConfigService();
  final loc = AppLocalizations.of(context)!;
  final map = <HotkeyId, String>{};
  if (config.pttKeyCode != 0 && excludeFeature != 'ptt') {
    map[(config.pttKeyCode, config.pttModifiers)] = loc.pttMode;
  }
  if (config.toggleInputEnabled && config.toggleInputKeyCode != 0 && excludeFeature != 'toggleInput') {
    map[(config.toggleInputKeyCode, config.toggleInputModifiers)] = loc.toggleModeTip;
  }
  if (config.diaryEnabled && config.diaryKeyCode != 0 && excludeFeature != 'diary') {
    map[(config.diaryKeyCode, config.diaryModifiers)] = loc.diaryMode;
  }
  // toggleDiary 仅在整个闪念笔记功能启用时才生效（与运行时 core_engine 逻辑对齐）
  if (config.diaryEnabled && config.toggleDiaryEnabled && config.toggleDiaryKeyCode != 0 && excludeFeature != 'toggleDiary') {
    map[(config.toggleDiaryKeyCode, config.toggleDiaryModifiers)] = loc.diaryMode;
  }
  if (config.organizeEnabled && config.organizeKeyCode != 0 && excludeFeature != 'organize') {
    map[(config.organizeKeyCode, config.organizeModifiers)] = loc.organizeEnabled;
  }
  if (config.translateEnabled && config.translateKeyCode != 0 && excludeFeature != 'translate') {
    map[(config.translateKeyCode, config.translateModifiers)] = loc.quickTranslate;
  }
  if (config.correctionEnabled && config.correctionKeyCode != 0 && excludeFeature != 'correction') {
    map[(config.correctionKeyCode, config.correctionModifiers)] = '纠错反馈';
  }
  if (config.aiReportEnabled && config.aiReportBaseKeyCode != 0 && excludeFeature != 'aiReport') {
    map[(config.aiReportBaseKeyCode, 0)] = 'AI 一键调试';
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
