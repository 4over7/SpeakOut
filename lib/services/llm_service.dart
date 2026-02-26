import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  /// Clients can be injected for testing.
  /// When not injected, a shared default client is used.
  http.Client? _client;
  http.Client? _defaultClient;

  void setClient(http.Client client) {
    _client = client;
  }

  http.Client get _effectiveClient {
    if (_client != null) return _client!;
    _defaultClient ??= http.Client();
    return _defaultClient!;
  }

  void _log(String msg) {
    final time = DateTime.now().toIso8601String();
    File('/tmp/SpeakOut_debug.log')
        .writeAsString("[$time] [LLM] $msg\n", mode: FileMode.append)
        .ignore();
  }

  Future<String> correctText(String input) async {
    if (input.trim().isEmpty) return input;
    if (!ConfigService().aiCorrectionEnabled) {
      _log("RAW INPUT (AI OFF): $input");
      return input;
    }
    
    final apiKey = ConfigService().llmApiKey;
    final baseUrl = ConfigService().llmBaseUrl;
    final model = ConfigService().llmModel;
    final systemPrompt = ConfigService().aiCorrectionPrompt;

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      return input;
    }

    _log("RAW INPUT: $input");
    _log("Calling LLM: $baseUrl, model=$model, inputLen=${input.length}");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/chat/completions');
      
      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": "<speech_text>\n$input\n</speech_text>"}
        ],
        "temperature": 0.3, // Low temperature for deterministic cleanup
      };

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10)); // Safety timeout

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = json['choices']?[0]?['message']?['content']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("LLM SUCCESS. Output differs: ${content.trim() != input}");
          return content.trim();
        }
        _log("LLM returned empty content.");
      } else {
        _log("LLM ERROR: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      _log("LLM EXCEPTION: $e");
    }

    // Fallback: return original input if anything fails
    return input;
  }
  
  // Imports for routing
  Future<Map<String, dynamic>?> routeIntent(String input, List<dynamic> tools) async {
    if (!ConfigService().aiCorrectionEnabled) return null;
    
    final apiKey = ConfigService().llmApiKey;
    final baseUrl = ConfigService().llmBaseUrl;
    final model = ConfigService().agentRouterModel; // Use dedicated router model
    
    if (apiKey.isEmpty) return null;
    
    // Construct Tool Definitions
    final toolsDesc = tools.map((t) => "- ${t.name}: ${t.description}\n  Schema: ${jsonEncode(t.inputSchema)}").join("\n");
    
    final routerPrompt = """
You are an Intent Router. 
Your task is to decide if the user's input matches any of the available tools.

Available Tools:
$toolsDesc

Rules:
1. If the user input explicitly asks to perform an action covered by a tool, output a JSON object:
   {"tool": "tool_name", "arguments": { ... }}
2. If the user input is just a thought, a note, or does not match any tool, output EXACTLY the string: "NOTE"
3. Do not output markdown code blocks. Just the raw JSON or "NOTE".
""";

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/chat/completions');
      
      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": routerPrompt},
          {"role": "user", "content": input}
        ],
        "temperature": 0.1, // Very strict
      };

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = json['choices']?[0]?['message']?['content']?.toString().trim();
        
        if (content == null || content == "NOTE") return null;
        
        // Try parse JSON
        try {
           // Remove markdown backticks if present (lazy cleanup)
           final clean = content.replaceAll("```json", "").replaceAll("```", "").trim();
           final Map<String, dynamic> result = jsonDecode(clean);
           if (result.containsKey('tool')) {
             return {
               "name": result['tool'],
               "arguments": result['arguments'] ?? {}
             };
           }
        } catch (e) {
          _log("Router JSON Parse Error: $e");
        }
      }
    } catch (e) {
      _log("Router Exception: $e");
    }
    
    return null;
  }
}
