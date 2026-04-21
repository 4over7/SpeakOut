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
    String title;
    String subtitle;
    switch (target) {
      case 'shared':
        title = '录制录音键';
        subtitle = '短按 = 切换录音，长按 = 说话松开停（共享键）';
      case 'ptt':
        title = '录制 PTT 键';
        subtitle = '长按该键录音，松开停止';
      case 'toggleInput':
        title = '录制 Toggle 键';
        subtitle = '点一下开录、再点一下停';
      default:
        title = '录制快捷键';
        subtitle = '请按下您想要设置的按键';
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
          title: Text('${result.displayName} 已被「$conflictWith」使用', style: const TextStyle(fontWeight: FontWeight.bold)),
          message: const Text('该按键已被占用，请选择其他按键。'),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: const Text('好的'),
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
        advanced ? _buildAdvancedCard(loc) : _buildSimpleCard(loc),
        const SizedBox(height: 12),
        _buildMaxDurationCard(loc),
        const SizedBox(height: 12),
        const _Tip(
          icon: CupertinoIcons.lightbulb,
          text: '推荐 Right Option / Fn / F13-F19 — Cmd / Ctrl 等组合键常被系统应用占用。',
        ),
      ],
    );
  }

  Widget _buildSimpleCard(AppLocalizations loc) {
    return SettingsCard(
      title: '录音键',
      titleIcon: CupertinoIcons.mic,
      accentColor: AppTheme.getAccent(context),
      children: [
        _row(
          '录音键',
          '短按 = 切换录音，长按 = 说话松开停',
          hotkeyBadge(
            context,
            _currentKeyName,
            onTap: () => _recordHotkey('shared'),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedCard(AppLocalizations loc) {
    return SettingsCard(
      title: '录音键（PTT / Toggle 分键）',
      titleIcon: CupertinoIcons.mic,
      accentColor: AppTheme.getAccent(context),
      children: [
        _row(
          '长按说话 (PTT)',
          '长按该键录音，松开停止',
          hotkeyBadge(
            context,
            _currentKeyName,
            onTap: () => _recordHotkey('ptt'),
          ),
        ),
        const SizedBox(height: 14),
        _row(
          '单击切换 (Toggle)',
          '点一下开录、再点一下停',
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
      ],
    );
  }

  Widget _buildMaxDurationCard(AppLocalizations loc) {
    return SettingsCard(
      children: [
        _row(
          loc.toggleMaxDuration,
          'Toggle 模式下自动停止录音的时长',
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
