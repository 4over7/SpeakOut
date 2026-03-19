import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import '../theme.dart';

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
