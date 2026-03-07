/// Black-box tests for ChatService — 聊天服务模块
///
/// Test cases derived from requirements only (no implementation peeking).
/// Focuses on public API behavior: add methods, stream, persistence, trimming.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/models/chat_model.dart';
import 'package:speakout/services/chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatService service;
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('chat_blackbox_test_');
    ChatService.resetForTest();
    service = ChatService();
    service.setTestDirectory(tmpDir.path);
  });

  tearDown(() {
    ChatService.resetForTest();
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════
  // 1. Singleton
  // ═══════════════════════════════════════════════════════════
  group('Singleton', () {
    test('多次调用构造函数返回同一实例', () {
      final a = ChatService();
      final b = ChatService();
      expect(identical(a, b), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. init() 初始化
  // ═══════════════════════════════════════════════════════════
  group('init()', () {
    test('初始化后 messages 为空 (无历史文件)', () async {
      await service.init();
      expect(service.messages, isEmpty);
    });

    test('重复调用 init 不会报错', () async {
      await service.init();
      await service.init(); // idempotent
      expect(service.messages, isEmpty);
    });

    test('init 从已有 JSON 文件加载历史', () async {
      // Pre-populate a history file
      final historyFile = File('${tmpDir.path}/chat_history.json');
      final data = [
        ChatMessage(
          id: 'pre-1',
          text: 'Pre-existing message',
          role: ChatRole.user,
          timestamp: DateTime.parse('2026-01-01T00:00:00.000'),
        ).toJson(),
      ];
      historyFile.writeAsStringSync(jsonEncode(data));

      await service.init();

      expect(service.messages.length, 1);
      expect(service.messages.first.text, 'Pre-existing message');
      expect(service.messages.first.role, ChatRole.user);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. addInfo()
  // ═══════════════════════════════════════════════════════════
  group('addInfo()', () {
    test('添加 system role 消息', () async {
      await service.init();
      service.addInfo('System information');

      expect(service.messages.length, 1);
      expect(service.messages.first.role, ChatRole.system);
      expect(service.messages.first.text, 'System information');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. addUserMessage()
  // ═══════════════════════════════════════════════════════════
  group('addUserMessage()', () {
    test('添加 user role 消息', () async {
      await service.init();
      service.addUserMessage('Hello from user');

      expect(service.messages.length, 1);
      expect(service.messages.first.role, ChatRole.user);
      expect(service.messages.first.text, 'Hello from user');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 5. addAiMessage()
  // ═══════════════════════════════════════════════════════════
  group('addAiMessage()', () {
    test('添加 ai role 消息', () async {
      await service.init();
      service.addAiMessage('AI response');

      expect(service.messages.length, 1);
      expect(service.messages.first.role, ChatRole.ai);
      expect(service.messages.first.text, 'AI response');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 6. addToolResult()
  // ═══════════════════════════════════════════════════════════
  group('addToolResult()', () {
    test('添加 tool role 消息，包含格式化文本', () async {
      await service.init();
      service.addToolResult('search', 'found 3 items');

      expect(service.messages.length, 1);
      expect(service.messages.first.role, ChatRole.tool);
      // Text should contain tool name and result
      expect(service.messages.first.text, contains('search'));
      expect(service.messages.first.text, contains('found 3 items'));
    });

    test('metadata 包含 tool 名称', () async {
      await service.init();
      service.addToolResult('calculator', '42');

      final msg = service.messages.first;
      expect(msg.metadata, isNotNull);
      expect(msg.metadata!['tool'], 'calculator');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 7. addDictation()
  // ═══════════════════════════════════════════════════════════
  group('addDictation()', () {
    test('添加 dictation role 消息', () async {
      await service.init();
      service.addDictation('Voice input text');

      expect(service.messages.length, 1);
      expect(service.messages.first.role, ChatRole.dictation);
      expect(service.messages.first.text, 'Voice input text');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 8. 消息属性完整性
  // ═══════════════════════════════════════════════════════════
  group('消息属性', () {
    test('每条消息有唯一 id', () async {
      await service.init();
      service.addUserMessage('A');
      service.addUserMessage('B');
      service.addUserMessage('C');

      final ids = service.messages.map((m) => m.id).toSet();
      expect(ids.length, 3); // All unique
    });

    test('每条消息有 id (uuid 格式)', () async {
      await service.init();
      service.addUserMessage('Test');

      final id = service.messages.first.id;
      expect(id, isNotEmpty);
      // UUID v4 format: 8-4-4-4-12
      expect(id.length, 36);
      expect(id.contains('-'), isTrue);
    });

    test('每条消息有 timestamp', () async {
      await service.init();
      final before = DateTime.now();
      service.addUserMessage('Timestamped');
      final after = DateTime.now();

      final ts = service.messages.first.timestamp;
      expect(ts.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(ts.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 9. messages 只读属性
  // ═══════════════════════════════════════════════════════════
  group('messages 只读', () {
    test('返回的列表不可直接修改 (unmodifiable)', () async {
      await service.init();
      service.addUserMessage('Immutable test');

      expect(
        () => service.messages.add(
          ChatMessage(
            id: 'hack',
            text: 'injected',
            role: ChatRole.user,
            timestamp: DateTime.now(),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 10. clearHistory()
  // ═══════════════════════════════════════════════════════════
  group('clearHistory()', () {
    test('清空所有消息', () async {
      await service.init();
      service.addUserMessage('A');
      service.addAiMessage('B');
      service.addInfo('C');
      expect(service.messages.length, 3);

      await service.clearHistory();
      expect(service.messages, isEmpty);
    });

    test('清空后持久化文件也被清空', () async {
      await service.init();
      service.addUserMessage('Will be cleared');
      await Future.delayed(const Duration(milliseconds: 300));

      await service.clearHistory();
      await Future.delayed(const Duration(milliseconds: 300));

      final file = File('${tmpDir.path}/chat_history.json');
      if (file.existsSync()) {
        final content = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        expect(content, isEmpty);
      }
    });

    test('清空后可继续添加消息', () async {
      await service.init();
      service.addUserMessage('Before clear');
      await service.clearHistory();
      service.addUserMessage('After clear');

      expect(service.messages.length, 1);
      expect(service.messages.first.text, 'After clear');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 11. messageStream
  // ═══════════════════════════════════════════════════════════
  group('messageStream', () {
    test('添加消息时 stream 发送更新', () async {
      await service.init();

      final completer = Completer<List<ChatMessage>>();
      final sub = service.messageStream.listen((msgs) {
        if (!completer.isCompleted) completer.complete(msgs);
      });

      service.addUserMessage('Stream test');
      final received = await completer.future;

      expect(received.length, 1);
      expect(received.first.text, 'Stream test');

      await sub.cancel();
    });

    test('每次添加消息都触发 stream 事件', () async {
      await service.init();

      var eventCount = 0;
      final completer = Completer<void>();
      final sub = service.messageStream.listen((msgs) {
        eventCount++;
        if (eventCount == 3) completer.complete();
      });

      service.addUserMessage('1');
      service.addUserMessage('2');
      service.addUserMessage('3');

      await completer.future;
      // All 3 additions triggered stream events
      expect(eventCount, 3);
      // Final state has all 3 messages in order
      expect(service.messages.length, 3);
      expect(service.messages[0].text, '1');
      expect(service.messages[1].text, '2');
      expect(service.messages[2].text, '3');

      await sub.cancel();
    });

    test('clearHistory 也触发 stream 事件', () async {
      await service.init();
      service.addUserMessage('Will clear');
      await Future.delayed(const Duration(milliseconds: 100));

      final completer = Completer<List<ChatMessage>>();
      final sub = service.messageStream.listen((msgs) {
        if (!completer.isCompleted && msgs.isEmpty) {
          completer.complete(msgs);
        }
      });

      await service.clearHistory();
      final received = await completer.future;
      expect(received, isEmpty);

      await sub.cancel();
    });

    test('stream 是 broadcast (支持多订阅者)', () async {
      await service.init();

      final c1 = Completer<List<ChatMessage>>();
      final c2 = Completer<List<ChatMessage>>();

      final sub1 = service.messageStream.listen((msgs) {
        if (!c1.isCompleted) c1.complete(msgs);
      });
      final sub2 = service.messageStream.listen((msgs) {
        if (!c2.isCompleted) c2.complete(msgs);
      });

      service.addUserMessage('Broadcast');

      final r1 = await c1.future;
      final r2 = await c2.future;

      expect(r1.length, 1);
      expect(r2.length, 1);

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 12. 消息持久化和加载
  // ═══════════════════════════════════════════════════════════
  group('持久化', () {
    test('添加消息后持久化到 JSON 文件', () async {
      await service.init();
      service.addUserMessage('Persist this');
      // Wait for async save
      await Future.delayed(const Duration(milliseconds: 500));

      final file = File('${tmpDir.path}/chat_history.json');
      expect(file.existsSync(), isTrue);

      final content = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(content.length, 1);
      expect(content.first['text'], 'Persist this');
      expect(content.first['role'], 'user');
    });

    test('重新 init 后恢复消息', () async {
      await service.init();
      service.addUserMessage('Remember me');
      service.addAiMessage('I remember');
      await Future.delayed(const Duration(milliseconds: 500));

      // Reset and re-init
      ChatService.resetForTest();
      final freshService = ChatService();
      freshService.setTestDirectory(tmpDir.path);
      await freshService.init();

      expect(freshService.messages.length, 2);
      expect(freshService.messages[0].text, 'Remember me');
      expect(freshService.messages[0].role, ChatRole.user);
      expect(freshService.messages[1].text, 'I remember');
      expect(freshService.messages[1].role, ChatRole.ai);
    });

    test('持久化保留所有消息类型', () async {
      await service.init();
      service.addInfo('info msg');
      service.addUserMessage('user msg');
      service.addAiMessage('ai msg');
      service.addToolResult('tool1', 'result1');
      service.addDictation('dictation msg');
      await Future.delayed(const Duration(milliseconds: 500));

      // Reset and reload
      ChatService.resetForTest();
      final fresh = ChatService();
      fresh.setTestDirectory(tmpDir.path);
      await fresh.init();

      expect(fresh.messages.length, 5);
      expect(fresh.messages[0].role, ChatRole.system);
      expect(fresh.messages[1].role, ChatRole.user);
      expect(fresh.messages[2].role, ChatRole.ai);
      expect(fresh.messages[3].role, ChatRole.tool);
      expect(fresh.messages[4].role, ChatRole.dictation);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 13. 超过 100 条自动裁剪
  // ═══════════════════════════════════════════════════════════
  group('自动裁剪', () {
    test('超过 100 条时裁剪到 100', () async {
      await service.init();

      for (int i = 0; i < 120; i++) {
        service.addUserMessage('Message $i');
      }
      // Wait for saves
      await Future.delayed(const Duration(milliseconds: 800));

      expect(service.messages.length, 100);
      // Oldest messages should be trimmed: 0..19 removed, 20..119 remain
      expect(service.messages.first.text, 'Message 20');
      expect(service.messages.last.text, 'Message 119');
    });

    test('裁剪结果持久化到文件', () async {
      await service.init();

      for (int i = 0; i < 110; i++) {
        service.addUserMessage('Msg $i');
      }
      await Future.delayed(const Duration(milliseconds: 800));

      final file = File('${tmpDir.path}/chat_history.json');
      final content = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(content.length, 100);
    });

    test('恰好 100 条不裁剪', () async {
      await service.init();

      for (int i = 0; i < 100; i++) {
        service.addUserMessage('Exact $i');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      expect(service.messages.length, 100);
      expect(service.messages.first.text, 'Exact 0');
    });

    test('少于 100 条不裁剪', () async {
      await service.init();

      for (int i = 0; i < 50; i++) {
        service.addUserMessage('Half $i');
      }
      await Future.delayed(const Duration(milliseconds: 300));

      expect(service.messages.length, 50);
      expect(service.messages.first.text, 'Half 0');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 14. 消息添加顺序
  // ═══════════════════════════════════════════════════════════
  group('消息顺序', () {
    test('多条消息按添加顺序排列', () async {
      await service.init();
      service.addUserMessage('First');
      service.addAiMessage('Second');
      service.addInfo('Third');
      service.addDictation('Fourth');

      expect(service.messages.length, 4);
      expect(service.messages[0].text, 'First');
      expect(service.messages[1].text, 'Second');
      expect(service.messages[2].text, 'Third');
      expect(service.messages[3].text, 'Fourth');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 15. 边界条件
  // ═══════════════════════════════════════════════════════════
  group('边界条件', () {
    test('空文本可添加', () async {
      await service.init();
      service.addUserMessage('');

      expect(service.messages.length, 1);
      expect(service.messages.first.text, '');
    });

    test('超长文本正常保存和加载', () async {
      await service.init();
      final longText = 'A' * 10000;
      service.addUserMessage(longText);
      await Future.delayed(const Duration(milliseconds: 500));

      // Reload
      ChatService.resetForTest();
      final fresh = ChatService();
      fresh.setTestDirectory(tmpDir.path);
      await fresh.init();

      expect(fresh.messages.first.text.length, 10000);
    });

    test('特殊字符正常保存和加载', () async {
      await service.init();
      const special = r'Hello\n\t"quotes" <html>&amp; emoji: 🎉 中文 日本語';
      service.addUserMessage(special);
      await Future.delayed(const Duration(milliseconds: 500));

      // Reload
      ChatService.resetForTest();
      final fresh = ChatService();
      fresh.setTestDirectory(tmpDir.path);
      await fresh.init();

      expect(fresh.messages.first.text, special);
    });

    test('换行符保留', () async {
      await service.init();
      const multiLine = 'Line 1\nLine 2\nLine 3';
      service.addUserMessage(multiLine);
      await Future.delayed(const Duration(milliseconds: 500));

      ChatService.resetForTest();
      final fresh = ChatService();
      fresh.setTestDirectory(tmpDir.path);
      await fresh.init();

      expect(fresh.messages.first.text, multiLine);
    });

    test('中文文本正常保存和加载', () async {
      await service.init();
      const chinese = '你好世界，这是一段中文测试消息。包含标点符号：《》「」【】';
      service.addUserMessage(chinese);
      await Future.delayed(const Duration(milliseconds: 500));

      ChatService.resetForTest();
      final fresh = ChatService();
      fresh.setTestDirectory(tmpDir.path);
      await fresh.init();

      expect(fresh.messages.first.text, chinese);
    });

    test('快速连续添加不丢失消息', () async {
      await service.init();

      // Rapid-fire additions
      for (int i = 0; i < 20; i++) {
        service.addUserMessage('Rapid $i');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      expect(service.messages.length, 20);
      for (int i = 0; i < 20; i++) {
        expect(service.messages[i].text, 'Rapid $i');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 16. 损坏数据恢复
  // ═══════════════════════════════════════════════════════════
  group('损坏数据恢复', () {
    test('损坏的 JSON 文件不导致 init 崩溃', () async {
      final file = File('${tmpDir.path}/chat_history.json');
      file.writeAsStringSync('{invalid json!!!');

      // Should not throw
      await service.init();
      expect(service.messages, isEmpty);
    });

    test('空 JSON 文件正常处理', () async {
      final file = File('${tmpDir.path}/chat_history.json');
      file.writeAsStringSync('[]');

      await service.init();
      expect(service.messages, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 17. resetForTest 行为
  // ═══════════════════════════════════════════════════════════
  group('resetForTest()', () {
    test('重置后 messages 为空', () async {
      await service.init();
      service.addUserMessage('Will be reset');
      expect(service.messages.length, 1);

      ChatService.resetForTest();
      expect(service.messages, isEmpty);
    });

    test('重置后可重新 init', () async {
      await service.init();
      service.addUserMessage('First run');

      ChatService.resetForTest();
      service.setTestDirectory(tmpDir.path);
      await service.init();

      // Should load from file (first run was saved)
      // Wait for potential save from first run
      await Future.delayed(const Duration(milliseconds: 300));
    });
  });
}
