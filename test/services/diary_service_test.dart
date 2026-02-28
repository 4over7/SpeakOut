import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/diary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late DiaryService service;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('speakout_diary_test_');
    // ConfigService is a singleton — may already be initialized.
    // Use setMockInitialValues with the correct key, then re-init.
    SharedPreferences.setMockInitialValues({
      'diary_directory': tmpDir.path,
    });
    // Force re-read of SharedPreferences by calling setDiaryDirectory
    await ConfigService().init();
    await ConfigService().setDiaryDirectory(tmpDir.path);
    service = DiaryService();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════
  // 1. appendNote 基础功能
  // ═══════════════════════════════════════════════════════════
  group('appendNote', () {
    test('追加笔记到当天日期文件', () async {
      final result = await service.appendNote('测试笔记');
      expect(result, isNull, reason: '返回 null 表示成功');

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('测试笔记'));
    });

    test('文件名格式: yyyy-MM-dd.md', () async {
      await service.appendNote('test');

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.existsSync(), isTrue);
    });

    test('内容格式: - **[HH:mm:ss]** text', () async {
      await service.appendNote('格式测试');

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      final content = file.readAsStringSync();

      // Should match pattern: - **[HH:mm:ss]** 格式测试
      expect(content, matches(RegExp(r'^- \*\*\[\d{2}:\d{2}:\d{2}\]\*\* 格式测试\n$')));
    });

    test('多次追加到同一文件', () async {
      await service.appendNote('第一条');
      await service.appendNote('第二条');

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      final content = file.readAsStringSync();
      final lines = content.split('\n').where((l) => l.isNotEmpty).toList();

      expect(lines.length, 2);
      expect(lines[0], contains('第一条'));
      expect(lines[1], contains('第二条'));
    });

    test('英文文本', () async {
      final result = await service.appendNote('Hello world');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.readAsStringSync(), contains('Hello world'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. 错误处理
  // ═══════════════════════════════════════════════════════════
  group('错误处理', () {
    test('空文本 → 返回错误', () async {
      final result = await service.appendNote('');
      expect(result, isNotNull);
      expect(result, contains('Empty'));
    });

    test('纯空格文本 → 返回错误', () async {
      final result = await service.appendNote('   ');
      expect(result, isNotNull);
      expect(result, contains('Empty'));
    });

    test('目录不存在 → 自动创建', () async {
      final nestedDir = '${tmpDir.path}/nested/deep/dir';
      await ConfigService().setDiaryDirectory(nestedDir);

      final result = await service.appendNote('nested test');
      expect(result, isNull);
      expect(Directory(nestedDir).existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. 边界情况
  // ═══════════════════════════════════════════════════════════
  group('边界情况', () {
    test('包含特殊字符的文本', () async {
      final result = await service.appendNote('包含 **markdown** 和 [链接](url) 的文本');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.readAsStringSync(), contains('**markdown**'));
    });

    test('包含换行符的文本', () async {
      final result = await service.appendNote('第一行\n第二行');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.readAsStringSync(), contains('第一行\n第二行'));
    });

    test('很长的文本', () async {
      final longText = '长' * 10000;
      final result = await service.appendNote(longText);
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${tmpDir.path}/$today.md');
      expect(file.readAsStringSync().length, greaterThan(10000));
    });
  });
}
