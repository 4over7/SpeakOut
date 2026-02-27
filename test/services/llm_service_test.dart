import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
