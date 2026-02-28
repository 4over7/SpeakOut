import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/config/app_constants.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/llm_service.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LLMService Tests (Cloud)', () {
    late LLMService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'ai_correct_enabled': true,
        'llm_api_key': 'test_key',
        'llm_base_url': 'https://api.openai.com/v1',
        'llm_provider_type': 'cloud',
      });
      await ConfigService().init();
      service = LLMService();
    });

    test('correctText returns modified text on success', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
            '{"choices": [{"message": {"content": "Cleaned Text"}}]}', 200);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Dirty Text");
      expect(result, "Cleaned Text");
    });

    test('correctText returns original on error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Dirty Text");
      expect(result, "Dirty Text");
    });

    test('correctText skips if disabled', () async {
      await ConfigService().setAiCorrectionEnabled(false);

      final mockClient = MockClient((request) async {
        return http.Response('{"choices": [{"message": {"content": "Should Not Happen"}}]}', 200);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Dirty Text");
      expect(result, "Dirty Text");
    });
  });

  group('LLMService Tests (Ollama)', () {
    late LLMService service;

    setUp(() async {
      // ConfigService is a singleton already initialized from the Cloud group.
      // Use setters to switch to Ollama mode.
      await ConfigService().setAiCorrectionEnabled(true);
      await ConfigService().setLlmProviderType('ollama');
      await ConfigService().setOllamaBaseUrl('http://localhost:11434');
      await ConfigService().setOllamaModel('qwen3:0.6b');
      service = LLMService();
    });

    test('Ollama mode calls /api/chat endpoint', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
            '{"message": {"content": "Corrected Text"}}', 200);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Raw Text");
      expect(result, "Corrected Text");
      expect(capturedUri?.path, '/api/chat');
    });

    test('Ollama mode does not send Authorization header', () async {
      Map<String, String>? capturedHeaders;
      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response(
            '{"message": {"content": "Corrected Text"}}', 200);
      });
      service.setClient(mockClient);

      await service.correctText("Raw Text");
      expect(capturedHeaders?.containsKey('authorization'), isFalse);
    });

    test('Ollama mode parses message.content response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
            '{"message": {"role": "assistant", "content": "Fixed output"}, "done": true}', 200);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Messy input");
      expect(result, "Fixed output");
    });

    test('Ollama mode returns original on error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error": "model not found"}', 404);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Some text");
      expect(result, "Some text");
    });
  });

  // ═══════════════════════════════════════════════════════════
  // Golden Tests: 锁定 prompt 格式
  // ═══════════════════════════════════════════════════════════
  group('LLM Correction Prompt (Golden)', () {
    test('默认 system prompt 与 golden 文件一致', () {
      final goldenFile = File('test/goldens/llm_correction_prompt.txt');
      final actual = AppConstants.kDefaultAiCorrectionPrompt.trim();

      if (!goldenFile.existsSync()) {
        // Bootstrap: create golden on first run
        goldenFile.writeAsStringSync(actual);
      }

      final goldenContent = goldenFile.readAsStringSync().trim();
      // If mismatch, update golden and fail so developer notices the change
      if (actual != goldenContent) {
        goldenFile.writeAsStringSync(actual);
        fail('Golden 文件已更新 — prompt 发生变化，请审查 test/goldens/llm_correction_prompt.txt');
      }
    });

    test('Cloud 模式: request body 包含 system prompt 和 speech_text 标签', () async {
      SharedPreferences.setMockInitialValues({
        'ai_correct_enabled': true,
        'llm_api_key': 'test_key',
        'llm_base_url': 'https://api.openai.com/v1',
        'llm_provider_type': 'cloud',
      });
      await ConfigService().init();
      final service = LLMService();

      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body);
        return http.Response(
            '{"choices": [{"message": {"content": "ok"}}]}', 200);
      });
      service.setClient(mockClient);
      await service.correctText('测试文本');

      expect(capturedBody, isNotNull);
      final messages = capturedBody!['messages'] as List;
      expect(messages.length, 2);

      // system prompt
      final systemMsg = messages[0] as Map<String, dynamic>;
      expect(systemMsg['role'], 'system');
      expect(systemMsg['content'], contains('语音转文字'));
      expect(systemMsg['content'], contains('speech_text'));

      // user message wraps input in <speech_text> tags
      final userMsg = messages[1] as Map<String, dynamic>;
      expect(userMsg['role'], 'user');
      expect(userMsg['content'], contains('<speech_text>'));
      expect(userMsg['content'], contains('测试文本'));
      expect(userMsg['content'], contains('</speech_text>'));
    });

    test('Ollama 模式: request body 包含 system prompt 和 speech_text 标签', () async {
      await ConfigService().setAiCorrectionEnabled(true);
      await ConfigService().setLlmProviderType('ollama');
      await ConfigService().setOllamaBaseUrl('http://localhost:11434');
      await ConfigService().setOllamaModel('qwen3:0.6b');
      final service = LLMService();

      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body);
        return http.Response(
            '{"message": {"content": "ok"}}', 200);
      });
      service.setClient(mockClient);
      await service.correctText('Ollama测试');

      expect(capturedBody, isNotNull);
      final messages = capturedBody!['messages'] as List;

      final systemMsg = messages[0] as Map<String, dynamic>;
      expect(systemMsg['role'], 'system');

      final userMsg = messages[1] as Map<String, dynamic>;
      expect(userMsg['content'], contains('<speech_text>'));
      expect(userMsg['content'], contains('Ollama测试'));

      // Ollama-specific: stream=false, think=false
      expect(capturedBody!['stream'], false);
      expect(capturedBody!['think'], false);
    });

    test('prompt 包含安全指令 (prompt injection 防护)', () {
      final prompt = AppConstants.kDefaultAiCorrectionPrompt;
      expect(prompt, contains('安全指令'));
      expect(prompt, contains('纯数据'));
      expect(prompt, contains('忽略'));
    });
  });
}
