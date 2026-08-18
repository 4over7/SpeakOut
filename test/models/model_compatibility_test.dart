import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/cloud_providers.dart';
import 'package:speakout/models/chat_model.dart';
import 'package:speakout/models/cloud_account.dart';

void main() {
  group('CloudProvider 凭证完整性', () {
    const provider = CloudProvider(
      id: 'mixed',
      name: 'Mixed',
      credentialFields: [
        CredentialField(key: 'tenant', label: 'Tenant'),
        CredentialField(
          key: 'api_key',
          label: 'API Key',
          scope: {CloudCapability.llm},
        ),
      ],
      capabilities: {CloudCapability.llm},
    );

    test('通用字段齐全但能力专属字段缺失时仍不可启用', () {
      expect(provider.hasAnyValidCredentials({'tenant': 'tenant-1'}), isFalse);
    });

    test('完整能力组填写后可以启用', () {
      expect(
        provider.hasAnyValidCredentials({
          'tenant': 'tenant-1',
          'api_key': 'key-1',
        }),
        isTrue,
      );
    });

    test('腾讯只填 SecretId 时不可启用', () {
      final tencent = CloudProviders.getById('tencent')!;

      expect(
        tencent.hasAnyValidCredentials({'secret_id': 'secret-id'}),
        isFalse,
      );
      expect(
        tencent.hasAnyValidCredentials({
          'secret_id': 'secret-id',
          'secret_key': 'secret-key',
          'app_id': 'app-id',
        }),
        isTrue,
      );
    });
  });

  group('ChatMessage role 兼容', () {
    Map<String, dynamic> message(Object role) => {
      'id': 'message-1',
      'text': '保留的历史内容',
      'role': role,
      'timestamp': '2026-08-18T12:00:00.000',
    };

    test('未知字符串 role 降级为 system 并保留消息', () {
      final restored = ChatMessage.fromJson(message('future_role'));

      expect(restored.role, ChatRole.system);
      expect(restored.text, '保留的历史内容');
    });

    test('越界的旧整数 role 降级为 system 并保留消息', () {
      final restored = ChatMessage.fromJson(message(99));

      expect(restored.role, ChatRole.system);
      expect(restored.text, '保留的历史内容');
    });
  });
}
