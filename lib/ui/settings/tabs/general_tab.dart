import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../services/config_service.dart';
import '../../../services/app_service.dart';
import '../../../services/audio_device_service.dart';
import '../../../services/update_service.dart';
import '../../../services/config_backup_service.dart';
import '../../../config/distribution.dart';
import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../settings_shared.dart';

/// General tab — combines the old General tab + About tab into one view.
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

  // About
  String _version = '';
  bool _isCheckingUpdate = false;
  bool _versionCopied = false;
  String? _updateResult;

  // Subscriptions
  StreamSubscription? _deviceChangeSubscription;

  @override
  void initState() {
    super.initState();
    _loadVersion();
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

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {}
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

          const SizedBox(height: 32),

          // =================================================================
          // 3. About section (centered)
          // =================================================================
          const SizedBox(height: 32),

          // App icon
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/app_icon.png',
                  width: 100, height: 100),
            ),
          ),
          const SizedBox(height: 24),

          // App name
          Text(
            '子曰 SpeakOut',
            style: AppTheme.display(context).copyWith(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Version badge + update check
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Version badge (double-tap to copy)
              GestureDetector(
                onDoubleTap: () {
                  Clipboard.setData(ClipboardData(text: _version));
                  setState(() => _versionCopied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _versionCopied = false);
                  });
                },
                child: Tooltip(
                  message: '双击复制版本号',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _versionCopied
                          ? MacosColors.systemGreenColor
                              .withValues(alpha: 0.15)
                          : MacosColors.systemGrayColor
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _versionCopied
                            ? MacosColors.systemGreenColor
                                .withValues(alpha: 0.4)
                            : MacosColors.systemGrayColor
                                .withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_versionCopied) ...[
                          const MacosIcon(CupertinoIcons.checkmark,
                              size: 12,
                              color: MacosColors.systemGreenColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _versionCopied ? '已复制' : 'v$_version',
                          style: AppTheme.mono(context).copyWith(
                            fontSize: 12,
                            color: _versionCopied
                                ? MacosColors.systemGreenColor
                                : MacosColors.labelColor
                                    .resolveFrom(context)
                                    .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Update check button (hidden in App Store build)
              if (Distribution.supportsUpdateCheck) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isCheckingUpdate
                      ? null
                      : () async {
                          setState(() {
                            _isCheckingUpdate = true;
                            _updateResult = null;
                          });
                          try {
                            final info = await PackageInfo.fromPlatform();
                            UpdateService().resetCheck();
                            await UpdateService().checkForUpdate();
                            final latest = UpdateService().latestVersion;
                            if (latest != null &&
                                UpdateService.isNewer(
                                    latest, info.version)) {
                              setState(() => _updateResult =
                                  loc.updateAvailable(latest));
                            } else {
                              setState(
                                  () => _updateResult = loc.updateUpToDate);
                            }
                          } catch (_) {
                            setState(
                                () => _updateResult = loc.updateUpToDate);
                          }
                          setState(() => _isCheckingUpdate = false);
                        },
                  child: Tooltip(
                    message: loc.updateAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MacosColors.systemGrayColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MacosColors.systemGrayColor
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: _isCheckingUpdate
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CupertinoActivityIndicator(),
                            )
                          : const MacosIcon(
                              CupertinoIcons.arrow_clockwise,
                              size: 14,
                              color: MacosColors.secondaryLabelColor,
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Update result
          if (Distribution.supportsUpdateCheck)
            SizedBox(
              height: 40,
              child: _updateResult != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _updateResult == loc.updateUpToDate
                          ? Text(
                              _updateResult!,
                              style: AppTheme.caption(context).copyWith(
                                fontSize: 11,
                                color: MacosColors.systemGrayColor,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _updateResult!,
                                  style: AppTheme.caption(context).copyWith(
                                    fontSize: 11,
                                    color: MacosColors.systemOrangeColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    final svc = UpdateService();
                                    if (svc.canAutoUpdate) {
                                      svc.downloadUpdate();
                                    } else {
                                      final url = svc.downloadUrl ??
                                          'https://github.com/4over7/SpeakOut/releases/latest';
                                      launchUrl(Uri.parse(url));
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getAccent(context),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      UpdateService().canAutoUpdate
                                          ? '下载更新'
                                          : loc.updateAction,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    )
                  : null,
            ),

          const SizedBox(height: 16),

          // Tagline
          Text(
            loc.aboutTagline,
            style: AppTheme.body(context).copyWith(
              fontSize: 16,
              color: AppTheme.getAccent(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            loc.aboutSubTagline,
            style: AppTheme.caption(context).copyWith(fontSize: 13),
          ),

          const SizedBox(height: 36),

          // Powered-by credits
          Column(
            children: [
              Text(loc.aboutPoweredBy,
                  style:
                      AppTheme.caption(context).copyWith(fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Sherpa-ONNX',
                      style: AppTheme.body(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('•',
                        style: TextStyle(
                            color: MacosColors.tertiaryLabelColor)),
                  ),
                  Text('Aliyun NLS',
                      style: AppTheme.body(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('•',
                        style: TextStyle(
                            color: MacosColors.tertiaryLabelColor)),
                  ),
                  Text('Ollama',
                      style: AppTheme.body(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Copyright
          Text(
            loc.aboutCopyright,
            style: AppTheme.caption(context)
                .copyWith(color: MacosColors.quaternaryLabelColor),
          ),
          const SizedBox(height: 12),

          // Privacy policy link
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(
                'https://github.com/4over7/SpeakOut/wiki/Privacy-Policy')),
            child: Text(
              '隐私政策',
              style: AppTheme.caption(context).copyWith(
                color: AppTheme.getAccent(context),
                decoration: TextDecoration.underline,
              ),
            ),
          ),

          const SizedBox(height: 48),

          // =================================================================
          // 4. Developer section
          // =================================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SettingsGroup(
              title: '开发者',
              children: [
                SettingsTile(
                  label: '详细日志',
                  icon: CupertinoIcons.doc_text,
                  child: MacosSwitch(
                    value: ConfigService().verboseLogging,
                    onChanged: (v) async {
                      await ConfigService().setVerboseLogging(v);
                      AppService().applyVerboseLogging();
                      setState(() {});
                    },
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  label: '日志输出目录',
                  icon: CupertinoIcons.folder,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ConfigService().logDirectory.isEmpty
                            ? '未设置（仅输出到控制台）'
                            : ConfigService()
                                .logDirectory
                                .replaceFirst(
                                    RegExp(r'^/Users/[^/]+'), '~'),
                        style: AppTheme.caption(context)
                            .copyWith(color: MacosColors.systemGrayColor),
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: const MacosIcon(
                            CupertinoIcons.folder_badge_plus,
                            size: 16),
                        backgroundColor: MacosColors.transparent,
                        onPressed: () async {
                          final dir =
                              await FilePicker.platform.getDirectoryPath(
                            dialogTitle: '选择日志输出目录',
                          );
                          if (dir != null) {
                            await ConfigService().setLogDirectory(dir);
                            AppService().applyVerboseLogging();
                            setState(() {});
                          }
                        },
                      ),
                      if (ConfigService().logDirectory.isNotEmpty)
                        MacosIconButton(
                          icon: const MacosIcon(
                              CupertinoIcons.xmark_circle,
                              size: 16),
                          backgroundColor: MacosColors.transparent,
                          onPressed: () async {
                            await ConfigService().setLogDirectory('');
                            AppService().applyVerboseLogging();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // =================================================================
          // 5. Config backup section
          // =================================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SettingsGroup(
              title: '配置备份',
              children: [
                SettingsTile(
                  label: '导出配置',
                  subtitle: '将所有设置和凭证导出为文件（含明文密钥，请妥善保管）',
                  icon: CupertinoIcons.arrow_up_doc,
                  child: PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () async {
                      final path = await FilePicker.platform.saveFile(
                        dialogTitle: '导出配置文件',
                        fileName: 'speakout_config.json',
                        allowedExtensions: ['json'],
                        type: FileType.custom,
                      );
                      if (path != null) {
                        final result =
                            await ConfigBackupService.exportToFile(path);
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content: Text(result.success
                                ? '已导出：${result.message}'
                                : '导出失败：${result.error}'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: const Text('导出'),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  label: '导入配置',
                  subtitle: '从备份文件恢复所有设置，立即生效',
                  icon: CupertinoIcons.arrow_down_doc,
                  child: PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () async {
                      final result =
                          await FilePicker.platform.pickFiles(
                        dialogTitle: '选择配置文件',
                        allowedExtensions: ['json'],
                        type: FileType.custom,
                      );
                      if (result != null &&
                          result.files.single.path != null) {
                        final importResult =
                            await ConfigBackupService.importFromFile(
                                result.files.single.path!);
                        if (mounted) {
                          setState(() {}); // Refresh UI
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content: Text(importResult.success
                                ? '${importResult.message}，配置已生效'
                                : '导入失败：${importResult.error}'),
                            backgroundColor: importResult.success
                                ? MacosColors.systemGreenColor
                                : null,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: const Text('导入'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
