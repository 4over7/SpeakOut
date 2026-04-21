import 'package:flutter/widgets.dart';
import 'sidebar/sidebar_shell.dart';

/// v1.8 起，SettingsPage 直接渲染 sidebar shell，旧 5-tab 视图已退役。
/// 外部仍可 `Navigator.push(MaterialPageRoute(builder: (_) => SettingsPage()))`。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsSidebarShell();
}
