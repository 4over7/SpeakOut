import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/engine/model_manager.dart';

/// Mock path_provider
class MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  MockPathProvider(this.basePath);

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// 模型全流程测试：下载 → 解压 → 验证文件完整性
///
/// 运行：flutter test test/engine/model_full_flow_test.dart --timeout 30m
/// 注意：会下载 ~3GB 数据，需要网络连接
void main() {
  late Directory tmpDir;
  late ModelManager manager;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('speakout_model_flow_');
    PathProviderPlatform.instance = MockPathProvider(tmpDir.path);
    SharedPreferences.setMockInitialValues({});
    manager = ModelManager();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // 9 个可见模型 = 1 streaming + 8 offline
  final visibleModels = [
    ...ModelManager.availableModels,
    ...ModelManager.offlineModels,
  ];

  group('模型全流程（下载+解压+验证）', () {
    for (final model in visibleModels) {
      test('${model.name} (${model.id})', () async {
        print('\n=== 测试模型: ${model.name} ===');
        print('  ID: ${model.id}');
        print('  URL: ${model.url}');
        print('  类型: ${model.type}');

        // 1. 确认未下载
        final downloaded = await manager.isModelDownloaded(model.id);
        expect(downloaded, isFalse, reason: '初始应为未下载');

        // 2. 下载 + 解压
        String? lastStatus;
        double lastProgress = 0;
        final modelPath = await manager.downloadAndExtractModel(
          model.id,
          onStatus: (s) {
            lastStatus = s;
            print('  状态: $s');
          },
          onProgress: (p) {
            // 每 25% 打印一次
            if (p - lastProgress >= 0.25) {
              lastProgress = p;
              print('  进度: ${(p * 100).toStringAsFixed(0)}%');
            }
          },
        );

        print('  解压路径: $modelPath');

        // 3. 验证模型目录存在
        final modelDir = Directory(modelPath);
        expect(modelDir.existsSync(), isTrue, reason: '模型目录应存在');

        // 4. 验证 isModelDownloaded 返回 true
        final afterDownload = await manager.isModelDownloaded(model.id);
        expect(afterDownload, isTrue, reason: '下载后 isModelDownloaded 应为 true');

        // 5. 验证 tokens 文件存在（anchor 文件）
        final hasTokens = _hasTokensOrTokenizer(modelPath);
        expect(hasTokens, isTrue, reason: '模型目录应包含 tokens.txt 或 tokenizer.json');

        // 6. 验证 .onnx 文件存在
        final onnxFiles = Directory(modelPath)
            .listSync(recursive: true)
            .where((f) => f.path.endsWith('.onnx') || f.path.endsWith('.ort'))
            .toList();
        expect(onnxFiles, isNotEmpty, reason: '模型目录应包含 .onnx 或 .ort 文件');

        // 7. 验证 getActiveModelPath 可以找到模型
        await manager.setActiveModel(model.id);
        final activePath = await manager.getActiveModelPath();
        expect(activePath, isNotNull, reason: 'getActiveModelPath 应返回有效路径');

        print('  ✅ 通过 (onnx文件: ${onnxFiles.length}, tokens: $hasTokens)');

        // 清理本模型释放磁盘空间（保持 tmpDir 给下一个模型）
        if (modelDir.existsSync()) modelDir.deleteSync(recursive: true);
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });

  // 标点模型单独测试
  test('标点模型下载+解压', () async {
    print('\n=== 测试标点模型 ===');

    final path = await manager.downloadPunctuationModel(
      onStatus: (s) => print('  状态: $s'),
      onProgress: (p) {},
    );

    expect(path, isNotNull, reason: '标点模型应下载成功');
    if (path != null) {
      final dir = Directory(path);
      expect(dir.existsSync(), isTrue);
      final onnxFiles = dir.listSync(recursive: true)
          .where((f) => f.path.endsWith('.onnx'))
          .toList();
      expect(onnxFiles, isNotEmpty, reason: '标点模型应包含 .onnx 文件');
      print('  ✅ 通过 (onnx文件: ${onnxFiles.length})');
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

bool _hasTokensOrTokenizer(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return false;
  return dir.listSync(recursive: true).any((f) =>
      f.path.endsWith('tokens.txt') || f.path.endsWith('tokenizer.json'));
}
