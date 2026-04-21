import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../../services/config_service.dart';
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

/// 给 sidebar 内的 page 用：跳转到另一个 sidebar 条目。
class SidebarNavigation extends InheritedWidget {
  final void Function(String pageId) goto;

  const SidebarNavigation({super.key, required this.goto, required super.child});

  static SidebarNavigation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarNavigation>();

  @override
  bool updateShouldNotify(SidebarNavigation oldWidget) => goto != oldWidget.goto;
}

class _SettingsSidebarShellState extends State<SettingsSidebarShell> {
  String _selectedId = 'overview';

  void _goto(String id) {
    if (_selectedId == id) return;
    setState(() => _selectedId = id);
  }

  List<SidebarSection> _buildSections() {
    return [
      SidebarSection(
        entries: [
          SidebarEntry(
            id: 'overview',
            label: '概览',
            icon: CupertinoIcons.square_grid_2x2,
            builder: (_) => OverviewPage(),
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
            builder: (_) => GeneralPage(),
          ),
          SidebarEntry(
            id: 'shortcuts',
            label: '快捷键',
            icon: CupertinoIcons.keyboard,
            hasAdvanced: true,
            builder: (_) => ShortcutsPage(),
          ),
          SidebarEntry(
            id: 'permissions',
            label: '权限',
            icon: CupertinoIcons.lock_shield,
            builder: (_) => PermissionsPage(),
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
            hasAdvanced: true,
            builder: (_) => RecognitionEnginePage(),
          ),
          SidebarEntry(
            id: 'ai_plus',
            label: 'AI Plus',
            icon: CupertinoIcons.sparkles,
            hasAdvanced: true,
            builder: (_) => AiPlusPage(),
          ),
          SidebarEntry(
            id: 'vocab',
            label: '词典',
            icon: CupertinoIcons.book,
            builder: (_) => VocabPage(),
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
            builder: (_) => DiaryPage(),
          ),
          SidebarEntry(
            id: 'organize',
            label: 'AI 梳理',
            icon: CupertinoIcons.wand_stars,
            builder: (_) => OrganizePage(),
          ),
          SidebarEntry(
            id: 'translate',
            label: '即时翻译',
            icon: CupertinoIcons.globe,
            builder: (_) => TranslatePage(),
          ),
          SidebarEntry(
            id: 'correction',
            label: '纠错反馈',
            icon: CupertinoIcons.pencil_circle,
            builder: (_) => CorrectionPage(),
          ),
          SidebarEntry(
            id: 'debug',
            label: 'AI 调试',
            icon: CupertinoIcons.ant,
            builder: (_) => AiReportPage(),
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
            builder: (_) => AboutPage(),
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

    return SidebarNavigation(
      goto: _goto,
      child: MacosWindow(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PageHeader(
                            entry: selected,
                            showAdvanced: ConfigService().showAdvanced,
                            onToggleAdvanced: (v) async {
                              await ConfigService().setShowAdvanced(v);
                              if (mounted) setState(() {});
                            },
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: selected.builder(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final SidebarEntry entry;
  final bool showAdvanced;
  final ValueChanged<bool> onToggleAdvanced;

  const _PageHeader({
    required this.entry,
    required this.showAdvanced,
    required this.onToggleAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.getBorder(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          MacosIcon(entry.icon, size: 20, color: AppTheme.getAccent(context)),
          const SizedBox(width: 10),
          Text(
            entry.label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const Spacer(),
          if (entry.hasAdvanced) ...[
            Text(
              '显示高级',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.getTextSecondary(context),
              ),
            ),
            const SizedBox(width: 8),
            MacosSwitch(
              value: showAdvanced,
              onChanged: onToggleAdvanced,
            ),
          ],
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
