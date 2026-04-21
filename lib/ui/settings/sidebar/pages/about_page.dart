import 'package:flutter/widgets.dart';
import '../../tabs/about_tab.dart';

/// v1.8 Sidebar - 关于页
///
/// 直接 wrap AboutTab（整个 tab 已是单一 Card 结构，不需要 view filter）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => const AboutTab();
}
