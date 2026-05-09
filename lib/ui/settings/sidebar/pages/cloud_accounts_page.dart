import 'package:flutter/widgets.dart';
import '../../../cloud_accounts_page.dart' as core;

/// v1.8 Sidebar - 云账户页（wrap 既有 CloudAccountsPage）
class CloudAccountsPage extends StatelessWidget {
  const CloudAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const core.CloudAccountsPage();
  }
}
