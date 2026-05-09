import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import 'cloud_account_service.dart';
import '../config/app_constants.dart';
import '../config/app_log.dart';
import '../config/cloud_providers.dart';

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

  /// 最近一次 correctText / correctTextStream 调用是否成功
  /// true = LLM 成功返回（无论是否有修改）
  /// false = 调用失败（API 错误、超时、空响应、Key 缺失等）
  bool lastCallSucceeded = false;

  void log(String msg) => _log(msg);
  void _log(String msg) => AppLog.d('[LLM] $msg');

  /// Resolve LLM config: prioritize CloudAccount, fall back to preset system.
  /// Returns (apiKey, baseUrl, model, isAnthropic).
  ({String apiKey, String baseUrl, String model, bool isAnthropic}) _resolveLlmConfig() {
    // 1. Check if a CloudAccount is selected for LLM
    final accountId = ConfigService().selectedLlmAccountId;
    if (accountId != null && accountId.isNotEmpty) {
      final account = CloudAccountService().getAccountById(accountId);
      if (account != null && account.isEnabled) {
        final provider = CloudProviders.getById(account.providerId);
        if (provider != null && provider.hasLLM) {
          final apiKey = account.credentials[provider.llmApiKeyField] ?? '';
          final baseUrl = provider.llmBaseUrl ?? '';
          // 优先用用户选择的模型，否则回退到服务商默认
          final savedModel = ConfigService().llmModelOverride;
          final model = (savedModel != null && savedModel.isNotEmpty)
              ? savedModel
              : (provider.llmDefaultModel ?? '');
          final isAnthropic = provider.llmApiFormat == LlmApiFormat.anthropic;
          _log("Resolved LLM from CloudAccount: provider=${account.providerId}, keyLen=${apiKey.length}");
          return (apiKey: apiKey, baseUrl: baseUrl, model: model, isAnthropic: isAnthropic);
        }
      }
    }

    // 2. Fall back to existing preset system
    final presetId = ConfigService().llmPresetId;
    final preset = AppConstants.kLlmPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => AppConstants.kLlmPresets.last,
    );
    return (
      apiKey: ConfigService().llmApiKey,
      baseUrl: ConfigService().llmBaseUrl,
      model: ConfigService().llmModel,
      isAnthropic: preset.apiFormat == LlmApiFormat.anthropic,
    );
  }

  /// 清洗 LLM 输出：去除推理标签（think 等）
  static String _cleanLlmOutput(String text) {
    // Remove <think>...</think> blocks (including multiline)
    var cleaned = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    // Remove standalone <think> or </think> tags (unclosed)
    cleaned = cleaned.replaceAll(RegExp(r'</?think>', caseSensitive: false), '');
    return cleaned.trim();
  }

  Future<String> correctText(String input, {List<String>? vocabHints, String? translateTo}) async {
    lastCallSucceeded = false;
    if (input.trim().isEmpty) return input;
    // translateTo 强制启用 LLM（即使 AI 润色关闭）
    if (!ConfigService().aiCorrectionEnabled && translateTo == null) {
      _log("RAW INPUT (AI OFF): len=${input.length}");
      return input;
    }

    final providerType = ConfigService().llmProviderType;
    String result;
    if (providerType == 'ollama') {
      result = await _correctTextOllama(input, vocabHints: vocabHints, translateTo: translateTo);
    } else {
      final resolved = _resolveLlmConfig();
      if (resolved.isAnthropic) {
        result = await _correctTextAnthropic(input, vocabHints: vocabHints, resolved: resolved, translateTo: translateTo);
      } else {
        result = await _correctTextCloud(input, vocabHints: vocabHints, resolved: resolved, translateTo: translateTo);
      }
    }
    // lastCallSucceeded 由各 _correctText* 方法在成功时设为 true
    return _cleanLlmOutput(result);
  }

  /// Streaming version: yields incremental text chunks as they arrive from LLM.
  /// Falls back to non-streaming for Anthropic/Ollama.
  Stream<String> correctTextStream(String input, {List<String>? vocabHints, String? translateTo}) async* {
    lastCallSucceeded = false;
    if (input.trim().isEmpty) {
      yield input;
      return;
    }
    if (!ConfigService().aiCorrectionEnabled && translateTo == null) {
      _log("RAW INPUT (AI OFF): len=${input.length}");
      yield input;
      return;
    }

    final providerType = ConfigService().llmProviderType;
    if (providerType == 'ollama') {
      yield await _correctTextOllama(input, vocabHints: vocabHints, translateTo: translateTo);
      return;
    }
    final resolved = _resolveLlmConfig();
    if (resolved.isAnthropic) {
      yield await _correctTextAnthropic(input, vocabHints: vocabHints, resolved: resolved, translateTo: translateTo);
      return;
    }
    yield* _correctTextCloudStream(input, vocabHints: vocabHints, resolved: resolved, translateTo: translateTo);
  }

  /// SSE streaming for OpenAI-compatible APIs
  Stream<String> _correctTextCloudStream(String input, {List<String>? vocabHints, ({String apiKey, String baseUrl, String model, bool isAnthropic})? resolved, String? translateTo}) async* {
    final r = resolved ?? _resolveLlmConfig();
    final apiKey = r.apiKey;
    final baseUrl = r.baseUrl;
    final model = r.model;
    final systemPrompt = _buildSystemPrompt(translateTo: translateTo);

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      yield input;
      return;
    }

    _log("RAW INPUT (${input.length}字): '$input'");
    _log("Calling Cloud LLM (stream): $baseUrl, model=$model");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/chat/completions');

      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "temperature": AppConstants.kLlmDefaultTemperature,
        "stream": true,
      };
      _applyModelSpecificParams(body, model);

      final request = http.Request('POST', uri)
        ..headers.addAll({
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        })
        ..body = jsonEncode(body);

      final streamedResponse = await client.send(request).timeout(AppConstants.kLlmStreamTimeout);

      if (streamedResponse.statusCode != 200) {
        final respBody = await streamedResponse.stream.bytesToString();
        _log("LLM STREAM ERROR: ${streamedResponse.statusCode} - $respBody");
        yield input;
        return;
      }

      final fullBuffer = StringBuffer();
      String lineBuffer = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        lineBuffer += chunk;
        final lines = lineBuffer.split('\n');
        // Keep the last (possibly incomplete) line in buffer
        lineBuffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
          final data = trimmed.substring(6);
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data);
            final delta = json['choices']?[0]?['delta']?['content']?.toString();
            if (delta != null && delta.isNotEmpty) {
              fullBuffer.write(delta);
              yield delta; // Yield incremental chunk
            }
          } catch (_) {}
        }
      }

      final result = fullBuffer.toString().trim();
      if (result.isNotEmpty) {
        lastCallSucceeded = true;
      }
      _log("LLM STREAM SUCCESS (${result.length}字, differs=${result != input}): '$result'");
    } catch (e) {
      _log("LLM STREAM EXCEPTION: $e");
      yield input;
    }
  }

  /// Language code → human-readable name (for prompt injection)
  static const _langNames = {
    'zh': '中文', 'zh-Hans': '简体中文', 'zh-Hant': '繁體中文',
    'en': 'English', 'ja': '日本語', 'ko': '한국어', 'yue': '粤语',
    'es': 'Español', 'fr': 'Français', 'de': 'Deutsch',
    'ru': 'Русский', 'pt': 'Português',
  };

  /// Build effective system prompt with language/translation constraints.
  /// [translateTo] overrides outputLanguage for one-shot quick translate.
  String _buildSystemPrompt({String? translateTo}) {
    final base = ConfigService().aiCorrectionPrompt;
    final input = ConfigService().inputLanguage;
    final output = translateTo ?? ConfigService().outputLanguage;

    // No constraint when both are auto
    if (output == 'auto' && input == 'auto') return base;

    final parts = <String>[base];

    // Determine if translation is needed
    final inputBase = input == 'auto' ? null : input;
    final outputBase = output == 'auto' ? null : (output.startsWith('zh') ? 'zh' : output);
    final isTranslation = inputBase != null && outputBase != null && inputBase != outputBase;

    if (isTranslation) {
      final inputName = _langNames[input] ?? input;
      final outputName = _langNames[output] ?? output;
      parts.add('6. The input is $inputName speech. Translate it into $outputName while fixing errors.');
    } else if (output != 'auto') {
      // Same language, just enforce script/language
      final outputName = _langNames[output] ?? output;
      parts.add('6. 输出必须使用$outputName。');
    }

    return parts.join('\n');
  }

  String _buildUserMessage(String input, {List<String>? vocabHints}) {
    final vocabSection = (vocabHints != null && vocabHints.isNotEmpty)
        ? '\n\n<vocab_hints>\n${vocabHints.join(', ')}\n</vocab_hints>'
        : '';
    return '<speech_text>\n$input\n</speech_text>$vocabSection';
  }

  /// 模型特定参数注入。DeepSeek V4 默认开 thinking mode，会让总耗时翻 2x+
  /// （实测 v4-flash thinking ON 总耗时 2386ms vs OFF 1050ms）。
  /// SpeakOut 的短句润色 / 翻译 / 梳理场景都不需要思考链，强制关闭。
  void _applyModelSpecificParams(Map<String, dynamic> body, String model) {
    if (model.startsWith('deepseek-v4')) {
      body['thinking'] = {'type': 'disabled'};
    }
  }

  Future<String> _correctTextCloud(String input, {List<String>? vocabHints, ({String apiKey, String baseUrl, String model, bool isAnthropic})? resolved, String? translateTo}) async {
    final r = resolved ?? _resolveLlmConfig();
    final apiKey = r.apiKey;
    final baseUrl = r.baseUrl;
    final model = r.model;
    final systemPrompt = _buildSystemPrompt(translateTo: translateTo);

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      return input;
    }

    _log("RAW INPUT (${input.length}字): '$input'");
    _log("Calling Cloud LLM: $baseUrl, model=$model");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/chat/completions');

      final body = {
        "model": model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "temperature": AppConstants.kLlmDefaultTemperature,
      };
      _applyModelSpecificParams(body, model);

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode(body),
      ).timeout(AppConstants.kLlmSyncTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = json['choices']?[0]?['message']?['content']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("LLM SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): '${content.trim()}'");
          lastCallSucceeded = true;
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

  Future<String> _correctTextAnthropic(String input, {List<String>? vocabHints, ({String apiKey, String baseUrl, String model, bool isAnthropic})? resolved, String? translateTo}) async {
    final r = resolved ?? _resolveLlmConfig();
    final apiKey = r.apiKey;
    final baseUrl = r.baseUrl;
    final model = r.model;
    final systemPrompt = _buildSystemPrompt(translateTo: translateTo);

    if (apiKey.isEmpty) {
      _log("API Key MISSING. Returning input.");
      return input;
    }

    _log("RAW INPUT (${input.length}字): '$input'");
    _log("Calling Anthropic: $baseUrl, model=$model");

    try {
      final client = _effectiveClient;
      final uri = Uri.parse('$baseUrl/v1/messages');

      final body = {
        "model": model,
        "max_tokens": AppConstants.kAnthropicMaxTokens,
        "system": systemPrompt,
        "messages": [
          {"role": "user", "content": _buildUserMessage(input, vocabHints: vocabHints)}
        ],
        "temperature": AppConstants.kLlmDefaultTemperature,
      };

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": AppConstants.kAnthropicApiVersion,
        },
        body: jsonEncode(body),
      ).timeout(AppConstants.kLlmSyncTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = (json['content'] as List?)
            ?.firstWhere((b) => b['type'] == 'text', orElse: () => null)
            ?['text']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("Anthropic SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): '${content.trim()}'");
          lastCallSucceeded = true;
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

  Future<String> _correctTextOllama(String input, {List<String>? vocabHints, String? translateTo}) async {
    final baseUrl = ConfigService().ollamaBaseUrl;
    final model = ConfigService().ollamaModel;
    final systemPrompt = _buildSystemPrompt(translateTo: translateTo);

    _log("RAW INPUT (${input.length}字): '$input'");
    _log("Calling Ollama: $baseUrl, model=$model");

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
          "temperature": AppConstants.kLlmDefaultTemperature,
        },
      };

      final response = await client.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(AppConstants.kLlmSyncTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final content = json['message']?['content']?.toString();
        if (content != null && content.isNotEmpty) {
          _log("Ollama SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): '${content.trim()}'");
          lastCallSucceeded = true;
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
  
  /// AI 梳理：深度重组文字结构（非流式，一次性返回完整结果）
  /// 使用独立的 organizePrompt，复用已配置的 LLM 服务商。
  Future<String> organizeText(String input) async {
    if (input.trim().isEmpty) return input;

    final providerType = ConfigService().llmProviderType;
    final organizePrompt = ConfigService().organizePrompt;

    if (providerType == 'ollama') {
      return _callLlmGeneric(
        input: input,
        systemPrompt: organizePrompt,
        callOllama: true,
      );
    }

    final resolved = _resolveLlmConfig();
    if (resolved.apiKey.isEmpty) {
      _log("[Organize] API Key MISSING");
      return '';
    }

    return _callLlmGeneric(
      input: input,
      systemPrompt: organizePrompt,
      resolved: resolved,
    );
  }

  /// 通用 LLM 调用（非流式），支持自定义 system prompt
  Future<String> _callLlmGeneric({
    required String input,
    required String systemPrompt,
    ({String apiKey, String baseUrl, String model, bool isAnthropic})? resolved,
    bool callOllama = false,
  }) async {
    _log("[Generic] inputLen=${input.length}");

    try {
      final client = _effectiveClient;

      if (callOllama) {
        final baseUrl = ConfigService().ollamaBaseUrl;
        final model = ConfigService().ollamaModel;
        final resp = await client.post(
          Uri.parse('$baseUrl/api/chat'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "model": model,
            "messages": [
              {"role": "system", "content": systemPrompt},
              {"role": "user", "content": input},
            ],
            "stream": false,
            "think": false,
            "options": {"temperature": AppConstants.kLlmDefaultTemperature},
          }),
        ).timeout(AppConstants.kOrganizeTimeout);
        if (resp.statusCode == 200) {
          final content = jsonDecode(utf8.decode(resp.bodyBytes))['message']?['content']?.toString();
          return _cleanLlmOutput(content?.trim() ?? '');
        }
        _log("[Generic] Ollama ERROR: ${resp.statusCode}");
        return '';
      }

      final r = resolved!;
      if (r.isAnthropic) {
        final resp = await client.post(
          Uri.parse('${r.baseUrl}/v1/messages'),
          headers: {
            "Content-Type": "application/json",
            "x-api-key": r.apiKey,
            "anthropic-version": AppConstants.kAnthropicApiVersion,
          },
          body: jsonEncode({
            "model": r.model,
            "max_tokens": AppConstants.kAnthropicMaxTokens,
            "system": systemPrompt,
            "messages": [{"role": "user", "content": input}],
            "temperature": AppConstants.kLlmDefaultTemperature,
          }),
        ).timeout(AppConstants.kOrganizeTimeout);
        if (resp.statusCode == 200) {
          final content = (jsonDecode(utf8.decode(resp.bodyBytes))['content'] as List?)
              ?.firstWhere((b) => b['type'] == 'text', orElse: () => null)?['text']?.toString();
          return _cleanLlmOutput(content?.trim() ?? '');
        }
        _log("[Generic] Anthropic ERROR: ${resp.statusCode}");
        return '';
      }

      // OpenAI-compatible
      final body = <String, dynamic>{
        "model": r.model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": input},
        ],
        "temperature": AppConstants.kLlmDefaultTemperature,
      };
      _applyModelSpecificParams(body, r.model);
      final resp = await client.post(
        Uri.parse('${r.baseUrl}/chat/completions'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${r.apiKey}",
        },
        body: jsonEncode(body),
      ).timeout(AppConstants.kOrganizeTimeout);
      if (resp.statusCode == 200) {
        final content = jsonDecode(utf8.decode(resp.bodyBytes))['choices']?[0]?['message']?['content']?.toString();
        return _cleanLlmOutput(content?.trim() ?? '');
      }
      _log("[Generic] Cloud ERROR: ${resp.statusCode} - ${resp.body}");
      return '';
    } catch (e) {
      _log("[Generic] EXCEPTION: $e");
      return '';
    }
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
          headers: {"Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": AppConstants.kAnthropicApiVersion},
          body: jsonEncode({"model": model, "max_tokens": 5, "messages": [{"role": "user", "content": "Hi"}]}),
        ).timeout(AppConstants.kLlmTestTimeout);
        _log("TEST: Anthropic response ${resp.statusCode}");
        if (resp.statusCode == 200) return (true, '连接成功 ($model)');
        final body = jsonDecode(resp.body);
        return (false, '${resp.statusCode}: ${body['error']?['message'] ?? resp.body}');
      } else {
        final resp = await client.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
          body: jsonEncode({"model": model, "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 5}),
        ).timeout(AppConstants.kLlmTestTimeout);
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
      ).timeout(AppConstants.kLlmTestTimeout);
      if (resp.statusCode == 200) return (true, '连接成功 ($model)');
      return (false, '${resp.statusCode}: ${resp.body}');
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Imports for routing
  Future<Map<String, dynamic>?> routeIntent(String input, List<dynamic> tools) async {
    if (!ConfigService().aiCorrectionEnabled) return null;

    final resolved = _resolveLlmConfig();
    final apiKey = resolved.apiKey;
    final baseUrl = resolved.baseUrl;
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
      _applyModelSpecificParams(body, model);

      final response = await client.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode(body),
      ).timeout(AppConstants.kLlmSyncTimeout);

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
