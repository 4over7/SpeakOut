import 'package:flutter/widgets.dart';
import '../../cloud_accounts_page.dart';

/// Service tab — wraps CloudAccountsPage
class ServiceTab extends StatelessWidget {
  const ServiceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const CloudAccountsPage();
  }
}
