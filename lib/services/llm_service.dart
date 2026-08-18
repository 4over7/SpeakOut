import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import 'cloud_account_service.dart';
import '../models/cloud_account.dart';
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

  /// 释放默认 client（应用退出时调用）。注入的 _client 由注入方负责。
  void dispose() {
    _defaultClient?.close();
    _defaultClient = null;
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
    CloudAccount? account;
    bool fromRecommendation = false;
    if (accountId != null && accountId.isNotEmpty) {
      final candidate = CloudAccountService().getAccountById(accountId);
      if (candidate != null && candidate.isEnabled) {
        account = candidate;
      }
    }
    // selectedLlmAccountId 为空 / 失效 → 按推荐优先级兜底（避免落到豆包 lite 等弱模型）
    if (account == null) {
      account = CloudAccountService().pickRecommendedLlmAccount();
      fromRecommendation = account != null;
    }

    if (account != null) {
      final provider = CloudProviders.getById(account.providerId);
      if (provider != null && provider.hasLLM) {
        final apiKey = account.credentials[provider.llmApiKeyField] ?? '';
        final baseUrl = provider.llmBaseUrl ?? '';
        // selectedLlmAccountId 命中时尊重用户的 model 选择；推荐兜底时强制用服务商默认模型。
        // 仅当全局 model 归属当前 account 时才用，否则用 provider 默认——
        // 防止用户为 provider A 选的 model 名被打到 provider B（C2）。
        final savedModel = ConfigService().llmModelOverride;
        final modelOwner = ConfigService().llmModelOwnerAccountId;
        final model = (!fromRecommendation &&
                savedModel != null && savedModel.isNotEmpty &&
                modelOwner == account.id)
            ? savedModel
            : (provider.llmDefaultModel ?? '');
        final isAnthropic = provider.llmApiFormat == LlmApiFormat.anthropic;
        _log("Resolved LLM from CloudAccount: provider=${account.providerId}, keyLen=${apiKey.length}${fromRecommendation ? ' (recommended fallback)' : ''}");
        return (apiKey: apiKey, baseUrl: baseUrl, model: model, isAnthropic: isAnthropic);
      }
    }

    // 2. Fall back to existing preset system
    final presetId = ConfigService().llmPresetId;
    final presetProvider = CloudProviders.getById(presetId);
    final isAnthropic =
        presetId == 'custom_anthropic' ||
        presetProvider?.llmApiFormat == LlmApiFormat.anthropic;
    return (
      apiKey: ConfigService().llmApiKey,
      baseUrl: ConfigService().llmBaseUrl,
      model: ConfigService().llmModel,
      isAnthropic: isAnthropic,
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

    // 这两条是「伪流式」：整段结果一次性 yield 出去。
    // **必须先 _cleanLlmOutput** —— 非流式入口 correctText() 会清，这里漏清的话
    // thinking 模型的 `<think>…</think>` 会被打字机原样粘进用户文档
    // （引擎收完后确实也清一遍，但清的是留档用的 finalText，粘出去的撤不回来）。
    final providerType = ConfigService().llmProviderType;
    if (providerType == 'ollama') {
      yield _cleanLlmOutput(
          await _correctTextOllama(input, vocabHints: vocabHints, translateTo: translateTo));
      return;
    }
    final resolved = _resolveLlmConfig();
    if (resolved.isAnthropic) {
      yield _cleanLlmOutput(await _correctTextAnthropic(input,
          vocabHints: vocabHints, resolved: resolved, translateTo: translateTo));
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

    _log("RAW INPUT (${input.length}字): ${AppLog.redact(input)}");
    _log("Calling Cloud LLM (stream): $baseUrl, model=$model");

    var emittedAny = false;
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
        _log("LLM STREAM ERROR: ${streamedResponse.statusCode} - ${AppLog.redact(respBody)}");
        yield input;
        return;
      }

      final fullBuffer = StringBuffer();
      final think = ThinkTagFilter();
      String lineBuffer = '';

      /// 一行 SSE → 可安全输出的正文（已剥掉 think 段），拿不到内容就返回 null
      String? parseLine(String line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) return null;
        final data = trimmed.substring(6);
        if (data == '[DONE]') return null;
        try {
          final json = jsonDecode(data);
          final delta = json['choices']?[0]?['delta']?['content']?.toString();
          if (delta == null || delta.isEmpty) return null;
          final safe = think.add(delta);
          return safe.isEmpty ? null : safe;
        } catch (_) {
          return null;
        }
      }

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        lineBuffer += chunk;
        final lines = lineBuffer.split('\n');
        // Keep the last (possibly incomplete) line in buffer
        lineBuffer = lines.removeLast();

        for (final line in lines) {
          final safe = parseLine(line);
          if (safe != null) {
            fullBuffer.write(safe);
            emittedAny = true;
            yield safe; // Yield incremental chunk
          }
        }
      }

      // 收尾：服务端不以换行结束时，最后一条 data: 还留在 lineBuffer 里。
      // 不处理的话末尾那个 token 会静默丢掉。
      final lastSafe = parseLine(lineBuffer);
      if (lastSafe != null) {
        fullBuffer.write(lastSafe);
        emittedAny = true;
        yield lastSafe;
      }
      // think 过滤器可能还扣着「疑似标签前缀」的几个字，流结束时补吐出来
      final tail = think.flush();
      if (tail.isNotEmpty) {
        fullBuffer.write(tail);
        emittedAny = true;
        yield tail;
      }

      final result = fullBuffer.toString().trim();
      if (result.isNotEmpty) {
        lastCallSucceeded = true;
      }
      _log("LLM STREAM SUCCESS (${result.length}字, differs=${result != input}): ${AppLog.redact(result)}");
    } catch (e) {
      _log("LLM STREAM EXCEPTION: $e");
      // **只在一个字都没吐过时才回退原文**。已经吐过一部分再吐整段原文，
      // 打字机模式会把「半段润色文本 + 完整原文」一起粘进用户文档 —— 文本翻倍。
      if (!emittedAny) yield input;
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
    // Kimi K 系列（k2/k2.5/k2.6/k3…）只接受 temperature=1，传别的值直接 HTTP 400
    // （"invalid temperature: only 1 is allowed for this model"）——
    // 默认 0.3 会让整家 Kimi 账户 100% 失败。
    // 用 contains('kimi-k') 而非具体版本：k3 已实测同样限制，写死版本号下一代又会漏；
    // 也能覆盖带前缀的转售形式（如 Groq 的 moonshotai/kimi-k2-instruct-0905）。
    // moonshot-v1-* 老系列不受此限制，正好不被命中。
    if (model.contains('kimi-k')) {
      body['temperature'] = 1;
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

    _log("RAW INPUT (${input.length}字): ${AppLog.redact(input)}");
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
          _log("LLM SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): ${AppLog.redact(content.trim())}");
          lastCallSucceeded = true;
          return content.trim();
        }
        _log("LLM returned empty content.");
      } else {
        _log("LLM ERROR: ${response.statusCode} - ${AppLog.redact(response.body)}");
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

    _log("RAW INPUT (${input.length}字): ${AppLog.redact(input)}");
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
          _log("Anthropic SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): ${AppLog.redact(content.trim())}");
          lastCallSucceeded = true;
          return content.trim();
        }
        _log("Anthropic returned empty content.");
      } else {
        _log("Anthropic ERROR: ${response.statusCode} - ${AppLog.redact(response.body)}");
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

    _log("RAW INPUT (${input.length}字): ${AppLog.redact(input)}");
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
          _log("Ollama SUCCESS (${content.trim().length}字, differs=${content.trim() != input}): ${AppLog.redact(content.trim())}");
          lastCallSucceeded = true;
          return content.trim();
        }
        _log("Ollama returned empty content.");
      } else {
        _log("Ollama ERROR: ${response.statusCode} - ${AppLog.redact(response.body)}");
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
      _log("[Generic] Cloud ERROR: ${resp.statusCode} - ${AppLog.redact(resp.body)}");
      return '';
    } catch (e) {
      _log("[Generic] EXCEPTION: $e");
      return '';
    }
  }

  /// 把失败响应转成给用户看的一行字。
  ///
  /// 两个坑都踩过一次才补上：
  /// - `resp.body` 按 Content-Type 的 charset 解码，缺省是 latin1 ——
  ///   国内服务商（DeepSeek/Kimi/豆包/智谱）返回的中文错误直接变乱码。
  ///   本文件其它地方都用 `utf8.decode(bodyBytes)`，这里以前漏了。
  /// - 非 200 的响应**不一定是 JSON**（网关 502 会返回 HTML），
  ///   直接 jsonDecode 会抛，被外层 catch 成 "FormatException: ..." ——
  ///   用户看到的是解析错误，而不是「502 网关错误」。
  static String _describeHttpFailure(http.Response resp) {
    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    try {
      final body = jsonDecode(raw);
      if (body is Map) {
        // error 两种形态都有：`{"error":{"message":"..."}}`（OpenAI 系）
        // 和 `{"error":"invalid_api_key"}`（部分代理 / Ollama）。
        // 只认前者的话，后者会 fall through 到打印整段 JSON。
        final err = body['error'];
        final msg = (err is Map ? err['message'] : err) ?? body['message'];
        if (msg != null) return '${resp.statusCode}: $msg';
      }
    } catch (_) {
      // 不是 JSON，退回原文
    }
    final trimmed = raw.trim();
    const maxLen = AppConstants.kHttpErrorBodyMaxChars;
    return '${resp.statusCode}: '
        '${trimmed.length > maxLen ? '${trimmed.substring(0, maxLen)}…' : trimmed}';
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
        return (false, _describeHttpFailure(resp));
      } else {
        final resp = await client.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer $apiKey"},
          body: jsonEncode({"model": model, "messages": [{"role": "user", "content": "Hi"}], "max_tokens": 5}),
        ).timeout(AppConstants.kLlmTestTimeout);
        _log("TEST: OpenAI response ${resp.statusCode}");
        if (resp.statusCode == 200) return (true, '连接成功 ($model)');
        return (false, _describeHttpFailure(resp));
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
      return (false, _describeHttpFailure(resp));
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
    // 优先用为 router 单独配置的模型；否则用 resolve 出的（已按 account 过滤的）model，
    // 避免 router 用到不属于当前 provider 的旧模型名（C2）
    final routerRaw = ConfigService().agentRouterModelRaw;
    final model = (routerRaw != null && routerRaw.isNotEmpty) ? routerRaw : resolved.model;

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

/// 流式输出里剥离 `<think>…</think>` 推理段。
///
/// 非流式路径用 `_cleanLlmOutput` 一次性正则清掉就行，流式不行：
/// delta 是一小段一小段来的，标签会被切成两半；而**打字机模式边收边往用户文档里粘**，
/// 等收完再清已经来不及 —— 引擎那边清的只是留档用的 finalText，
/// 已经粘出去的字撤不回来。thinking 模型（R1 / Qwen thinking 等）一开就会漏。
///
/// 策略：能确定在 think 段之外的字立刻放行；末尾若是**疑似标签前缀**就先扣住，
/// 等下一段 delta 来了再判。流结束时 `flush()` 把扣住的补出来
/// （未闭合的 `<think>` 视为思考内容，整段丢弃）。
class ThinkTagFilter {
  static final _open = RegExp(r'<think>', caseSensitive: false);
  static final _close = RegExp(r'</think>', caseSensitive: false);
  static const _openLit = '<think>';
  static const _closeLit = '</think>';

  final StringBuffer _buf = StringBuffer();
  bool _inThink = false;

  /// 喂一段 delta，返回此刻可以安全输出的正文（可能为空串）。
  String add(String delta) {
    _buf.write(delta);
    var work = _buf.toString();
    final out = StringBuffer();

    while (true) {
      if (_inThink) {
        final m = _close.firstMatch(work);
        if (m == null) {
          // 还在思考段里：整段丢掉，只留可能是 </think> 前缀的尾巴
          work = _keepPartialSuffix(work, _closeLit);
          break;
        }
        work = work.substring(m.end);
        _inThink = false;
        continue;
      }
      // 不在思考段：`<think>` 和落单的 `</think>` 都要处理，取靠前的那个。
      // 落单闭标签也得删 —— 非流式路径的 _cleanLlmOutput 就是这么做的，
      // 两条路径的输出必须一致，否则同一个模型开不开打字机结果不一样。
      final mo = _open.firstMatch(work);
      final mc = _close.firstMatch(work);
      final m = (mo == null)
          ? mc
          : (mc == null || mo.start <= mc.start ? mo : mc);
      if (m == null) {
        // 尾巴可能是任一标签的前缀，扣住等下一段
        final keep = _keepPartialSuffix(work, _openLit, _closeLit);
        out.write(work.substring(0, work.length - keep.length));
        work = keep;
        break;
      }
      out.write(work.substring(0, m.start));
      final wasOpen = identical(m, mo);
      work = work.substring(m.end);
      if (wasOpen) _inThink = true;
    }

    _buf.clear();
    _buf.write(work);
    return out.toString();
  }

  /// 流结束：把扣住的残留吐出来。仍在未闭合的 think 段里则整段丢弃。
  String flush() {
    final rest = _inThink ? '' : _buf.toString();
    _buf.clear();
    _inThink = false;
    return rest;
  }

  /// 返回 s 末尾**可能是任一 tag 前缀**的那一小段（取最长的那个）。
  /// 比如 `"好的</thi"` → `"</thi"`，下一段 delta 补齐后才判得出来。
  /// 不扣住的话，跨 delta 的标签会被当成正文原样粘进用户文档。
  static String _keepPartialSuffix(String s, String tag, [String? tag2]) {
    final tags = [tag, ?tag2];
    final maxLen = tags.map((t) => t.length - 1).reduce((a, b) => a > b ? a : b);
    final start = s.length - maxLen;
    for (var i = start < 0 ? 0 : start; i < s.length; i++) {
      final suffix = s.substring(i).toLowerCase();
      if (tags.any((t) => t.toLowerCase().startsWith(suffix))) {
        return s.substring(i);
      }
    }
    return '';
  }
}
