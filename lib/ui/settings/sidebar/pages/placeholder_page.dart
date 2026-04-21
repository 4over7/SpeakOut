import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../../theme.dart';

/// D1 阶段占位页：D2/D3 迁移真实内容后替换。
class SidebarPlaceholderPage extends StatelessWidget {
  final String title;
  final String sourceFile;

  const SidebarPlaceholderPage({
    super.key,
    required this.title,
    required this.sourceFile,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: AppTheme.getCardBackground(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.getBorder(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MacosIcon(CupertinoIcons.wrench, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '此页在 v1.8 Phase 1 D2/D3 迁移，来源：$sourceFile',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.getTextSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
