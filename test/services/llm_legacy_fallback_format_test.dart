import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/cloud_account_service.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/llm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Groq 账户失效后的旧配置兜底仍走 OpenAI 兼容协议', () async {
    SharedPreferences.setMockInitialValues({
      'ai_correct_enabled': true,
      'llm_provider_type': 'cloud',
      'llm_preset_id': 'groq',
      'llm_base_url': 'https://api.groq.com/openai/v1',
      'llm_model': 'llama-3.3-70b-versatile',
    });
    await ConfigService().reload();
    await ConfigService().setLlmApiKey('test-key');
    await CloudAccountService().reload();

    Uri? requestUri;
    Map<String, dynamic>? requestBody;
    LLMService().setClient(
      MockClient((request) async {
        requestUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"content":"corrected"}}]}',
          200,
        );
      }),
    );

    final result = await LLMService().correctText('raw');

    expect(requestUri?.path, '/openai/v1/chat/completions');
    expect(requestBody, contains('messages'));
    expect(requestBody, isNot(contains('system')));
    expect(result, 'corrected');
  });

  test('自定义 Anthropic 旧配置兜底仍走 Anthropic 协议', () async {
    SharedPreferences.setMockInitialValues({
      'ai_correct_enabled': true,
      'llm_provider_type': 'cloud',
      'llm_preset_id': 'custom_anthropic',
      'llm_base_url': 'https://api.anthropic.com',
      'llm_model': 'claude-sonnet-4-6',
    });
    await ConfigService().reload();
    await ConfigService().setLlmApiKey('test-key');
    await CloudAccountService().reload();

    Uri? requestUri;
    Map<String, dynamic>? requestBody;
    LLMService().setClient(
      MockClient((request) async {
        requestUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"content":[{"type":"text","text":"corrected"}]}',
          200,
        );
      }),
    );

    final result = await LLMService().correctText('raw');

    expect(requestUri?.path, '/v1/messages');
    expect(requestBody, contains('system'));
    expect(requestBody, contains('messages'));
    expect(result, 'corrected');
  });
}
