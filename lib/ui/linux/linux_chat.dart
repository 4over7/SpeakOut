import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_model.dart';
import '../../services/chat_service.dart';

/// Linux 聊天页面
///
/// Material Design 3 风格，功能与 macOS/Windows 聊天页对应。
class LinuxChatPage extends StatefulWidget {
  const LinuxChatPage({super.key});

  @override
  State<LinuxChatPage> createState() => _LinuxChatPageState();
}

class _LinuxChatPageState extends State<LinuxChatPage> {
  final ChatService _chatService = ChatService();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<ChatMessage>>? _chatSub;

  @override
  void initState() {
    super.initState();
    _chatSub = _chatService.messageStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _chatService.messages;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
      ),
      body: messages.isEmpty
          ? Center(
              child: Text(
                '暂无记录',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              msg.role == ChatRole.dictation
                                  ? Icons.keyboard
                                  : Icons.edit_note,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              msg.role == ChatRole.dictation ? '听写' : '闪念',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(msg.timestamp),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          msg.text,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}
