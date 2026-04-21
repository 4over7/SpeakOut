import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../theme.dart';
import 'pages/placeholder_page.dart';
import 'sidebar_item.dart';

/// v1.8 设置页新版 shell：左 sidebar + 右 content。
/// D1 阶段只做脚手架，13 个页面均为 placeholder，D2/D3 迁移真实内容。
class SettingsSidebarShell extends StatefulWidget {
  const SettingsSidebarShell({super.key});

  @override
  State<SettingsSidebarShell> createState() => _SettingsSidebarShellState();
}

class _SettingsSidebarShellState extends State<SettingsSidebarShell> {
  String _selectedId = 'overview';

  List<SidebarSection> _buildSections() {
    SidebarEntry placeholder(String id, String label, IconData icon, String src) {
      return SidebarEntry(
        id: id,
        label: label,
        icon: icon,
        builder: (_) => SidebarPlaceholderPage(title: label, sourceFile: src),
      );
    }

    return [
      SidebarSection(
        entries: [
          placeholder('overview', '概览', CupertinoIcons.square_grid_2x2, 'Phase 4'),
        ],
      ),
      SidebarSection(
        title: '基础',
        entries: [
          placeholder('general', '通用', CupertinoIcons.settings, 'general_tab.dart'),
          placeholder('shortcuts', '快捷键', CupertinoIcons.keyboard, 'mode_tab.dart'),
          placeholder('permissions', '权限', CupertinoIcons.lock_shield, 'general_tab.dart'),
        ],
      ),
      SidebarSection(
        title: '语音',
        entries: [
          placeholder('recognition', '识别引擎', CupertinoIcons.waveform_circle_fill, 'mode_tab.dart'),
          placeholder('ai_plus', 'AI Plus', CupertinoIcons.sparkles, 'mode_tab.dart'),
          placeholder('vocab', '词典', CupertinoIcons.book, 'mode_tab.dart'),
        ],
      ),
      SidebarSection(
        title: '超能力',
        entries: [
          placeholder('diary', '闪念笔记', CupertinoIcons.lightbulb, 'superpower_tab.dart'),
          placeholder('organize', 'AI 梳理', CupertinoIcons.wand_stars, 'superpower_tab.dart'),
          placeholder('translate', '即时翻译', CupertinoIcons.globe, 'superpower_tab.dart'),
          placeholder('correction', '纠错反馈', CupertinoIcons.pencil_circle, 'superpower_tab.dart'),
          placeholder('debug', 'AI 调试', CupertinoIcons.ant, 'superpower_tab.dart'),
        ],
      ),
      SidebarSection(
        title: '其他',
        entries: [
          placeholder('about', '关于', CupertinoIcons.info_circle, 'about_tab.dart'),
        ],
      ),
    ];
  }

  SidebarEntry? _findEntry(List<SidebarSection> sections, String id) {
    for (final section in sections) {
      for (final entry in section.entries) {
        if (entry.id == id) return entry;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections();
    final selected = _findEntry(sections, _selectedId) ?? sections.first.entries.first;

    return MacosWindow(
      backgroundColor: AppTheme.getBackground(context),
      disableWallpaperTinting: true,
      child: MacosScaffold(
        backgroundColor: AppTheme.getBackground(context),
        toolBar: ToolBar(
          title: const Text('设置（v1.8 预览）'),
          titleWidth: 200,
        ),
        children: [
          ContentArea(
            builder: (context, _) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Sidebar(
                    sections: sections,
                    selectedId: _selectedId,
                    onSelect: (id) => setState(() => _selectedId = id),
                  ),
                  Container(
                    width: 1,
                    color: AppTheme.getBorder(context),
                  ),
                  Expanded(
                    child: Container(
                      color: AppTheme.getBackground(context),
                      padding: const EdgeInsets.all(20),
                      child: selected.builder(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<SidebarSection> sections;
  final String selectedId;
  final ValueChanged<String> onSelect;

  const _Sidebar({
    required this.sections,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppTheme.getSidebarBackground(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in sections) ...[
              if (section.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Text(
                    section.title!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.getTextSecondary(context),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              for (final entry in section.entries)
                _SidebarItem(
                  entry: entry,
                  selected: entry.id == selectedId,
                  onTap: () => onSelect(entry.id),
                ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final SidebarEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    Color bg;
    if (widget.selected) {
      bg = accent.withValues(alpha: 0.14);
    } else if (_hover) {
      bg = AppTheme.getBorder(context).withValues(alpha: 0.5);
    } else {
      bg = const Color(0x00000000);
    }
    final iconColor = widget.selected ? accent : AppTheme.getTextSecondary(context);
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
      color: widget.selected ? accent : textPrimary,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              MacosIcon(widget.entry.icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.entry.label, style: labelStyle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
