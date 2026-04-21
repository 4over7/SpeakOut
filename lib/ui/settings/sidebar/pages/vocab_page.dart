import 'package:flutter/widgets.dart';
import '../../../vocab_settings_page.dart';

/// v1.8 Sidebar - 词典页
///
/// 直接复用 VocabSettingsView，该 view 已从旧 page 抽出。
class VocabPage extends StatelessWidget {
  const VocabPage({super.key});

  @override
  Widget build(BuildContext context) => const VocabSettingsView();
}
