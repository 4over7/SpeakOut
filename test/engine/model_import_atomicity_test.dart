import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:speakout/engine/model_manager.dart';

import '../helpers/test_helpers.dart';

/// 导入损坏的模型包，**不得**毁掉本来能用的旧模型。
///
/// 原实现在解压后、anchor 校验之前就 `finalModelDir.delete(recursive: true)`，
/// 于是「导入一个坏包」= 「顺便把已装好的模型删了」，且无法回滚 ——
/// 内置模型还能重下，手动导入的就真没了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory modelsRoot;
  const modelId = 'paraformer_bi_zh_en';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('speakout_import_atomic');
    PathProviderPlatform.instance = MockPathProviderPlatform(tmp.path);
    modelsRoot = Directory('${tmp.path}/Models')..createSync(recursive: true);
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 模拟一个已装好、可用的模型目录
  Directory seedExistingModel() {
    final model = ModelManager.allModels.firstWhere((m) => m.id == modelId);
    final dirName = model.url.split('/').last.replaceAll('.tar.bz2', '');
    final d = Directory('${modelsRoot.path}/$dirName')..createSync(recursive: true);
    File('${d.path}/tokens.txt').writeAsStringSync('existing-tokens');
    File('${d.path}/model.onnx').writeAsStringSync('existing-onnx');
    return d;
  }

  test('导入损坏包失败后，原有模型必须原封不动', () async {
    final existing = seedExistingModel();
    final before = existing
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();

    // 一个不是合法 tar.bz2 的文件 —— 解压就会失败
    final bad = File('${tmp.path}/corrupt.tar.bz2')
      ..writeAsBytesSync(List.filled(64, 0x00));

    await expectLater(
      ModelManager().importModel(modelId, bad.path),
      throwsA(anything),
      reason: '损坏包应当导入失败',
    );

    expect(existing.existsSync(), isTrue,
        reason: '导入失败却把已装好的模型目录删了 —— 这正是本测试要防的事故');
    final after = existing
        .listSync()
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
    expect(after, before, reason: '原模型内容被改动');
    expect(File('${existing.path}/tokens.txt').readAsStringSync(),
        'existing-tokens');
  });

  test('失败后不得留下 .old 备份残骸', () async {
    final existing = seedExistingModel();
    final bad = File('${tmp.path}/corrupt2.tar.bz2')
      ..writeAsBytesSync(List.filled(64, 0x01));

    await expectLater(
        ModelManager().importModel(modelId, bad.path), throwsA(anything));

    final leftovers = modelsRoot
        .listSync()
        .where((e) => e.path.endsWith('.old'))
        .map((e) => e.path)
        .toList();
    expect(leftovers, isEmpty, reason: '残留 .old 目录会白占几百 MB 磁盘');
    expect(existing.existsSync(), isTrue);
  });
}
