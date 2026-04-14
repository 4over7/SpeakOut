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

/// "超能力" tab — 4 independent features as a dual-column card grid:
/// 闪念笔记 / AI 梳理 / 即时翻译 / 纠错反馈
class SuperpowerTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const SuperpowerTab({super.key, required this.onNavigateToTab});

  @override
  State<SuperpowerTab> createState() => _SuperpowerTabState();
}

class _SuperpowerTabState extends State<SuperpowerTab> {
  // ---------------------------------------------------------------------------
  // State variables
  // ---------------------------------------------------------------------------

  // Diary
  bool _isCapturingDiaryKey = false;
  String _diaryKeyName = 'Right Option';
  bool _isCapturingToggleDiaryKey = false;
  String _toggleDiaryKeyName = '';
  String? _diaryDirError;

  // Organize
  bool _isCapturingOrganizeKey = false;
  late final TextEditingController _organizePromptController;
  bool _showOrganizePrompt = false;

  // Translate
  bool _isCapturingTranslateKey = false;

  // Correction
  bool _isCapturingCorrectionKey = false;

  // AI Report
  bool _isCapturingAiReportBaseKey = false;
  int _bindingAiReportSlot = -1; // -1 = not binding

  // Key capture infrastructure
  HotkeyCapturer? _keyCapturer;
  final CoreEngine _engine = CoreEngine();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _organizePromptController = TextEditingController(
      text: ConfigService().organizePrompt,
    );
    _loadHotkeyConfig();
    // 页面加载时验证日记目录权限（避免已授权仍显示警告）
    if (ConfigService().diaryEnabled) {
      _validateDiaryDirectory();
    }
  }

  @override
  void dispose() {
    _keyCapturer?.cancel();
    _organizePromptController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Config loading
  // ---------------------------------------------------------------------------

  void _loadHotkeyConfig() {
    final config = ConfigService();
    setState(() {
      _diaryKeyName = config.diaryKeyName;
      _toggleDiaryKeyName = config.toggleDiaryKeyName;
    });
  }

  // ---------------------------------------------------------------------------
  // Key capture
  // ---------------------------------------------------------------------------

  void _startKeyCapture(String target) {
    _keyCapturer?.cancel();
    setState(() {
      switch (target) {
        case 'diary':
          _isCapturingDiaryKey = true;
        case 'toggleDiary':
          _isCapturingToggleDiaryKey = true;
        case 'organize':
          _isCapturingOrganizeKey = true;
        case 'translate':
          _isCapturingTranslateKey = true;
        case 'correction':
          _isCapturingCorrectionKey = true;
        case 'aiReport':
          _isCapturingAiReportBaseKey = true;
      }
    });

    _keyCapturer = HotkeyCapturer(
      keyStream: _engine.rawKeyEventStream,
      onCaptured: (keyCode, modifierFlags) {
        final keyName = mapKeyCodeToString(keyCode);
        _saveHotkeyConfig(keyCode, keyName, modifierFlags: modifierFlags);
        _resetCaptureState();
      },
      onTimeout: _resetCaptureState,
    )..start();
  }

  void _resetCaptureState() {
    if (mounted) {
      setState(() {
        _isCapturingDiaryKey = false;
        _isCapturingToggleDiaryKey = false;
        _isCapturingOrganizeKey = false;
        _isCapturingTranslateKey = false;
        _isCapturingCorrectionKey = false;
        _isCapturingAiReportBaseKey = false;
      });
    }
  }

  void _stopKeyCapture() {
    _keyCapturer?.cancel();
    _keyCapturer = null;
    _resetCaptureState();
  }

  // ---------------------------------------------------------------------------
  // Hotkey save with conflict detection
  // ---------------------------------------------------------------------------

  Future<void> _saveHotkeyConfig(int keyCode, String keyName,
      {int modifierFlags = 0}) async {
    final config = ConfigService();
    final isDiaryGroup = _isCapturingDiaryKey || _isCapturingToggleDiaryKey;

    final requiredMods = stripOwnModifier(keyCode, modifierFlags);
    final displayName =
        requiredMods != 0 ? comboKeyName(keyCode, requiredMods) : keyName;

    // Determine which feature is being captured
    final String currentFeature;
    if (_isCapturingAiReportBaseKey) {
      currentFeature = 'aiReport';
    } else if (_isCapturingCorrectionKey) {
      currentFeature = 'correction';
    } else if (_isCapturingTranslateKey) {
      currentFeature = 'translate';
    } else if (_isCapturingOrganizeKey) {
      currentFeature = 'organize';
    } else if (_isCapturingToggleDiaryKey) {
      currentFeature = 'toggleDiary';
    } else if (_isCapturingDiaryKey) {
      currentFeature = 'diary';
    } else {
      currentFeature = '';
    }

    // Unified conflict check using (keyCode, modifiers) tuple
    if (currentFeature.isNotEmpty) {
      final activeKeys = getActiveHotkeys(context, excludeFeature: currentFeature);
      // Diary group: also exclude the other diary key (diary ↔ toggleDiary can share)
      if (isDiaryGroup) {
        if (_isCapturingDiaryKey) activeKeys.remove((config.toggleDiaryKeyCode, config.toggleDiaryModifiers));
        if (_isCapturingToggleDiaryKey) activeKeys.remove((config.diaryKeyCode, config.diaryModifiers));
      }
      // AI Report base key stores and matches as bare key (modifiers=0),
      // so conflict check must also use (keyCode, 0) to match what's actually stored.
      final hotkeyId = _isCapturingAiReportBaseKey ? (keyCode, 0) : (keyCode, requiredMods);
      final conflict = findHotkeyConflict(activeKeys, hotkeyId);
      if (conflict != null) {
        _stopKeyCapture();
        _showHotkeyInUseDialog(displayName, conflict);
        return;
      }
    }

    // Feature-specific saving
    if (_isCapturingAiReportBaseKey) {
      // AI Report base key is a hold-to-record trigger — modifiers are intentionally
      // ignored (user needs free fingers for number keys). Save bare key name only.
      await config.setAiReportBaseKey(keyCode, keyName);
      setState(() => _isCapturingAiReportBaseKey = false);
    } else if (_isCapturingCorrectionKey) {
      await config.setCorrectionKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingCorrectionKey = false);
    } else if (_isCapturingTranslateKey) {
      await config.setTranslateKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingTranslateKey = false);
    } else if (_isCapturingOrganizeKey) {
      await config.setOrganizeKey(keyCode, displayName,
          modifiers: requiredMods);
      setState(() => _isCapturingOrganizeKey = false);
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
    }
  }

  // ---------------------------------------------------------------------------
  // Conflict dialogs
  // ---------------------------------------------------------------------------

  /// 统一的冲突弹窗：标题和消息都基于真实冲突的功能名
  void _showHotkeyInUseDialog(String keyName, String conflictFeature) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
            size: 48, color: Colors.orange),
        title: Text('$keyName 已被「$conflictFeature」使用',
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
      String keyName, Future<void> Function() clearKey, {int modifiers = 0}) async {
    if (keyCode == 0) return;
    final activeKeys = getActiveHotkeys(context, excludeFeature: feature);
    final hotkeyId = (keyCode, modifiers);
    final conflictWith = findHotkeyConflict(activeKeys, hotkeyId);
    if (conflictWith != null) {
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
  // Compact UI helpers
  // ---------------------------------------------------------------------------

  Widget _compactRow(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.body(context).copyWith(fontSize: 12)),
          trailing,
        ],
      ),
    );
  }

  Widget _hotkeyBadge(String keyName,
      {bool isCapturing = false,
      VoidCallback? onTap,
      VoidCallback? onClear}) =>
      hotkeyBadge(context, keyName,
          isCapturing: isCapturing, onTap: onTap, onClear: onClear);

  Widget _compactDivider() {
    return Divider(
      height: 12,
      color: MacosColors.separatorColor.withValues(alpha: 0.3),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          SettingsCardGrid(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildDiaryCard(loc),
              _buildOrganizeCard(loc),
              _buildTranslateCard(loc),
              _buildCorrectionCard(loc),
              _buildAiReportCard(loc),
            ],
          ),
          const SizedBox(height: 12),
          // Hotkey overview at bottom (full width)
          _buildHotkeyOverview(loc),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. 闪念笔记
  // ---------------------------------------------------------------------------

  Widget _buildDiaryCard(AppLocalizations loc) {
    final config = ConfigService();
    return SettingsCard(
      minHeight: 100,
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
                () async => config.setDiaryKey(0, ''),
                modifiers: config.diaryModifiers);
            await _validateDiaryDirectory();
          }
          setState(() {});
        },
      ),
      padding: const EdgeInsets.all(12),
      children: [
        if (config.diaryEnabled) ...[
          // Directory permission warning
          if (_diaryDirError == null || _diaryDirError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: (_diaryDirError == null
                          ? MacosColors.systemOrangeColor
                          : MacosColors.systemRedColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
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
                      size: 12,
                      color: _diaryDirError == null
                          ? MacosColors.systemOrangeColor
                          : MacosColors.systemRedColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _diaryDirError == null
                            ? '请选择保存目录以授权访问'
                            : _diaryDirError!,
                        style: TextStyle(
                          fontSize: 11,
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

          _compactRow(
            loc.pttMode,
            _hotkeyBadge(
              _diaryKeyName,
              isCapturing: _isCapturingDiaryKey,
              onTap: () => _startKeyCapture('diary'),
              onClear: _diaryKeyName.isEmpty ? null : () async {
                await ConfigService().clearDiaryKey();
                setState(() => _diaryKeyName = '');
              },
            ),
          ),
          const SizedBox(height: 6),
          _compactRow(
            loc.toggleModeTip,
            _hotkeyBadge(
              _toggleDiaryKeyName,
              isCapturing: _isCapturingToggleDiaryKey,
              onTap: () => _startKeyCapture('toggleDiary'),
              onClear: _toggleDiaryKeyName.isEmpty ? null : () async {
                await ConfigService().clearToggleDiaryKey();
                setState(() => _toggleDiaryKeyName = '');
              },
            ),
          ),
          _compactDivider(),
          _compactRow(
            loc.diaryPath,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    config.diaryDirectory.isEmpty
                        ? loc.notSet
                        : config.diaryDirectory.split('/').last,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption(context),
                    maxLines: 1,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _pickDiaryFolder,
                  child: MacosIcon(
                    CupertinoIcons.folder_open,
                    size: 14,
                    color: AppTheme.getAccent(context),
                  ),
                ),
              ],
            ),
          ),
        ] else
          Text(
            '随时随地语音记录灵感，自动保存为 Markdown 日记。',
            style: AppTheme.caption(context),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. AI 梳理
  // ---------------------------------------------------------------------------

  Widget _buildOrganizeCard(AppLocalizations loc) {
    final config = ConfigService();
    return SettingsCard(
      minHeight: 100,
      title: loc.organizeEnabled,
      titleIcon: CupertinoIcons.text_alignleft,
      accentColor: AppTheme.triggerOrganize,
      trailing: MacosSwitch(
        value: config.organizeEnabled,
        onChanged: (v) async {
          await config.setOrganizeEnabled(v);
          if (v) {
            await _checkConflictOnEnable('organize', config.organizeKeyCode,
                config.organizeKeyName, config.clearOrganizeKey,
                modifiers: config.organizeModifiers);
          }
          setState(() {});
        },
      ),
      padding: const EdgeInsets.all(12),
      children: [
        if (config.organizeEnabled) ...[
          _compactRow(
            loc.organizeHotkey,
            _hotkeyBadge(
              config.organizeKeyName,
              isCapturing: _isCapturingOrganizeKey,
              onTap: () => _startKeyCapture('organize'),
              onClear: config.organizeKeyName.isEmpty ? null : () async {
                await config.clearOrganizeKey();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 6),
          _compactRow(
            loc.organizePrompt,
            GestureDetector(
              onTap: () => setState(() => _showOrganizePrompt = !_showOrganizePrompt),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showOrganizePrompt ? '收起' : '编辑指令',
                    style: AppTheme.caption(context).copyWith(
                        color: AppTheme.triggerOrganize, fontSize: 11),
                  ),
                  const SizedBox(width: 2),
                  MacosIcon(
                    _showOrganizePrompt
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_right,
                    size: 10,
                    color: AppTheme.triggerOrganize,
                  ),
                ],
              ),
            ),
          ),
          // Collapsible prompt editor
          if (_showOrganizePrompt) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                        color: AppTheme.triggerOrganize, fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            MacosTextField(
              maxLines: 6,
              controller: _organizePromptController,
              style: const TextStyle(fontSize: 11),
              decoration: BoxDecoration(
                color: AppTheme.getInputBackground(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.getBorder(context)),
              ),
              onChanged: (v) => config.setOrganizePrompt(v),
            ),
          ],
          // LLM hint
          if (!_showOrganizePrompt) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                MacosIcon(CupertinoIcons.info_circle,
                    size: 11, color: MacosColors.systemGrayColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    loc.organizeLlmHint,
                    style: AppTheme.caption(context).copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => widget.onNavigateToTab(1),
                  child: Text(
                    loc.organizeGoConfig,
                    style: AppTheme.caption(context).copyWith(
                        color: AppTheme.getAccent(context), fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ] else
          Text(
            loc.organizeDesc,
            style: AppTheme.caption(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. 即时翻译
  // ---------------------------------------------------------------------------

  Widget _buildTranslateCard(AppLocalizations loc) {
    final config = ConfigService();
    return SettingsCard(
      minHeight: 100,
      title: loc.quickTranslate,
      titleIcon: CupertinoIcons.globe,
      accentColor: AppTheme.triggerTranslate,
      trailing: MacosSwitch(
        value: config.translateEnabled,
        onChanged: (v) async {
          await config.setTranslateEnabled(v);
          if (v) {
            await _checkConflictOnEnable('translate', config.translateKeyCode,
                config.translateKeyName, config.clearTranslateKey,
                modifiers: config.translateModifiers);
          }
          setState(() {});
        },
      ),
      padding: const EdgeInsets.all(12),
      children: [
        if (config.translateEnabled) ...[
          _compactRow(
            loc.translateHotkey,
            _hotkeyBadge(
              config.translateKeyName,
              isCapturing: _isCapturingTranslateKey,
              onTap: () => _startKeyCapture('translate'),
              onClear: config.translateKeyName.isEmpty ? null : () async {
                await config.clearTranslateKey();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 6),
          _compactRow(
            loc.translateTargetLanguage,
            MacosPopupButton<String>(
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
              }.entries.map((e) =>
                MacosPopupMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))
              ).toList(),
              onChanged: (v) async {
                if (v != null) {
                  await config.setTranslateTargetLanguage(v);
                  setState(() {});
                }
              },
            ),
          ),
          // LLM not configured warning
          if (resolveLlmApiKey().isEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const MacosIcon(CupertinoIcons.exclamationmark_triangle,
                    color: Colors.orange, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    loc.translateNoLlm,
                    style: AppTheme.caption(context)
                        .copyWith(color: Colors.orange, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ] else
          Text(
            loc.quickTranslateDesc,
            style: AppTheme.caption(context),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. 纠错反馈
  // ---------------------------------------------------------------------------

  Widget _buildCorrectionCard(AppLocalizations loc) {
    final config = ConfigService();
    return SettingsCard(
      minHeight: 100,
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
                config.clearCorrectionKey,
                modifiers: config.correctionModifiers);
          }
          setState(() {});
        },
      ),
      padding: const EdgeInsets.all(12),
      children: [
        if (config.correctionEnabled) ...[
          _compactRow(
            '纠错快捷键',
            _hotkeyBadge(
              config.correctionKeyName,
              isCapturing: _isCapturingCorrectionKey,
              onTap: () => _startKeyCapture('correction'),
              onClear: config.correctionKeyName.isEmpty ? null : () async {
                await config.clearCorrectionKey();
                setState(() {});
              },
            ),
          ),
          _compactDivider(),
          Row(
            children: [
              PushButton(
                controlSize: ControlSize.mini,
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
                child: const Text('导出', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              PushButton(
                controlSize: ControlSize.mini,
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
                child: const Text('导入', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ] else
          Text(
            '选中修正后的文字，一键提交纠错。ASR 自动学习你的用词习惯。',
            style: AppTheme.caption(context),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. AI 报告
  // ---------------------------------------------------------------------------

  Widget _buildAiReportCard(AppLocalizations loc) {
    final config = ConfigService();
    final slotCount = config.aiReportSlotCount;
    final baseKeyName = config.aiReportBaseKeyName;
    return SettingsCard(
      minHeight: 100,
      title: 'AI 一键调试',
      titleIcon: CupertinoIcons.camera_viewfinder,
      accentColor: AppTheme.triggerAiReport,
      trailing: MacosSwitch(
        value: config.aiReportEnabled,
        onChanged: (v) async {
          await config.setAiReportEnabled(v);
          setState(() {});
        },
      ),
      padding: const EdgeInsets.all(12),
      children: [
        if (config.aiReportEnabled) ...[
          // 基础按键
          _compactRow(
            '基础按键',
            _hotkeyBadge(
              baseKeyName,
              isCapturing: _isCapturingAiReportBaseKey,
              onTap: () => _startKeyCapture('aiReport'),
              onClear: baseKeyName.isEmpty ? null : () async {
                await config.clearAiReportBaseKey();
                setState(() {});
              },
            ),
          ),
          if (slotCount > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '按住 $baseKeyName + 数字键（1-$slotCount）选择目标窗口',
                style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor),
              ),
            ),
          _compactDivider(),
          // 窗口槽位列表
          for (int i = 0; i < slotCount; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _buildAiReportSlotRow(i),
          ],
          // 添加窗口
          if (slotCount < ConfigService.kMaxAiReportSlots) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                await config.setAiReportSlotCount(slotCount + 1);
                setState(() {});
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MacosIcon(CupertinoIcons.plus_circle, size: 13, color: AppTheme.triggerAiReport),
                  const SizedBox(width: 4),
                  Text(
                    slotCount == 0 ? '添加第一个窗口' : '添加窗口',
                    style: AppTheme.caption(context).copyWith(color: AppTheme.triggerAiReport, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '为 AI Coding 而生 — 截屏+语音自动发送到绑定窗口',
            style: AppTheme.caption(context).copyWith(fontSize: 10),
          ),
        ] else
          Text(
            '为 AI Coding 而生 — 截屏+语音描述，一键发送到 Claude Code / Cursor。',
            style: AppTheme.caption(context),
          ),
      ],
    );
  }

  /// 单个槽位行：[#N] App名 — 窗口标题 [绑定] [删除]
  Widget _buildAiReportSlotRow(int index) {
    final config = ConfigService();
    final appName = config.aiReportSlotAppName(index);
    final windowTitle = config.aiReportSlotWindowTitle(index);
    final isBinding = _bindingAiReportSlot == index;
    final slotCount = config.aiReportSlotCount;

    // 显示文本：App名 — 窗口标题
    String displayText;
    if (isBinding) {
      displayText = '请切换到目标窗口...';
    } else if (appName != null && appName.isNotEmpty) {
      displayText = appName;
      if (windowTitle != null && windowTitle.isNotEmpty) {
        displayText += ' — $windowTitle';
      }
    } else {
      displayText = '未绑定';
    }

    return Row(
      children: [
        // 槽位编号（多槽位时显示）
        if (slotCount > 1) ...[
          Container(
            width: 18, height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.triggerAiReport.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${index + 1}', style: AppTheme.mono(context).copyWith(fontSize: 10, color: AppTheme.triggerAiReport)),
          ),
          const SizedBox(width: 6),
        ],
        // 目标窗口
        Expanded(
          child: Text(
            displayText,
            style: AppTheme.caption(context).copyWith(
              fontSize: 11,
              color: (appName == null || appName.isEmpty) && !isBinding ? MacosColors.systemGrayColor : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        // 绑定按钮
        GestureDetector(
          onTap: isBinding ? null : () => _bindSlotTargetWindow(index),
          child: MacosIcon(CupertinoIcons.scope, size: 14, color: isBinding ? MacosColors.systemGrayColor : AppTheme.triggerAiReport),
        ),
        const SizedBox(width: 6),
        // 删除按钮
        GestureDetector(
          onTap: () async {
            await config.removeAiReportSlot(index);
            setState(() {});
          },
          child: MacosIcon(CupertinoIcons.minus_circle, size: 14, color: MacosColors.systemGrayColor),
        ),
      ],
    );
  }

  /// 绑定槽位目标窗口：3秒倒计时 → 读取前台 App
  Future<void> _bindSlotTargetWindow(int slotIndex) async {
    setState(() => _bindingAiReportSlot = slotIndex);

    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.camera_viewfinder,
            size: 48, color: Color(0xFFE74C3C)),
        title: const Text('绑定 AI 工具窗口',
            style: TextStyle(fontWeight: FontWeight.bold)),
        message: const Text('点击「开始」后，你有 3 秒时间切换到目标窗口。'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('开始'),
          onPressed: () {
            Navigator.of(context).pop();
            _doSlotBind(slotIndex);
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('取消'),
          onPressed: () {
            Navigator.of(context).pop();
            setState(() => _bindingAiReportSlot = -1);
          },
        ),
      ),
    );
  }

  Future<void> _doSlotBind(int slotIndex) async {
    await Future.delayed(const Duration(seconds: 3));
    try {
      final infoJson = _engine.nativeInput?.getFrontmostAppInfo() ?? '{}';
      final bundleIdMatch = RegExp(r'"bundleId":"([^"]*)"').firstMatch(infoJson);
      final nameMatch = RegExp(r'"name":"([^"]*)"').firstMatch(infoJson);
      final titleMatch = RegExp(r'"windowTitle":"((?:[^"\\]|\\.)*)"').firstMatch(infoJson);
      final bundleId = bundleIdMatch?.group(1) ?? '';
      final name = nameMatch?.group(1) ?? '';
      final title = titleMatch?.group(1) ?? '';
      if (bundleId.isNotEmpty && bundleId != 'com.speakout.speakout') {
        await ConfigService().setAiReportSlotTarget(slotIndex, bundleId, name, windowTitle: title);
        AppLog.d('[AIReport] Slot $slotIndex bound to: $name ($bundleId) "$title"');
      }
    } catch (e) {
      AppLog.d('[AIReport] Bind error: $e');
    }
    if (mounted) setState(() => _bindingAiReportSlot = -1);
  }

  // ---------------------------------------------------------------------------
  // Hotkey overview helpers
  // ---------------------------------------------------------------------------

  Widget _hotkeyOverviewItem((String, String, bool) entry) {
    return Row(
      children: [
        Expanded(
          child: Text(
            entry.$1,
            style: AppTheme.caption(context).copyWith(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: MacosColors.systemGrayColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            entry.$2,
            style: AppTheme.mono(context).copyWith(fontSize: 10),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hotkey overview (full-width, below grid)
  // ---------------------------------------------------------------------------

  Widget _buildHotkeyOverview(AppLocalizations loc) {
    final config = ConfigService();
    final entries = <(String, String, bool)>[
      ('${loc.diaryMode}（PTT）', config.diaryKeyName, config.diaryEnabled),
      ('${loc.diaryMode}（Toggle）', config.toggleDiaryKeyName,
          config.diaryEnabled && config.toggleDiaryEnabled),
      (loc.quickTranslate, config.translateKeyName, config.translateEnabled),
      ('AI 梳理', config.organizeKeyName, config.organizeEnabled),
      ('纠错反馈', config.correctionKeyName, config.correctionEnabled),
      if (config.aiReportSlotCount > 0)
        ('AI 一键调试', config.aiReportBaseKeyName, config.aiReportEnabled),
    ];

    final activeEntries = entries.where((e) => e.$3 && e.$2.isNotEmpty).toList();
    if (activeEntries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacosColors.systemGrayColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MacosIcon(CupertinoIcons.keyboard, size: 11, color: MacosColors.systemGrayColor),
              const SizedBox(width: 6),
              Text('已启用的快捷键', style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
            ],
          ),
          const SizedBox(height: 6),
          // 双列网格
          for (var i = 0; i < activeEntries.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
              child: Row(
                children: [
                  Expanded(child: _hotkeyOverviewItem(activeEntries[i])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < activeEntries.length
                        ? _hotkeyOverviewItem(activeEntries[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
