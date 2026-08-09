import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../tabs/superpower_tab.dart';

/// v1.8 Sidebar - 超能力页面 wrapper
///
/// 当前策略：wrap SuperpowerTab with 对应 viewFilter.
/// Phase 6 清理旧 5-tab 后再做真正的文件级拆分。

/// E4：超能力合并入口 —— 单页展示全部超能力功能（复用 all 视图）
class SuperpowerHubPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const SuperpowerHubPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => SuperpowerTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: SuperpowerView.all,
      );
}

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
