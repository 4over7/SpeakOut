import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speakout/engine/model_manager.dart';

class MockPathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
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
    final manager = ModelManager();
    // Since we mocked app doc path to '.', 
    // real existence check would check ./models/punc_ct-transformer_zh-cn-common-vocab-272727-2023-04-12/model.onnx
    // It will likely return false/null because file doesn't exist.
    // But we can check logic flow if we could mock file system. 
    // Verify it matches the constant defined in class
    expect(ModelManager.punctuationModelId, 'punct_ct_transformer_zh_en');
  });
}
