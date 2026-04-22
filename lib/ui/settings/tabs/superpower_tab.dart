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
import '../sidebar/hotkey_recorder_modal.dart';

/// Which subset of superpower_tab to render.
/// `all` — legacy 5-tab settings page (默认, 5 卡 + hotkey overview).
/// 其余 — v1.8 sidebar 下的单个超能力独立页.
enum SuperpowerView { all, diary, organize, translate, correction, aiReport }

/// "超能力" tab — 4 independent features as a dual-column card grid:
/// 闪念笔记 / AI 梳理 / 即时翻译 / 纠错反馈
class SuperpowerTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;
  final SuperpowerView viewFilter;

  const SuperpowerTab({
    super.key,
    required this.onNavigateToTab,
    this.viewFilter = SuperpowerView.all,
  });

  @override
  State<SuperpowerTab> createState() => _SuperpowerTabState();
}

class _SuperpowerTabState extends State<SuperpowerTab> {
  // ---------------------------------------------------------------------------
  // State variables
  // ---------------------------------------------------------------------------

  // Diary
  String _diaryKeyName = 'Right Option';
  String _toggleDiaryKeyName = '';
  String? _diaryDirError;

  // Organize
  late final TextEditingController _organizePromptController;
  bool _showOrganizePrompt = false;

  // AI Report
  int _bindingAiReportSlot = -1; // -1 = not binding

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
  // Key capture（使用热键 modal）
  // ---------------------------------------------------------------------------

  /// disabled 状态下的 hero 视觉：大 icon + 标题 + 说明。
  /// 旧 5-tab (viewFilter=all) 下保持短 desc（grid 空间小）。
  Widget _buildDisabledHero({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    if (widget.viewFilter == SuperpowerView.all) {
      return Text(desc, style: AppTheme.caption(context));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: MacosIcon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.getTextSecondary(context),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _hotkeyRecorderLabels(String target, AppLocalizations loc) {
    switch (target) {
      case 'diary':
        return (loc.hotkeyRecordDiary, loc.hotkeyRecordDiaryHint);
      case 'toggleDiary':
        return (loc.hotkeyRecordToggleDiary, loc.hotkeyRecordToggleDiaryHint);
      case 'organize':
        return (loc.hotkeyRecordOrganize, loc.hotkeyRecordOrganizeHint);
      case 'translate':
        return (loc.hotkeyRecordTranslate, loc.hotkeyRecordTranslateHint);
      case 'correction':
        return (loc.hotkeyRecordCorrection, loc.hotkeyRecordCorrectionHint);
      case 'aiReport':
        return (loc.hotkeyRecordAiReport, loc.hotkeyRecordAiReportHint);
      default:
        return (loc.hotkeyModalTitle, loc.hotkeyModalSubtitle);
    }
  }

  Future<void> _startKeyCapture(String target) async {
    final loc = AppLocalizations.of(context)!;
    final labels = _hotkeyRecorderLabels(target, loc);
    final result = await showHotkeyRecorder(context, title: labels.$1, subtitle: labels.$2);
    if (result == null || !mounted) return;

    final config = ConfigService();
    final keyCode = result.keyCode;
    final mods = result.modifiers;
    final displayName = result.displayName;
    // aiReport 存储为裸键（忽略修饰键），其他都带修饰键
    final keyName = mapKeyCodeToString(keyCode);

    // 冲突检查
    final activeKeys = getActiveHotkeys(context, excludeFeature: target);
    final isDiaryGroup = target == 'diary' || target == 'toggleDiary';
    if (isDiaryGroup) {
      if (target == 'diary') activeKeys.remove((config.toggleDiaryKeyCode, config.toggleDiaryModifiers));
      if (target == 'toggleDiary') activeKeys.remove((config.diaryKeyCode, config.diaryModifiers));
    }
    final hotkeyId = target == 'aiReport' ? (keyCode, 0) : (keyCode, mods);
    final conflict = findHotkeyConflict(activeKeys, hotkeyId);
    if (conflict != null) {
      if (mounted) _showHotkeyInUseDialog(displayName, conflict);
      return;
    }

    // Feature-specific saving
    switch (target) {
      case 'aiReport':
        await config.setAiReportBaseKey(keyCode, keyName);
      case 'correction':
        await config.setCorrectionKey(keyCode, displayName, modifiers: mods);
      case 'translate':
        await config.setTranslateKey(keyCode, displayName, modifiers: mods);
      case 'organize':
        await config.setOrganizeKey(keyCode, displayName, modifiers: mods);
      case 'toggleDiary':
        await config.setToggleDiaryKey(keyCode, displayName, modifiers: mods);
        if (mounted) setState(() => _toggleDiaryKeyName = displayName);
        return;
      case 'diary':
        await config.setDiaryKey(keyCode, displayName, modifiers: mods);
        if (mounted) setState(() => _diaryKeyName = displayName);
        return;
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Conflict dialogs
  // ---------------------------------------------------------------------------

  /// 统一的冲突弹窗：标题和消息都基于真实冲突的功能名
  void _showHotkeyInUseDialog(String keyName, String conflictFeature) {
    final loc = AppLocalizations.of(context)!;
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
            size: 48, color: Colors.orange),
        title: Text(loc.hotkeyInUseTitle(keyName, conflictFeature),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        message: Text(loc.hotkeyConflictTaken),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: Text(loc.hotkeyInUseOk),
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
        final loc = AppLocalizations.of(context)!;
        showMacosAlertDialog(
          context: context,
          builder: (_) => MacosAlertDialog(
            appIcon: const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: Colors.orange),
            title: Text(loc.hotkeyConflictAutoClearTitle(keyName, conflictWith),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            message: Text(loc.hotkeyConflictAutoClearMsg),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: Text(loc.hotkeyInUseOk),
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
      setState(() => _diaryDirError = AppLocalizations.of(context)!.diaryDirNotSet);
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
      setState(() => _diaryDirError = AppLocalizations.of(context)!.diaryDirCannotWrite);
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

    // v1.8 sidebar single-card views
    Widget? single;
    switch (widget.viewFilter) {
      case SuperpowerView.diary:
        single = _buildDiaryCard(loc);
      case SuperpowerView.organize:
        single = _buildOrganizeCard(loc);
      case SuperpowerView.translate:
        single = _buildTranslateCard(loc);
      case SuperpowerView.correction:
        single = _buildCorrectionCard(loc);
      case SuperpowerView.aiReport:
        single = _buildAiReportCard(loc);
      case SuperpowerView.all:
        single = null;
    }
    if (single != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: single,
      );
    }

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
    final showTitle = widget.viewFilter == SuperpowerView.all;
    return SettingsCard(
      minHeight: showTitle ? 100 : null,
      title: showTitle ? loc.diaryMode : null,
      titleIcon: showTitle ? CupertinoIcons.book : null,
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
                            ? loc.diaryDirPick
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
              isCapturing: false,
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
              isCapturing: false,
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
          _buildDisabledHero(
            icon: CupertinoIcons.book,
            iconColor: AppTheme.triggerNote,
            title: loc.diaryMode,
            desc: loc.diaryDesc,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. AI 梳理
  // ---------------------------------------------------------------------------

  Widget _buildOrganizeCard(AppLocalizations loc) {
    final config = ConfigService();
    final showTitle = widget.viewFilter == SuperpowerView.all;
    return SettingsCard(
      minHeight: showTitle ? 100 : null,
      title: showTitle ? loc.organizeEnabled : null,
      titleIcon: showTitle ? CupertinoIcons.text_alignleft : null,
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
              isCapturing: false,
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
                    _showOrganizePrompt ? loc.organizeCollapse : loc.organizeEditInstruction,
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
          _buildDisabledHero(
            icon: CupertinoIcons.text_alignleft,
            iconColor: AppTheme.triggerOrganize,
            title: loc.organizeEnabled,
            desc: loc.organizeDesc,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. 即时翻译
  // ---------------------------------------------------------------------------

  Widget _buildTranslateCard(AppLocalizations loc) {
    final config = ConfigService();
    final showTitle = widget.viewFilter == SuperpowerView.all;
    return SettingsCard(
      minHeight: showTitle ? 100 : null,
      title: showTitle ? loc.quickTranslate : null,
      titleIcon: showTitle ? CupertinoIcons.globe : null,
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
              isCapturing: false,
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
          _buildDisabledHero(
            icon: CupertinoIcons.globe,
            iconColor: AppTheme.triggerTranslate,
            title: loc.quickTranslate,
            desc: loc.quickTranslateDesc,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. 纠错反馈
  // ---------------------------------------------------------------------------

  Widget _buildCorrectionCard(AppLocalizations loc) {
    final config = ConfigService();
    final showTitle = widget.viewFilter == SuperpowerView.all;
    return SettingsCard(
      minHeight: showTitle ? 100 : null,
      title: showTitle ? loc.sidebarCorrection : null,
      titleIcon: showTitle ? CupertinoIcons.checkmark_seal : null,
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
            loc.correctionHotkey,
            _hotkeyBadge(
              config.correctionKeyName,
              isCapturing: false,
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
                    dialogTitle: loc.correctionExportDialog,
                    fileName: 'speakout_corrections.jsonl',
                  );
                  if (result != null) {
                    final ok = await CorrectionService().exportData(result);
                    if (mounted) {
                      showSettingsInfo(ok ? loc.correctionExportSuccess : loc.correctionExportFailedEmpty);
                    }
                  }
                },
                child: Text(loc.correctionExportBtn, style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              PushButton(
                controlSize: ControlSize.mini,
                secondary: true,
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    dialogTitle: loc.correctionImportDialog,
                    type: FileType.custom,
                    allowedExtensions: ['jsonl', 'json'],
                  );
                  if (result != null &&
                      result.files.single.path != null) {
                    final count = await CorrectionService()
                        .importData(result.files.single.path!);
                    if (mounted) {
                      showSettingsInfo(loc.correctionImportSuccess(count));
                    }
                  }
                },
                child: Text(loc.correctionImportBtn, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ] else
          _buildDisabledHero(
            icon: CupertinoIcons.checkmark_seal,
            iconColor: AppTheme.triggerCorrect,
            title: loc.sidebarCorrection,
            desc: loc.correctionDesc,
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
    final showTitle = widget.viewFilter == SuperpowerView.all;
    return SettingsCard(
      minHeight: showTitle ? 100 : null,
      title: showTitle ? loc.sidebarAiReport : null,
      titleIcon: showTitle ? CupertinoIcons.camera_viewfinder : null,
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
            loc.aiReportBaseKey,
            _hotkeyBadge(
              baseKeyName,
              isCapturing: false,
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
                loc.aiReportBaseKeyDesc(baseKeyName, slotCount),
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
                    slotCount == 0 ? loc.aiReportAddFirstWindow : loc.aiReportAddWindow,
                    style: AppTheme.caption(context).copyWith(color: AppTheme.triggerAiReport, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            loc.aiReportDescShort,
            style: AppTheme.caption(context).copyWith(fontSize: 10),
          ),
        ] else
          _buildDisabledHero(
            icon: CupertinoIcons.camera_viewfinder,
            iconColor: AppTheme.triggerAiReport,
            title: loc.sidebarAiReport,
            desc: loc.aiReportDescLong,
          ),
      ],
    );
  }

  /// 单个槽位行：[#N] App名 — 窗口标题 [绑定] [删除]
  Widget _buildAiReportSlotRow(int index) {
    final loc = AppLocalizations.of(context)!;
    final config = ConfigService();
    final appName = config.aiReportSlotAppName(index);
    final windowTitle = config.aiReportSlotWindowTitle(index);
    final isBinding = _bindingAiReportSlot == index;
    final slotCount = config.aiReportSlotCount;

    // 显示文本：App名 — 窗口标题
    String displayText;
    if (isBinding) {
      displayText = loc.aiReportSwitchWindow;
    } else if (appName != null && appName.isNotEmpty) {
      displayText = appName;
      if (windowTitle != null && windowTitle.isNotEmpty) {
        displayText += ' — $windowTitle';
      }
    } else {
      displayText = loc.aiReportUnbound;
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
    final loc = AppLocalizations.of(context)!;

    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.camera_viewfinder,
            size: 48, color: Color(0xFFE74C3C)),
        title: Text(loc.aiReportBindTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        message: Text(loc.aiReportBindMsg),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: Text(loc.aiReportStart),
          onPressed: () {
            Navigator.of(context).pop();
            _doSlotBind(slotIndex);
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: Text(loc.aiReportCancel),
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
      (loc.organizeEnabled, config.organizeKeyName, config.organizeEnabled),
      (loc.featureCorrection, config.correctionKeyName, config.correctionEnabled),
      if (config.aiReportSlotCount > 0)
        (loc.featureAiReport, config.aiReportBaseKeyName, config.aiReportEnabled),
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
              Text(loc.activeHotkeys, style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
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
