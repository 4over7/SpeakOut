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
  bool _isExportingLog = false;

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

  /// 一键导出日志包：zip 内含
  /// - syslog.log（`log show --process SpeakOut --last 10m`）
  /// - app-logs/（ConfigService.logDirectory 下的 .log 文件，如有）
  /// - diagnostics.txt（版本/配置/路径）
  Future<void> _exportLogBundle(AppLocalizations loc) async {
    if (_isExportingLog) return;
    setState(() => _isExportingLog = true);
    Directory? tempDir;
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: loc.aboutSystemLogFileTitle,
        fileName: 'speakout-logs-$timestamp.zip',
        allowedExtensions: ['zip'],
        type: FileType.custom,
      );
      if (path == null) {
        if (mounted) setState(() => _isExportingLog = false);
        return;
      }

      tempDir = Directory.systemTemp.createTempSync('speakout_logs_');

      // 1. syslog
      final syslogResult = await Process.run('log', [
        'show', '--process', 'SpeakOut', '--last', '10m', '--info', '--debug',
      ]);
      await File('${tempDir.path}/syslog.log').writeAsString(
        syslogResult.exitCode == 0
            ? syslogResult.stdout.toString()
            : '[log show failed: ${syslogResult.stderr}]',
      );

      // 2. 应用详细日志目录（如果用户设了）
      final logDir = ConfigService().logDirectory;
      if (logDir.isNotEmpty && Directory(logDir).existsSync()) {
        final appLogsDest = Directory('${tempDir.path}/app-logs');
        appLogsDest.createSync();
        for (final entity in Directory(logDir).listSync()) {
          if (entity is File && entity.path.endsWith('.log')) {
            final name = entity.uri.pathSegments.last;
            await entity.copy('${appLogsDest.path}/$name');
          }
        }
      }

      // 3. diagnostics
      await File('${tempDir.path}/diagnostics.txt').writeAsString(await _buildDiagnostics());

      // 4. 打包
      final zipPath = path.endsWith('.zip') ? path : '$path.zip';
      if (File(zipPath).existsSync()) File(zipPath).deleteSync();
      final dittoResult = await Process.run('ditto', [
        '-c', '-k', '--sequesterRsrc', '--keepParent',
        tempDir.path, zipPath,
      ]);
      if (dittoResult.exitCode != 0) {
        throw Exception('ditto failed: ${dittoResult.stderr}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(loc.aboutSystemLogSuccess(zipPath)),
        backgroundColor: MacosColors.systemGreenColor,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(loc.aboutSystemLogFailed('$e')),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      try {
        tempDir?.deleteSync(recursive: true);
      } catch (_) {}
      if (mounted) setState(() => _isExportingLog = false);
    }
  }

  Future<String> _buildDiagnostics() async {
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
    return buf.toString();
  }

  Future<void> _copyDiagnostics() async {
    final text = await _buildDiagnostics();
    await Clipboard.setData(ClipboardData(text: text));
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
          label: loc.aboutSystemLog,
          subtitle: loc.aboutSystemLogDesc,
          icon: CupertinoIcons.doc_text_search,
          child: PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: _isExportingLog ? null : () => _exportLogBundle(loc),
            child: _isExportingLog
                ? const SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator())
                : Text(loc.aboutSystemLogExport),
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
