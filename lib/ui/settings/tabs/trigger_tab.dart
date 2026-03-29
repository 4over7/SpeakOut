import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../services/config_service.dart';
import '../../../services/correction_service.dart';
import '../../../config/app_constants.dart';
import '../../../config/app_log.dart';
import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';
import '../settings_shared.dart';

class TriggerTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const TriggerTab({super.key, required this.onNavigateToTab});

  @override
  State<TriggerTab> createState() => _TriggerTabState();
}

class _TriggerTabState extends State<TriggerTab> {
  // Hotkey capture state
  int _currentKeyCode = AppConstants.kDefaultPttKeyCode;
  String _currentKeyName = AppConstants.kDefaultPttKeyName;
  bool _isCapturingKey = false;
  String _diaryKeyName = 'Right Option';
  bool _isCapturingDiaryKey = false;
  String _toggleInputKeyName = '';
  String _toggleDiaryKeyName = '';
  bool _isCapturingToggleInputKey = false;
  bool _isCapturingToggleDiaryKey = false;
  bool _isCapturingOrganizeKey = false;
  bool _isCapturingTranslateKey = false;
  bool _isCapturingCorrectionKey = false;
  int _toggleMaxDuration = 0;

  // Diary state
  String? _diaryDirError;

  // Organize prompt
  late final TextEditingController _organizePromptController;

  // Key capture infrastructure
  StreamSubscription<(int, int)>? _keySubscription;
  final CoreEngine _engine = CoreEngine();

  @override
  void initState() {
    super.initState();
    _organizePromptController = TextEditingController(
      text: ConfigService().organizePrompt,
    );
    _loadHotkeyConfig();
  }

  @override
  void dispose() {
    _keySubscription?.cancel();
    _organizePromptController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Config loading
  // ---------------------------------------------------------------------------

  void _loadHotkeyConfig() {
    final config = ConfigService();
    setState(() {
      _currentKeyCode = config.pttKeyCode;
      _currentKeyName = config.pttKeyName;
      _diaryKeyName = config.diaryKeyName;
      _toggleInputKeyName = config.toggleInputKeyName;
      _toggleDiaryKeyName = config.toggleDiaryKeyName;
      _toggleMaxDuration = config.toggleMaxDuration;
    });
    _engine.pttKeyCode = _currentKeyCode;
  }

  // ---------------------------------------------------------------------------
  // Key capture
  // ---------------------------------------------------------------------------

  void _startKeyCapture([String target = 'ptt']) {
    setState(() {
      switch (target) {
        case 'toggleInput':
          _isCapturingToggleInputKey = true;
        case 'toggleDiary':
          _isCapturingToggleDiaryKey = true;
        case 'diary':
          _isCapturingDiaryKey = true;
        case 'organize':
          _isCapturingOrganizeKey = true;
        case 'translate':
          _isCapturingTranslateKey = true;
        case 'correction':
          _isCapturingCorrectionKey = true;
        default:
          _isCapturingKey = true;
      }
    });

    _keySubscription = _engine.rawKeyEventStream.listen((event) {
      final (keyCode, modifierFlags) = event;
      final keyName = mapKeyCodeToString(keyCode);
      _saveHotkeyConfig(keyCode, keyName, modifierFlags: modifierFlags);
      _stopKeyCapture();
    });

    // Timeout after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted &&
          (_isCapturingKey ||
              _isCapturingDiaryKey ||
              _isCapturingToggleInputKey ||
              _isCapturingToggleDiaryKey ||
              _isCapturingOrganizeKey ||
              _isCapturingTranslateKey ||
              _isCapturingCorrectionKey)) {
        _stopKeyCapture();
      }
    });
  }

  void _stopKeyCapture() {
    _keySubscription?.cancel();
    _keySubscription = null;
    if (mounted) {
      setState(() {
        _isCapturingKey = false;
        _isCapturingDiaryKey = false;
        _isCapturingToggleInputKey = false;
        _isCapturingToggleDiaryKey = false;
        _isCapturingOrganizeKey = false;
        _isCapturingTranslateKey = false;
        _isCapturingCorrectionKey = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Hotkey save with conflict detection
  // ---------------------------------------------------------------------------

  Future<void> _saveHotkeyConfig(int keyCode, String keyName,
      {int modifierFlags = 0}) async {
    final config = ConfigService();
    final isInputGroup = _isCapturingKey || _isCapturingToggleInputKey;
    final isDiaryGroup = _isCapturingDiaryKey || _isCapturingToggleDiaryKey;

    final requiredMods = stripOwnModifier(keyCode, modifierFlags);
    final displayName =
        requiredMods != 0 ? comboKeyName(keyCode, requiredMods) : keyName;

    // Cross-group conflict: input keys vs diary keys
    if (isInputGroup && config.diaryEnabled) {
      final diaryKeys = <int>[
        config.diaryKeyCode,
        if (config.toggleDiaryEnabled) config.toggleDiaryKeyCode,
      ].where((k) => k != 0);
      if (diaryKeys.contains(keyCode)) {
        _showHotkeyConflict(displayName, true);
        return;
      }
    } else if (isDiaryGroup) {
      final inputKeys = [
        config.pttKeyCode,
        if (config.toggleInputEnabled) config.toggleInputKeyCode,
      ].where((k) => k != 0);
      if (inputKeys.contains(keyCode)) {
        _showHotkeyConflict(displayName, false);
        return;
      }
    }

    // Feature-specific saving
    if (_isCapturingCorrectionKey) {
      final activeKeys = <int>[
        config.pttKeyCode,
        if (config.toggleInputEnabled) config.toggleInputKeyCode,
        if (config.diaryEnabled) config.diaryKeyCode,
        if (config.toggleDiaryEnabled) config.toggleDiaryKeyCode,
        if (config.organizeEnabled) config.organizeKeyCode,
        if (config.translateEnabled) config.translateKeyCode,
      ].where((k) => k != 0);
      if (activeKeys.contains(keyCode)) {
        _stopKeyCapture();
        _showGenericHotkeyConflict(displayName);
        return;
      }
      await config.setCorrectionKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingCorrectionKey = false);
    } else if (_isCapturingTranslateKey) {
      final activeKeys = <int>[
        config.pttKeyCode,
        if (config.toggleInputEnabled) config.toggleInputKeyCode,
        if (config.diaryEnabled) config.diaryKeyCode,
        if (config.toggleDiaryEnabled) config.toggleDiaryKeyCode,
        if (config.organizeEnabled) config.organizeKeyCode,
        if (config.correctionEnabled) config.correctionKeyCode,
      ].where((k) => k != 0);
      if (activeKeys.contains(keyCode)) {
        _stopKeyCapture();
        _showGenericHotkeyConflict(displayName);
        return;
      }
      await config.setTranslateKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingTranslateKey = false);
    } else if (_isCapturingOrganizeKey) {
      final activeKeys = <int>[
        config.pttKeyCode,
        if (config.toggleInputEnabled) config.toggleInputKeyCode,
        if (config.diaryEnabled) config.diaryKeyCode,
        if (config.toggleDiaryEnabled) config.toggleDiaryKeyCode,
        if (config.translateEnabled) config.translateKeyCode,
        if (config.correctionEnabled) config.correctionKeyCode,
      ].where((k) => k != 0);
      if (activeKeys.contains(keyCode)) {
        _stopKeyCapture();
        _showGenericHotkeyConflict(displayName);
        return;
      }
      await config.setOrganizeKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingOrganizeKey = false);
    } else if (_isCapturingToggleInputKey) {
      await config.setToggleInputKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() {
        _toggleInputKeyName = displayName;
        _isCapturingToggleInputKey = false;
      });
    } else if (_isCapturingToggleDiaryKey) {
      await config.setToggleDiaryKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() {
        _toggleDiaryKeyName = displayName;
        _isCapturingToggleDiaryKey = false;
      });
    } else if (_isCapturingDiaryKey) {
      await config.setDiaryKey(keyCode, displayName, modifiers: requiredMods);
      setState(() {
        _diaryKeyName = displayName;
        _isCapturingDiaryKey = false;
      });
    } else {
      // PTT key
      await config.setPttKey(keyCode, displayName, modifiers: requiredMods);
      _engine.pttKeyCode = keyCode;
      setState(() {
        _currentKeyCode = keyCode;
        _currentKeyName = displayName;
        _isCapturingKey = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Conflict dialogs
  // ---------------------------------------------------------------------------

  void _showHotkeyConflict(String keyName, bool conflictsWithDiary) {
    final loc = AppLocalizations.of(context)!;
    final target = conflictsWithDiary ? loc.diaryMode : loc.tabTrigger;
    _stopKeyCapture();
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
            size: 48, color: Colors.orange),
        title: Text('$keyName 已被 $target 使用',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        message: const Text('文本注入和闪念笔记不能使用相同的热键，请选择其他按键。'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('好的'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _showGenericHotkeyConflict(String keyName) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
            size: 48, color: Colors.orange),
        title: Text('$keyName 已被其他功能使用',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        message: const Text('该按键已被占用，请选择其他按键。'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('好的'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// On feature re-enable: check if its hotkey conflicts with active keys
  Future<void> _checkConflictOnEnable(String feature, int keyCode,
      String keyName, Future<void> Function() clearKey) async {
    if (keyCode == 0) return;
    final activeKeys = getActiveHotkeys(context, excludeFeature: feature);
    if (activeKeys.containsKey(keyCode)) {
      final conflictWith = activeKeys[keyCode]!;
      await clearKey();
      if (mounted) {
        showMacosAlertDialog(
          context: context,
          builder: (_) => MacosAlertDialog(
            appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: Colors.orange),
            title: Text('$keyName 已被「$conflictWith」占用',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            message: const Text('快捷键已自动清除，请重新设置。'),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: const Text('好的'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Diary directory management
  // ---------------------------------------------------------------------------

  Future<void> _pickDiaryFolder() async {
    try {
      final String? outputDir = await const MethodChannel('com.SpeakOut/overlay')
          .invokeMethod('pickDirectory');
      if (outputDir != null) {
        await ConfigService().setDiaryDirectory(outputDir);
        await _validateDiaryDirectory();
        setState(() {});
      }
    } catch (e) {
      AppLog.d('Pick Directory Failed: $e');
    }
  }

  Future<void> _validateDiaryDirectory() async {
    final dirPath = ConfigService().diaryDirectory;
    if (dirPath.isEmpty) {
      setState(() => _diaryDirError = '未设置保存目录');
      return;
    }
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final testFile = File('${dir.path}/.speakout_write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      setState(() => _diaryDirError = '');
    } catch (e) {
      setState(() => _diaryDirError = '无法写入目录，请重新选择（macOS 需重新授权）');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final config = ConfigService();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 语音输入
          _buildVoiceInputCard(loc, config),
          const SizedBox(height: 12),

          // 2. 录音保护
          _buildRecordingProtectionCard(loc, config),
          const SizedBox(height: 12),

          // 3. 快捷翻译
          _buildQuickTranslateCard(loc, config),
          const SizedBox(height: 12),

          // 4. 纠错反馈
          _buildCorrectionCard(loc, config),
          const SizedBox(height: 12),

          // 5. AI 梳理
          _buildOrganizeCard(loc, config),
          const SizedBox(height: 12),

          // 6. 闪念笔记
          _buildDiaryCard(loc, config),
          const SizedBox(height: 12),

          // 7. 快捷键一览
          _buildHotkeyOverview(loc, config),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. 语音输入
  // ---------------------------------------------------------------------------

  Widget _buildVoiceInputCard(AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: loc.textInjection,
      titleIcon: CupertinoIcons.mic_fill,
      accentColor: AppTheme.triggerVoice,
      children: [
        buildKeyCaptureTile(context, loc.pttMode, CupertinoIcons.keyboard,
          isCapturing: _isCapturingKey,
          keyName: _currentKeyName,
          onEdit: _startKeyCapture,
          onClear: _currentKeyName.isNotEmpty
              ? () async {
                  await config.clearPttKey();
                  _engine.pttKeyCode = 0;
                  setState(() {
                    _currentKeyCode = 0;
                    _currentKeyName = '';
                  });
                }
              : null,
        ),
        const SettingsDivider(),
        buildKeyCaptureTile(
            context, loc.toggleModeTip, CupertinoIcons.text_cursor,
          isCapturing: _isCapturingToggleInputKey,
          keyName: _toggleInputKeyName,
          onEdit: () => _startKeyCapture('toggleInput'),
          onClear: () async {
            await config.clearToggleInputKey();
            setState(() => _toggleInputKeyName = '');
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. 录音保护
  // ---------------------------------------------------------------------------

  Widget _buildRecordingProtectionCard(
      AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: loc.recordingProtection,
      titleIcon: CupertinoIcons.shield,
      children: [
        SettingsTile(
          label: loc.toggleMaxDuration,
          icon: CupertinoIcons.timer,
          child: MacosPopupButton<int>(
            value: _toggleMaxDuration,
            items: [
              MacosPopupMenuItem(value: 0, child: Text(loc.toggleMaxNone)),
              MacosPopupMenuItem(value: 60, child: Text(loc.toggleMaxMin(1))),
              MacosPopupMenuItem(value: 180, child: Text(loc.toggleMaxMin(3))),
              MacosPopupMenuItem(value: 300, child: Text(loc.toggleMaxMin(5))),
              MacosPopupMenuItem(
                  value: 600, child: Text(loc.toggleMaxMin(10))),
            ],
            onChanged: (v) async {
              if (v != null) {
                await config.setToggleMaxDuration(v);
                setState(() => _toggleMaxDuration = v);
              }
            },
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const MacosIcon(CupertinoIcons.info_circle,
                  color: MacosColors.systemGrayColor, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.toggleHint,
                  style: AppTheme.caption(context)
                      .copyWith(color: MacosColors.systemGrayColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. 快捷翻译
  // ---------------------------------------------------------------------------

  Widget _buildQuickTranslateCard(
      AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: loc.quickTranslate,
      titleIcon: CupertinoIcons.globe,
      accentColor: AppTheme.triggerTranslate,
      trailing: MacosSwitch(
        value: config.translateEnabled,
        onChanged: (v) async {
          await config.setTranslateEnabled(v);
          if (v) {
            await _checkConflictOnEnable('translate', config.translateKeyCode,
                config.translateKeyName, config.clearTranslateKey);
          }
          setState(() {});
        },
      ),
      children: [
        if (config.translateEnabled) ...[
          buildKeyCaptureTile(
              context, loc.translateHotkey, CupertinoIcons.keyboard,
            isCapturing: _isCapturingTranslateKey,
            keyName: config.translateKeyName,
            onEdit: () => _startKeyCapture('translate'),
            onClear: () async {
              await config.clearTranslateKey();
              setState(() {});
            },
          ),
          const SettingsDivider(),
          SettingsTile(
            label: loc.translateTargetLanguage,
            icon: CupertinoIcons.textformat,
            child: buildDropdown(
              context,
              value: config.translateTargetLanguage,
              items: {
                'en': loc.langEn,
                'zh-Hans': loc.langZhHans,
                'zh-Hant': loc.langZhHant,
                'ja': loc.langJa,
                'ko': loc.langKo,
                'es': loc.langEs,
                'fr': loc.langFr,
                'de': loc.langDe,
                'ru': loc.langRu,
                'pt': loc.langPt,
              },
              onChanged: (v) async {
                await config.setTranslateTargetLanguage(v!);
                setState(() {});
              },
            ),
          ),
          // LLM 未配置警告
          if (resolveLlmApiKey().isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const MacosIcon(CupertinoIcons.exclamationmark_triangle,
                      color: Colors.orange, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.translateNoLlm,
                      style: AppTheme.caption(context)
                          .copyWith(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              loc.quickTranslateDesc,
              style: AppTheme.caption(context),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. 纠错反馈
  // ---------------------------------------------------------------------------

  Widget _buildCorrectionCard(AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: '纠错反馈',
      titleIcon: CupertinoIcons.checkmark_seal,
      accentColor: AppTheme.triggerCorrect,
      trailing: MacosSwitch(
        value: config.correctionEnabled,
        onChanged: (v) async {
          await config.setCorrectionEnabled(v);
          if (v) {
            await _checkConflictOnEnable(
                'correction',
                config.correctionKeyCode,
                config.correctionKeyName,
                config.clearCorrectionKey);
          }
          setState(() {});
        },
      ),
      children: [
        if (config.correctionEnabled) ...[
          buildKeyCaptureTile(
              context, '纠错快捷键', CupertinoIcons.keyboard,
            isCapturing: _isCapturingCorrectionKey,
            keyName: config.correctionKeyName,
            onEdit: () => _startKeyCapture('correction'),
            onClear: () async {
              await config.clearCorrectionKey();
              setState(() {});
            },
          ),
          const SettingsDivider(),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () async {
                    final result = await FilePicker.platform.saveFile(
                      dialogTitle: '导出纠错数据',
                      fileName: 'speakout_corrections.jsonl',
                    );
                    if (result != null) {
                      final ok = await CorrectionService().exportData(result);
                      if (mounted) {
                        showSettingsInfo(ok ? '导出成功' : '导出失败：无数据');
                      }
                    }
                  },
                  child: const Text('导出'),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      dialogTitle: '导入纠错数据',
                      type: FileType.custom,
                      allowedExtensions: ['jsonl', 'json'],
                    );
                    if (result != null &&
                        result.files.single.path != null) {
                      final count = await CorrectionService()
                          .importData(result.files.single.path!);
                      if (mounted) {
                        showSettingsInfo('导入 $count 条记录（词汇已同步）');
                      }
                    }
                  },
                  child: const Text('导入'),
                ),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '选中修正后的文字，按快捷键提交。系统自动学习纠正，追加到词汇表。',
              style: AppTheme.caption(context),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. AI 梳理
  // ---------------------------------------------------------------------------

  Widget _buildOrganizeCard(AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: loc.organizeEnabled,
      titleIcon: CupertinoIcons.text_alignleft,
      accentColor: AppTheme.triggerOrganize,
      trailing: MacosSwitch(
        value: config.organizeEnabled,
        onChanged: (v) async {
          await config.setOrganizeEnabled(v);
          if (v) {
            await _checkConflictOnEnable('organize', config.organizeKeyCode,
                config.organizeKeyName, config.clearOrganizeKey);
          }
          setState(() {});
        },
      ),
      children: [
        if (config.organizeEnabled) ...[
          buildKeyCaptureTile(
              context, loc.organizeHotkey, CupertinoIcons.keyboard,
            isCapturing: _isCapturingOrganizeKey,
            keyName: config.organizeKeyName.isEmpty
                ? '未设置'
                : config.organizeKeyName,
            onEdit: () => _startKeyCapture('organize'),
            onClear: config.organizeKeyCode != 0
                ? () async {
                    await config.clearOrganizeKey();
                    setState(() {});
                  }
                : null,
          ),
          const SettingsDivider(),

          // 功能说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.triggerOrganize.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.triggerOrganize.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: MacosIcon(CupertinoIcons.lightbulb,
                        size: 16, color: AppTheme.triggerOrganize),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.organizeDesc,
                      style: AppTheme.caption(context).copyWith(
                          color: AppTheme.triggerOrganize, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 自定义 prompt
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(loc.organizePrompt, style: AppTheme.body(context)),
                    GestureDetector(
                      onTap: () async {
                        await config.setOrganizePrompt(
                            AppConstants.kDefaultOrganizePrompt);
                        _organizePromptController.text =
                            AppConstants.kDefaultOrganizePrompt;
                        setState(() {});
                      },
                      child: Text(
                        loc.organizeResetDefault,
                        style: AppTheme.caption(context).copyWith(
                            color: AppTheme.triggerOrganize, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MacosTextField(
                  maxLines: 8,
                  controller: _organizePromptController,
                  decoration: BoxDecoration(
                    color: AppTheme.getInputBackground(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.getBorder(context)),
                  ),
                  onChanged: (v) => config.setOrganizePrompt(v),
                ),
              ],
            ),
          ),

          // LLM 服务提示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const MacosIcon(CupertinoIcons.info_circle,
                      size: 14, color: MacosColors.systemGrayColor),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(loc.organizeLlmHint,
                          style: AppTheme.caption(context))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => widget.onNavigateToTab(0),
                    child: Text(
                      loc.organizeGoConfig,
                      style: AppTheme.caption(context)
                          .copyWith(color: AppTheme.getAccent(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              loc.organizeDesc,
              style: AppTheme.caption(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 6. 闪念笔记
  // ---------------------------------------------------------------------------

  Widget _buildDiaryCard(AppLocalizations loc, ConfigService config) {
    return SettingsCard(
      title: loc.diaryMode,
      titleIcon: CupertinoIcons.book,
      accentColor: AppTheme.triggerNote,
      trailing: MacosSwitch(
        value: config.diaryEnabled,
        onChanged: (v) async {
          await config.setDiaryEnabled(v);
          if (v) {
            await _checkConflictOnEnable(
                'diary',
                config.diaryKeyCode,
                config.diaryKeyName,
                () async => config.setDiaryKey(0, ''));
            await _validateDiaryDirectory();
          }
          setState(() {});
        },
      ),
      children: [
        if (config.diaryEnabled) ...[
          // 目录权限警告横幅
          if (_diaryDirError == null || _diaryDirError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (_diaryDirError == null
                          ? MacosColors.systemOrangeColor
                          : MacosColors.systemRedColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (_diaryDirError == null
                            ? MacosColors.systemOrangeColor
                            : MacosColors.systemRedColor)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    MacosIcon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      size: 14,
                      color: _diaryDirError == null
                          ? MacosColors.systemOrangeColor
                          : MacosColors.systemRedColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _diaryDirError == null
                            ? '请点击右侧文件夹图标选择保存目录，以授权访问'
                            : _diaryDirError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _diaryDirError == null
                              ? MacosColors.systemOrangeColor
                              : MacosColors.systemRedColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          buildKeyCaptureTile(context, loc.pttMode,
              CupertinoIcons.keyboard_chevron_compact_down,
            isCapturing: _isCapturingDiaryKey,
            keyName: _diaryKeyName,
            onEdit: () => _startKeyCapture('diary'),
            onClear: _diaryKeyName.isNotEmpty
                ? () async {
                    await config.clearDiaryKey();
                    setState(() => _diaryKeyName = '');
                  }
                : null,
          ),
          const SettingsDivider(),
          buildKeyCaptureTile(
              context, loc.toggleModeTip, CupertinoIcons.book,
            isCapturing: _isCapturingToggleDiaryKey,
            keyName: _toggleDiaryKeyName,
            onEdit: () => _startKeyCapture('toggleDiary'),
            onClear: () async {
              await config.clearToggleDiaryKey();
              setState(() => _toggleDiaryKeyName = '');
            },
          ),
          const SettingsDivider(),
          SettingsTile(
            label: loc.diaryPath,
            icon: CupertinoIcons.folder,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    config.diaryDirectory.split('/').last,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption(context),
                    maxLines: 1,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 8),
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.folder_open),
                  onPressed: _pickDiaryFolder,
                ),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '语音记录闪念灵感，自动保存到指定目录。',
              style: AppTheme.caption(context),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. 快捷键一览
  // ---------------------------------------------------------------------------

  Widget _buildHotkeyOverview(AppLocalizations loc, ConfigService config) {
    final entries = <(String, String, bool)>[
      (loc.pttMode, config.pttKeyName, true),
      (loc.toggleModeTip, config.toggleInputKeyName, config.toggleInputEnabled),
      (loc.diaryMode, config.diaryKeyName, config.diaryEnabled),
      ('${loc.diaryMode}（Toggle）', config.toggleDiaryKeyName,
          config.toggleDiaryEnabled),
      (loc.quickTranslate, config.translateKeyName, config.translateEnabled),
      ('AI 梳理', config.organizeKeyName, config.organizeEnabled),
      ('纠错反馈', config.correctionKeyName, config.correctionEnabled),
    ];

    return SettingsCard(
      title: '全部快捷键一览',
      titleIcon: CupertinoIcons.keyboard,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SettingsDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    entries[i].$1,
                    style: AppTheme.body(context).copyWith(
                      color: entries[i].$3
                          ? null
                          : MacosColors.systemGrayColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        MacosColors.systemGrayColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entries[i].$2.isEmpty ? '未设置' : entries[i].$2,
                    style: AppTheme.mono(context).copyWith(
                      fontSize: 12,
                      color: entries[i].$2.isEmpty
                          ? MacosColors.systemGrayColor
                          : (entries[i].$3
                              ? null
                              : MacosColors.systemGrayColor),
                    ),
                  ),
                ),
                if (!entries[i].$3) ...[
                  const SizedBox(width: 6),
                  Text('已关闭',
                      style: AppTheme.caption(context)
                          .copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
