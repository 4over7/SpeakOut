import 'dart:io';

import 'package:archive/archive_io.dart';
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
    File('${d.path}/encoder.int8.onnx').writeAsStringSync('existing-encoder');
    File('${d.path}/decoder.int8.onnx').writeAsStringSync('existing-decoder');
    return d;
  }

  File createArchive(String name, Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = entry.value.codeUnits;
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final encoded = BZip2Encoder().encode(TarEncoder().encode(archive));
    return File('${tmp.path}/$name.tar.bz2')..writeAsBytesSync(encoded);
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

  test('合法压缩包只有 tokens、没有推理模型时，拒绝导入并保留旧模型', () async {
    final existing = seedExistingModel();
    final incomplete = createArchive('tokens_only', {
      'candidate/tokens.txt': 'new-tokens',
    });

    await expectLater(
      ModelManager().importModel(modelId, incomplete.path),
      throwsA(anything),
    );

    expect(existing.existsSync(), isTrue);
    expect(
      File('${existing.path}/tokens.txt').readAsStringSync(),
      'existing-tokens',
      reason: '结构不完整但可解压的包不得替换原模型',
    );
    expect(File('${existing.path}/encoder.int8.onnx').existsSync(), isTrue);
  });

  test('完整且类型匹配的模型包可以替换旧模型', () async {
    final existing = seedExistingModel();
    final complete = createArchive('complete', {
      'candidate/tokens.txt': 'new-tokens',
      'candidate/encoder.int8.onnx': 'new-encoder',
      'candidate/decoder.int8.onnx': 'new-decoder',
    });

    final installedPath =
        await ModelManager().importModel(modelId, complete.path);

    expect(installedPath, existing.path);
    expect(File('${existing.path}/tokens.txt').readAsStringSync(), 'new-tokens');
    expect(Directory('${existing.path}.old').existsSync(), isFalse);
  });

  test('进程中断后只留下 .old 时，读取状态会恢复原模型', () async {
    final existing = seedExistingModel();
    final backup = Directory('${existing.path}.old');
    existing.renameSync(backup.path);

    expect(await ModelManager().isModelDownloaded(modelId), isTrue);
    expect(existing.existsSync(), isTrue);
    expect(backup.existsSync(), isFalse);
    expect(
      File('${existing.path}/tokens.txt').readAsStringSync(),
      'existing-tokens',
    );
  });
}
