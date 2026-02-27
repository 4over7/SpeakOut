import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speakout/engine/model_manager.dart';

class MockPathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    return '.';
  }
}

void main() {
  setUp(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  test('ModelManager should have correct default models', () {
    expect(ModelManager.availableModels.length, greaterThan(0));
    final defaultModel = ModelManager.availableModels.first;
    expect(defaultModel.id, 'zipformer_bi_2023_02_20');
    expect(defaultModel.type, 'zipformer');
  });

  test('getPunctuationModelPath should return correct relative path structure', () async {
    ModelManager();
    expect(ModelManager.punctuationModelId, 'punct_ct_transformer_zh_en');
  });
}
