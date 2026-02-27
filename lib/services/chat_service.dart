import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'notification_service.dart';
import '../models/chat_model.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final List<ChatMessage> _messages = [];
  final StreamController<List<ChatMessage>> _streamController = StreamController.broadcast();
  
  Stream<List<ChatMessage>> get messageStream => _streamController.stream;
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isInit = false;
  Future<void>? _pendingSave; // Serialize writes to prevent concurrent file I/O

  Future<void> init() async {
    if (_isInit) return;
    await _loadHistory();
    _isInit = true;
  }

  // --- Actions ---

  void addInfo(String text) {
    _addMessage(text, ChatRole.system);
  }

  void addUserMessage(String text) {
    _addMessage(text, ChatRole.user);
  }

  void addAiMessage(String text) {
    _addMessage(text, ChatRole.ai);
  }
  
  void addToolResult(String toolName, String result) {
    _addMessage(
      "Executed: $toolName\nResult: $result", 
      ChatRole.tool, 
      metadata: {"tool": toolName}
    );
  }
  
  void addDictation(String text) {
    _addMessage(text, ChatRole.dictation);
  }
  
  Future<void> clearHistory() async {
    _messages.clear();
    _streamController.add(_messages);
    await _saveHistory();
  }

  // --- Internal ---

  void _addMessage(String text, ChatRole role, {Map<String, dynamic>? metadata}) {
    final msg = ChatMessage(
      id: const Uuid().v4(),
      text: text,
      role: role,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    
    _messages.add(msg);
    _streamController.add(_messages);
    _scheduleSave();
  }

  /// Serialize save operations to prevent concurrent file writes
  void _scheduleSave() {
    _pendingSave = (_pendingSave ?? Future.value()).then((_) => _saveHistory());
  }

  // --- Persistence ---

  Future<Directory> _getChatDir() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return Directory(appSupportDir.path);
  }

  Future<void> _loadHistory() async {
    try {
      final dir = await _getChatDir();
      if (!dir.existsSync()) return;

      final file = File("${dir.path}/chat_history.json");
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _messages.clear();
        _messages.addAll(jsonList.map((e) => ChatMessage.fromJson(e)).toList());
        _streamController.add(_messages);
      }
    } catch (e) {
      debugPrint("Error loading chat history: $e");
      NotificationService().notifyError("Failed to load chat history: $e");
    }
  }

  Future<void> _saveHistory() async {
    try {
      // Keep last 100 messages to avoid bloat
      if (_messages.length > 100) {
        _messages.removeRange(0, _messages.length - 100);
        _streamController.add(_messages); // Notify UI of truncation
      }
      
      final dir = await _getChatDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final file = File("${dir.path}/chat_history.json");
      final jsonList = _messages.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint("Error saving chat history: $e");
      NotificationService().notifyError("Failed to save chat history: $e");
    }
  }
}
