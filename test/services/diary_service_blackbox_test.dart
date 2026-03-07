/// DiaryService 黑盒扩展测试
///
/// 覆盖场景：并发追加、超长文本压力、路径含空格/中文、未设置 diaryPath
/// 基础功能测试见 diary_service_test.dart
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
    tmpDir = Directory.systemTemp.createTempSync('speakout_diary_bb_');
    SharedPreferences.setMockInitialValues({
      'diary_directory': tmpDir.path,
    });
    await ConfigService().init();
    await ConfigService().setDiaryDirectory(tmpDir.path);
    service = DiaryService();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  String todayFile() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return '${tmpDir.path}/$today.md';
  }

  // ═══════════════════════════════════════════════════════════
  // 1. 并发追加
  // ═══════════════════════════════════════════════════════════
  group('并发追加', () {
    test('10 条笔记并发写入 → 全部返回成功（不崩溃）', () async {
      final futures = List.generate(
        10,
        (i) => service.appendNote('并发笔记 #$i'),
      );
      final results = await Future.wait(futures);

      // 所有调用都应返回成功（不抛异常）
      for (final r in results) {
        expect(r, isNull, reason: '每条并发笔记都应返回成功');
      }

      // 文件应存在且非空
      final file = File(todayFile());
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().isNotEmpty, isTrue);
    });

    test('顺序快速追加 50 条 → 全部写入文件', () async {
      // 顺序追加（非并发），验证数据完整性
      for (var i = 0; i < 50; i++) {
        final r = await service.appendNote('顺序 $i');
        expect(r, isNull);
      }

      final content = File(todayFile()).readAsStringSync();
      final lines = content.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, 50, reason: '50 条顺序笔记应产生 50 行');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. 超长文本压力测试
  // ═══════════════════════════════════════════════════════════
  group('超长文本压力', () {
    test('100KB 文本 → 写入成功', () async {
      final longText = 'A' * 100000; // 100KB
      final result = await service.appendNote(longText);
      expect(result, isNull);

      final content = File(todayFile()).readAsStringSync();
      expect(content.length, greaterThanOrEqualTo(100000));
    });

    test('1MB 文本 → 写入成功', () async {
      final megaText = '中' * 500000; // ~1.5MB UTF-8
      final result = await service.appendNote(megaText);
      expect(result, isNull);

      final file = File(todayFile());
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(500000));
    });

    test('多次追加累积大文件 → 后续追加仍成功', () async {
      // 先写入一个较大的基底
      final bigChunk = 'X' * 50000;
      for (var i = 0; i < 5; i++) {
        final r = await service.appendNote(bigChunk);
        expect(r, isNull, reason: '第 ${i + 1} 次大块追加应成功');
      }

      // 再追加一条普通笔记
      final result = await service.appendNote('收尾笔记');
      expect(result, isNull);

      final content = File(todayFile()).readAsStringSync();
      expect(content, contains('收尾笔记'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. 路径含空格/中文
  // ═══════════════════════════════════════════════════════════
  group('路径含特殊字符', () {
    test('路径含空格 → 正常写入', () async {
      final spacePath = '${tmpDir.path}/path with spaces/notes';
      await ConfigService().setDiaryDirectory(spacePath);

      final result = await service.appendNote('空格路径测试');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('$spacePath/$today.md');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('空格路径测试'));
    });

    test('路径含中文 → 正常写入', () async {
      final cnPath = '${tmpDir.path}/我的笔记/日记';
      await ConfigService().setDiaryDirectory(cnPath);

      final result = await service.appendNote('中文路径测试');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('$cnPath/$today.md');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('中文路径测试'));
    });

    test('路径含空格+中文混合 → 正常写入', () async {
      final mixedPath = '${tmpDir.path}/My 笔记/daily 日记';
      await ConfigService().setDiaryDirectory(mixedPath);

      final result = await service.appendNote('混合路径');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('$mixedPath/$today.md');
      expect(file.existsSync(), isTrue);
    });

    test('路径含特殊符号 (括号、&) → 正常写入', () async {
      final specialPath = '${tmpDir.path}/notes (v2) & more';
      await ConfigService().setDiaryDirectory(specialPath);

      final result = await service.appendNote('特殊符号路径');
      expect(result, isNull);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('$specialPath/$today.md');
      expect(file.existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. 未设置 / 空 diaryPath
  // ═══════════════════════════════════════════════════════════
  group('diaryPath 异常', () {
    test('diaryDirectory 为空字符串 → 返回错误', () async {
      // 通过设置空字符串模拟未配置
      await ConfigService().setDiaryDirectory('');

      final result = await service.appendNote('无路径测试');
      // 应该返回错误信息（不为 null）
      expect(result, isNotNull, reason: '空路径应返回错误');
    });

    test('diaryDirectory 指向不可写路径 → 返回错误信息而非崩溃', () async {
      // /proc 或 /dev/null 类路径在 macOS 上不可写
      await ConfigService().setDiaryDirectory('/dev/null/impossible');

      final result = await service.appendNote('不可写路径');
      expect(result, isNotNull, reason: '不可写路径应返回错误而非抛异常');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 5. 输入边界
  // ═══════════════════════════════════════════════════════════
  group('输入边界', () {
    test('Tab 字符文本 → 返回错误（纯空白）', () async {
      final result = await service.appendNote('\t\t\t');
      expect(result, isNotNull, reason: 'Tab 纯空白应被拒绝');
    });

    test('Unicode 零宽字符 → 不视为空白，写入成功', () async {
      // Zero-width space U+200B 不是 Dart trim() 会去掉的字符
      final result = await service.appendNote('\u200B');
      expect(result, isNull, reason: '零宽字符不是空白，应写入成功');
    });

    test('单字符文本 → 成功', () async {
      final result = await service.appendNote('A');
      expect(result, isNull);

      final content = File(todayFile()).readAsStringSync();
      expect(content, contains('A'));
    });

    test('Emoji 文本 → 成功', () async {
      final result = await service.appendNote('Today was great! 🎉🚀');
      expect(result, isNull);

      final content = File(todayFile()).readAsStringSync();
      expect(content, contains('🎉🚀'));
    });
  });
}
