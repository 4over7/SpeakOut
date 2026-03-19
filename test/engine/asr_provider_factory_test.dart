import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/providers/asr_provider_factory.dart';
import 'package:speakout/engine/providers/tencent_asr_provider.dart';
import 'package:speakout/engine/providers/volcengine_asr_provider.dart';
import 'package:speakout/engine/providers/xfyun_asr_provider.dart';
import 'package:speakout/engine/providers/dashscope_asr_provider.dart';
import 'package:speakout/engine/providers/openai_asr_provider.dart';
import 'package:speakout/engine/providers/aliyun_provider.dart';
import 'package:speakout/models/cloud_account.dart';

void main() {
  group('ASRProviderFactory.create', () {
    test('dashscope → DashScopeASRProvider', () {
      final p = ASRProviderFactory.create('dashscope');
      expect(p, isA<DashScopeASRProvider>());
      expect(p.type, 'dashscope');
    });

    test('openai → OpenAIASRProvider', () {
      final p = ASRProviderFactory.create('openai');
      expect(p, isA<OpenAIASRProvider>());
    });

    test('groq → OpenAIASRProvider', () {
      final p = ASRProviderFactory.create('groq');
      expect(p, isA<OpenAIASRProvider>());
    });

    test('aliyun_nls → AliyunProvider', () {
      final p = ASRProviderFactory.create('aliyun_nls');
      expect(p, isA<AliyunProvider>());
    });

    test('volcengine → VolcengineASRProvider', () {
      final p = ASRProviderFactory.create('volcengine');
      expect(p, isA<VolcengineASRProvider>());
      expect(p.type, 'volcengine_asr');
    });

    test('xfyun → XfyunASRProvider', () {
      final p = ASRProviderFactory.create('xfyun');
      expect(p, isA<XfyunASRProvider>());
      expect(p.type, 'xfyun_asr');
    });

    test('tencent → TencentASRProvider', () {
      final p = ASRProviderFactory.create('tencent');
      expect(p, isA<TencentASRProvider>());
      expect(p.type, 'tencent_asr');
    });

    test('unknown provider throws', () {
      expect(() => ASRProviderFactory.create('nonexistent'), throwsException);
    });
  });

  group('ASRProviderFactory.buildConfig', () {
    test('volcengine maps asr_app_id, asr_token, asr_cluster', () {
      final account = CloudAccount(
        id: 'test',
        providerId: 'volcengine',
        displayName: 'Test',
        credentials: {
          'asr_app_id': 'my_app',
          'asr_token': 'my_token',
          'asr_cluster': 'my_cluster',
        },
      );
      final model = CloudASRModel(id: 'seed-asr', name: 'Seed', isStreaming: true);
      final config = ASRProviderFactory.buildConfig(account, model);
      expect(config['appKey'], 'my_app');
      expect(config['accessKey'], 'my_token');
      expect(config['cluster'], 'my_cluster');
    });

    test('xfyun maps app_id, api_key, api_secret', () {
      final account = CloudAccount(
        id: 'test',
        providerId: 'xfyun',
        displayName: 'Test',
        credentials: {
          'app_id': 'xf_app',
          'api_key': 'xf_key',
          'api_secret': 'xf_secret',
        },
      );
      final model = CloudASRModel(id: 'iat', name: 'IAT', isStreaming: true);
      final config = ASRProviderFactory.buildConfig(account, model);
      expect(config['appId'], 'xf_app');
      expect(config['apiKey'], 'xf_key');
      expect(config['apiSecret'], 'xf_secret');
    });

    test('tencent maps secret_id, secret_key, app_id', () {
      final account = CloudAccount(
        id: 'test',
        providerId: 'tencent',
        displayName: 'Test',
        credentials: {
          'secret_id': 'sid',
          'secret_key': 'skey',
          'app_id': 'appid123',
        },
      );
      final model = CloudASRModel(id: 'asr-streaming', name: 'ASR', isStreaming: true);
      final config = ASRProviderFactory.buildConfig(account, model);
      expect(config['secretId'], 'sid');
      expect(config['secretKey'], 'skey');
      expect(config['appId'], 'appid123');
    });
  });
}
