import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:intl/intl.dart';
import '../../models/chat_model.dart';
import '../../services/chat_service.dart';
import '../../services/diary_service.dart';
import '../../services/agent_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
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
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<int>(
                      children: const {
                        0: Text("All History"),
                        1: Text("Agent Chat"),
                        2: Text("Dictation Log"),
                      },
                      groupValue: _selectedFilterIndex,
                      onValueChanged: (v) {
                        setState(() => _selectedFilterIndex = v ?? 0);
                      },
                      backgroundColor: MacosColors.systemGrayColor.withOpacity(0.2),
                      thumbColor: MacosTheme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFF636366) 
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
                                color: MacosColors.systemGrayColor.withOpacity(0.3),
                                size: 48
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedFilterIndex == 2 ? "No dictation logs yet." : "No interaction history.", 
                                style: AppTheme.caption(context)
                              ),
                            ],
                          ),
                        );
                      }
                      
                      // Auto-scroll on new message ONLY if showing All or relevant tab
                      // And only if at bottom? For simplicity, we keep auto-scroll behavior.
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced top padding
                        itemCount: msgs.length,
                        itemBuilder: (context, index) {
                          final msg = msgs[index];
                          return _buildMessageBubble(msg);
                        },
                      );
                    },
                  ),
                ),
                _buildInputArea(),
              ],
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == ChatRole.user;
    final isTool = msg.role == ChatRole.tool;
    // Dictation is conceptually 'User' but system-logged. Let's treat it as system-aligned but with avatar.
    final isSystem = msg.role == ChatRole.system;
    
    // Formatting
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(msg.role),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: GestureDetector(
               onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition, msg),
               child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getBubbleColor(msg.role),
                  borderRadius: BorderRadius.circular(12),
                  border: isTool ? Border.all(color: AppTheme.getAccent(context), width: 1.5) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isTool)
                      Text("🔧 Tool Result", style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getAccent(context)
                      )),
                      
                    if (msg.role == ChatRole.dictation)
                      Text("⌨️ Dictation Log", style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey
                      )),
                      
                    SelectableText(
                      msg.text,
                      style: TextStyle(
                        color: isUser ? Colors.white : MacosTheme.of(context).typography.body.color,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(timeStr, style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white70 : MacosColors.secondaryLabelColor.resolveFrom(context),
                    )),
                  ],
                ),
              ),
            ),
          ),
          
          if (isUser) ...[
             const SizedBox(width: 8),
             _buildAvatar(msg.role),
          ],
        ],
      ),
    );
  }
  
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
  
  Color _getBubbleColor(ChatRole role) {
    switch (role) {
      case ChatRole.user:
        return AppTheme.accentColor;
      case ChatRole.tool:
        return const Color(0xFF2C3E50); // Dark Blue
      case ChatRole.dictation:
        return Colors.blueGrey.withOpacity(0.15); // Light distinct style
      case ChatRole.ai:
        return MacosColors.systemGrayColor.withOpacity(0.2);
      case ChatRole.system:
        return Colors.transparent; // Special handling maybe?
    }
  }
  
  Widget _buildAvatar(ChatRole role) {
    IconData icon;
    Color color;
    
    switch (role) {
      case ChatRole.user:
        icon = CupertinoIcons.person_fill;
        color = AppTheme.accentColor;
        break;
      case ChatRole.ai:
        icon = CupertinoIcons.sparkles;
        color = Colors.purple;
        break;
      case ChatRole.tool:
        icon = CupertinoIcons.hammer_fill;
        color = Colors.orange;
        break;
      case ChatRole.dictation:
        icon = CupertinoIcons.keyboard;
        color = Colors.blueGrey;
        break;
      case ChatRole.system:
        icon = CupertinoIcons.info;
        color = Colors.grey;
        break;
    }
    
    return CircleAvatar(
      radius: 12,
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, size: 14, color: color),
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
              placeholder: "Type a detailed message...",
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
    
    // Process text as a potential command
    AgentService().process(text);
  }
}
