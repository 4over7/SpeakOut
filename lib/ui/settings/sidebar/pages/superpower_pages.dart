import 'package:flutter/widgets.dart';
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

class AiReportPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const AiReportPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.aiReport,
      );
}
