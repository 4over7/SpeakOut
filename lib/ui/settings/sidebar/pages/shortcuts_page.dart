import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../../config/app_constants.dart';
import '../../../../engine/core_engine.dart';
import '../../../../services/config_service.dart';
import '../../../theme.dart';
import '../../../widgets/settings_widgets.dart';
import '../../settings_shared.dart';
import '../hotkey_recorder_modal.dart';

/// v1.8 Sidebar - 快捷键页
class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  String _toggleInputKeyName = '';
  int _toggleMaxDuration = 0;

  @override
  void initState() {
    super.initState();
    final config = ConfigService();
    _currentKeyCode = config.pttKeyCode;
    _currentKeyName = config.pttKeyName;
    _toggleInputKeyName = config.toggleInputKeyName;
    _toggleMaxDuration = config.toggleMaxDuration;
    CoreEngine().pttKeyCode = _currentKeyCode;
  }

  Future<void> _recordHotkey(String target) async {
    final loc = AppLocalizations.of(context)!;
    String title;
    String subtitle;
    switch (target) {
      case 'shared':
        title = loc.shortcutsRecordKey;
        subtitle = loc.shortcutsSharedHint;
      case 'ptt':
        title = loc.shortcutsPttTitle;
        subtitle = loc.shortcutsPttHint;
      case 'toggleInput':
        title = loc.shortcutsToggleTitle;
        subtitle = loc.shortcutsToggleHint;
      default:
        title = loc.hotkeyModalTitle;
        subtitle = loc.hotkeyModalSubtitle;
    }

    final result = await showHotkeyRecorder(context, title: title, subtitle: subtitle);
    if (result == null || !mounted) return;

    // 冲突检查
    final config = ConfigService();
    final excludeFeature = target == 'toggleInput' ? 'toggleInput' : 'ptt';
    final activeKeys = getActiveHotkeys(context, excludeFeature: excludeFeature);
    if (target == 'shared' || target == 'ptt') {
      activeKeys.remove((config.toggleInputKeyCode, config.toggleInputModifiers));
    }
    if (target == 'shared' || target == 'toggleInput') {
      activeKeys.remove((config.pttKeyCode, config.pttModifiers));
    }
    final conflictWith = findHotkeyConflict(activeKeys, (result.keyCode, result.modifiers));
    if (conflictWith != null) {
      if (!mounted) return;
      await showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: Colors.orange),
          title: Text(loc.hotkeyInUseTitle(result.displayName, conflictWith), style: const TextStyle(fontWeight: FontWeight.bold)),
          message: Text(loc.hotkeyInUseMessage),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: Text(loc.hotkeyInUseOk),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
      return;
    }

    // 保存
    switch (target) {
      case 'shared':
        await config.setPttKey(result.keyCode, result.displayName, modifiers: result.modifiers);
        await config.setToggleInputKey(result.keyCode, result.displayName, modifiers: result.modifiers);
        CoreEngine().pttKeyCode = result.keyCode;
        setState(() {
          _currentKeyCode = result.keyCode;
          _currentKeyName = result.displayName;
          _toggleInputKeyName = result.displayName;
        });
      case 'toggleInput':
        await config.setToggleInputKey(result.keyCode, result.displayName, modifiers: result.modifiers);
        setState(() => _toggleInputKeyName = result.displayName);
      default:
        await config.setPttKey(result.keyCode, result.displayName, modifiers: result.modifiers);
        CoreEngine().pttKeyCode = result.keyCode;
        setState(() {
          _currentKeyCode = result.keyCode;
          _currentKeyName = result.displayName;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final advanced = ConfigService().showAdvanced;

    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        SettingsCard(
          title: advanced ? loc.shortcutsSplitTitle : loc.shortcutsRecordKey,
          titleIcon: CupertinoIcons.mic,
          accentColor: AppTheme.getAccent(context),
          children: [
            if (advanced) ...[
              _row(
                loc.shortcutsPttTitle,
                loc.shortcutsPttHint,
                hotkeyBadge(context, _currentKeyName, onTap: () => _recordHotkey('ptt')),
              ),
              _divider(),
              _row(
                loc.shortcutsToggleTitle,
                loc.shortcutsToggleHint,
                hotkeyBadge(
                  context,
                  _toggleInputKeyName,
                  onTap: () => _recordHotkey('toggleInput'),
                  onClear: _toggleInputKeyName.isEmpty
                      ? null
                      : () async {
                          await ConfigService().clearToggleInputKey();
                          setState(() => _toggleInputKeyName = '');
                        },
                ),
              ),
            ] else
              _row(
                loc.shortcutsRecordKey,
                loc.shortcutsSharedHint,
                hotkeyBadge(context, _currentKeyName, onTap: () => _recordHotkey('shared')),
              ),
            _divider(),
            _row(
              loc.toggleMaxDuration,
              'Toggle',
              MacosPopupButton<int>(
                value: _toggleMaxDuration,
                items: [
                  MacosPopupMenuItem(value: 0, child: Text(loc.toggleMaxNone)),
                  MacosPopupMenuItem(value: 60, child: Text(loc.toggleMaxMin(1))),
                  MacosPopupMenuItem(value: 180, child: Text(loc.toggleMaxMin(3))),
                  MacosPopupMenuItem(value: 300, child: Text(loc.toggleMaxMin(5))),
                  MacosPopupMenuItem(value: 600, child: Text(loc.toggleMaxMin(10))),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    await ConfigService().setToggleMaxDuration(v);
                    setState(() => _toggleMaxDuration = v);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Tip(
          icon: CupertinoIcons.lightbulb,
          text: loc.shortcutsTip,
        ),
      ],
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 1,
        color: AppTheme.getBorder(context),
      ),
    );
  }

  Widget _row(String label, String hint, Widget trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacosColors.systemYellowColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacosColors.systemYellowColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MacosIcon(icon, size: 14, color: MacosColors.systemYellowColor.darkColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.getTextSecondary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
