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

/// v1.8 Sidebar - 快捷键页
///
/// D2 从 mode_tab._buildHotkeyCard 提取，独立维护 state。
/// 旧 mode_tab 暂时保留（旧 tab 设置页仍在用），Phase 6 清理时一并删除。
class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  final CoreEngine _engine = CoreEngine();

  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  bool _isCapturingKey = false;

  String _toggleInputKeyName = '';
  bool _isCapturingToggleInputKey = false;

  int _toggleMaxDuration = 0;

  HotkeyCapturer? _keyCapturer;

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

  @override
  void dispose() {
    _keyCapturer?.cancel();
    super.dispose();
  }

  void _startKeyCapture([String target = 'ptt']) {
    _keyCapturer?.cancel();
    setState(() {
      if (target == 'toggleInput') {
        _isCapturingToggleInputKey = true;
      } else {
        _isCapturingKey = true;
      }
    });
    _keyCapturer = HotkeyCapturer(
      keyStream: _engine.rawKeyEventStream,
      onCaptured: (keyCode, modifierFlags) {
        _saveHotkeyConfig(keyCode, mapKeyCodeToString(keyCode), modifierFlags: modifierFlags);
        _resetCaptureState();
      },
      onTimeout: _resetCaptureState,
    )..start();
  }

  void _resetCaptureState() {
    if (!mounted) return;
    setState(() {
      _isCapturingKey = false;
      _isCapturingToggleInputKey = false;
    });
  }

  void _stopKeyCapture() {
    _keyCapturer?.cancel();
    _keyCapturer = null;
    _resetCaptureState();
  }

  Future<void> _saveHotkeyConfig(int keyCode, String keyName, {int modifierFlags = 0}) async {
    final config = ConfigService();
    final requiredMods = stripOwnModifier(keyCode, modifierFlags);
    final displayName = requiredMods != 0 ? comboKeyName(keyCode, requiredMods) : keyName;

    final activeKeys = getActiveHotkeys(context, excludeFeature: _isCapturingKey ? 'ptt' : 'toggleInput');
    if (_isCapturingKey) activeKeys.remove((config.toggleInputKeyCode, config.toggleInputModifiers));
    if (_isCapturingToggleInputKey) activeKeys.remove((config.pttKeyCode, config.pttModifiers));
    final hotkeyId = (keyCode, requiredMods);
    final conflictWith = findHotkeyConflict(activeKeys, hotkeyId);
    if (conflictWith != null) {
      _stopKeyCapture();
      if (!mounted) return;
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: Colors.orange),
          title: Text('$displayName 已被「$conflictWith」使用', style: const TextStyle(fontWeight: FontWeight.bold)),
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

    if (_isCapturingToggleInputKey) {
      await config.setToggleInputKey(keyCode, displayName, modifiers: requiredMods);
      setState(() {
        _toggleInputKeyName = displayName;
        _isCapturingToggleInputKey = false;
      });
    } else {
      await config.setPttKey(keyCode, displayName, modifiers: requiredMods);
      CoreEngine().pttKeyCode = keyCode;
      setState(() {
        _currentKeyCode = keyCode;
        _currentKeyName = displayName;
        _isCapturingKey = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        SettingsCard(
          title: '录音键',
          titleIcon: CupertinoIcons.mic,
          accentColor: AppTheme.getAccent(context),
          children: [
            _row(
              '长按说话 (PTT)',
              '长按该键录音，松开停止',
              hotkeyBadge(
                context,
                _currentKeyName,
                isCapturing: _isCapturingKey,
                onTap: () => _startKeyCapture('ptt'),
              ),
            ),
            const SizedBox(height: 14),
            _row(
              '单击切换 (Toggle)',
              '点一下开录、再点一下停',
              hotkeyBadge(
                context,
                _toggleInputKeyName,
                isCapturing: _isCapturingToggleInputKey,
                onTap: () => _startKeyCapture('toggleInput'),
                onClear: _toggleInputKeyName.isEmpty
                    ? null
                    : () async {
                        await ConfigService().clearToggleInputKey();
                        setState(() => _toggleInputKeyName = '');
                      },
              ),
            ),
            const SizedBox(height: 14),
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
        ),
        const SizedBox(height: 12),
        _Tip(
          icon: CupertinoIcons.lightbulb,
          text: '推荐 Right Option / Fn / F13-F19 — Cmd / Ctrl 等组合键常被系统应用占用。',
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
