import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config_service.dart';
import 'mcp_config_service.dart';
import 'mcp_client.dart';
import 'chat_service.dart';
import 'llm_service.dart';
import 'notification_service.dart';

/// Represents a pending tool execution awaiting user approval
class PendingToolCall {
  final String id;
  final String toolName;
  final Map<String, dynamic> arguments;
  final Completer<bool> completer;
  
  PendingToolCall({
    required this.id,
    required this.toolName,
    required this.arguments,
  }) : completer = Completer<bool>();
  
  void approve() => completer.complete(true);
  void deny() => completer.complete(false);
}

class AgentService {
  static final AgentService _instance = AgentService._internal();
  factory AgentService() => _instance;
  AgentService._internal();

  final List<McpClient> _clients = [];
  bool _isInit = false;
  
  // Status Monitoring
  final StreamController<Map<String, McpConnectionStatus>> _statusController = StreamController.broadcast();
  Stream<Map<String, McpConnectionStatus>> get statusStream => _statusController.stream;
  
  Map<String, McpConnectionStatus> get serverStatuses {
    final Map<String, McpConnectionStatus> map = {};
    for (var client in _clients) {
      map[client.config.id] = client.status;
    }
    return map;
  }
  
  // Stream for pending confirmations (UI listens to this)
  final _pendingController = StreamController<PendingToolCall>.broadcast();
  Stream<PendingToolCall> get pendingConfirmations => _pendingController.stream;

  Future<void> init() async {
    if (_isInit) return;
    
    // Listen for config changes (dynamic reload)
    McpConfigService().addListener(_onConfigChanged);
    
    await _connectAll();
    _isInit = true;
  }
  
  void _onConfigChanged() {
    debugPrint("[Agent] Config changed, reconnecting...");
    _reconnectAll();
  }
  
  Future<void> _reconnectAll() async {
    // Disconnect all
    for (var client in _clients) {
      try { 
         client.dispose(); // Important: Stop listening to old streams
      } catch (_) {}
    }
    _clients.clear();
    
    // Reconnect
    await _connectAll();
  }
  
  Future<void> _connectAll() async {
    final configs = McpConfigService().servers.where((s) => s.enabled).toList();
    
    for (var config in configs) {
       final client = McpClient(config);
       _clients.add(client); // Add immediately so UI sees "Disconnected/Connecting"
       
       // Listen to status changes
       client.statusStream.listen((status) {
         _statusController.add(serverStatuses); // Broadcast aggregate update
         
         if (status == McpConnectionStatus.disconnected || status == McpConnectionStatus.error) {
           _scheduleReconnect(client);
         }
       });
       
       try {
         await client.connect();
         debugPrint("[Agent] Connected to ${config.label}");
       } catch (e) {
         debugPrint("[Agent] Failed to connect to ${config.label}: $e");
         // The status stream listener above will catch the error state
       }
    }
    // Update initial UI
    _statusController.add(serverStatuses);
  }
  
  // Exponential Backoff Reconnect
  final Map<String, int> _retryCounts = {};
  
  void _scheduleReconnect(McpClient client) async {
    final id = client.config.id;
    if (!McpConfigService().servers.any((s) => s.id == id && s.enabled)) return; // Stopped by user
    
    int retries = _retryCounts[id] ?? 0;
    if (retries > 5) {
      debugPrint("[Agent] Giving up on ${client.config.label} after 5 retries.");
      return; 
    }
    
    final delay = Duration(seconds: (retries + 1) * 2); 
    debugPrint("[Agent] Scheduling reconnect for ${client.config.label} in ${delay.inSeconds}s (Attempt ${retries+1})");
    
    _retryCounts[id] = retries + 1;
    
    await Future.delayed(delay);
    
    if (client.status != McpConnectionStatus.connected) {
       try {
         await client.restart(); // This triggers Connect -> Status change -> Reset retry if success?
         // Actually restart() calls connect(), which sets status to connected.
       } catch (e) {
         debugPrint("[Agent] Reconnect failed: $e");
         // Will stay disconnected/error, triggering loop again via listener? 
         // No, listener fires on CHANGE. If it stays error, it might not fire.
         // But connect() sets status to Connecting -> Error. So it WILL fire.
       }
    }
    
    if (client.isConnected) {
       _retryCounts[id] = 0; // Reset on success
    }
  }
  
  void retryServer(String serverId) {
     final client = _clients.firstWhere((c) => c.config.id == serverId, orElse: () => throw "Server not found");
     _retryCounts[serverId] = 0; // Reset
     client.restart();
  }
  
  /// The main entry point for the "Agent Brain"
  Future<void> process(String text) async {
    // 1. Check for Tools
    if (_clients.isEmpty) {
      ChatService().addInfo("⚠️ No MCP tools connected. Please add tools in Settings -> MCP Agents to enable capabilities.");
      return;
    }
    
    final allTools = _clients.where((c) => c.isConnected).expand((c) => c.tools).toList();
    if (allTools.isEmpty) {
       ChatService().addInfo("⚠️ No active tools found. Please check your MCP server connections.");
       return;
    }
    
    debugPrint("[Agent] Analyzing: '$text' with ${allTools.length} tools.");
    ChatService().addInfo("🤔 Analyzing intent with ${allTools.length} tools...");
    
    // 2. Ask LLM (Router)
    final toolCall = await LLMService().routeIntent(text, allTools);
    
    if (toolCall != null) {
      final name = toolCall['name'] as String;
      final args = Map<String, dynamic>.from(toolCall['arguments'] ?? {});
      
      debugPrint("[Agent] Intent Detected: $name($args)");
      ChatService().addInfo("🎯 Intent Detected: $name");
      
      // 3. User Confirmation (HITL Security)
      final pending = PendingToolCall(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        toolName: name,
        arguments: args,
      );
      
      // Emit to UI
      _pendingController.add(pending);
      
      // Wait for user decision
      await _logCommand(name, args, "PENDING");
      final approved = await pending.completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false, // Auto-deny after 30s
      );
      
      if (!approved) {
        debugPrint("[Agent] User denied: $name");
        await _logCommand(name, args, "DENIED");
        ChatService().addToolResult(name, "User Denied Execution");
        return;
      }
      
      // 4. Execute
      try {
        for (var client in _clients) {
            // Check tools from CONNECTED clients only
           if (client.isConnected && client.tools.any((t) => t.name == name)) {
              debugPrint("[Agent] Executing on ${client.config.label}...");
              ChatService().addInfo("⚙️ Executing on ${client.config.label}...");
              
              final result = await client.callTool(name, args);
              
              debugPrint("[Agent] Result: $result");
              await _logCommand(name, args, "SUCCESS", result: result);
              ChatService().addToolResult(name, result);
              return;
           }
        }
        debugPrint("[Agent] Tool $name not found in connected clients.");
        ChatService().addToolResult(name, "Tool not found (Server disconnected?)");
      } catch (e) {
        debugPrint("[Agent] Execution Failed: $e");
        await _logCommand(name, args, "ERROR", result: {"error": e.toString()});
        ChatService().addToolResult(name, "Error: $e");
      }
    } else {
      debugPrint("[Agent] No intent matched.");
      ChatService().addInfo("📝 No command matched. Saved as Context/Note.");
    }
  }
  
  Future<void> _logCommand(String tool, dynamic args, String status, {dynamic result}) async {
    final dir = Directory(ConfigService().diaryDirectory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    
    final f = File("${dir.path}/commands.log");
    final time = DateTime.now().toIso8601String();
    final logEntry = jsonEncode({
      "timestamp": time,
      "tool": tool,
      "args": args,
      "status": status,
      if (result != null) "result": result
    });
    
    try {
      if (!await f.exists()) await f.parent.create(recursive: true);
      await f.writeAsString("$logEntry\n", mode: FileMode.append);
    } catch (e) {
      NotificationService().notifyError("Failed to log command: $e");
    }
  }
}
