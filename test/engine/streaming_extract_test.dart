import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 extractFileToDisk 流式解压（与 model_manager Dart 回退路径相同）
///
/// 注意: 生产环境的模型 tar.bz2 由 Linux 服务器打包（GNU tar），
/// 这里用 Dart archive 包自身打包确保格式兼容。
void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('speakout_extract_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  /// 用 Dart archive 包创建归档文件
  File createArchive(String format, Map<String, List<int>> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final archivePath = '${tmpDir.path}/test$format';
    List<int> encoded;
    if (format == '.tar.bz2') {
      encoded = BZip2Encoder().encode(TarEncoder().encode(archive));
    } else if (format == '.tar.gz') {
      encoded = GZipEncoder().encode(TarEncoder().encode(archive));
    } else if (format == '.zip') {
      encoded = ZipEncoder().encode(archive);
    } else {
      encoded = TarEncoder().encode(archive);
    }
    File(archivePath).writeAsBytesSync(encoded);
    return File(archivePath);
  }

  /// 快捷方式: 文本内容 → bytes Map
  Map<String, List<int>> textFiles(Map<String, String> files) =>
      files.map((k, v) => MapEntry(k, v.codeUnits));

  void verifyExtracted(String destDir, Map<String, String> expected) {
    for (final entry in expected.entries) {
      final f = File('$destDir/${entry.key}');
      expect(f.existsSync(), isTrue, reason: '${entry.key} 应存在');
      expect(f.readAsStringSync(), entry.value, reason: '${entry.key} 内容应匹配');
    }
  }

  group('extractFileToDisk 流式解压', () {
    test('.tar.bz2 解压 3 个文件', () async {
      final testFiles = {
        'model/config.json': '{"model": "test", "version": 1}',
        'model/weights.bin': 'fake_binary_data_0123456789' * 100,
        'model/vocab.txt': 'hello\nworld\ntest\n',
      };

      final archive = createArchive('.tar.bz2', textFiles(testFiles));
      final destDir = '${tmpDir.path}/out_bz2';

      await extractFileToDisk(archive.path, destDir);
      verifyExtracted(destDir, testFiles);
    });

    test('.tar.gz 解压嵌套目录', () async {
      final testFiles = {
        'data/readme.txt': 'This is a test.',
        'data/sub/nested.txt': 'Nested content.',
      };

      final archive = createArchive('.tar.gz', textFiles(testFiles));
      final destDir = '${tmpDir.path}/out_gz';

      await extractFileToDisk(archive.path, destDir);
      verifyExtracted(destDir, testFiles);
    });

    test('.zip 解压', () async {
      final testFiles = {
        'file_a.txt': 'content_a',
        'dir/file_b.txt': 'content_b',
      };

      final archive = createArchive('.zip', textFiles(testFiles));
      final destDir = '${tmpDir.path}/out_zip';

      await extractFileToDisk(archive.path, destDir);
      verifyExtracted(destDir, testFiles);
    });

    test('10MB tar.bz2 解压不崩溃', () async {
      final bigContent = 'A' * (10 * 1024 * 1024);
      final archive = createArchive('.tar.bz2', {
        'large/weights.bin': bigContent.codeUnits,
      });
      final destDir = '${tmpDir.path}/out_large';

      await extractFileToDisk(archive.path, destDir);

      final f = File('$destDir/large/weights.bin');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), bigContent.length);
    });
  });
}
