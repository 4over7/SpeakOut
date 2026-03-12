import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import '../config/app_constants.dart';

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

  void log(String msg) => _log(msg);
  void _log(String msg) {
    final line = "[${DateTime.now().toIso8601String()}] [LLM] $msg\n";
    try {
      File('/tmp/SpeakOut.log').writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {}
  }

  Future<String> correctText(String input, {List<String>? vocabHints}) async {
    if (input.trim().isEmpty) return input;
    if (!ConfigService().aiCorrectionEnabled) {
      _log("RAW INPUT (AI OFF): $input");
      return input;
    }

    final providerType = ConfigService().llmProviderType;
    if (providerType == 'ollama') {
      return _correctTextOllama(input, vocabHints: vocabHints);
    }
    // Check if current preset uses Anthropic format
    final presetId = ConfigService().llmPresetId;
    final preset = AppConstants.kLlmPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => AppConstants.kLlmPresets.last,
    );
    if (preset.apiFormat == LlmApiFormat.anthropic) {
      return _correctTextAnthropic(input, vocabHints: vocabHints);
    }
    return _correctTextCloud(input, vocabHints: vocabHints);
  }

  String _buildUserMessage(String input, {List<String>? vocabHints}) {
    final vocabSection = (vocabHints != null && vocabHints.isNotEmpty)
        ? '\n\n<vocab_hints>\n${vocabHints.join(', ')}\n</vocab_hints>'
        : '';
    return '<speech_text>\n$input\n</speech_text>$vocabSection';
  }

  Future<String> _correctTextCloud(String input, {List<String>? vocabHints}) async {
    final apiKey = ConfigService().llmApiKey;
    final baseUrl = ConfigService().llmBaseUrl;
    final model = ConfigService().llmModel;
    final systemPrompt = ConfigService().aiCorrectionPrompt;

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      return input;
    }

    _log("RAW INPUT: $input");
    _log("Calling Cloud LLM: $baseUrl, model=$model, inputLen=${input.length}");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/chat/completions');

      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "temperature": 0.3,
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

    return input;
  }

  Future<String> _correctTextAnthropic(String input, {List<String>? vocabHints}) async {
    final apiKey = ConfigService().llmApiKey;
    final baseUrl = ConfigService().llmBaseUrl;
    final model = ConfigService().llmModel;
    final systemPrompt = ConfigService().aiCorrectionPrompt;

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      return input;
    }

    _log("RAW INPUT: $input");
    _log("Calling Anthropic: $baseUrl, model=$model, inputLen=${input.length}");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/v1/messages');

      final body = {
        "model": model,
        "max_tokens": 1024,
        "system": systemPrompt,
        "messages": [
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "temperature": 0.3,
      };

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = (json['content'] as List?)
            ?.firstWhere((b) => b['type'] == 'text', orElse: () => null)
            ?['text']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("Anthropic SUCCESS. Output differs: ${content.trim() != input}");
          return content.trim();
        }
        _log("Anthropic returned empty content.");
      } else {
        _log("Anthropic ERROR: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      _log("Anthropic EXCEPTION: $e");
    }

    return input;
  }

  Future<String> _correctTextOllama(String input, {List<String>? vocabHints}) async {
    final baseUrl = ConfigService().ollamaBaseUrl;
    final model = ConfigService().ollamaModel;
    final systemPrompt = ConfigService().aiCorrectionPrompt;

    _log("RAW INPUT: $input");
    _log("Calling Ollama: $baseUrl, model=$model, inputLen=${input.length}");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/api/chat');

      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "stream": false,
        "think": false,
        "options": {
          "temperature": 0.3,
        },
      };

      final response = await client.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = json['message']?['content']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("Ollama SUCCESS. Output differs: ${content.trim() != input}");
          return content.trim();
        }
        _log("Ollama returned empty content.");
      } else {
        _log("Ollama ERROR: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      _log("Ollama EXCEPTION: $e");
    }

    return input;
  }
  
  /// Test LLM connection with explicit parameters (no Keychain dependency)
  Future<(bool, String)> testConnectionWith({
    required String apiKey,
    required String baseUrl,
    required String model,
    required LlmApiFormat apiFormat,
  }) async {
    _log("TEST: apiFormat=$apiFormat, baseUrl=$baseUrl, model=$model, keyLen=${apiKey.length}");
    if (apiKey.isEmpty) return (false, 'API Key 未设置');
    if (baseUrl.isEmpty) return (false, 'Base URL 未设置');
    if (model.isEmpty) return (false, 'Model 未设置');
    try {
      final client = _effectiveClient;
      if (apiFormat == LlmApiFormat.anthropic) {
        final resp = await client.post(
          Uri.parse('$baseUrl/v1/messages'),
          headers: {"Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01"},
          body: jsonEncode({"model": model, "max_tokens": 5, "messages": [{"role": "user", "content": "Hi"}]}),
        ).timeout(const Duration(seconds: 15));
        _log("TEST: Anthropic response ${resp.statusCode}");
        if (resp.statusCode == 200) return (true, '连接成功 ($model)');
        final body = jsonDecode(resp.body);
        return (false, '${resp.statusCode}: ${body['error']?['message'] ?? resp.body}');
      } else {
        final resp = await client.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
          body: jsonEncode({"model": model, "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 5}),
        ).timeout(const Duration(seconds: 15));
        _log("TEST: OpenAI response ${resp.statusCode}");
        if (resp.statusCode == 200) return (true, '连接成功 ($model)');
        final body = jsonDecode(resp.body);
        return (false, '${resp.statusCode}: ${body['error']?['message'] ?? resp.body}');
      }
    } catch (e) {
      _log("TEST: exception $e");
      return (false, e.toString());
    }
  }

  /// Test Ollama connection
  Future<(bool, String)> testOllamaConnection() async {
    final baseUrl = ConfigService().ollamaBaseUrl;
    final model = ConfigService().ollamaModel;
    try {
      final resp = await _effectiveClient.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"model": model, "messages": [{"role": "user", "content": "Hi"}], "stream": false}),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return (true, '连接成功 ($model)');
      return (false, '${resp.statusCode}: ${resp.body}');
    } catch (e) {
      return (false, e.toString());
    }
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
