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
import '../../settings_shared.dart';
import '../../../../services/app_service.dart';
import '../../../../services/config_backup_service.dart';
import '../../../../services/config_service.dart';
import '../../../widgets/settings_widgets.dart';
import '../../../../services/notification_service.dart';

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
  int _redundantBytes = 0;
  bool _cleaningRedundant = false;
  bool _diagnosticsCopied = false;
  bool _isExportingLog = false;

  @override
  void initState() {
    super.initState();
    _loadModelsDir();
    _loadRedundant();
  }

  Future<void> _loadRedundant() async {
    try {
      final (total, _) = await AppService().findRedundantBundledCopies();
      if (mounted) setState(() => _redundantBytes = total);
    } catch (_) {}
  }

  String _fmtSize(int b) => b >= 1073741824
      ? '${(b / 1073741824).toStringAsFixed(1)} GB'
      : '${(b / 1048576).toStringAsFixed(0)} MB';

  Future<void> _cleanRedundant(AppLocalizations loc) async {
    // 必须确认：这个目录同时也是「导入模型」的落盘位置，
    // 用户手动导入过的自定义模型就在里面，不能不问就删。
    final ok = await showMacosAlertDialog<bool>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle,
            size: 48, color: Colors.orange),
        title: Text(loc.devRedundantModels),
        message: Text(loc.devRedundantConfirm(_fmtSize(_redundantBytes)),
            textAlign: TextAlign.center),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(loc.devRedundantConfirmBtn),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(loc.devRedundantCancel),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cleaningRedundant = true);
    final freed = await AppService().cleanupRedundantBundledCopies();
    if (!mounted) return;
    setState(() => _cleaningRedundant = false);
    // 重新检测而不是假设归零：删除可能部分失败，
    // 直接置 0 会让条目消失、用户没法重试
    await _loadRedundant();
    if (!mounted) return;
    showSettingsInfo(freed > 0
        ? loc.devRedundantDone(_fmtSize(freed))
        : loc.devRedundantNone);
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

      // 2. 应用日志。**两个来源都要收**：
      //    - 用户自定义目录（设了才有）
      //    - app support 默认目录 —— AppLog.e() 的 speakout_errors.log 写在这里，
      //      它记的是回滚失败/凭证残留/悬空引用这类事件，恰恰是报障时最需要的。
      //      只收自定义目录的话，没设过目录的用户导出来是空的，等于白记。
      final appLogsDest = Directory('${tempDir.path}/app-logs');
      appLogsDest.createSync();
      final logDirs = <Directory>[
        if (ConfigService().logDirectory.isNotEmpty)
          Directory(ConfigService().logDirectory),
        await getApplicationSupportDirectory(),
      ];
      final copied = <String>{};
      for (final dir in logDirs) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync()) {
          if (entity is! File || !entity.path.endsWith('.log')) continue;
          final name = entity.uri.pathSegments.last;
          if (!copied.add(name)) continue; // 同名只收第一个（自定义目录优先）
          await entity.copy('${appLogsDest.path}/$name');
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
      NotificationService().notifySuccess(loc.aboutSystemLogSuccess(zipPath));
    } catch (e) {
      if (!mounted) return;
      NotificationService().notifyError(loc.aboutSystemLogFailed('$e'));
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
          label: loc.aboutLogSensitive,
          subtitle: loc.aboutLogSensitiveDesc,
          icon: CupertinoIcons.exclamationmark_shield,
          child: MacosSwitch(
            value: ConfigService().logSensitiveContent,
            onChanged: (v) async {
              await ConfigService().setLogSensitiveContent(v);
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
        if (_redundantBytes > 0) ...[
          const SettingsDivider(),
          SettingsTile(
            label: loc.devRedundantModels,
            subtitle: '${loc.devRedundantModelsDesc} · ${_fmtSize(_redundantBytes)}',
            icon: CupertinoIcons.trash,
            child: PushButton(
              controlSize: ControlSize.regular,
              onPressed: _cleaningRedundant ? null : () => _cleanRedundant(loc),
              child: Text(_cleaningRedundant ? loc.aboutLoading : loc.devRedundantModels),
            ),
          ),
        ],
        const SettingsDivider(),
        SettingsTile(
          label: loc.devResetOnboarding,
          subtitle: loc.devResetOnboardingDesc,
          icon: CupertinoIcons.arrow_counterclockwise,
          child: PushButton(
            controlSize: ControlSize.regular,
            onPressed: () async {
              // 同页其他有副作用的操作都带确认，这个会改变下次启动行为，不该一键触发
              final ok = await showMacosAlertDialog<bool>(
                context: context,
                builder: (ctx) => MacosAlertDialog(
                  appIcon: const MacosIcon(CupertinoIcons.arrow_counterclockwise,
                      size: 48, color: Colors.orange),
                  title: Text(loc.devResetOnboarding),
                  message: Text(loc.devResetOnboardingConfirm,
                      textAlign: TextAlign.center),
                  primaryButton: PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(loc.devResetOnboardingConfirmBtn),
                  ),
                  secondaryButton: PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(loc.devRedundantCancel),
                  ),
                ),
              );
              if (ok != true) return;
              await ConfigService().resetOnboarding();
              showSettingsInfo(loc.devResetOnboardingDone);
            },
            child: Text(loc.devResetOnboarding),
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
              // 原来第一句就是 ScaffoldMessenger.of(context) —— macOS 根是 MacosApp
              // （基于 WidgetsApp），没有 ScaffoldMessenger 祖先，这里直接抛，
              // 对话框根本弹不出来：配置导出/导入整个功能坏死，不是"少个提示"。
              // 导出前让用户选择是否包含密钥（默认不含，更安全）
              final includeCreds = await showMacosAlertDialog<bool>(
                context: context,
                builder: (ctx) => MacosAlertDialog(
                  appIcon: const MacosIcon(CupertinoIcons.lock_shield, size: 48),
                  title: Text(loc.exportConfigDialogTitle),
                  message: Text(
                    loc.exportConfigDialogMsg,
                    textAlign: TextAlign.center,
                  ),
                  primaryButton: PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(loc.exportConfigWithout),
                  ),
                  secondaryButton: PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(loc.exportConfigWith),
                  ),
                ),
              );
              if (includeCreds == null) return; // 用户关闭对话框
              final path = await FilePicker.platform.saveFile(
                dialogTitle: loc.aboutExportFileTitle,
                fileName: 'speakout_config.json',
                allowedExtensions: ['json'],
                type: FileType.custom,
              );
              if (path != null) {
                final result = await ConfigBackupService.exportToFile(path, includeCredentials: includeCreds);
                result.success
                    ? NotificationService().notifySuccess(loc.aboutExportSuccess(result.message))
                    : NotificationService().notifyError(loc.aboutExportFailed(result.error ?? ''));
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
              // 原来第一句就是 ScaffoldMessenger.of(context) —— macOS 根是 MacosApp
              // （基于 WidgetsApp），没有 ScaffoldMessenger 祖先，这里直接抛，
              // 对话框根本弹不出来：配置导出/导入整个功能坏死，不是"少个提示"。
              final result = await FilePicker.platform.pickFiles(
                dialogTitle: loc.aboutImportFileTitle,
                allowedExtensions: ['json'],
                type: FileType.custom,
              );
              if (result != null && result.files.single.path != null) {
                final importResult = await ConfigBackupService.importFromFile(result.files.single.path!);
                if (!mounted) return;
                setState(() {});
                importResult.success
                    ? NotificationService().notifySuccess(loc.aboutImportSuccess(importResult.message))
                    : NotificationService().notifyError(loc.aboutImportFailed(importResult.error ?? ''));
              }
            },
            child: Text(loc.aboutImportAction),
          ),
        ),
      ],
    );
  }
}
