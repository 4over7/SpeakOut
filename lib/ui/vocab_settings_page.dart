import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../services/config_service.dart';
import '../services/vocab_service.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'theme.dart';
import 'widgets/settings_widgets.dart';

class VocabSettingsView extends StatefulWidget {
  const VocabSettingsView({super.key});

  @override
  State<VocabSettingsView> createState() => _VocabSettingsViewState();
}

class _VocabSettingsViewState extends State<VocabSettingsView> {
  late bool _vocabEnabled;
  late Map<String, bool> _packEnabled;
  late bool _userEnabled;
  List<VocabEntry> _userEntries = [];
  late bool _phoneticEnabled;
  late double _phoneticThreshold;

  @override
  void initState() {
    super.initState();
    final config = ConfigService();
    _vocabEnabled = config.vocabEnabled;
    _userEnabled = config.vocabUserEnabled;
    _packEnabled = {
      'tech': config.vocabTechEnabled,
      'medical': config.vocabMedicalEnabled,
      'legal': config.vocabLegalEnabled,
      'finance': config.vocabFinanceEnabled,
      'education': config.vocabEducationEnabled,
    };
    _userEntries = List.from(VocabService().userEntries);
    _phoneticEnabled = config.vocabPhoneticEnabled;
    _phoneticThreshold = config.vocabPhoneticThreshold;

    VocabService().ensurePacksLoaded();
  }

  Future<void> _setPackEnabled(String id, bool value) async {
    final config = ConfigService();
    switch (id) {
      case 'tech': await config.setVocabTechEnabled(value);
      case 'medical': await config.setVocabMedicalEnabled(value);
      case 'legal': await config.setVocabLegalEnabled(value);
      case 'finance': await config.setVocabFinanceEnabled(value);
      case 'education': await config.setVocabEducationEnabled(value);
    }
    setState(() => _packEnabled[id] = value);
  }

  Future<void> _showAddEntryDialog() async {
    final loc = AppLocalizations.of(context)!;
    final wrongCtrl = TextEditingController();
    final correctCtrl = TextEditingController();

    final confirmed = await showMacosAlertDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.textformat_abc_dottedunderline, size: 48),
          title: Text(loc.vocabAddEntry),
          message: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.vocabWrongForm, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              MacosTextField(controller: wrongCtrl, placeholder: "按装"),
              const SizedBox(height: 12),
              Text(loc.vocabCorrectForm, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              MacosTextField(controller: correctCtrl, placeholder: "安装"),
            ],
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.vocabAddEntry),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    final wrong = wrongCtrl.text.trim();
    final correct = correctCtrl.text.trim();
    if (correct.isEmpty) return;

    await VocabService().addUserEntry(VocabEntry(wrong: wrong, correct: correct));
    setState(() {
      _userEntries = List.from(VocabService().userEntries);
    });
  }

  Future<void> _deleteEntry(int index) async {
    await VocabService().deleteUserEntry(index);
    setState(() {
      _userEntries = List.from(VocabService().userEntries);
    });
  }

  Future<void> _importTsv() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tsv', 'csv', 'txt'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final lines = content.split(RegExp(r'\r?\n'));

      int count = 0;
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        // Support both tab and comma as separator
        final parts = line.contains('\t') ? line.split('\t') : line.split(',');
        if (parts.length < 2) continue;
        final wrong = parts[0].trim();
        final correct = parts[1].trim();
        if (correct.isEmpty) continue;
        await VocabService().addUserEntry(VocabEntry(wrong: wrong, correct: correct));
        count++;
      }

      setState(() {
        _userEntries = List.from(VocabService().userEntries);
      });

      if (mounted) {
        // ignore: use_build_context_synchronously
        showMacosAlertDialog(
          context: context,
          builder: (ctx) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.checkmark_circle, size: 48),
            title: Text(loc.vocabImportSuccess(count)),
            message: const SizedBox.shrink(),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        showMacosAlertDialog(
          context: context,
          builder: (ctx) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.xmark_circle, size: 48),
            title: Text(loc.vocabImportFailed('$e')),
            message: const SizedBox.shrink(),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportTsv() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Vocab Entries',
        fileName: 'vocab_entries.tsv',
        allowedExtensions: ['tsv'],
        type: FileType.custom,
      );
      if (result == null) return;

      final buffer = StringBuffer();
      for (final entry in _userEntries) {
        buffer.writeln('${entry.wrong}\t${entry.correct}');
      }
      await File(result).writeAsString(buffer.toString());
    } catch (_) {
      // ignore export errors silently
    }
  }

  Widget _buildBetaTag() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: MacosColors.systemOrangeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.5)),
      ),
      child: const Text(
        'Beta',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: MacosColors.systemOrangeColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总开关
        SettingsGroup(
          title: loc.vocabEnhancement,
          children: [
            SettingsTile(
              label: loc.vocabEnabled,
              icon: CupertinoIcons.textformat_abc_dottedunderline,
              trailing: _buildBetaTag(),
              child: MacosSwitch(
                value: _vocabEnabled,
                onChanged: (v) async {
                  await ConfigService().setVocabEnabled(v);
                  setState(() => _vocabEnabled = v);
                },
              ),
            ),
            if (_vocabEnabled) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 8),
                child: Text(
                  loc.vocabEnabledNote,
                  style: AppTheme.caption(context).copyWith(
                    color: MacosColors.systemGrayColor,
                  ),
                ),
              ),
            ],
          ],
        ),

        if (_vocabEnabled) ...[
          const SizedBox(height: 24),

          // 音近匹配 Phase 2
          SettingsGroup(
            title: loc.vocabPhoneticMatching,
            children: [
              SettingsTile(
                label: loc.vocabPhoneticEnabled,
                icon: CupertinoIcons.waveform,
                trailing: _buildBetaTag(),
                child: MacosSwitch(
                  value: _phoneticEnabled,
                  onChanged: (v) async {
                    await ConfigService().setVocabPhoneticEnabled(v);
                    VocabService().invalidatePinyinCache();
                    setState(() => _phoneticEnabled = v);
                  },
                ),
              ),
              if (_phoneticEnabled) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 4),
                  child: Text(
                    loc.vocabPhoneticEnabledNote,
                    style: AppTheme.caption(context).copyWith(
                      color: MacosColors.systemGrayColor,
                    ),
                  ),
                ),
                const SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const MacosIcon(CupertinoIcons.slider_horizontal_3, size: 16),
                          const SizedBox(width: 8),
                          Text(loc.vocabPhoneticThreshold, style: AppTheme.body(context)),
                          const Spacer(),
                          Text(
                            _phoneticThreshold.toStringAsFixed(1),
                            style: AppTheme.caption(context),
                          ),
                        ],
                      ),
                      MacosSlider(
                        value: _phoneticThreshold,
                        min: 1.0,
                        max: 3.0,
                        onChanged: (v) async {
                          await ConfigService().setVocabPhoneticThreshold(v);
                          setState(() => _phoneticThreshold = v);
                        },
                      ),
                      Text(
                        loc.vocabPhoneticThresholdNote,
                        style: AppTheme.caption(context).copyWith(
                          color: MacosColors.systemGrayColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // 行业预设
          SettingsGroup(
            title: loc.vocabIndustryPresets,
            children: [
              _buildPackTile('tech', loc.vocabTech, CupertinoIcons.desktopcomputer),
              const SettingsDivider(),
              _buildPackTile('medical', loc.vocabMedical, CupertinoIcons.heart),
              const SettingsDivider(),
              _buildPackTile('legal', loc.vocabLegal, CupertinoIcons.book),
              const SettingsDivider(),
              _buildPackTile('finance', loc.vocabFinance, CupertinoIcons.chart_bar),
              const SettingsDivider(),
              _buildPackTile('education', loc.vocabEducation, CupertinoIcons.book_circle),
            ],
          ),

          const SizedBox(height: 24),

          // 自定义词条
          SettingsGroup(
            title: loc.vocabCustomVocab,
            children: [
              SettingsTile(
                label: loc.vocabEnabled,
                icon: CupertinoIcons.person_crop_square,
                child: MacosSwitch(
                  value: _userEnabled,
                  onChanged: (v) async {
                    await ConfigService().setVocabUserEnabled(v);
                    setState(() => _userEnabled = v);
                  },
                ),
              ),
              if (_userEnabled) ...[
              const SettingsDivider(),
              if (_userEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '尚无自定义词条',
                    style: AppTheme.caption(context).copyWith(
                      color: MacosColors.systemGrayColor,
                    ),
                  ),
                )
              else
                ..._userEntries.asMap().entries.map((e) {
                  final idx = e.key;
                  final entry = e.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (entry.wrong.isNotEmpty)
                                    Text(
                                      '${entry.wrong} → ${entry.correct}',
                                      style: AppTheme.body(context),
                                    )
                                  else
                                    Text(
                                      entry.correct,
                                      style: AppTheme.body(context),
                                    ),
                                ],
                              ),
                            ),
                            MacosIconButton(
                              icon: const MacosIcon(
                                CupertinoIcons.trash,
                                color: MacosColors.systemRedColor,
                                size: 16,
                              ),
                              backgroundColor: MacosColors.transparent,
                              onPressed: () => _deleteEntry(idx),
                            ),
                          ],
                        ),
                      ),
                      if (idx < _userEntries.length - 1) const SettingsDivider(),
                    ],
                  );
                }),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    PushButton(
                      controlSize: ControlSize.regular,
                      onPressed: _showAddEntryDialog,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MacosIcon(CupertinoIcons.plus, size: 14),
                          const SizedBox(width: 6),
                          Text(loc.vocabAddEntry),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.regular,
                      secondary: true,
                      onPressed: _importTsv,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MacosIcon(CupertinoIcons.arrow_down_doc, size: 14),
                          const SizedBox(width: 6),
                          Text(loc.vocabImportTsv),
                        ],
                      ),
                    ),
                    if (_userEntries.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      PushButton(
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: _exportTsv,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MacosIcon(CupertinoIcons.arrow_up_doc, size: 14),
                            const SizedBox(width: 6),
                            Text(loc.vocabExportTsv),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ], // end if (_userEnabled)
            ],
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPackTile(String id, String label, IconData icon) {
    return SettingsTile(
      label: label,
      icon: icon,
      child: MacosSwitch(
        value: _packEnabled[id] ?? false,
        onChanged: (v) => _setPackEnabled(id, v),
      ),
    );
  }
}
