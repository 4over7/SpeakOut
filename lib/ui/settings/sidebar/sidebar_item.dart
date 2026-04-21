import 'package:flutter/cupertino.dart';

/// 单项侧栏条目（对应右侧一整页内容）
class SidebarEntry {
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  const SidebarEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
  });
}

/// 侧栏分组（一个标题 + 若干条目）
class SidebarSection {
  final String? title;
  final List<SidebarEntry> entries;

  const SidebarSection({this.title, required this.entries});
}
