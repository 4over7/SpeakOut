import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../engine/core_engine.dart';
import '../../../theme.dart';
import '../../tabs/superpower_tab.dart';

/// v1.8 Sidebar - 5 个超能力独立页
///
/// 当前策略：wrap SuperpowerTab with 对应 viewFilter.
/// Phase 6 清理旧 5-tab 后再做真正的文件级拆分。

class DiaryPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const DiaryPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.diary,
      );
}

class OrganizePage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const OrganizePage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.organize,
      );
}

class TranslatePage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const TranslatePage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.translate,
      );
}

class CorrectionPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const CorrectionPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.correction,
      );
}

class AiReportPage extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;
  const AiReportPage({super.key, this.onNavigateToTab});

  @override
  State<AiReportPage> createState() => _AiReportPageState();
}

class _AiReportPageState extends State<AiReportPage> with WidgetsBindingObserver {
  bool _screenRecordingGranted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从系统设置切回来，重新检测
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  void _checkPermission() {
    final granted = CoreEngine().nativeInput?.checkScreenRecordingPermission() ?? true;
    if (mounted && granted != _screenRecordingGranted) {
      setState(() => _screenRecordingGranted = granted);
    } else if (mounted) {
      _screenRecordingGranted = granted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final tab = SuperpowerTab(
      onNavigateToTab: widget.onNavigateToTab ?? (_) {},
      viewFilter: SuperpowerView.aiReport,
    );

    if (_screenRecordingGranted) return tab;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScreenRecordingBanner(loc: loc, onOpen: () {
          launchUrl(Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
        }),
        Expanded(child: tab),
      ],
    );
  }
}

class _ScreenRecordingBanner extends StatelessWidget {
  final AppLocalizations loc;
  final VoidCallback onOpen;
  const _ScreenRecordingBanner({required this.loc, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacosColors.systemOrangeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacosColors.systemOrangeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const MacosIcon(CupertinoIcons.exclamationmark_triangle_fill,
              size: 16, color: MacosColors.systemOrangeColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loc.aiReportScreenRecordingWarning,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.getTextPrimary(context),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          PushButton(
            controlSize: ControlSize.regular,
            color: MacosColors.systemOrangeColor,
            onPressed: onOpen,
            child: Text(loc.aiReportOpenSettings, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
