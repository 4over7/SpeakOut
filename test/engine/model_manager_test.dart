import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/engine/model_manager.dart';

/// Mock path_provider: getApplicationSupportPath → 临时目录
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  MockPathProviderPlatform(this.basePath);

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  late Directory tmpDir;
  late ModelManager manager;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('speakout_model_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tmpDir.path);
    SharedPreferences.setMockInitialValues({});
    manager = ModelManager();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // ─── 辅助：按 URL 推导目录名 ───
  String dirNameFromUrl(String url) {
    final filename = url.split('/').last;
    return filename.endsWith('.tar.bz2')
        ? filename.substring(0, filename.length - 8)
        : filename;
  }

  /// 创建模拟模型目录，返回该目录
  Directory createFakeModelDir(ModelInfo model, {String tokenFileName = 'tokens.txt'}) {
    final dirName = dirNameFromUrl(model.url);
    final modelDir = Directory('${tmpDir.path}/Models/$dirName');
    modelDir.createSync(recursive: true);
    File('${modelDir.path}/$tokenFileName').writeAsStringSync('dummy');
    return modelDir;
  }

  // ═══════════════════════════════════════════════════════════
  // 1. 基础属性
  // ═══════════════════════════════════════════════════════════
  group('基础属性', () {
    test('allModels 包含所有 streaming + offline 模型', () {
      expect(
        ModelManager.allModels.length,
        ModelManager.availableModels.length + ModelManager.offlineModels.length,
      );
    });

    test('每个模型 ID 唯一', () {
      final ids = ModelManager.allModels.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length, reason: '存在重复 ID');
    });

    test('每个模型 URL 不为空且以 .tar.bz2 结尾', () {
      for (final m in ModelManager.allModels) {
        expect(m.url, isNotEmpty, reason: '${m.id} URL 为空');
        expect(m.url.endsWith('.tar.bz2'), isTrue, reason: '${m.id} URL 非 tar.bz2');
      }
    });

    test('getModelById 能找到所有模型', () {
      for (final m in ModelManager.allModels) {
        expect(manager.getModelById(m.id), isNotNull, reason: '找不到 ${m.id}');
      }
    });

    test('getModelById 对无效 ID 返回 null', () {
      expect(manager.getModelById('nonexistent_model'), isNull);
    });

    test('_getDirNameFromUrl 对所有模型正确提取目录名', () {
      for (final m in ModelManager.allModels) {
        final dirName = dirNameFromUrl(m.url);
        expect(dirName, isNotEmpty, reason: '${m.id} dirName 为空');
        expect(dirName.contains('.tar'), isFalse, reason: '${m.id} dirName 含 .tar');
        expect(dirName.contains('.bz2'), isFalse, reason: '${m.id} dirName 含 .bz2');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. isModelDownloaded — 遍历所有模型
  // ═══════════════════════════════════════════════════════════
  group('isModelDownloaded — 全模型遍历', () {
    /// 每个模型用标准 tokens.txt 测试
    for (final model in ModelManager.allModels) {
      test('${model.id}: tokens.txt → true', () async {
        createFakeModelDir(model, tokenFileName: 'tokens.txt');
        expect(await manager.isModelDownloaded(model.id), isTrue);
      });
    }

    /// Whisper 风格: prefix-tokens.txt
    for (final model in ModelManager.allModels) {
      test('${model.id}: large-v3-tokens.txt → true', () async {
        createFakeModelDir(model, tokenFileName: 'large-v3-tokens.txt');
        expect(await manager.isModelDownloaded(model.id), isTrue);
      });
    }

    test('目录不存在 → false', () async {
      expect(await manager.isModelDownloaded('sensevoice_zh_en_int8'), isFalse);
    });

    test('目录存在但无 tokens 文件 → false', () async {
      final model = ModelManager.allModels.first;
      final dirName = dirNameFromUrl(model.url);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName');
      modelDir.createSync(recursive: true);
      // 只放一个无关文件
      File('${modelDir.path}/model.onnx').writeAsStringSync('dummy');
      expect(await manager.isModelDownloaded(model.id), isFalse);
    });

    test('无效模型 ID → false', () async {
      expect(await manager.isModelDownloaded('does_not_exist'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. getActiveModelPath — 遍历所有模型
  // ═══════════════════════════════════════════════════════════
  group('getActiveModelPath — 全模型遍历', () {
    for (final model in ModelManager.allModels) {
      test('${model.id}: 设为活跃后能找到路径', () async {
        final tokenName = model.type == 'whisper' ? 'large-v3-tokens.txt' : 'tokens.txt';
        createFakeModelDir(model, tokenFileName: tokenName);

        SharedPreferences.setMockInitialValues({'active_model_id': model.id});
        final path = await manager.getActiveModelPath();
        expect(path, isNotNull, reason: '${model.id} getActiveModelPath 返回 null');

        final dirName = dirNameFromUrl(model.url);
        expect(path, endsWith(dirName), reason: '${model.id} 路径不匹配');
      });
    }

    test('模型目录不存在 → null', () async {
      SharedPreferences.setMockInitialValues({'active_model_id': 'sensevoice_zh_en_int8'});
      expect(await manager.getActiveModelPath(), isNull);
    });

    test('嵌套子目录: tokens.txt 在子文件夹中', () async {
      final model = ModelManager.allModels.first;
      final dirName = dirNameFromUrl(model.url);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName');
      modelDir.createSync(recursive: true);
      // tokens.txt 在子目录中
      final subDir = Directory('${modelDir.path}/nested');
      subDir.createSync();
      File('${subDir.path}/tokens.txt').writeAsStringSync('dummy');

      SharedPreferences.setMockInitialValues({'active_model_id': model.id});
      final path = await manager.getActiveModelPath();
      expect(path, isNotNull, reason: '嵌套子目录下的 tokens.txt 应该能找到');
      expect(path, endsWith('nested'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. 标点模型
  // ═══════════════════════════════════════════════════════════
  group('标点模型', () {
    test('isPunctuationModelDownloaded: model.onnx 在子目录中 → true', () async {
      final dirName = dirNameFromUrl(ModelManager.punctuationModelUrl);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName/$dirName');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx').writeAsStringSync('dummy');
      expect(await manager.isPunctuationModelDownloaded(), isTrue);
    });

    test('isPunctuationModelDownloaded: 目录不存在 → false', () async {
      expect(await manager.isPunctuationModelDownloaded(), isFalse);
    });

    test('getPunctuationModelPath: model.onnx 在 root → 返回 root', () async {
      final dirName = dirNameFromUrl(ModelManager.punctuationModelUrl);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx').writeAsStringSync('dummy');
      final path = await manager.getPunctuationModelPath();
      expect(path, isNotNull);
      expect(path, endsWith(dirName));
    });

    test('getPunctuationModelPath: model.onnx 在子目录 → 返回子目录', () async {
      final dirName = dirNameFromUrl(ModelManager.punctuationModelUrl);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName');
      modelDir.createSync(recursive: true);
      final subDir = Directory('${modelDir.path}/$dirName');
      subDir.createSync();
      File('${subDir.path}/model.onnx').writeAsStringSync('dummy');
      final path = await manager.getPunctuationModelPath();
      expect(path, isNotNull);
    });

    test('getPunctuationModelPath: 无 model.onnx → null', () async {
      final dirName = dirNameFromUrl(ModelManager.punctuationModelUrl);
      final modelDir = Directory('${tmpDir.path}/Models/$dirName');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/other.txt').writeAsStringSync('dummy');
      expect(await manager.getPunctuationModelPath(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 5. setActiveModel / getActiveModelInfo
  // ═══════════════════════════════════════════════════════════
  group('活跃模型管理', () {
    test('setActiveModel + getActiveModelInfo 往返一致', () async {
      for (final model in ModelManager.allModels) {
        await manager.setActiveModel(model.id);
        final info = await manager.getActiveModelInfo();
        expect(info, isNotNull);
        expect(info!.id, model.id);
      }
    });

    test('默认活跃模型 = kDefaultModelId', () async {
      SharedPreferences.setMockInitialValues({});
      final info = await manager.getActiveModelInfo();
      expect(info, isNotNull);
      expect(info!.id, 'sensevoice_zh_en_int8');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 6. tokens 文件名边界测试
  // ═══════════════════════════════════════════════════════════
  group('tokens 文件名边界', () {
    final model = ModelManager.allModels.first;

    test('tokens.txt (标准命名)', () async {
      createFakeModelDir(model, tokenFileName: 'tokens.txt');
      expect(await manager.isModelDownloaded(model.id), isTrue);
    });

    test('large-v3-tokens.txt (Whisper 风格)', () async {
      createFakeModelDir(model, tokenFileName: 'large-v3-tokens.txt');
      expect(await manager.isModelDownloaded(model.id), isTrue);
    });

    test('my-custom-tokens.txt (任意 prefix-tokens.txt)', () async {
      createFakeModelDir(model, tokenFileName: 'my-custom-tokens.txt');
      expect(await manager.isModelDownloaded(model.id), isTrue);
    });

    test('TOKENS.txt (大写) → macOS HFS+ 大小写不敏感，仍匹配', () async {
      createFakeModelDir(model, tokenFileName: 'TOKENS.txt');
      // macOS 默认文件系统大小写不敏感，所以 TOKENS.txt == tokens.txt
      expect(await manager.isModelDownloaded(model.id), isTrue);
    });

    test('tokens.json (错误扩展名) → false', () async {
      createFakeModelDir(model, tokenFileName: 'tokens.json');
      expect(await manager.isModelDownloaded(model.id), isFalse);
    });

    test('空目录 → false', () async {
      final dirName = dirNameFromUrl(model.url);
      Directory('${tmpDir.path}/Models/$dirName').createSync(recursive: true);
      expect(await manager.isModelDownloaded(model.id), isFalse);
    });
  });
}
