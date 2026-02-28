import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import '../../models/chat_model.dart';
import '../../services/chat_service.dart';

/// Windows 聊天页面
///
/// 功能与 macOS chat_page.dart 对应：显示语音输入历史记录。
class WindowsChatPage extends StatefulWidget {
  const WindowsChatPage({super.key});

  @override
  State<WindowsChatPage> createState() => _WindowsChatPageState();
}

class _WindowsChatPageState extends State<WindowsChatPage> {
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

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('历史记录'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(FluentIcons.back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
      content: messages.isEmpty
          ? Center(
              child: Text(
                '暂无记录',
                style: TextStyle(color: Colors.grey[120]),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              msg.role == ChatRole.dictation
                                  ? FluentIcons.keyboard_classic
                                  : FluentIcons.edit_note,
                              size: 14,
                              color: Colors.grey[120],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              msg.role == ChatRole.dictation ? '听写' : '闪念',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[120],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(msg.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[120],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          msg.text,
                          style: const TextStyle(fontSize: 14),
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
