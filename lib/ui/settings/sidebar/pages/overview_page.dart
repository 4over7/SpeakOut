import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../../theme.dart';

/// v1.8 Sidebar - 概览页
///
/// Phase 1 只是占位，Phase 4 填充：产品介绍 4 卡 + 帮助链接（FAQ / 微信群 / X / 反馈 / 更新日志）。
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(24),
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
                  MacosIcon(CupertinoIcons.square_grid_2x2, size: 22, color: accent),
                  const SizedBox(width: 10),
                  Text(
                    '概览',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Phase 4 填充：产品介绍 4 卡 + 帮助链接（FAQ / 微信群 / X / 反馈 / 更新日志）。',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.getTextSecondary(context),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
