import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
    } catch (_) {}
  }


  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main switch
        SettingsCard(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('📚', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(loc.vocabEnhancement, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                MacosSwitch(
                  value: _vocabEnabled,
                  onChanged: (v) async {
                    await ConfigService().setVocabEnabled(v);
                    setState(() => _vocabEnabled = v);
                  },
                ),
              ],
            ),
            if (_vocabEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(loc.vocabEnabledNote, style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor)),
              ),
          ],
        ),

        if (_vocabEnabled) ...[
          const SizedBox(height: 10),

          // Dual column: Industry presets (left) | Custom vocab + info (right)
          SettingsCardGrid(
            spacing: 10,
            runSpacing: 10,
            children: [
              // Left: Industry presets
              SettingsCard(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(loc.vocabIndustryPresets, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 8),
                  _buildCompactPackRow('tech', loc.vocabTech, CupertinoIcons.desktopcomputer),
                  _buildCompactPackRow('medical', loc.vocabMedical, CupertinoIcons.heart),
                  _buildCompactPackRow('legal', loc.vocabLegal, CupertinoIcons.book),
                  _buildCompactPackRow('finance', loc.vocabFinance, CupertinoIcons.chart_bar),
                  _buildCompactPackRow('education', loc.vocabEducation, CupertinoIcons.book_circle),
                ],
              ),

              // Right: Custom vocab + matrix info
              SettingsCard(
                padding: const EdgeInsets.all(12),
                children: [
                  // Custom vocab header + toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(loc.vocabCustomVocab, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                      MacosSwitch(
                        value: _userEnabled,
                        onChanged: (v) async {
                          await ConfigService().setVocabUserEnabled(v);
                          setState(() => _userEnabled = v);
                        },
                      ),
                    ],
                  ),
                  if (_userEnabled) ...[
                    const SizedBox(height: 6),
                    if (_userEntries.isEmpty)
                      Text('尚无自定义词条', style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor, fontSize: 11))
                    else
                      ...List.generate(_userEntries.length, (idx) {
                        final entry = _userEntries[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(children: [
                            Expanded(child: Text(
                              entry.wrong.isNotEmpty ? '${entry.wrong} → ${entry.correct}' : entry.correct,
                              style: AppTheme.body(context).copyWith(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            )),
                            GestureDetector(
                              onTap: () => _deleteEntry(idx),
                              child: const MacosIcon(CupertinoIcons.xmark_circle, color: MacosColors.systemRedColor, size: 14),
                            ),
                          ]),
                        );
                      }),
                    const SizedBox(height: 6),
                    Row(children: [
                      GestureDetector(
                        onTap: _showAddEntryDialog,
                        child: Text(loc.vocabAddEntry, style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _importTsv,
                        child: Text(loc.vocabImportTsv, style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
                      ),
                      if (_userEntries.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _exportTsv,
                          child: Text(loc.vocabExportTsv, style: TextStyle(fontSize: 11, color: AppTheme.getAccent(context))),
                        ),
                      ],
                    ]),
                  ],
                  // Matrix info
                  Divider(height: 16, color: AppTheme.getBorder(context)),
                  Text(
                    'AI 润色 ✓ + 词典 ✓ → 术语注入 LLM\n'
                    'AI 润色 ✓ + 词典 ✗ → 纯 LLM 润色\n'
                    'AI 润色 ✗ + 词典 ✓ → 精确替换（离线）\n'
                    'AI 润色 ✗ + 词典 ✗ → 原始 ASR 输出',
                    style: AppTheme.caption(context).copyWith(fontSize: 10, color: MacosColors.systemGrayColor, height: 1.5),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCompactPackRow(String id, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          MacosIcon(icon, size: 14, color: MacosColors.systemGrayColor),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTheme.body(context).copyWith(fontSize: 12))),
          MacosSwitch(
            value: _packEnabled[id] ?? false,
            onChanged: (v) => _setPackEnabled(id, v),
          ),
        ],
      ),
    );
  }

}
