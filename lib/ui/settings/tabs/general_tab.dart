import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../config/app_constants.dart';
import '../../../services/config_service.dart';
import '../../../services/audio_device_service.dart';
import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../settings_shared.dart';
import '../sidebar/hotkey_recorder_modal.dart';

/// v1.8 Sidebar - 通用页（合并快捷键、基础设置、权限三段）。
/// 版面按"频率 + 重要性"排序：快捷键（常改）→ 基础设置（偶改）→ 权限（首次配置后不再碰，
/// 但自带警告横幅兜底）。
class GeneralTab extends StatefulWidget {
  const GeneralTab({super.key});

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  // Audio
  List<AudioDevice> _audioDevices = [];
  AudioDevice? _currentAudioDevice;
  bool _autoManageAudio = true;
  bool _useSystemDefaultAudio = true;

  // Hotkeys
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  String _toggleInputKeyName = '';
  int _toggleMaxDuration = 0;

  StreamSubscription? _deviceChangeSubscription;

  @override
  void initState() {
    super.initState();
    _loadAudioDevices();
    _deviceChangeSubscription =
        CoreEngine().audioDeviceService?.deviceChanges.listen((_) {
      if (mounted) _loadAudioDevices();
    });

    final config = ConfigService();
    _currentKeyCode = config.pttKeyCode;
    _currentKeyName = config.pttKeyName;
    _toggleInputKeyName = config.toggleInputKeyName;
    _toggleMaxDuration = config.toggleMaxDuration;
    CoreEngine().pttKeyCode = _currentKeyCode;
  }

  @override
  void dispose() {
    _deviceChangeSubscription?.cancel();
    super.dispose();
  }

  void _loadAudioDevices() {
    final service = CoreEngine().audioDeviceService;
    if (service == null) return;
    service.refreshDevices();
    setState(() {
      _audioDevices = service.devices;
      _currentAudioDevice = service.currentDevice;
      _autoManageAudio = service.autoManageEnabled;
      _useSystemDefaultAudio = service.isUsingSystemDefault;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final engine = CoreEngine();
    final isBluetooth =
        _useSystemDefaultAudio && (_currentAudioDevice?.isBluetooth ?? false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ——— 段 1：快捷键 ———
          _sectionHeader(loc.sidebarShortcuts, CupertinoIcons.keyboard),
          _buildShortcutsSection(loc),
          const SizedBox(height: 28),

          // ——— 段 2：基础设置 ———
          _sectionHeader(loc.sidebarSectionBasic, CupertinoIcons.settings),
          _buildBasicsSection(loc, engine, isBluetooth),
          const SizedBox(height: 28),

          // ——— 段 3：系统权限 ———
          _sectionHeader(loc.sidebarPermissions, CupertinoIcons.lock_shield),
          _buildPermissionsSection(loc),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section header
  // ---------------------------------------------------------------------------

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          MacosIcon(icon, size: 14, color: AppTheme.getTextSecondary(context)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: AppTheme.getBorder(context).withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section: 快捷键
  // ---------------------------------------------------------------------------

  Widget _buildShortcutsSection(AppLocalizations loc) {
    final cards = <Widget>[
      _hotkeyCard(
        loc.shortcutsPttTitle,
        loc.shortcutsPttHint,
        hotkeyBadge(context, _currentKeyName,
            onTap: () => _recordHotkey('ptt')),
      ),
      _hotkeyCard(
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
    ];

    return Column(
      children: [
        SettingsCardGrid(forceDualColumn: true, children: cards),
        const SizedBox(height: 12),
        _tipBanner(
          CupertinoIcons.lightbulb,
          loc.shortcutsTip,
          MacosColors.systemYellowColor,
        ),
      ],
    );
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

    final result =
        await showHotkeyRecorder(context, title: title, subtitle: subtitle);
    if (result == null || !mounted) return;

    final config = ConfigService();
    final excludeFeature = target == 'toggleInput' ? 'toggleInput' : 'ptt';
    final activeKeys =
        getActiveHotkeys(context, excludeFeature: excludeFeature);
    if (target == 'shared' || target == 'ptt') {
      activeKeys
          .remove((config.toggleInputKeyCode, config.toggleInputModifiers));
    }
    if (target == 'shared' || target == 'toggleInput') {
      activeKeys.remove((config.pttKeyCode, config.pttModifiers));
    }
    final conflictWith =
        findHotkeyConflict(activeKeys, (result.keyCode, result.modifiers));
    if (conflictWith != null) {
      if (!mounted) return;
      await showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
              size: 48, color: Colors.orange),
          title: Text(loc.hotkeyInUseTitle(result.displayName, conflictWith),
              style: const TextStyle(fontWeight: FontWeight.bold)),
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

    switch (target) {
      case 'shared':
        await config.setPttKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        await config.setToggleInputKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        CoreEngine().pttKeyCode = result.keyCode;
        setState(() {
          _currentKeyCode = result.keyCode;
          _currentKeyName = result.displayName;
          _toggleInputKeyName = result.displayName;
        });
      case 'toggleInput':
        await config.setToggleInputKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        setState(() => _toggleInputKeyName = result.displayName);
      default:
        await config.setPttKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        CoreEngine().pttKeyCode = result.keyCode;
        setState(() {
          _currentKeyCode = result.keyCode;
          _currentKeyName = result.displayName;
        });
    }
  }

  Widget _hotkeyCard(String label, String hint, Widget trailing) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      children: [_labelRow(label, hint, trailing)],
    );
  }

  Widget _maxDurationCard(AppLocalizations loc) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      children: [
        _settingsRow(
          label: loc.toggleMaxDuration,
          subtitle: loc.toggleMaxDurationDesc,
          trailing: SizedBox(
            width: 110,
            child: MacosPopupButton<int>(
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
        ),
      ],
    );
  }

  Widget _labelRow(String label, String hint, Widget trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 2),
              Text(hint,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.getTextSecondary(context))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section: 基础设置（语言 / 音频输入 / 自动优化）
  // ---------------------------------------------------------------------------

  Widget _buildBasicsSection(
      AppLocalizations loc, CoreEngine engine, bool isBluetooth) {
    return SettingsCardGrid(
      forceDualColumn: true,
      children: [
        _languageCard(loc),
        _audioCard(loc, engine, isBluetooth),
        _autoOptimizeCard(loc, engine),
        _maxDurationCard(loc),
      ],
    );
  }

  Widget _languageCard(AppLocalizations loc) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      children: [
        _settingsRow(
          label: loc.language,
          trailing: SizedBox(
            width: 160,
            child: MacosPopupButton<String>(
              value: ConfigService().appLanguage,
              items: [
                MacosPopupMenuItem(
                    value: 'system', child: Text(loc.langSystem)),
                MacosPopupMenuItem(value: 'zh', child: Text(loc.langZhHans)),
                MacosPopupMenuItem(value: 'en', child: Text(loc.langEn)),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await ConfigService().setAppLanguage(v);
                  setState(() {});
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _audioCard(
      AppLocalizations loc, CoreEngine engine, bool isBluetooth) {
    final audioDropdown = SizedBox(
      width: 160,
      child: MacosPopupButton<String>(
        value: () {
          if (_useSystemDefaultAudio) return 'system';
          final savedId = ConfigService().audioInputDeviceId;
          if (savedId != null && _audioDevices.any((d) => d.id == savedId)) {
            return savedId;
          }
          return 'system';
        }(),
        items: [
          MacosPopupMenuItem(
              value: 'system', child: Text(loc.systemDefault)),
          ..._audioDevices.map((d) => MacosPopupMenuItem(
                value: d.id,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (d.isBluetooth)
                    const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: MacosIcon(CupertinoIcons.bluetooth, size: 12)),
                  Text(d.name),
                ]),
              )),
        ],
        onChanged: (value) async {
          if (value == null) return;
          final service = engine.audioDeviceService;
          if (service == null) return;
          if (value == 'system') {
            service.clearPreferredDevice();
            await ConfigService().setAudioInputDeviceId(null);
          } else {
            service.setInputDevice(value);
            final device = _audioDevices.firstWhere((d) => d.id == value,
                orElse: () => _audioDevices.first);
            await ConfigService()
                .setAudioInputDeviceId(value, name: device.name);
          }
          _loadAudioDevices();
        },
      ),
    );

    String? audioSubtitle;
    if (_useSystemDefaultAudio && _currentAudioDevice != null) {
      audioSubtitle = loc.audioDeviceCurrent(_currentAudioDevice!.name);
    }

    return SettingsCard(
      padding: const EdgeInsets.all(16),
      children: [
        _settingsRow(
          label: loc.audioInput,
          subtitle: audioSubtitle,
          trailing: audioDropdown,
        ),
        if (isBluetooth) ...[
          const SizedBox(height: 10),
          Row(children: [
            const MacosIcon(CupertinoIcons.exclamationmark_triangle,
                color: Colors.orange, size: 12),
            const SizedBox(width: 6),
            Expanded(
                child: Text(loc.bluetoothMicWarning,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.orange))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                final service = engine.audioDeviceService;
                if (service == null) return;
                service.switchToBuiltinMic();
                final builtIn = service.builtInMicrophone;
                if (builtIn != null && builtIn.id.isNotEmpty) {
                  await ConfigService()
                      .setAudioInputDeviceId(builtIn.id, name: builtIn.name);
                }
                _loadAudioDevices();
              },
              child: Text(loc.switchToBuiltin,
                  style: TextStyle(
                      fontSize: 11,
                      color: MacosColors.systemBlueColor,
                      decoration: TextDecoration.underline)),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _autoOptimizeCard(AppLocalizations loc, CoreEngine engine) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      children: [
        _settingsRow(
          label: loc.autoOptimizeAudio,
          subtitle: loc.autoOptimizeAudioDesc,
          trailing: MacosSwitch(
            value: _autoManageAudio,
            onChanged: (v) {
              setState(() => _autoManageAudio = v);
              engine.audioDeviceService?.autoManageEnabled = v;
            },
          ),
        ),
      ],
    );
  }

  Widget _settingsRow(
      {required String label, String? subtitle, required Widget trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.getTextPrimary(context))),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.getTextSecondary(context))),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section: 系统权限
  // ---------------------------------------------------------------------------

  Widget _buildPermissionsSection(AppLocalizations loc) {
    return Column(
      children: [
        _tipBanner(
          CupertinoIcons.exclamationmark_triangle,
          loc.permissionsReauthTip,
          MacosColors.systemOrangeColor,
        ),
        const SizedBox(height: 12),
        SettingsCardGrid(
          forceDualColumn: true,
          children: [
            _permissionCard(
              loc.permissionsAccessibility,
              loc.permissionsAccessibilityDesc,
              CupertinoIcons.hand_raised,
              'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
              loc,
            ),
            _permissionCard(
              loc.permissionsInputMonitoring,
              loc.permissionsInputMonitoringDesc,
              CupertinoIcons.keyboard,
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent',
              loc,
            ),
            _permissionCard(
              loc.permissionsMicrophone,
              loc.permissionsMicrophoneDesc,
              CupertinoIcons.mic,
              'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
              loc,
            ),
          ],
        ),
      ],
    );
  }

  Widget _permissionCard(String label, String desc, IconData icon, String url,
      AppLocalizations loc) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      onTap: () => launchUrl(Uri.parse(url)),
      children: [
        Row(
          children: [
            MacosIcon(icon, size: 20, color: AppTheme.getAccent(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextPrimary(context))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.getTextSecondary(context))),
                ],
              ),
            ),
            Text(
              '${loc.permissionsOpen} ▸',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.getAccent(context),
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared: tip banner (黄色提示 / 橙色警告)
  // ---------------------------------------------------------------------------

  Widget _tipBanner(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MacosIcon(icon, size: 14, color: color),
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
