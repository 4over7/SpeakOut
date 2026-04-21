import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../theme.dart';
import 'pages/about_page.dart';
import 'pages/ai_plus_page.dart';
import 'pages/general_pages.dart';
import 'pages/overview_page.dart';
import 'pages/recognition_engine_page.dart';
import 'pages/shortcuts_page.dart';
import 'pages/superpower_pages.dart';
import 'pages/vocab_page.dart';
import 'sidebar_item.dart';

/// v1.8 设置页新版 shell：左 sidebar + 右 content。
class SettingsSidebarShell extends StatefulWidget {
  const SettingsSidebarShell({super.key});

  @override
  State<SettingsSidebarShell> createState() => _SettingsSidebarShellState();
}

class _SettingsSidebarShellState extends State<SettingsSidebarShell> {
  String _selectedId = 'overview';

  List<SidebarSection> _buildSections() {
    return [
      SidebarSection(
        entries: [
          SidebarEntry(
            id: 'overview',
            label: '概览',
            icon: CupertinoIcons.square_grid_2x2,
            builder: (_) => const OverviewPage(),
          ),
        ],
      ),
      SidebarSection(
        title: '基础',
        entries: [
          SidebarEntry(
            id: 'general',
            label: '通用',
            icon: CupertinoIcons.settings,
            builder: (_) => const GeneralPage(),
          ),
          SidebarEntry(
            id: 'shortcuts',
            label: '快捷键',
            icon: CupertinoIcons.keyboard,
            builder: (_) => const ShortcutsPage(),
          ),
          SidebarEntry(
            id: 'permissions',
            label: '权限',
            icon: CupertinoIcons.lock_shield,
            builder: (_) => const PermissionsPage(),
          ),
        ],
      ),
      SidebarSection(
        title: '语音',
        entries: [
          SidebarEntry(
            id: 'recognition',
            label: '识别引擎',
            icon: CupertinoIcons.waveform_circle_fill,
            builder: (_) => const RecognitionEnginePage(),
          ),
          SidebarEntry(
            id: 'ai_plus',
            label: 'AI Plus',
            icon: CupertinoIcons.sparkles,
            builder: (_) => const AiPlusPage(),
          ),
          SidebarEntry(
            id: 'vocab',
            label: '词典',
            icon: CupertinoIcons.book,
            builder: (_) => const VocabPage(),
          ),
        ],
      ),
      SidebarSection(
        title: '超能力',
        entries: [
          SidebarEntry(
            id: 'diary',
            label: '闪念笔记',
            icon: CupertinoIcons.lightbulb,
            builder: (_) => const DiaryPage(),
          ),
          SidebarEntry(
            id: 'organize',
            label: 'AI 梳理',
            icon: CupertinoIcons.wand_stars,
            builder: (_) => const OrganizePage(),
          ),
          SidebarEntry(
            id: 'translate',
            label: '即时翻译',
            icon: CupertinoIcons.globe,
            builder: (_) => const TranslatePage(),
          ),
          SidebarEntry(
            id: 'correction',
            label: '纠错反馈',
            icon: CupertinoIcons.pencil_circle,
            builder: (_) => const CorrectionPage(),
          ),
          SidebarEntry(
            id: 'debug',
            label: 'AI 调试',
            icon: CupertinoIcons.ant,
            builder: (_) => const AiReportPage(),
          ),
        ],
      ),
      SidebarSection(
        title: '其他',
        entries: [
          SidebarEntry(
            id: 'about',
            label: '关于',
            icon: CupertinoIcons.info_circle,
            builder: (_) => const AboutPage(),
          ),
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
