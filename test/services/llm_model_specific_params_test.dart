import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/llm_service.dart';

/// _applyModelSpecificParams 的回归测试。
///
/// 这些参数一旦错了不是「效果变差」而是**整家服务商 100% HTTP 400**，
/// 却只靠一行 startsWith 判断，之前零测试覆盖 ——
/// kimi-k2.5 的温度限制就是线上撞出来的，且第一版只匹配 'kimi-k2'，漏了 k3。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LLMService service;
  Map<String, dynamic>? sentBody;

  Future<void> callWith(String model) async {
    await ConfigService().setLlmModel(model);
    sentBody = null;
    service.setClient(MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          '{"choices": [{"message": {"content": "ok"}}]}', 200);
    }));
    await service.correctText('测试');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai_correct_enabled': true,
      'llm_base_url': 'https://example.com/v1',
      'llm_provider_type': 'cloud',
    });
    await ConfigService().init();
    await ConfigService().setAiCorrectionEnabled(true);
    await ConfigService().setLlmProviderType('cloud');
    await ConfigService().setLlmBaseUrl('https://example.com/v1');
    await ConfigService().setLlmApiKey('test_key');
    service = LLMService();
  });

  group('Kimi K 系列的 temperature 限制', () {
    // 服务端原话：invalid temperature: only 1 is allowed for this model
    for (final model in ['kimi-k2.5', 'kimi-k2.6', 'kimi-k3']) {
      test('$model 必须发 temperature=1', () async {
        await callWith(model);
        expect(sentBody, isNotNull, reason: '请求未发出');
        expect(sentBody!['temperature'], 1,
            reason: '$model 只接受 temperature=1，传别的值整家 Kimi 都会 400');
      });
    }

    test('转售形式（Groq 的 moonshotai/kimi-k2-…）同样命中', () async {
      await callWith('moonshotai/kimi-k2-instruct-0905');
      expect(sentBody!['temperature'], 1);
    });

    test('moonshot-v1 老系列不受限制，保持默认温度', () async {
      await callWith('moonshot-v1-8k');
      expect(sentBody!['temperature'], isNot(1),
          reason: 'v1 老系列接受 0.3，不该被 kimi-k 规则误伤');
    });
  });

  group('DeepSeek V4 关闭 thinking', () {
    test('deepseek-v4-flash 带 thinking disabled', () async {
      await callWith('deepseek-v4-flash');
      expect(sentBody!['thinking'], {'type': 'disabled'},
          reason: '开着 thinking 总耗时翻倍（ADR-005）');
    });

    test('deepseek-v4-pro 同样带上', () async {
      await callWith('deepseek-v4-pro');
      expect(sentBody!['thinking'], {'type': 'disabled'});
    });

    test('非 V4 模型不注入 thinking 字段', () async {
      await callWith('qwen-turbo');
      expect(sentBody!.containsKey('thinking'), isFalse);
    });
  });

  test('普通模型不被任何特判影响', () async {
    await callWith('qwen-turbo');
    expect(sentBody!['temperature'], isNot(1));
    expect(sentBody!.containsKey('thinking'), isFalse);
  });
}
