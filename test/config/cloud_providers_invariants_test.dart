import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/cloud_providers.dart';
import 'package:speakout/models/cloud_account.dart';

void main() {
  test('服务商与各自模型 ID 唯一', () {
    final providerIds = CloudProviders.all.map((provider) => provider.id);
    expect(providerIds.toSet().length, providerIds.length);

    for (final provider in CloudProviders.all) {
      final credentialKeys = provider.credentialFields.map(
        (field) => field.key,
      );
      expect(
        credentialKeys.toSet().length,
        credentialKeys.length,
        reason: '${provider.id} 存在重复凭证字段',
      );
      final asrModelIds = provider.asrModels.map((model) => model.id);
      expect(
        asrModelIds.toSet().length,
        asrModelIds.length,
        reason: '${provider.id} 存在重复 ASR 模型 ID',
      );
      final llmModelIds = provider.llmModels.map((model) => model.id);
      expect(
        llmModelIds.toSet().length,
        llmModelIds.length,
        reason: '${provider.id} 存在重复 LLM 模型 ID',
      );
    }
  });

  test('声明的能力都有凭证与模型，LLM 默认模型可选', () {
    for (final provider in CloudProviders.all) {
      for (final capability in provider.capabilities) {
        expect(
          provider.credentialFields.any((field) => field.appliesTo(capability)),
          isTrue,
          reason: '${provider.id} 的 $capability 没有适用凭证',
        );
      }

      if (provider.hasASR) {
        expect(
          provider.asrModels,
          isNotEmpty,
          reason: '${provider.id} 声明 ASR 却没有模型',
        );
      }
      if (provider.hasLLM) {
        expect(
          provider.llmBaseUrl,
          isNotNull,
          reason: '${provider.id} 缺 LLM URL',
        );
        expect(
          provider.llmModels.map((model) => model.id),
          contains(provider.llmDefaultModel),
          reason: '${provider.id} 的默认 LLM 模型不在模型列表',
        );
        expect(
          provider.credentialFields.any(
            (field) =>
                field.key == provider.llmApiKeyField &&
                field.appliesTo(CloudCapability.llm),
          ),
          isTrue,
          reason: '${provider.id} 的 LLM 鉴权字段不存在或 scope 错误',
        );
      }
    }
  });

  test('讯飞只配置星火密码即可满足 LLM 凭证', () {
    final provider = CloudProviders.getById('xfyun')!;

    expect(
      provider.hasValidCredentialsFor(CloudCapability.llm, {
        'api_password': 'token',
      }),
      isTrue,
    );
  });
}
