import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/model_manager.dart';

/// ModelManager 元数据黑盒测试
///
/// 仅测试模型列表常量和 getModelById 等纯内存操作，
/// 不测试下载、解压、IO 等依赖文件系统的方法。
void main() {
  late ModelManager manager;

  setUp(() {
    manager = ModelManager();
  });

  group('availableModels (流式模型列表)', () {
    test('应包含 Zipformer Bilingual 模型', () {
      final ids = ModelManager.availableModels.map((m) => m.id).toList();
      expect(ids, contains('zipformer_bi_2023_02_20'));
    });

    test('应包含 Paraformer Bilingual (Streaming) 模型', () {
      final ids = ModelManager.availableModels.map((m) => m.id).toList();
      expect(ids, contains('paraformer_bi_zh_en'));
    });

    test('流式模型的 isOffline 应为 false', () {
      for (final model in ModelManager.availableModels) {
        expect(model.isOffline, isFalse,
            reason: '流式模型 ${model.id} 的 isOffline 应为 false');
      }
    });

    test('流式模型列表不应为空', () {
      expect(ModelManager.availableModels, isNotEmpty);
    });
  });

  group('offlineModels (离线模型列表)', () {
    test('应包含 SenseVoice 2024 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('sensevoice_zh_en_int8'));
    });

    test('应包含 SenseVoice 2025 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('sensevoice_zh_en_int8_2025'));
    });

    test('应包含 Paraformer Offline 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('offline_paraformer_zh'));
    });

    test('应包含 Paraformer Dialect 2025 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('offline_paraformer_dialect_2025'));
    });

    test('应包含 Whisper Large-v3 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('whisper_large_v3'));
    });

    test('应包含 FireRedASR Large 模型', () {
      final ids = ModelManager.offlineModels.map((m) => m.id).toList();
      expect(ids, contains('fire_red_asr_large'));
    });

    test('离线模型的 isOffline 应为 true', () {
      for (final model in ModelManager.offlineModels) {
        expect(model.isOffline, isTrue,
            reason: '离线模型 ${model.id} 的 isOffline 应为 true');
      }
    });

    test('离线模型列表不应为空', () {
      expect(ModelManager.offlineModels, isNotEmpty);
    });
  });

  group('allModels (全部模型合集)', () {
    test('allModels 应等于 availableModels + offlineModels', () {
      final allIds = ModelManager.allModels.map((m) => m.id).toList();
      final expectedIds = [
        ...ModelManager.availableModels.map((m) => m.id),
        ...ModelManager.offlineModels.map((m) => m.id),
      ];
      expect(allIds, equals(expectedIds));
    });

    test('allModels 长度应等于 availableModels + offlineModels 长度之和', () {
      expect(
        ModelManager.allModels.length,
        equals(ModelManager.availableModels.length +
            ModelManager.offlineModels.length),
      );
    });
  });

  group('模型 ID 唯一性', () {
    test('所有模型 ID 应唯一', () {
      final ids = ModelManager.allModels.map((m) => m.id).toList();
      final uniqueIds = ids.toSet();
      expect(uniqueIds.length, equals(ids.length),
          reason: '发现重复 ID: ${ids.where((id) => ids.where((x) => x == id).length > 1).toSet()}');
    });
  });

  group('模型元数据完整性', () {
    test('每个模型的 name 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.name, isNotEmpty,
            reason: '模型 ${model.id} 的 name 为空');
      }
    });

    test('每个模型的 description 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.description, isNotEmpty,
            reason: '模型 ${model.id} 的 description 为空');
      }
    });

    test('每个模型的 url 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.url, isNotEmpty,
            reason: '模型 ${model.id} 的 url 为空');
      }
    });

    test('每个模型的 url 应以 https:// 开头', () {
      for (final model in ModelManager.allModels) {
        expect(model.url, startsWith('https://'),
            reason: '模型 ${model.id} 的 url 格式不正确: ${model.url}');
      }
    });

    test('每个模型的 id 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.id, isNotEmpty);
      }
    });

    test('每个模型的 type 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.type, isNotEmpty,
            reason: '模型 ${model.id} 的 type 为空');
      }
    });

    test('每个模型的 lang 应非空', () {
      for (final model in ModelManager.allModels) {
        expect(model.lang, isNotEmpty,
            reason: '模型 ${model.id} 的 lang 为空');
      }
    });
  });

  group('getModelById', () {
    test('已知 ID 应返回对应模型', () {
      final model = manager.getModelById('zipformer_bi_2023_02_20');
      expect(model, isNotNull);
      expect(model!.id, equals('zipformer_bi_2023_02_20'));
      expect(model.name, contains('Zipformer'));
    });

    test('已知离线模型 ID 应返回对应模型', () {
      final model = manager.getModelById('sensevoice_zh_en_int8');
      expect(model, isNotNull);
      expect(model!.id, equals('sensevoice_zh_en_int8'));
      expect(model.isOffline, isTrue);
    });

    test('未知 ID 应返回 null', () {
      final model = manager.getModelById('nonexistent_model_xyz');
      expect(model, isNull);
    });

    test('空字符串 ID 应返回 null', () {
      final model = manager.getModelById('');
      expect(model, isNull);
    });

    test('所有已知模型 ID 均能查询到', () {
      for (final expected in ModelManager.allModels) {
        final found = manager.getModelById(expected.id);
        expect(found, isNotNull,
            reason: '无法通过 getModelById 查到模型 ${expected.id}');
        expect(found!.id, equals(expected.id));
      }
    });
  });

  group('punctuationModelUrl', () {
    test('应非空', () {
      expect(ModelManager.punctuationModelUrl, isNotEmpty);
    });

    test('应以 https:// 开头', () {
      expect(ModelManager.punctuationModelUrl, startsWith('https://'));
    });

    test('应包含 punctuation 关键词', () {
      expect(
        ModelManager.punctuationModelUrl.toLowerCase(),
        contains('punct'),
      );
    });
  });

  group('hasPunctuation 属性', () {
    test('SenseVoice 2024 应有内置标点', () {
      final model = manager.getModelById('sensevoice_zh_en_int8');
      expect(model!.hasPunctuation, isTrue);
    });

    test('SenseVoice 2025 应无内置标点', () {
      final model = manager.getModelById('sensevoice_zh_en_int8_2025');
      expect(model!.hasPunctuation, isFalse);
    });

    test('Whisper Large-v3 应有内置标点', () {
      final model = manager.getModelById('whisper_large_v3');
      expect(model!.hasPunctuation, isTrue);
    });

    test('Zipformer Bilingual 应无内置标点', () {
      final model = manager.getModelById('zipformer_bi_2023_02_20');
      expect(model!.hasPunctuation, isFalse);
    });
  });

  group('ModelArch 架构分类', () {
    test('Zipformer 应为 transducerStreaming', () {
      final model = manager.getModelById('zipformer_bi_2023_02_20');
      expect(model!.arch, equals(ModelArch.transducerStreaming));
    });

    test('Paraformer Streaming 应为 ctcStreaming', () {
      final model = manager.getModelById('paraformer_bi_zh_en');
      expect(model!.arch, equals(ModelArch.ctcStreaming));
    });

    test('SenseVoice 应为 ctcOffline', () {
      final model = manager.getModelById('sensevoice_zh_en_int8');
      expect(model!.arch, equals(ModelArch.ctcOffline));
    });

    test('Whisper 应为 whisperLike', () {
      final model = manager.getModelById('whisper_large_v3');
      expect(model!.arch, equals(ModelArch.whisperLike));
    });

    test('supportsConfidence 当前所有模型均应为 false (无 transducerOffline)', () {
      for (final model in ModelManager.allModels) {
        expect(model.supportsConfidence, isFalse,
            reason: '模型 ${model.id} 不应支持置信度');
      }
    });
  });
}
