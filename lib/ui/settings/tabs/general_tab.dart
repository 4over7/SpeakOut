import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../config/app_constants.dart';
import '../../../services/config_service.dart';
import '../../../services/audio_device_service.dart';
import '../../../config/app_log.dart';
import '../../../services/app_service.dart';
import '../../../services/notification_service.dart';
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

class _GeneralTabState extends State<GeneralTab> with WidgetsBindingObserver {
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

  // Permission status (refresh on lifecycle resume)
  bool _accessibilityGranted = true;
  bool _inputMonitoringGranted = true;
  bool _microphoneGranted = true;

  StreamSubscription? _deviceChangeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAudioDevices();
    _deviceChangeSubscription =
        AppService().audioDeviceService?.deviceChanges.listen((_) {
      if (mounted) _loadAudioDevices();
    });

    final config = ConfigService();
    _currentKeyCode = config.pttKeyCode;
    _currentKeyName = config.pttKeyName;
    _toggleInputKeyName = config.toggleInputKeyName;
    _toggleMaxDuration = config.toggleMaxDuration;
    AppService().pttKeyCode = _currentKeyCode;
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceChangeSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从系统设置切回来时刷新权限状态
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  void _refreshPermissions() {
    final ni = AppService().nativeInput;
    if (ni == null) return;
    setState(() {
      _accessibilityGranted = ni.checkAccessibilityPermission();
      _inputMonitoringGranted = ni.checkInputMonitoringPermission();
      _microphoneGranted = ni.checkMicrophonePermission();
    });
  }

  void _loadAudioDevices() {
    final service = AppService().audioDeviceService;
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
    final engine = AppService();
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
                  if (!mounted) return;
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
        // 两个键相同是**受支持**的用法（按住 >1s 走 PTT，点一下走 Toggle），
        // 但界面上只并排显示两个一样的键名，不说明就只能靠猜。
        // toggleHint 这条文案早就写好了，此前零引用。
        if (_toggleInputKeyName.isNotEmpty &&
            _toggleInputKeyName == _currentKeyName) ...[
          const SizedBox(height: 8),
          _tipBanner(
            CupertinoIcons.info_circle,
            loc.toggleHint,
            MacosColors.systemBlueColor,
          ),
        ],
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

    // mounted 判断只能挡 setState，**不能挡在落盘前面** ——
    // 用户刚录完快捷键就关掉设置页的话，那次录制会被静默丢掉。
    switch (target) {
      case 'shared':
        await config.setPttKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        await config.setToggleInputKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        AppService().pttKeyCode = result.keyCode;
        if (!mounted) return;
        setState(() {
          _currentKeyCode = result.keyCode;
          _currentKeyName = result.displayName;
          _toggleInputKeyName = result.displayName;
        });
      case 'toggleInput':
        await config.setToggleInputKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        if (!mounted) return;
        setState(() => _toggleInputKeyName = result.displayName);
      default:
        await config.setPttKey(result.keyCode, result.displayName,
            modifiers: result.modifiers);
        AppService().pttKeyCode = result.keyCode;
        if (!mounted) return;
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
                  if (!mounted) return;
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
      AppLocalizations loc, AppService engine, bool isBluetooth) {
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
                  if (!mounted) return;
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
      AppLocalizations loc, AppService engine, bool isBluetooth) {
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

  Widget _autoOptimizeCard(AppLocalizations loc, AppService engine) {
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
              granted: _accessibilityGranted,
            ),
            _permissionCard(
              loc.permissionsInputMonitoring,
              loc.permissionsInputMonitoringDesc,
              CupertinoIcons.keyboard,
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent',
              loc,
              granted: _inputMonitoringGranted,
            ),
            _permissionCard(
              loc.permissionsMicrophone,
              loc.permissionsMicrophoneDesc,
              CupertinoIcons.mic,
              'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
              loc,
              granted: _microphoneGranted,
              onTapOverride: _handleMicrophoneTap,
            ),
          ],
        ),
      ],
    );
  }

  /// 麦克风跟另外两个权限不一样：从没请求过时（status=0）系统还没把本 App
  /// 列进「隐私与安全性 > 麦克风」，把用户丢去系统设置他根本找不到开关。
  /// 这种情况要先弹系统授权框；已拒绝（status=2）才是去系统设置的场景。
  /// （onboarding 已经这么做了，这里是同一条分支 —— 之前只改了 onboarding，
  ///   选了「稍后设置」的用户从设置页进来就卡死在找不到开关。）
  Future<void> _handleMicrophoneTap(String url) async {
    final loc = AppLocalizations.of(context)!;
    final status = AppService().microphonePermissionStatus();
    if (status == 1) {
      NotificationService().notifyError(loc.permissionsMicrophoneRestricted);
      return;
    }
    if (status == 0) {
      AppService().requestMicrophonePermission();
      // 每轮读**完整状态**，不能只看 granted：用户在系统弹框里点了「不允许」
      // 之后状态就变成 denied 了，只盯着 granted 会继续空转满 30 秒然后
      // 一声不响地结束 —— 用户以为点了没反应。
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        _refreshPermissions();
        final s = AppService().microphonePermissionStatus();
        if (s == 3) return; // 已授权
        if (s == 2) { // 用户点了不允许 —— 直接送去系统设置改
          await _openSettingsUrl(url, loc);
          return;
        }
        if (s == 1) {
          NotificationService()
              .notifyError(loc.permissionsMicrophoneRestricted);
          return;
        }
      }
      // 30 秒还是未决定：弹框没出来或用户没理它，给个提示别静默结束。
      // 不判 mounted：全局横幅不依赖本页 context，页面关了也该看到结论。
      NotificationService().notifyError(loc.permissionsNotGranted);
      return;
    }
    await _openSettingsUrl(url, loc);
  }

  /// launchUrl 打不开时**通常不抛异常，而是返回 false** —— 只 await 不看返回值
  /// 等于静默失败，用户看到的是「点了没反应」。
  Future<void> _openSettingsUrl(String url, AppLocalizations loc) async {
    final ok = await launchUrl(Uri.parse(url));
    if (ok || !mounted) return;
    AppLog.e('launchUrl returned false: $url');
    NotificationService().notifyError(loc.permissionsNotGranted);
  }

  Widget _permissionCard(String label, String desc, IconData icon, String url,
      AppLocalizations loc,
      {required bool granted, Future<void> Function(String url)? onTapOverride}) {
    final statusColor = granted
        ? MacosColors.systemGreenColor
        : MacosColors.systemOrangeColor;
    final statusIcon = granted
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.exclamationmark_circle_fill;
    final statusText = granted ? loc.permissionsGranted : loc.permissionsNotGranted;
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      // onTap 是 VoidCallback：直接把 Future 交出去等于把异常丢进全局 Zone，
      // 用户只会看到「点了没反应」。这里自己 await 并兜住。
      onTap: () async {
        try {
          if (onTapOverride != null) {
            await onTapOverride(url);
          } else {
            await _openSettingsUrl(url, loc);
          }
        } catch (e) {
          AppLog.e('permission card tap failed: $e');
          NotificationService().notifyError(loc.permissionsNotGranted); // 同上，全局横幅不判 mounted
        }
      },
      children: [
        Row(
          children: [
            MacosIcon(icon, size: 20, color: AppTheme.getAccent(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.getTextPrimary(context))),
                    const SizedBox(width: 8),
                    MacosIcon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 3),
                    Text(statusText,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: statusColor)),
                  ]),
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
