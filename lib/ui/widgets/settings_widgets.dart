import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../theme.dart';

// =============================================================================
// New card-based components for UI v4.0 — 墨竹
// =============================================================================

/// Independent settings card with optional colored left border.
/// Used in trigger tab (one card per feature) and mode tab (grouped settings).
class SettingsCard extends StatefulWidget {
  final String? title;
  final IconData? titleIcon;
  final Color? accentColor;       // Colored left border
  final List<Widget> children;
  final Widget? trailing;          // Top-right widget (e.g. enable switch)
  final EdgeInsets padding;
  final double? minHeight;         // 最小高度，保证卡片不会太扁
  final VoidCallback? onTap;       // v1.8: 可点击卡片（带 hover 效果）

  const SettingsCard({
    super.key,
    this.title,
    this.titleIcon,
    this.accentColor,
    required this.children,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.minHeight,
    this.onTap,
  });

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.onTap != null && _hover
        ? (widget.accentColor ?? AppTheme.getAccent(context)).withValues(alpha: 0.4)
        : AppTheme.getBorder(context);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      constraints: widget.minHeight != null ? BoxConstraints(minHeight: widget.minHeight!) : null,
      decoration: BoxDecoration(
        color: AppTheme.getCardBackground(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored left accent bar
            if (widget.accentColor != null)
              Container(
                width: 4,
                constraints: const BoxConstraints(minHeight: 60),
                color: widget.accentColor,
              ),
            // Card content
            Expanded(
              child: Padding(
                padding: widget.padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title != null) ...[
                      Row(
                        children: [
                          if (widget.titleIcon != null) ...[
                            MacosIcon(widget.titleIcon, size: 16, color: widget.accentColor ?? AppTheme.getAccent(context)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              widget.title!,
                              style: AppTheme.body(context).copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          ?widget.trailing,
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...widget.children,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onTap == null) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}

/// Dual-column card grid. Falls back to single column when width < [dualBreakpoint].
/// v1.8: threshold 降到 520; 可通过 [forceDualColumn] 强制双列（无视宽度）.
class SettingsCardGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double dualBreakpoint;
  final bool forceDualColumn;

  const SettingsCardGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
    this.dualBreakpoint = 520,
    this.forceDualColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useDualColumn = forceDualColumn || constraints.maxWidth >= dualBreakpoint;

        if (!useDualColumn) {
          // Single column
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: runSpacing),
              ],
            ],
          );
        }

        // Dual column
        final List<Widget> rows = [];
        for (int i = 0; i < children.length; i += 2) {
          final left = children[i];
          final right = (i + 1 < children.length) ? children[i + 1] : null;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: left),
                  SizedBox(width: spacing),
                  Expanded(child: right ?? const SizedBox.shrink()),
                ],
              ),
            ),
          );
          if (i + 2 < children.length) {
            rows.add(SizedBox(height: runSpacing));
          }
        }
        return Column(children: rows);
      },
    );
  }
}

/// Capsule-style value display (replaces far-right-aligned dropdowns).
class SettingsPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const SettingsPill({
    super.key,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pillColor = color ?? AppTheme.getAccent(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: pillColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: pillColor),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_down, size: 10, color: pillColor),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal tab bar for settings page (replaces sidebar).
class SettingsHorizontalTabs extends StatelessWidget {
  final List<SettingsTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const SettingsHorizontalTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.getBorder(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            _TabButton(
              icon: tabs[i].icon,
              label: tabs[i].label,
              isSelected: i == selectedIndex,
              onTap: () => onTabChanged(i),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class SettingsTabItem {
  final IconData icon;
  final String label;
  const SettingsTabItem({required this.icon, required this.label});
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    final color = isSelected ? accent : AppTheme.getTextSecondary(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Existing components (preserved for backward compatibility during migration)
// =============================================================================

class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (title != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(title!, style: AppTheme.heading(context)),
          ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.getCardBackground(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.getBorder(context)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  const SettingsTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.child,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            MacosIcon(icon, size: 20, color: MacosColors.systemGrayColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: AppTheme.body(context)),
                    ?trailing,
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: AppTheme.caption(context)),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: MacosColors.separatorColor.withValues(alpha: 0.5),
      indent: 16,
      endIndent: 0,
    );
  }
}
