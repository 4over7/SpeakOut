import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:intl/intl.dart';
import '../../models/chat_model.dart';
import '../../services/chat_service.dart';
import '../../services/diary_service.dart';
import '../../ui/theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  int _selectedFilterIndex = 0; // 0: All, 1: Chat, 2: Dictation
  
  @override
  void initState() {
    super.initState();
    ChatService().init();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<ChatMessage> _filterMessages(List<ChatMessage> all) {
    if (_selectedFilterIndex == 0) return all;
    if (_selectedFilterIndex == 1) {
      // Chat: User, AI, Tool, System (excluding Dictation)
      return all.where((m) => m.role != ChatRole.dictation).toList();
    }
    if (_selectedFilterIndex == 2) {
      // Dictation only
      return all.where((m) => m.role == ChatRole.dictation).toList();
    }
    return all;
  }
  
  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 100, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeOut
      );
    }
  }

  /// Group messages by date for timeline display
  Map<String, List<ChatMessage>> _groupByDate(List<ChatMessage> msgs) {
    final groups = <String, List<ChatMessage>>{};
    for (final msg in msgs) {
      final key = DateFormat('yyyy-MM-dd').format(msg.timestamp);
      groups.putIfAbsent(key, () => []).add(msg);
    }
    return groups;
  }

  String _dateLabel(String dateKey) {
    final date = DateFormat('yyyy-MM-dd').parse(dateKey);
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return DateFormat('EEEE', 'zh').format(date);
    return DateFormat('M月d日').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      backgroundColor: AppTheme.getBackground(context),
      toolBar: ToolBar(
        title: const Text("Chat History"),
        titleWidth: 150.0,
        actions: [
          ToolBarIconButton(
            label: "Clear History",
            icon: const MacosIcon(CupertinoIcons.trash),
            showLabel: false,
            onPressed: _showClearConfirmation,
          ),
          ToolBarIconButton(
            label: "Refresh",
            icon: const MacosIcon(CupertinoIcons.refresh),
            showLabel: false,
            onPressed: () => setState((){}),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: AppTheme.getBackground(context),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<int>(
                        children: const {
                          0: Text("全部"),
                          1: Text("Agent"),
                          2: Text("语音记录"),
                        },
                        groupValue: _selectedFilterIndex,
                        onValueChanged: (v) {
                          setState(() => _selectedFilterIndex = v ?? 0);
                        },
                        backgroundColor: AppTheme.getBorder(context),
                        thumbColor: MacosTheme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: ChatService().messageStream,
                      initialData: ChatService().messages,
                      builder: (context, snapshot) {
                        final allMsgs = snapshot.data ?? [];
                        final msgs = _filterMessages(allMsgs);

                        if (msgs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedFilterIndex == 2 ? CupertinoIcons.keyboard : CupertinoIcons.bubble_left,
                                  color: AppTheme.getTextSecondary(context).withValues(alpha: 0.3),
                                  size: 48,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedFilterIndex == 2 ? "暂无语音记录" : "暂无历史记录",
                                  style: AppTheme.caption(context),
                                ),
                              ],
                            ),
                          );
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                        // Group by date for timeline
                        final groups = _groupByDate(msgs);
                        final dateKeys = groups.keys.toList();

                        return ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: dateKeys.length,
                          itemBuilder: (context, groupIndex) {
                            final dateKey = dateKeys[groupIndex];
                            final groupMsgs = groups[dateKey]!;
                            return _buildDateGroup(dateKey, groupMsgs);
                          },
                        );
                      },
                    ),
                  ),
                  _buildInputArea(),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Build a date group with header and timeline entries
  Widget _buildDateGroup(String dateKey, List<ChatMessage> msgs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.getAccent(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _dateLabel(dateKey),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getAccent(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppTheme.getBorder(context),
                ),
              ),
            ],
          ),
        ),
        // Timeline entries
        for (int i = 0; i < msgs.length; i++)
          _buildTimelineEntry(msgs[i], isLast: i == msgs.length - 1),
      ],
    );
  }

  /// Build a single timeline entry: time on left, vertical line, content card on right
  Widget _buildTimelineEntry(ChatMessage msg, {bool isLast = false}) {
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    final roleColor = _getRoleColor(msg.role);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: time + dot + line
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(timeStr, style: AppTheme.caption(context).copyWith(fontSize: 11)),
                const SizedBox(height: 4),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleColor,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: AppTheme.getBorder(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: content card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildMessageCard(msg),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build a content card for a message (timeline style)
  Widget _buildMessageCard(ChatMessage msg) {
    final isTool = msg.role == ChatRole.tool;
    final roleColor = _getRoleColor(msg.role);
    final roleLabel = _getRoleLabel(msg.role);

    return GestureDetector(
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition, msg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.getCardBackground(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isTool ? AppTheme.getAccent(context) : AppTheme.getBorder(context),
            width: isTool ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Role label row
            Row(
              children: [
                _buildAvatar(msg.role),
                const SizedBox(width: 8),
                Text(
                  roleLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: roleColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Content
            SelectableText(
              msg.text,
              style: AppTheme.body(context).copyWith(height: 1.5),
            ),
            // ASR vs LLM comparison
            if (msg.role == ChatRole.dictation && msg.metadata?["asrOriginal"] != null)
              _buildAsrComparison(msg),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(ChatRole role) {
    return switch (role) {
      ChatRole.user => '用户',
      ChatRole.ai => 'AI',
      ChatRole.tool => '工具',
      ChatRole.dictation => '语音输入',
      ChatRole.system => '系统',
    };
  }

  Color _getRoleColor(ChatRole role) {
    return switch (role) {
      ChatRole.user => AppTheme.accentColor,
      ChatRole.ai => const Color(0xFF9B59B6),
      ChatRole.tool => const Color(0xFFE67E22),
      ChatRole.dictation => const Color(0xFF3498DB),
      ChatRole.system => MacosColors.systemGrayColor,
    };
  }
  
  /// ASR 原文 vs LLM 润色对比（可折叠）
  Widget _buildAsrComparison(ChatMessage msg) {
    final asrOriginal = msg.metadata!["asrOriginal"] as String;
    final llmResult = msg.text;
    final diffChars = asrOriginal.length - llmResult.length;
    final diffLabel = diffChars > 0 ? '精简 $diffChars 字' : (diffChars < 0 ? '扩展 ${-diffChars} 字' : '等长');

    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setInnerState(() => _expandedComparisons[msg.id] = !(_expandedComparisons[msg.id] ?? false)),
              child: Row(
                children: [
                  Icon(
                    (_expandedComparisons[msg.id] ?? false) ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                    size: 10,
                    color: AppTheme.getAccent(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'AI 润色 · $diffLabel',
                    style: TextStyle(fontSize: 10, color: AppTheme.getAccent(context), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (_expandedComparisons[msg.id] ?? false) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('原始识别', style: TextStyle(fontSize: 9, color: MacosColors.systemGrayColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    SelectableText(
                      asrOriginal,
                      style: TextStyle(fontSize: 11, color: MacosColors.systemGrayColor, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // 记录哪些消息的对比区域是展开的
  final Map<String, bool> _expandedComparisons = {};

  void _showContextMenu(BuildContext context, Offset position, ChatMessage msg) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Text("Copy"),
          onTap: () {
             // Future: Clipboard
          },
        ),
        PopupMenuItem(
          child: const Text("Save to Diary"),
          onTap: () {
             // Delay to allow menu to close
             Future.delayed(const Duration(milliseconds: 100), () {
               _saveToDiary(msg);
             });
          },
        ),
      ],
      elevation: 8.0,
    );
  }
  
  void _saveToDiary(ChatMessage msg) {
    DiaryService().appendNote("Source: Chat (${DateFormat('HH:mm').format(msg.timestamp)})\n${msg.text}");
    // Show toast ideally
  }
  
  Widget _buildAvatar(ChatRole role) {
    final icon = switch (role) {
      ChatRole.user => CupertinoIcons.person_fill,
      ChatRole.ai => CupertinoIcons.sparkles,
      ChatRole.tool => CupertinoIcons.hammer_fill,
      ChatRole.dictation => CupertinoIcons.keyboard,
      ChatRole.system => CupertinoIcons.info,
    };
    final color = _getRoleColor(role);

    return CircleAvatar(
      radius: 10,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, size: 11, color: color),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getCardBackground(context),
        border: Border(top: BorderSide(color: AppTheme.getBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: MacosTextField(
              controller: _textCtrl,
              placeholder: "输入消息...",
              maxLines: null,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.large,
            onPressed: _sendMessage,
            child: const Icon(CupertinoIcons.paperplane_fill, size: 16),
          ),
        ],
      ),
    );
  }
  
  void _showClearConfirmation() {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle_fill, color: MacosColors.systemRedColor, size: 56),
        title: const Text('Clear Chat History?'),
        message: const Text('This will permanently delete all chat messages in this view.\nYour previously saved Flash Notes (Diary) and Command Logs will NOT be affected.'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          onPressed: () {
            ChatService().clearHistory();
            Navigator.of(context).pop();
          },
          child: const Text('Delete All'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
  
  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    
    _textCtrl.clear();
    ChatService().addUserMessage(text);
  }
}
