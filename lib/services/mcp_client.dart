import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mcp_config_service.dart';

enum McpConnectionStatus {
  disconnected,
  connecting,
  connected,
  error
}

/// Represents a single tool discovered from an MCP server
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpTool({required this.name, required this.description, required this.inputSchema});

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'],
      description: json['description'] ?? '',
      inputSchema: json['inputSchema'] ?? {},
    );
  }
}

/// A client connection to a single MCP Server process.
class McpClient {
  final McpServerConfig config;
  Process? _process;
  int _msgId = 0;
  
  // Status Stream
  final StreamController<McpConnectionStatus> _statusController = StreamController.broadcast();
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  McpConnectionStatus get status => _status;
  
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  final List<McpTool> _tools = [];
  
  bool get isConnected => _status == McpConnectionStatus.connected;
  List<McpTool> get tools => List.unmodifiable(_tools);

  McpClient(this.config);

  /// Connect (Launch Process)
  Future<void> connect() async {
    if (_process != null) return;
    
    _updateStatus(McpConnectionStatus.connecting);
    
    try {
      _process = await Process.start(
        config.command,
        config.args,
        workingDirectory: config.cwd,
        environment: config.env,
      );
      
      // Monitor Exit
      _process!.exitCode.then((code) {
        print("[MCP] Process ${config.label} exited with code $code");
        _cleanup();
        _updateStatus(McpConnectionStatus.disconnected);
      });

      // Listen to Stdout (JSON-RPC)
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleResponse, onError: (e) {
             print("[MCP] Error: $e");
             _updateStatus(McpConnectionStatus.error);
          });

      // Listen to Stderr (Logs)
      _process!.stderr
          .transform(utf8.decoder)
          .listen((log) => print("[MCP STDERR] (${config.label}) $log"));
          
      // Protocol Handshake
      await _initialize();
      await _discoverTools();
      
      _updateStatus(McpConnectionStatus.connected);
      
    } catch (e) {
      print("[MCP] Connect Failed: $e");
      _updateStatus(McpConnectionStatus.error);
      _cleanup();
      // Don't rethrow, just statused as error
    }
  }
  
  Future<void> restart() async {
    print("[MCP] Restarting ${config.label}...");
    await disconnect();
    await Future.delayed(const Duration(seconds: 1)); // Grace period
    await connect();
  }
  
  void _cleanup() {
    _process?.kill();
    _process = null;
    _pendingRequests.values.forEach((c) => c.completeError("Connection Closed"));
    _pendingRequests.clear();
  }

  Future<void> disconnect() async {
    _cleanup();
    _updateStatus(McpConnectionStatus.disconnected);
  }
  
  void _updateStatus(McpConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
    }
  }

  // --- RPC Methods ---

  Future<void> _initialize() async {
    // 1. Send Initialize
    final result = await _sendRequest('initialize', {
      "protocolVersion": "2024-11-05", // Spec version
      "capabilities": {
        "roots": {"listChanged": false},
        "sampling": {}
      },
      "clientInfo": {"name": "SpeakOut", "version": "3.5.0"}
    });
    
    // 2. Send Initialized Notification
    _sendNotification('notifications/initialized', {});
  }

  Future<void> _discoverTools() async {
    // Spec: tools/list
    final result = await _sendRequest('tools/list', {});
    if (result != null && result['tools'] != null) {
      final list = result['tools'] as List;
      _tools.clear();
      _tools.addAll(list.map((e) => McpTool.fromJson(e)));
      print("[MCP] Discovered ${_tools.length} tools from ${config.label}");
    }
  }

  Future<dynamic> callTool(String toolName, Map<String, dynamic> args) async {
    if (!isConnected) throw Exception("Client not connected");
    return _sendRequest('tools/call', {
      "name": toolName,
      "arguments": args
    });
  }

  // --- Low Level RPC ---

  Future<dynamic> _sendRequest(String method, Map<String, dynamic>? params) {
    final id = _msgId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final req = {
      "jsonrpc": "2.0",
      "id": id,
      "method": method,
      if (params != null) "params": params
    };
    
    _sendJson(req);
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: (){
      _pendingRequests.remove(id);
      throw TimeoutException("RPC Timeout");
    });
  }

  void _sendNotification(String method, Map<String, dynamic>? params) {
    final req = {
      "jsonrpc": "2.0",
      "method": method,
      if (params != null) "params": params
    };
    _sendJson(req);
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_process == null) return;
    final str = jsonEncode(data);
    _process!.stdin.writeln(str);
  }

  void _handleResponse(String line) {
    if (line.trim().isEmpty) return;
    try {
      final Map<String, dynamic> msg = jsonDecode(line);
      
      if (msg.containsKey('id')) {
        final id = msg['id'] as int;
        final completer = _pendingRequests.remove(id);
        
        if (completer != null) {
          if (msg.containsKey('error')) {
            completer.completeError(msg['error']);
          } else {
            completer.complete(msg['result']);
          }
        }
      } else {
        // Notification or non-response message
      }
    } catch (e) {
      print("[MCP] Parse Error: $line");
    }
  }
  
  void dispose() {
    _statusController.close();
    disconnect();
  }
}
