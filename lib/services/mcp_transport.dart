import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:eventsource/eventsource.dart'; // Wait, do I have eventsource? Try to use basic http stream if package not added.

// I will use raw http stream since adding packages requires user approval/command.
// Actually, standard http client send() returns a StreamedResponse which is easy to parse for SSE.

abstract class McpTransport {
  Stream<Map<String, dynamic>> get incoming;
  Future<void> connect();
  Future<void> send(Map<String, dynamic> message);
  Future<void> close();
}

/// STDIO Transport (Local Process)
class StdioMcpTransport extends McpTransport {
  final String command;
  final List<String> args;
  final Map<String, String>? env;
  final String? cwd;
  
  Process? _process;
  final _incomingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  
  StdioMcpTransport({
    required this.command, 
    required this.args,
    this.env,
    this.cwd,
  });

  @override
  Stream<Map<String, dynamic>> get incoming => _incomingCtrl.stream;

  @override
  Future<void> connect() async {
    _process = await Process.start(
      command,
      args,
      workingDirectory: cwd,
      environment: env,
    );

    // Stderr
    _process!.stderr.transform(utf8.decoder).listen((log) {
      print("[StdioTransport] STDERR: $log");
    });
    
    // Stdout -> JSON
    _process!.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final msg = jsonDecode(line);
          _incomingCtrl.add(msg);
        } catch (e) {
          print("[StdioTransport] JSON Parse Error: $e\nLine: $line");
        }
      }, onDone: () {
        print("[StdioTransport] Process stdout closed");
        // We could close controller, but McpClient will handle "exitCode" externally usually
        // Or we should handle close here?
      });
      
    // Monitor exit
    _process!.exitCode.then((code) {
       print("[StdioTransport] Process exited with $code");
       // _incomingCtrl.close(); // Maybe?
    });
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_process == null) throw Exception("Not connected");
    final str = jsonEncode(message);
    _process!.stdin.writeln(str);
  }

  @override
  Future<void> close() async {
    _process?.kill();
    _process = null;
    await _incomingCtrl.close();
  }
}

/// SSE Transport (Remote HTTP)
class SseMcpTransport extends McpTransport {
  final Uri url;
  
  http.Client? _client;
  final _incomingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  
  // Endpoint to send POST requests to (discovered from SSE 'endpoint' event)
  Uri? _postEndpoint;
  String? _sessionId;
  
  SseMcpTransport(this.url);

  @override
  Stream<Map<String, dynamic>> get incoming => _incomingCtrl.stream;

  @override
  Future<void> connect() async {
    _client = http.Client();
    
    final request = http.Request('GET', url);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    request.headers['Connection'] = 'keep-alive';
    
    // We send request and get stream
    final response = await _client!.send(request);
    
    if (response.statusCode != 200) {
      throw Exception("SSE Connect Failed: ${response.statusCode}");
    }
    
    // Start listening to the stream
    _listenToSse(response.stream.toStringStream());
  }
  
  void _listenToSse(Stream<String> stream) async {
    String? currentEvent;
    String? currentData;
    
    // transform to lines
    await for (final line in stream.transform(const LineSplitter())) {
      if (line.isEmpty) {
        // End of event dispatch
        if (currentEvent != null && currentData != null) {
           _handleSseEvent(currentEvent!, currentData!);
        }
        currentEvent = null;
        currentData = null;
        continue;
      }
      
      if (line.startsWith("event: ")) {
        currentEvent = line.substring(7).trim();
      } else if (line.startsWith("data: ")) {
        currentData = line.substring(6).trim();
      }
    }
  }

  void _handleSseEvent(String event, String data) {
    if (event == "endpoint") {
      try {
        // data might be relative path or absolute URI
        // Usually it's a relative path e.g. "/messages?..."
        final uri = Uri.parse(data);
        if (uri.hasScheme) {
          _postEndpoint = uri;
        } else {
          _postEndpoint = url.resolve(data);
        }
        print("[SSE] Endpoint discovered: $_postEndpoint");
      } catch (e) {
        print("[SSE] Failed to parse endpoint: $data");
      }
    } else if (event == "message") {
      try {
         final msg = jsonDecode(data);
         _incomingCtrl.add(msg);
      } catch (e) {
         print("[SSE] JSON Parse Error: $e");
      }
    }
  }
  
  // Actually, I need a stateful parser for SSE.
  // Or I can just check if line starts with data: and try to parse it as JSON-RPC if it looks like one?
  // MCP Spec: 
  // event: endpoint
  // data: /messages?session_id=...
  //
  // event: message
  // data: { ... json rpc ... }
  
  // I will write a better parser below.
  
  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_postEndpoint == null) throw Exception("SSE not fully initialized (missing POST endpoint)");
    
    final resp = await http.post(
      _postEndpoint!,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(message),
    );
    
    if (resp.statusCode >= 400) {
      throw Exception("SSE Send Failed: ${resp.statusCode}");
    }
  }

  @override
  Future<void> close() async {
    _client?.close();
    await _incomingCtrl.close();
  }
}
