import 'package:flutter/widgets.dart';
import '../../tabs/mode_tab.dart';

/// v1.8 Sidebar - 识别引擎页
///
/// 当前策略：wrap ModeTab with ModeTabView.recognition filter.
/// Phase 6 清理旧 5-tab 后再做真正的文件级拆分。
class RecognitionEnginePage extends StatelessWidget {
  final ValueChanged<int>? onNavigateToTab;

  const RecognitionEnginePage({super.key, this.onNavigateToTab});

  @override
  Widget build(BuildContext context) {
    return ModeTab(
      onNavigateToTab: onNavigateToTab ?? (_) {},
      viewFilter: ModeTabView.recognition,
    );
  }
}
