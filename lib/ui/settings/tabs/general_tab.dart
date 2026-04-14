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
  // Build
  // ---------------------------------------------------------------------------

  Widget _compactRow(String label, Widget trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.body(context).copyWith(fontSize: 12)),
        trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final engine = CoreEngine();
    final isBluetooth = _useSystemDefaultAudio && (_currentAudioDevice?.isBluetooth ?? false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          SettingsCardGrid(
            spacing: 10,
            runSpacing: 10,
            children: [
              // --- General Settings card ---
              SettingsCard(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      const MacosIcon(CupertinoIcons.settings, size: 14, color: MacosColors.systemGrayColor),
                      const SizedBox(width: 6),
                      Text(loc.tabGeneral, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _compactRow(loc.language, buildDropdown(
                    context,
                    value: ConfigService().appLanguage,
                    items: {'system': loc.langSystem, 'zh': '简体中文', 'en': 'English'},
                    onChanged: (v) async { await ConfigService().setAppLanguage(v!); setState(() {}); },
                  )),
                  const SizedBox(height: 8),
                  _compactRow(loc.audioInput, SizedBox(width: 200, child: MacosPopupButton<String>(
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
                  ))),
                  if (_useSystemDefaultAudio && _currentAudioDevice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('当前: ${_currentAudioDevice!.name}', style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
                    ),
                  if (isBluetooth)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const MacosIcon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 12),
                        const SizedBox(width: 4),
                        Text('蓝牙麦克风可能降低质量', style: TextStyle(fontSize: 10, color: Colors.orange)),
                        const SizedBox(width: 6),
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
                          child: Text('切换内置', style: TextStyle(fontSize: 10, color: MacosColors.systemBlueColor, decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ),
                  Divider(height: 16, color: AppTheme.getBorder(context)),
                  _compactRow('自动优化音频', MacosSwitch(
                    value: _autoManageAudio,
                    onChanged: (v) { setState(() => _autoManageAudio = v); engine.audioDeviceService?.autoManageEnabled = v; },
                  )),
                  Text('蓝牙耳机时自动切换到高质量麦克风', style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
                ],
              ),

              // --- System Permissions card ---
              SettingsCard(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      const MacosIcon(CupertinoIcons.lock_shield, size: 14, color: MacosColors.systemGrayColor),
                      const SizedBox(width: 6),
                      Text('系统权限', style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MacosColors.systemOrangeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '更换签名证书后如快捷键失效，请逐项重新授权。',
                      style: TextStyle(fontSize: 10, color: MacosColors.systemOrangeColor, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _permissionRow('辅助功能', '快捷键+文本注入', CupertinoIcons.hand_raised,
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'),
                  const SizedBox(height: 6),
                  _permissionRow('输入监控', '键盘触发录音', CupertinoIcons.keyboard,
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'),
                  const SizedBox(height: 6),
                  _permissionRow('麦克风', '语音采集', CupertinoIcons.mic,
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _permissionRow(String label, String desc, IconData icon, String url) {
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
          child: Text('打开 ▸', style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
        ),
      ],
    );
  }
}
