import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// General tab — general settings and system permissions.
class GeneralTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const GeneralTab({super.key, required this.onNavigateToTab});

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
  // Audio input section
  // ---------------------------------------------------------------------------

  Widget _buildAudioInputSection(AppLocalizations loc) {
    final engine = CoreEngine();
    // Show Bluetooth warning only when using system default and it happens to be BT
    final isBluetooth =
        _useSystemDefaultAudio && (_currentAudioDevice?.isBluetooth ?? false);

    return Column(
      children: [
        SettingsTile(
          label: loc.audioInput,
          icon: CupertinoIcons.mic,
          child: MacosPopupButton<String>(
            value: () {
              if (_useSystemDefaultAudio) return 'system';
              final savedId = ConfigService().audioInputDeviceId;
              if (savedId != null &&
                  _audioDevices.any((d) => d.id == savedId)) {
                return savedId;
              }
              return 'system';
            }(),
            items: [
              MacosPopupMenuItem(
                value: 'system',
                child: Text(loc.systemDefault, style: AppTheme.body(context)),
              ),
              ..._audioDevices.map((d) => MacosPopupMenuItem(
                    value: d.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d.isBluetooth)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child:
                                MacosIcon(CupertinoIcons.bluetooth, size: 12),
                          ),
                        Text(d.name, style: AppTheme.body(context)),
                      ],
                    ),
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
                final device = _audioDevices.firstWhere(
                  (d) => d.id == value,
                  orElse: () => _audioDevices.first,
                );
                await ConfigService()
                    .setAudioInputDeviceId(value, name: device.name);
              }
              _loadAudioDevices();
            },
          ),
        ),

        // Current device info when using system default
        if (_useSystemDefaultAudio && _currentAudioDevice != null)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Text(
              '当前系统设备: ${_currentAudioDevice!.name}',
              style: AppTheme.caption(context)
                  .copyWith(color: MacosColors.systemGrayColor),
            ),
          ),

        // Bluetooth warning
        if (isBluetooth)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Row(
              children: [
                const MacosIcon(CupertinoIcons.exclamationmark_triangle,
                    color: Colors.orange, size: 14),
                const SizedBox(width: 4),
                Text(
                  '蓝牙麦克风可能降低转写质量',
                  style: AppTheme.caption(context)
                      .copyWith(color: Colors.orange),
                ),
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
                  child: Text(
                    '切换到内置麦克风',
                    style: AppTheme.caption(context).copyWith(
                      color: MacosColors.systemBlueColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SettingsDivider(),

        // Auto-manage toggle
        SettingsTile(
          label: '自动优化音频',
          icon: CupertinoIcons.wand_stars,
          child: MacosSwitch(
            value: _autoManageAudio,
            onChanged: (v) {
              setState(() => _autoManageAudio = v);
              engine.audioDeviceService?.autoManageEnabled = v;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 2),
          child: Text(
            '检测到蓝牙耳机时自动切换到高质量麦克风',
            style: AppTheme.caption(context)
                .copyWith(color: MacosColors.systemGrayColor),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Permission tile
  // ---------------------------------------------------------------------------

  Widget _buildPermissionTile(
    String label,
    String subtitle,
    IconData icon,
    String settingsUrl,
  ) {
    return SettingsTile(
      label: label,
      subtitle: subtitle,
      icon: icon,
      child: PushButton(
        controlSize: ControlSize.regular,
        secondary: true,
        onPressed: () => launchUrl(Uri.parse(settingsUrl)),
        child: const Text('打开设置'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: Column(
        children: [
          // =================================================================
          // 1. General Settings
          // =================================================================
          SettingsGroup(
            title: loc.tabGeneral,
            children: [
              // Interface Language
              SettingsTile(
                label: loc.language,
                icon: CupertinoIcons.globe,
                child: buildDropdown(
                  context,
                  value: ConfigService().appLanguage,
                  items: {
                    'system': loc.langSystem,
                    'zh': '简体中文',
                    'en': 'English',
                  },
                  onChanged: (v) async {
                    await ConfigService().setAppLanguage(v!);
                    setState(() {});
                  },
                ),
              ),
              const SettingsDivider(),
              // Audio Input
              _buildAudioInputSection(loc),
            ],
          ),

          const SizedBox(height: 24),

          // =================================================================
          // 2. System Permissions
          // =================================================================
          SettingsGroup(
            title: '系统权限',
            children: [
              // Certificate update warning
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MacosColors.systemOrangeColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MacosColors.systemOrangeColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MacosIcon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: MacosColors.systemOrangeColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '从 v1.5.22 起更换了签名证书。如果更新后快捷键失效，请在下方逐项点击「打开设置」，'
                          '将 SpeakOut 从权限列表中删除（按 - 号），再重新添加（按 + 号）。',
                          style: AppTheme.caption(context).copyWith(
                            fontSize: 11,
                            color: MacosColors.systemOrangeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SettingsDivider(),
              _buildPermissionTile(
                '辅助功能',
                '快捷键监听和文本注入',
                CupertinoIcons.hand_raised,
                'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
              ),
              const SettingsDivider(),
              _buildPermissionTile(
                '输入监控',
                '键盘快捷键触发录音',
                CupertinoIcons.keyboard,
                'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent',
              ),
              const SettingsDivider(),
              _buildPermissionTile(
                '麦克风',
                '语音采集',
                CupertinoIcons.mic,
                'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
