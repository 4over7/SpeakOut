import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../../services/config_service.dart';
import '../../../services/app_service.dart';
import '../../../services/update_service.dart';
import '../../../services/config_backup_service.dart';
import '../../../config/distribution.dart';
import '../../theme.dart';
import '../../widgets/settings_widgets.dart';

/// About tab — app info, version, update check, developer settings, config backup
class AboutTab extends StatefulWidget {
  const AboutTab({super.key});

  @override
  State<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<AboutTab> {
  String _version = '';
  bool _isCheckingUpdate = false;
  bool _versionCopied = false;
  String? _updateResult;
  String _modelsDir = '';
  bool _diagnosticsCopied = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadModelsDir();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {}
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

  Future<void> _copyDiagnostics() async {
    final info = await PackageInfo.fromPlatform();
    final buf = StringBuffer();
    buf.writeln('SpeakOut 诊断信息');
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
      child: Column(
        children: [
          // App icon
          const SizedBox(height: 32),
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
              child: Image.asset('assets/app_icon.png', width: 100, height: 100),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _versionCopied
                          ? MacosColors.systemGreenColor.withValues(alpha: 0.15)
                          : MacosColors.systemGrayColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _versionCopied
                            ? MacosColors.systemGreenColor.withValues(alpha: 0.4)
                            : MacosColors.systemGrayColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_versionCopied) ...[
                          const MacosIcon(CupertinoIcons.checkmark, size: 12, color: MacosColors.systemGreenColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _versionCopied ? '已复制' : 'v$_version',
                          style: AppTheme.mono(context).copyWith(
                            fontSize: 12,
                            color: _versionCopied
                                ? MacosColors.systemGreenColor
                                : MacosColors.labelColor.resolveFrom(context).withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (Distribution.supportsUpdateCheck) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isCheckingUpdate ? null : () async {
                    setState(() { _isCheckingUpdate = true; _updateResult = null; });
                    try {
                      final info = await PackageInfo.fromPlatform();
                      UpdateService().resetCheck();
                      await UpdateService().checkForUpdate();
                      final latest = UpdateService().latestVersion;
                      if (latest != null && UpdateService.isNewer(latest, info.version)) {
                        setState(() => _updateResult = loc.updateAvailable(latest));
                      } else {
                        setState(() => _updateResult = loc.updateUpToDate);
                      }
                    } catch (_) {
                      setState(() => _updateResult = loc.updateUpToDate);
                    }
                    setState(() => _isCheckingUpdate = false);
                  },
                  child: Tooltip(
                    message: loc.updateAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MacosColors.systemGrayColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha: 0.2)),
                      ),
                      child: _isCheckingUpdate
                          ? const SizedBox(width: 14, height: 14, child: CupertinoActivityIndicator())
                          : const MacosIcon(CupertinoIcons.arrow_clockwise, size: 14, color: MacosColors.secondaryLabelColor),
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
                          ? Text(_updateResult!, style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemGrayColor))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_updateResult!, style: AppTheme.caption(context).copyWith(fontSize: 11, color: MacosColors.systemOrangeColor)),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    final svc = UpdateService();
                                    if (svc.canAutoUpdate) {
                                      svc.downloadUpdate();
                                    } else {
                                      final url = svc.downloadUrl ?? 'https://github.com/4over7/SpeakOut/releases/latest';
                                      launchUrl(Uri.parse(url));
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getAccent(context),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      UpdateService().canAutoUpdate ? '下载更新' : loc.updateAction,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
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
            style: AppTheme.body(context).copyWith(fontSize: 16, color: AppTheme.getAccent(context)),
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
              Text(loc.aboutPoweredBy, style: AppTheme.caption(context).copyWith(fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Sherpa-ONNX', style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: TextStyle(color: MacosColors.tertiaryLabelColor))),
                  Text('Aliyun NLS', style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: TextStyle(color: MacosColors.tertiaryLabelColor))),
                  Text('Ollama', style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Copyright
          Text(loc.aboutCopyright, style: AppTheme.caption(context).copyWith(color: MacosColors.quaternaryLabelColor)),
          const SizedBox(height: 12),

          // Privacy policy
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://github.com/4over7/SpeakOut/wiki/Privacy-Policy')),
            child: Text('隐私政策', style: AppTheme.caption(context).copyWith(color: AppTheme.getAccent(context), decoration: TextDecoration.underline)),
          ),

          const SizedBox(height: 48),

          // Developer section
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
                            : ConfigService().logDirectory.replaceFirst(RegExp(r'^/Users/[^/]+'), '~'),
                        style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: const MacosIcon(CupertinoIcons.folder_badge_plus, size: 16),
                        backgroundColor: MacosColors.transparent,
                        onPressed: () async {
                          final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择日志输出目录');
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
                  icon: CupertinoIcons.cube_box,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _modelsDir.isEmpty
                            ? '加载中…'
                            : _modelsDir.replaceFirst(RegExp(r'^/Users/[^/]+'), '~'),
                        style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: const MacosIcon(CupertinoIcons.arrow_right_square, size: 16),
                        backgroundColor: MacosColors.transparent,
                        onPressed: _modelsDir.isEmpty ? null : () => _revealInFinder(_modelsDir),
                      ),
                    ],
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
            ),
          ),

          const SizedBox(height: 16),

          // Config backup
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
                        final result = await ConfigBackupService.exportToFile(path);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(result.success ? '已导出：${result.message}' : '导出失败：${result.error}'),
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
                      final result = await FilePicker.platform.pickFiles(
                        dialogTitle: '选择配置文件',
                        allowedExtensions: ['json'],
                        type: FileType.custom,
                      );
                      if (result != null && result.files.single.path != null) {
                        final importResult = await ConfigBackupService.importFromFile(result.files.single.path!);
                        if (context.mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(importResult.success ? '${importResult.message}，配置已生效' : '导入失败：${importResult.error}'),
                            backgroundColor: importResult.success ? MacosColors.systemGreenColor : null,
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
