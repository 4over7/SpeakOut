import 'package:flutter/widgets.dart';
import '../../tabs/mode_tab.dart';

/// v1.8 Sidebar - AI Plus 页
///
/// 当前策略：wrap ModeTab with ModeTabView.aiPlus filter.
/// Phase 6 清理旧 5-tab 后再做真正的文件级拆分。
class AiPlusPage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;

  const AiPlusPage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) {
    return ModeTab(
      onNavigateToTab: onNavigateToTab ?? (_) {},
      viewFilter: ModeTabView.aiPlus,
    );
  }
}
