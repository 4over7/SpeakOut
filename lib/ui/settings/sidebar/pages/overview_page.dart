import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../config/distribution.dart';
import '../../../../services/update_service.dart';
import '../../../theme.dart';
import '../../../widgets/settings_widgets.dart';
import '../sidebar_shell.dart';

/// v1.8 Sidebar - 概览页
///
/// 欢迎横幅 + 4 feature 卡 + 应用信息（版本/更新/Powered by/版权）+ 帮助链接
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  String _version = '';
  bool _versionCopied = false;
  bool _isCheckingUpdate = false;
  String? _updateResult;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  Future<void> _checkUpdate(AppLocalizations loc) async {
    setState(() { _isCheckingUpdate = true; _updateResult = null; });
    try {
      final info = await PackageInfo.fromPlatform();
      UpdateService().resetCheck();
      await UpdateService().checkForUpdate();
      final latest = UpdateService().latestVersion;
      if (latest != null && UpdateService.isNewer(latest, info.version)) {
        if (mounted) setState(() => _updateResult = loc.updateAvailable(latest));
      } else {
        if (mounted) setState(() => _updateResult = loc.updateUpToDate);
      }
    } catch (_) {
      if (mounted) setState(() => _updateResult = loc.updateUpToDate);
    }
    if (mounted) setState(() => _isCheckingUpdate = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final accent = AppTheme.getAccent(context);
    final nav = SidebarNavigation.of(context);

    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        // Welcome hero
        _buildWelcomeHero(loc, accent, nav),
        const SizedBox(height: 16),

        // Feature cards (2x2)
        SettingsCardGrid(
          spacing: 12,
          runSpacing: 12,
          forceDualColumn: true,
          children: [
            _FeatureCard(
              icon: CupertinoIcons.lock_shield_fill,
              iconColor: MacosColors.systemGreenColor,
              title: loc.featureOfflineTitle,
              desc: loc.featureOfflineDesc,
              onTap: () => nav?.goto('recognition'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.sparkles,
              iconColor: accent,
              title: loc.featureAiPolishTitle,
              desc: loc.featureAiPolishDesc,
              onTap: () => nav?.goto('ai_plus'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.bolt_fill,
              iconColor: MacosColors.systemYellowColor,
              title: loc.featureSuperpowerTitle,
              desc: loc.featureSuperpowerDesc,
              onTap: () => nav?.goto('diary'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.book,
              iconColor: MacosColors.systemBlueColor,
              title: loc.featureVocabTitle,
              desc: loc.featureVocabDesc,
              onTap: () => nav?.goto('vocab'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // App info
        _buildAppInfoCard(loc, accent),
        const SizedBox(height: 16),

        // Help links
        SettingsCard(
          title: loc.overviewHelpTitle,
          titleIcon: CupertinoIcons.question_circle,
          children: [
            _LinkRow(icon: CupertinoIcons.book_solid, label: loc.linkWikiFaq, url: 'https://github.com/4over7/SpeakOut/wiki'),
            _LinkRow(icon: CupertinoIcons.arrow_2_circlepath, label: loc.linkChangelog, url: 'https://github.com/4over7/SpeakOut/releases'),
            _LinkRow(icon: CupertinoIcons.chat_bubble_2_fill, label: loc.linkXHandle, url: 'https://x.com/4over7'),
            _LinkRow(icon: CupertinoIcons.envelope_fill, label: loc.linkFeedback, url: 'mailto:4over7@gmail.com?subject=SpeakOut%20Feedback'),
            _LinkRow(icon: CupertinoIcons.exclamationmark_bubble_fill, label: loc.linkGithubIssues, url: 'https://github.com/4over7/SpeakOut/issues', isLast: true),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWelcomeHero(AppLocalizations loc, Color accent, SidebarNavigation? nav) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          MacosIcon(CupertinoIcons.mic_circle_fill, size: 44, color: accent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.overviewWelcome, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.getTextPrimary(context))),
                const SizedBox(height: 4),
                Text(loc.overviewTagline, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
              ],
            ),
          ),
          PushButton(
            controlSize: ControlSize.regular,
            color: accent,
            onPressed: () => nav?.goto('shortcuts'),
            child: Text(loc.overviewGetStarted, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfoCard(AppLocalizations loc, Color accent) {
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/app_icon.png', width: 64, height: 64),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.appProductName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.getTextPrimary(context))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Version badge (double-tap to copy)
                      GestureDetector(
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(text: _version));
                          setState(() => _versionCopied = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _versionCopied = false);
                          });
                        },
                        child: Tooltip(
                          message: loc.aboutVersionCopyTip,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: _versionCopied
                                  ? MacosColors.systemGreenColor.withValues(alpha: 0.15)
                                  : MacosColors.systemGrayColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_versionCopied) ...[
                                  const MacosIcon(CupertinoIcons.checkmark, size: 11, color: MacosColors.systemGreenColor),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  _versionCopied ? loc.aboutVersionCopied : 'v$_version',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'SF Mono',
                                    color: _versionCopied ? MacosColors.systemGreenColor : MacosColors.labelColor.resolveFrom(context).withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Check update button
                      if (Distribution.supportsUpdateCheck) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isCheckingUpdate ? null : () => _checkUpdate(loc),
                          child: Tooltip(
                            message: loc.updateAction,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: MacosColors.systemGrayColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _isCheckingUpdate
                                  ? const SizedBox(width: 12, height: 12, child: CupertinoActivityIndicator())
                                  : const MacosIcon(CupertinoIcons.arrow_clockwise, size: 12, color: MacosColors.secondaryLabelColor),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_updateResult != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _updateResult!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _updateResult == loc.updateUpToDate
                            ? MacosColors.systemGrayColor
                            : MacosColors.systemOrangeColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: AppTheme.getBorder(context)),
        const SizedBox(height: 12),
        // Powered by
        Row(
          children: [
            Text('${loc.aboutPoweredBy}  ', style: TextStyle(fontSize: 11, color: AppTheme.getTextSecondary(context))),
            Text('Sherpa-ONNX · Aliyun NLS · Ollama', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                loc.aboutCopyright,
                style: TextStyle(fontSize: 10, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.8)),
              ),
            ),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://github.com/4over7/SpeakOut/wiki/Privacy-Policy')),
              child: Text(
                loc.aboutPrivacyPolicy,
                style: TextStyle(fontSize: 11, color: accent, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.desc,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      minHeight: 120,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            MacosIcon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.getTextSecondary(context),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final bool isLast;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(url)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  MacosIcon(icon, size: 14, color: AppTheme.getTextSecondary(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 13, color: AppTheme.getTextPrimary(context))),
                  ),
                  MacosIcon(CupertinoIcons.arrow_up_right_square, size: 13, color: AppTheme.getTextSecondary(context)),
                ],
              ),
            ),
          ),
        ),
        if (!isLast) Divider(height: 1, color: AppTheme.getBorder(context)),
      ],
    );
  }
}
