import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/llm_service.dart';
import 'package:speakout/config/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('LLMService Tests', () {
    late LLMService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'ai_correct_enabled': true,
        'llm_api_key': 'test_key',
        'llm_base_url': 'https://api.openai.com/v1',
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
       // ConfigService is already initialized in setUp. 
       // We must use the setter to update the value in the active instance.
      await ConfigService().setAiCorrectionEnabled(false);
      
      // Even if client works, it should skip

      final mockClient = MockClient((request) async {
        return http.Response('{"choices": [{"message": {"content": "Should Not Happen"}}]}', 200);
      });
      service.setClient(mockClient);

      final result = await service.correctText("Dirty Text");
      expect(result, "Dirty Text");
    });
  });
}
