import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../services/config_service.dart';
import '../../../services/audio_device_service.dart';
import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../settings_shared.dart';

/// Which subset of general_tab to render.
enum GeneralView { all, general, permissions }

/// General tab — general settings and system permissions.
class GeneralTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;
  final GeneralView viewFilter;

  const GeneralTab({
    super.key,
    required this.onNavigateToTab,
    this.viewFilter = GeneralView.all,
  });

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  // Audio
  List<AudioDevice> _audioDevices = [];
  AudioDevice? _currentAudioDevice;
  bool _autoManageAudio = true;
  bool _useSystemDefaultAudio = true;

  // Subscriptions
  StreamSubscription? _deviceChangeSubscription;

  @override
  void initState() {
    super.initState();
    _loadAudioDevices();
    _deviceChangeSubscription =
        CoreEngine().audioDeviceService?.deviceChanges.listen((_) {
      if (mounted) _loadAudioDevices();
    });
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
    final isBluetooth = _useSystemDefaultAudio && (_currentAudioDevice?.isBluetooth ?? false);

    // v1.8 sidebar single-card views
    switch (widget.viewFilter) {
      case GeneralView.general:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: _buildGeneralCard(loc, engine, isBluetooth),
        );
      case GeneralView.permissions:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: _buildPermissionsCard(),
        );
      case GeneralView.all:
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          SettingsCardGrid(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildGeneralCard(loc, engine, isBluetooth),
              _buildPermissionsCard(),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGeneralCard(AppLocalizations loc, CoreEngine engine, bool isBluetooth) {
    final audioDropdown = SizedBox(
      width: 200,
      child: MacosPopupButton<String>(
        value: () {
          if (_useSystemDefaultAudio) return 'system';
          final savedId = ConfigService().audioInputDeviceId;
          if (savedId != null && _audioDevices.any((d) => d.id == savedId)) return savedId;
          return 'system';
        }(),
        items: [
          MacosPopupMenuItem(value: 'system', child: Text(loc.systemDefault)),
          ..._audioDevices.map((d) => MacosPopupMenuItem(
            value: d.id,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (d.isBluetooth) const Padding(padding: EdgeInsets.only(right: 4), child: MacosIcon(CupertinoIcons.bluetooth, size: 12)),
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
            final device = _audioDevices.firstWhere((d) => d.id == value, orElse: () => _audioDevices.first);
            await ConfigService().setAudioInputDeviceId(value, name: device.name);
          }
          _loadAudioDevices();
        },
      ),
    );

    String? audioSubtitle;
    if (_useSystemDefaultAudio && _currentAudioDevice != null) {
      audioSubtitle = loc.audioDeviceCurrent(_currentAudioDevice!.name);
    }

    // 单页面视图下不重复 page header 的标题
    final showTitle = widget.viewFilter == GeneralView.all;
    return SettingsCard(
      title: showTitle ? loc.tabGeneral : null,
      titleIcon: showTitle ? CupertinoIcons.settings : null,
      accentColor: AppTheme.getAccent(context),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      children: [
        _settingsRow(
          label: loc.language,
          trailing: SizedBox(
            width: 200,
            child: buildDropdown(
              context,
              value: ConfigService().appLanguage,
              items: {'system': loc.langSystem, 'zh': loc.langZhHans, 'en': loc.langEn},
              onChanged: (v) async { await ConfigService().setAppLanguage(v!); setState(() {}); },
            ),
          ),
        ),
        _rowDivider(),
        _settingsRow(
          label: loc.audioInput,
          subtitle: audioSubtitle,
          trailing: audioDropdown,
        ),
        if (isBluetooth)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const MacosIcon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 12),
              const SizedBox(width: 6),
              Expanded(child: Text(loc.bluetoothMicWarning, style: const TextStyle(fontSize: 11, color: Colors.orange))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final service = engine.audioDeviceService;
                  if (service == null) return;
                  service.switchToBuiltinMic();
                  final builtIn = service.builtInMicrophone;
                  if (builtIn != null && builtIn.id.isNotEmpty) {
                    await ConfigService().setAudioInputDeviceId(builtIn.id, name: builtIn.name);
                  }
                  _loadAudioDevices();
                },
                child: Text(loc.switchToBuiltin, style: TextStyle(fontSize: 11, color: MacosColors.systemBlueColor, decoration: TextDecoration.underline)),
              ),
            ]),
          ),
        _rowDivider(),
        _settingsRow(
          label: loc.autoOptimizeAudio,
          subtitle: loc.autoOptimizeAudioDesc,
          trailing: MacosSwitch(
            value: _autoManageAudio,
            onChanged: (v) { setState(() => _autoManageAudio = v); engine.audioDeviceService?.autoManageEnabled = v; },
          ),
        ),
      ],
    );
  }

  Widget _settingsRow({required String label, String? subtitle, required Widget trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.getTextPrimary(context))),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: AppTheme.getTextSecondary(context))),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }

  Widget _rowDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(height: 1, color: AppTheme.getBorder(context)),
    );
  }

  Widget _buildPermissionsCard() {
    final loc = AppLocalizations.of(context)!;
    final showTitle = widget.viewFilter == GeneralView.all;
    return SettingsCard(
      padding: const EdgeInsets.all(14),
      children: [
        if (showTitle) ...[
          Row(
            children: [
              const MacosIcon(CupertinoIcons.lock_shield, size: 14, color: MacosColors.systemGrayColor),
              const SizedBox(width: 6),
              Text(loc.permissionsSectionTitle, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.25)),
          ),
          child: Text(
            loc.permissionsReauthTip,
            style: TextStyle(fontSize: 10, color: MacosColors.systemOrangeColor, height: 1.3),
          ),
        ),
        const SizedBox(height: 10),
        _permissionRow(loc.permissionsAccessibility, loc.permissionsAccessibilityDesc, CupertinoIcons.hand_raised,
          'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'),
        const SizedBox(height: 6),
        _permissionRow(loc.permissionsInputMonitoring, loc.permissionsInputMonitoringDesc, CupertinoIcons.keyboard,
          'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'),
        const SizedBox(height: 6),
        _permissionRow(loc.permissionsMicrophone, loc.permissionsMicrophoneDesc, CupertinoIcons.mic,
          'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'),
      ],
    );
  }

  Widget _permissionRow(String label, String desc, IconData icon, String url) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        MacosIcon(icon, size: 14, color: MacosColors.systemGrayColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.body(context).copyWith(fontSize: 12)),
              Text(desc, style: AppTheme.caption(context).copyWith(fontSize: 10)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(url)),
          child: Text('${loc.permissionsOpen} ▸', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
        ),
      ],
    );
  }
}
