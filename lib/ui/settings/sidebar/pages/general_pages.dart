import 'package:flutter/widgets.dart';
import '../../tabs/general_tab.dart';

/// v1.8 Sidebar - 通用页与权限页（复用 GeneralTab 的 viewFilter）

class GeneralPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const GeneralPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => GeneralTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: GeneralView.general,
      );
}

class PermissionsPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;
  const PermissionsPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) => GeneralTab(
        onNavigateToTab: onNavigateToTab ?? (_) {},
        viewFilter: GeneralView.permissions,
      );
}
