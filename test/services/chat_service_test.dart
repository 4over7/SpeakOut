import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/models/chat_model.dart';
import 'package:speakout/services/chat_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // 1. ChatMessage 序列化
  // ═══════════════════════════════════════════════════════════
  group('ChatMessage toJson / fromJson', () {
    test('基本往返: user role', () {
      final msg = ChatMessage(
        id: 'test-id-1',
        text: 'Hello world',
        role: ChatRole.user,
        timestamp: DateTime.parse('2026-01-15T10:30:00.000'),
      );
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.id, 'test-id-1');
      expect(restored.text, 'Hello world');
      expect(restored.role, ChatRole.user);
      expect(restored.timestamp, DateTime.parse('2026-01-15T10:30:00.000'));
      expect(restored.metadata, isNull);
    });

    test('往返: ai role', () {
      final msg = ChatMessage(
        id: 'ai-1',
        text: 'AI response',
        role: ChatRole.ai,
        timestamp: DateTime.parse('2026-01-15T10:31:00.000'),
      );
      final restored = ChatMessage.fromJson(msg.toJson());
      expect(restored.role, ChatRole.ai);
    });

    test('往返: dictation role', () {
      final msg = ChatMessage(
        id: 'dict-1',
        text: 'Dictated text',
        role: ChatRole.dictation,
        timestamp: DateTime.parse('2026-01-15T10:32:00.000'),
      );
      final restored = ChatMessage.fromJson(msg.toJson());
      expect(restored.role, ChatRole.dictation);
      expect(restored.text, 'Dictated text');
    });

    test('往返: tool role with metadata', () {
      final msg = ChatMessage(
        id: 'tool-1',
        text: 'Executed: search\nResult: found 3 items',
        role: ChatRole.tool,
        timestamp: DateTime.parse('2026-01-15T10:33:00.000'),
        metadata: {'tool': 'search'},
      );
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.tool);
      expect(restored.metadata, isNotNull);
      expect(restored.metadata!['tool'], 'search');
    });

    test('往返: system role', () {
      final msg = ChatMessage(
        id: 'sys-1',
        text: 'System info',
        role: ChatRole.system,
        timestamp: DateTime.parse('2026-01-15T10:34:00.000'),
      );
      final restored = ChatMessage.fromJson(msg.toJson());
      expect(restored.role, ChatRole.system);
    });

    test('中文文本序列化', () {
      final msg = ChatMessage(
        id: 'cn-1',
        text: '你好，这是一段中文测试',
        role: ChatRole.user,
        timestamp: DateTime.now(),
      );
      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);
      expect(restored.text, '你好，这是一段中文测试');
    });

    test('空文本序列化', () {
      final msg = ChatMessage(
        id: 'empty-1',
        text: '',
        role: ChatRole.user,
        timestamp: DateTime.now(),
      );
      final restored = ChatMessage.fromJson(msg.toJson());
      expect(restored.text, '');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. ChatRole 枚举
  // ═══════════════════════════════════════════════════════════
  group('ChatRole', () {
    test('包含全部 5 种角色', () {
      expect(ChatRole.values.length, 5);
    });

    test('所有 role 的 name 与枚举名一致', () {
      expect(ChatRole.user.name, 'user');
      expect(ChatRole.ai.name, 'ai');
      expect(ChatRole.system.name, 'system');
      expect(ChatRole.tool.name, 'tool');
      expect(ChatRole.dictation.name, 'dictation');
    });

    test('toJson 使用 name 而非 index', () {
      final msg = ChatMessage(
        id: 'ser-1',
        text: 'test',
        role: ChatRole.ai,
        timestamp: DateTime.parse('2026-01-15T10:00:00.000'),
      );
      expect(msg.toJson()['role'], 'ai');
    });

    test('fromJson 解析 string 格式', () {
      final json = {
        'id': 'str-1',
        'text': 'hello',
        'role': 'dictation',
        'timestamp': '2026-01-15T10:00:00.000',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, ChatRole.dictation);
    });

    test('fromJson 向后兼容旧 int 格式', () {
      final json = {
        'id': 'old-1',
        'text': 'legacy',
        'role': 0, // user
        'timestamp': '2026-01-15T10:00:00.000',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, ChatRole.user);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. JSON 持久化格式
  // ═══════════════════════════════════════════════════════════
  group('JSON 持久化', () {
    test('消息列表序列化/反序列化', () {
      final messages = [
        ChatMessage(
          id: '1',
          text: 'First message',
          role: ChatRole.user,
          timestamp: DateTime.parse('2026-01-15T10:00:00.000'),
        ),
        ChatMessage(
          id: '2',
          text: 'Second message',
          role: ChatRole.dictation,
          timestamp: DateTime.parse('2026-01-15T10:01:00.000'),
        ),
      ];

      final jsonList = messages.map((e) => e.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final restored = decoded.map((e) => ChatMessage.fromJson(e)).toList();

      expect(restored.length, 2);
      expect(restored[0].id, '1');
      expect(restored[1].role, ChatRole.dictation);
    });

    test('空列表序列化', () {
      final encoded = jsonEncode([]);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      expect(decoded, isEmpty);
    });

    test('损坏的 JSON 抛出异常', () {
      expect(() => jsonDecode('{invalid json}'), throwsFormatException);
    });

    test('缺少必要字段抛出异常', () {
      final badJson = {'id': '1', 'text': 'hello'};
      // Missing role and timestamp
      expect(() => ChatMessage.fromJson(badJson), throwsA(isA<TypeError>()));
    });

    test('写入/读取文件往返', () {
      final tmpDir = Directory.systemTemp.createTempSync('chat_test_');
      try {
        final messages = [
          ChatMessage(
            id: 'f1',
            text: '文件测试',
            role: ChatRole.user,
            timestamp: DateTime.parse('2026-01-15T12:00:00.000'),
          ),
        ];

        final file = File('${tmpDir.path}/chat_history.json');
        final jsonList = messages.map((e) => e.toJson()).toList();
        file.writeAsStringSync(jsonEncode(jsonList));

        final content = file.readAsStringSync();
        final decoded = jsonDecode(content) as List<dynamic>;
        final restored =
            decoded.map((e) => ChatMessage.fromJson(e)).toList();

        expect(restored.length, 1);
        expect(restored[0].text, '文件测试');
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. 消息上限裁剪逻辑 (真实 ChatService)
  // ═══════════════════════════════════════════════════════════
  group('ChatService 消息裁剪', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('chat_service_test_');
      ChatService.resetForTest();
      ChatService().setTestDirectory(tmpDir.path);
    });

    tearDown(() {
      ChatService.resetForTest();
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('超过 100 条时裁剪到 100 并持久化', () async {
      final service = ChatService();
      await service.init();

      // 添加 120 条消息
      for (int i = 0; i < 120; i++) {
        service.addUserMessage('Message $i');
      }

      // 等待所有异步保存完成
      await Future.delayed(const Duration(milliseconds: 500));

      expect(service.messages.length, 100);
      expect(service.messages.first.text, 'Message 20');
      expect(service.messages.last.text, 'Message 119');

      // 验证持久化文件也被裁剪
      final file = File('${tmpDir.path}/chat_history.json');
      expect(file.existsSync(), isTrue);
      final content = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(content.length, 100);
    });

    test('不到 100 条时不裁剪', () async {
      final service = ChatService();
      await service.init();

      for (int i = 0; i < 50; i++) {
        service.addUserMessage('Message $i');
      }

      await Future.delayed(const Duration(milliseconds: 500));

      expect(service.messages.length, 50);
    });
  });
}
