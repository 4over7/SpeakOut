import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../../config/distribution.dart';
import '../../../../services/app_service.dart';
import '../../../../services/config_backup_service.dart';
import '../../../../services/config_service.dart';
import '../../../theme.dart';
import '../../../widgets/settings_widgets.dart';

/// v1.8 Sidebar - 开发者选项页
///
/// 从原 about_tab 抽出：verbose log / log dir / models dir / gateway url
/// / diagnostics + 配置备份（导入/导出）。
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  String _modelsDir = '';
  bool _diagnosticsCopied = false;

  @override
  void initState() {
    super.initState();
    _loadModelsDir();
  }

  Future<void> _loadModelsDir() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      if (mounted) setState(() => _modelsDir = '${appSupport.path}/Models');
    } catch (_) {}
  }

  Future<void> _revealInFinder(String path) async {
    if (path.isEmpty) return;
    await Process.run('open', ['-R', path]);
  }

  String _shortenPath(String path, {int maxLen = 56}) {
    final normalized = path.replaceFirst(RegExp(r'^/Users/[^/]+'), '~');
    if (normalized.length <= maxLen) return normalized;
    const head = 16;
    final keepTail = maxLen - head - 3;
    return '${normalized.substring(0, head)}…${normalized.substring(normalized.length - keepTail)}';
  }

  Future<void> _copyDiagnostics() async {
    final info = await PackageInfo.fromPlatform();
    final buf = StringBuffer();
    buf.writeln('SpeakOut Diagnostics');
    buf.writeln('==========================');
    buf.writeln('App Version: ${info.version}+${info.buildNumber}');
    buf.writeln('Distribution: ${Distribution.channel}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('Locale: ${Platform.localeName}');
    buf.writeln('');
    buf.writeln('Config');
    buf.writeln('  workMode: ${ConfigService().workMode}');
    buf.writeln('  activeModelId: ${ConfigService().activeModelId}');
    buf.writeln('  inputLanguage: ${ConfigService().inputLanguage}');
    buf.writeln('  outputLanguage: ${ConfigService().outputLanguage}');
    buf.writeln('  aiCorrectionEnabled: ${ConfigService().aiCorrectionEnabled}');
    buf.writeln('  llmProviderType: ${ConfigService().llmProviderType}');
    buf.writeln('  verboseLogging: ${ConfigService().verboseLogging}');
    buf.writeln('');
    buf.writeln('Paths');
    buf.writeln('  modelsDir: $_modelsDir');
    buf.writeln('  logDir: ${ConfigService().logDirectory.isEmpty ? "(stdout only)" : ConfigService().logDirectory}');
    buf.writeln('  gatewayUrl: ${ConfigService.kDefaultGatewayUrl}');

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    setState(() => _diagnosticsCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _diagnosticsCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _buildDeveloperGroup(loc),
          const SizedBox(height: 12),
          _buildBackupGroup(loc),
        ],
      ),
    );
  }

  Widget _buildDeveloperGroup(AppLocalizations loc) {
    return SettingsGroup(
      title: loc.aboutDeveloper,
      children: [
        SettingsTile(
          label: loc.aboutVerboseLogging,
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
          label: loc.aboutLogDir,
          subtitle: ConfigService().logDirectory.isEmpty
              ? loc.aboutLogDirUnset
              : _shortenPath(ConfigService().logDirectory),
          icon: CupertinoIcons.folder,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.folder_badge_plus, size: 16),
                backgroundColor: MacosColors.transparent,
                onPressed: () async {
                  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: loc.aboutLogDir);
                  if (dir != null) {
                    await ConfigService().setLogDirectory(dir);
                    AppService().applyVerboseLogging();
                    setState(() {});
                  }
                },
              ),
              if (ConfigService().logDirectory.isNotEmpty)
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.xmark_circle, size: 16),
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
        const SettingsDivider(),
        SettingsTile(
          label: loc.aboutModelsDir,
          subtitle: _modelsDir.isEmpty ? loc.aboutLoading : _shortenPath(_modelsDir),
          icon: CupertinoIcons.cube_box,
          child: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.arrow_right_square, size: 16),
            backgroundColor: MacosColors.transparent,
            onPressed: _modelsDir.isEmpty ? null : () => _revealInFinder(_modelsDir),
          ),
        ),
        const SettingsDivider(),
        SettingsTile(
          label: loc.aboutGatewayUrl,
          subtitle: loc.aboutGatewayDesc,
          icon: CupertinoIcons.cloud,
          child: Text(
            ConfigService.kDefaultGatewayUrl.replaceFirst('https://', ''),
            style: AppTheme.caption(context).copyWith(
              color: MacosColors.systemGrayColor,
              fontFamily: 'SF Mono',
              fontSize: 10,
            ),
          ),
        ),
        const SettingsDivider(),
        SettingsTile(
          label: loc.aboutDiagnostics,
          subtitle: loc.aboutDiagnosticsDesc,
          icon: CupertinoIcons.ant,
          child: PushButton(
            controlSize: ControlSize.regular,
            color: _diagnosticsCopied ? MacosColors.systemGreenColor : null,
            secondary: !_diagnosticsCopied,
            onPressed: _copyDiagnostics,
            child: Text(
              _diagnosticsCopied ? loc.actionCopied : loc.actionCopy,
              style: TextStyle(color: _diagnosticsCopied ? Colors.white : null),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackupGroup(AppLocalizations loc) {
    return SettingsGroup(
      title: loc.aboutConfigBackup,
      children: [
        SettingsTile(
          label: loc.aboutExportConfig,
          subtitle: loc.aboutExportConfigDesc,
          icon: CupertinoIcons.arrow_up_doc,
          child: PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: () async {
              final path = await FilePicker.platform.saveFile(
                dialogTitle: loc.aboutExportFileTitle,
                fileName: 'speakout_config.json',
                allowedExtensions: ['json'],
                type: FileType.custom,
              );
              if (path != null) {
                final result = await ConfigBackupService.exportToFile(path);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(result.success
                        ? loc.aboutExportSuccess(result.message)
                        : loc.aboutExportFailed(result.error ?? '')),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            },
            child: Text(loc.aboutExportAction),
          ),
        ),
        const SettingsDivider(),
        SettingsTile(
          label: loc.aboutImportConfig,
          subtitle: loc.aboutImportConfigDesc,
          icon: CupertinoIcons.arrow_down_doc,
          child: PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                dialogTitle: loc.aboutImportFileTitle,
                allowedExtensions: ['json'],
                type: FileType.custom,
              );
              if (result != null && result.files.single.path != null) {
                final importResult = await ConfigBackupService.importFromFile(result.files.single.path!);
                if (context.mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(importResult.success
                        ? loc.aboutImportSuccess(importResult.message)
                        : loc.aboutImportFailed(importResult.error ?? '')),
                    backgroundColor: importResult.success ? MacosColors.systemGreenColor : null,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            },
            child: Text(loc.aboutImportAction),
          ),
        ),
      ],
    );
  }
}
