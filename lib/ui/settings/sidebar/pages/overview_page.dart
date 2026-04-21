import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme.dart';
import '../../../widgets/settings_widgets.dart';
import '../sidebar_shell.dart';

/// v1.8 Sidebar - 概览页
///
/// 四卡产品介绍 + 帮助链接。
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    final nav = SidebarNavigation.of(context);

    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        // Welcome card
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              MacosIcon(CupertinoIcons.mic_circle_fill, size: 44, color: accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '欢迎使用 SpeakOut',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'macOS 离线优先 AI 语音输入 · 隐私安全 · 免费开源',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              PushButton(
                controlSize: ControlSize.regular,
                color: accent,
                onPressed: () => nav?.goto('shortcuts'),
                child: const Text('开始配置', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Feature cards (2x2 grid)
        SettingsCardGrid(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FeatureCard(
              icon: CupertinoIcons.lock_shield_fill,
              iconColor: MacosColors.systemGreenColor,
              title: '离线识别',
              desc: '本地 Sherpa-ONNX ASR，中英识别媲美云端，音频不出设备',
              onTap: () => nav?.goto('recognition'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.sparkles,
              iconColor: accent,
              title: 'AI 润色',
              desc: '云端 LLM 智能纠错，修复同音字、标点、语法',
              onTap: () => nav?.goto('ai_plus'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.bolt_fill,
              iconColor: MacosColors.systemYellowColor,
              title: '超能力',
              desc: '闪念笔记 / AI 梳理 / 即时翻译 / 纠错反馈 / AI 调试',
              onTap: () => nav?.goto('diary'),
            ),
            _FeatureCard(
              icon: CupertinoIcons.book,
              iconColor: MacosColors.systemBlueColor,
              title: '专业词典',
              desc: '自定义术语注入 LLM prompt，医疗 / 法律 / 金融等包',
              onTap: () => nav?.goto('vocab'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Help links
        SettingsCard(
          title: '帮助与支持',
          titleIcon: CupertinoIcons.question_circle,
          children: [
            _LinkRow(
              icon: CupertinoIcons.book_solid,
              label: 'Wiki · FAQ',
              url: 'https://github.com/4over7/SpeakOut/wiki',
            ),
            _LinkRow(
              icon: CupertinoIcons.arrow_2_circlepath,
              label: '更新日志',
              url: 'https://github.com/4over7/SpeakOut/releases',
            ),
            _LinkRow(
              icon: CupertinoIcons.chat_bubble_2_fill,
              label: 'X · @4over7',
              url: 'https://x.com/4over7',
            ),
            _LinkRow(
              icon: CupertinoIcons.envelope_fill,
              label: '反馈 · 4over7@gmail.com',
              url: 'mailto:4over7@gmail.com?subject=SpeakOut%20Feedback',
            ),
            _LinkRow(
              icon: CupertinoIcons.exclamationmark_bubble_fill,
              label: 'GitHub Issues',
              url: 'https://github.com/4over7/SpeakOut/issues',
              isLast: true,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.desc,
    this.onTap,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.getCardBackground(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover ? widget.iconColor.withValues(alpha: 0.4) : AppTheme.getBorder(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Row(
                children: [
                  MacosIcon(widget.icon, size: 18, color: widget.iconColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.desc,
                style: TextStyle(
                  fontSize: 12,
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

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final bool isLast;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(url)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  MacosIcon(icon, size: 14, color: AppTheme.getTextSecondary(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ),
                  MacosIcon(
                    CupertinoIcons.arrow_up_right_square,
                    size: 13,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: AppTheme.getBorder(context)),
      ],
    );
  }
}
