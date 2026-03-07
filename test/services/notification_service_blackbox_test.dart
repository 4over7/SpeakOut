/// Black-box tests for NotificationService — 通知服务模块
///
/// Test cases derived from requirements only (no implementation peeking).
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/notification_service.dart';

void main() {
  // NotificationService is a singleton — no resetForTest available,
  // but since the stream is broadcast, each test subscribes independently.

  late NotificationService service;

  setUp(() {
    service = NotificationService();
  });

  // ═══════════════════════════════════════════════════════════
  // 1. Singleton
  // ═══════════════════════════════════════════════════════════
  group('Singleton', () {
    test('多次调用构造函数返回同一实例', () {
      final a = NotificationService();
      final b = NotificationService();
      expect(identical(a, b), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. notify() 基础方法
  // ═══════════════════════════════════════════════════════════
  group('notify()', () {
    test('发送 info 类型通知到 stream', () async {
      final future = service.stream.first;
      service.notify('Hello');
      final notification = await future;

      expect(notification.message, 'Hello');
      expect(notification.type, NotificationType.info);
    });

    test('默认 type 为 info', () async {
      final future = service.stream.first;
      service.notify('Test');
      final notification = await future;

      expect(notification.type, NotificationType.info);
    });

    test('可指定 type 为 success', () async {
      final future = service.stream.first;
      service.notify('OK', type: NotificationType.success);
      final notification = await future;

      expect(notification.type, NotificationType.success);
    });

    test('可指定 type 为 error', () async {
      final future = service.stream.first;
      service.notify('Fail', type: NotificationType.error);
      final notification = await future;

      expect(notification.type, NotificationType.error);
    });

    test('可指定 type 为 audioDeviceSwitch', () async {
      final future = service.stream.first;
      service.notify('Device changed', type: NotificationType.audioDeviceSwitch);
      final notification = await future;

      expect(notification.type, NotificationType.audioDeviceSwitch);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. notifyError() 快捷方法
  // ═══════════════════════════════════════════════════════════
  group('notifyError()', () {
    test('发送 error 类型通知', () async {
      final future = service.stream.first;
      service.notifyError('Something went wrong');
      final notification = await future;

      expect(notification.message, 'Something went wrong');
      expect(notification.type, NotificationType.error);
    });

    test('error 通知 duration 大于默认值', () async {
      // Error notifications should have a longer duration for user attention
      final future = service.stream.first;
      service.notifyError('Error msg');
      final notification = await future;

      expect(notification.duration.inSeconds, greaterThanOrEqualTo(5));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. notifySuccess() 快捷方法
  // ═══════════════════════════════════════════════════════════
  group('notifySuccess()', () {
    test('发送 success 类型通知', () async {
      final future = service.stream.first;
      service.notifySuccess('Done!');
      final notification = await future;

      expect(notification.message, 'Done!');
      expect(notification.type, NotificationType.success);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 5. notifyWithAction() 带操作按钮
  // ═══════════════════════════════════════════════════════════
  group('notifyWithAction()', () {
    test('发送带 actionLabel 的通知', () async {
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Undo?',
        actionLabel: 'Undo',
        onAction: () {},
      );
      final notification = await future;

      expect(notification.message, 'Undo?');
      expect(notification.actionLabel, 'Undo');
      expect(notification.onAction, isNotNull);
    });

    test('onAction 回调可被调用', () async {
      var called = false;
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Action test',
        actionLabel: 'Do it',
        onAction: () => called = true,
      );
      final notification = await future;

      notification.onAction!();
      expect(called, isTrue);
    });

    test('可指定自定义 type', () async {
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Switch device',
        actionLabel: 'Revert',
        onAction: () {},
        type: NotificationType.audioDeviceSwitch,
      );
      final notification = await future;

      expect(notification.type, NotificationType.audioDeviceSwitch);
    });

    test('可指定自定义 duration', () async {
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Long notice',
        actionLabel: 'OK',
        onAction: () {},
        duration: const Duration(seconds: 10),
      );
      final notification = await future;

      expect(notification.duration, const Duration(seconds: 10));
    });

    test('默认 type 为 info', () async {
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Default type',
        actionLabel: 'OK',
        onAction: () {},
      );
      final notification = await future;

      expect(notification.type, NotificationType.info);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 6. Stream 多订阅者行为
  // ═══════════════════════════════════════════════════════════
  group('Stream broadcast', () {
    test('多个订阅者都能收到通知', () async {
      final completer1 = Completer<AppNotification>();
      final completer2 = Completer<AppNotification>();

      final sub1 = service.stream.listen((n) {
        if (!completer1.isCompleted) completer1.complete(n);
      });
      final sub2 = service.stream.listen((n) {
        if (!completer2.isCompleted) completer2.complete(n);
      });

      service.notify('Broadcast test');

      final n1 = await completer1.future;
      final n2 = await completer2.future;

      expect(n1.message, 'Broadcast test');
      expect(n2.message, 'Broadcast test');

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 7. 多次通知顺序
  // ═══════════════════════════════════════════════════════════
  group('通知顺序', () {
    test('多次 notify 按发送顺序到达', () async {
      final received = <String>[];
      final completer = Completer<void>();

      final sub = service.stream.listen((n) {
        received.add(n.message);
        if (received.length == 3) completer.complete();
      });

      service.notify('First');
      service.notify('Second');
      service.notify('Third');

      await completer.future;
      expect(received, ['First', 'Second', 'Third']);

      await sub.cancel();
    });

    test('混合不同方法按发送顺序到达', () async {
      final received = <NotificationType>[];
      final completer = Completer<void>();

      final sub = service.stream.listen((n) {
        received.add(n.type);
        if (received.length == 3) completer.complete();
      });

      service.notify('A');
      service.notifyError('B');
      service.notifySuccess('C');

      await completer.future;
      expect(received, [
        NotificationType.info,
        NotificationType.error,
        NotificationType.success,
      ]);

      await sub.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 8. 无订阅者时不崩溃
  // ═══════════════════════════════════════════════════════════
  group('无订阅者', () {
    test('无订阅者时 notify 不抛异常', () {
      // Broadcast stream allows events without listeners
      expect(() => service.notify('No one listening'), returnsNormally);
    });

    test('无订阅者时 notifyError 不抛异常', () {
      expect(() => service.notifyError('No one listening'), returnsNormally);
    });

    test('无订阅者时 notifySuccess 不抛异常', () {
      expect(() => service.notifySuccess('No one listening'), returnsNormally);
    });

    test('无订阅者时 notifyWithAction 不抛异常', () {
      expect(
        () => service.notifyWithAction(
          message: 'No one',
          actionLabel: 'OK',
          onAction: () {},
        ),
        returnsNormally,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 9. 边界：空消息、超长消息、特殊字符
  // ═══════════════════════════════════════════════════════════
  group('边界条件', () {
    test('空消息不崩溃', () async {
      final future = service.stream.first;
      service.notify('');
      final notification = await future;

      expect(notification.message, '');
    });

    test('超长消息正常传递', () async {
      final longMsg = 'A' * 10000;
      final future = service.stream.first;
      service.notify(longMsg);
      final notification = await future;

      expect(notification.message, longMsg);
      expect(notification.message.length, 10000);
    });

    test('特殊字符正常传递', () async {
      const special = r'Hello\n\t"quotes" <html>&amp; emoji: 🎉 中文 日本語';
      final future = service.stream.first;
      service.notify(special);
      final notification = await future;

      expect(notification.message, special);
    });

    test('换行符保留', () async {
      const multiLine = 'Line 1\nLine 2\nLine 3';
      final future = service.stream.first;
      service.notify(multiLine);
      final notification = await future;

      expect(notification.message, multiLine);
    });

    test('Unicode emoji 正常传递', () async {
      const emoji = '🔥🎵💻📱';
      final future = service.stream.first;
      service.notify(emoji);
      final notification = await future;

      expect(notification.message, emoji);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 10. AppNotification 数据类验证
  // ═══════════════════════════════════════════════════════════
  group('AppNotification 数据完整性', () {
    test('notify 生成的通知无 actionLabel 和 onAction', () async {
      final future = service.stream.first;
      service.notify('Plain notification');
      final notification = await future;

      expect(notification.actionLabel, isNull);
      expect(notification.onAction, isNull);
    });

    test('notify 生成的通知有默认 duration', () async {
      final future = service.stream.first;
      service.notify('With default duration');
      final notification = await future;

      expect(notification.duration, isNotNull);
      expect(notification.duration.inSeconds, greaterThan(0));
    });

    test('notifyWithAction 包含完整数据', () async {
      var actionTriggered = false;
      final future = service.stream.first;
      service.notifyWithAction(
        message: 'Full data',
        actionLabel: 'Click me',
        onAction: () => actionTriggered = true,
        type: NotificationType.success,
        duration: const Duration(seconds: 7),
      );
      final notification = await future;

      expect(notification.message, 'Full data');
      expect(notification.type, NotificationType.success);
      expect(notification.actionLabel, 'Click me');
      expect(notification.onAction, isNotNull);
      expect(notification.duration, const Duration(seconds: 7));

      notification.onAction!();
      expect(actionTriggered, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 11. NotificationType 枚举
  // ═══════════════════════════════════════════════════════════
  group('NotificationType 枚举', () {
    test('包含 info, success, error, audioDeviceSwitch', () {
      expect(NotificationType.values, contains(NotificationType.info));
      expect(NotificationType.values, contains(NotificationType.success));
      expect(NotificationType.values, contains(NotificationType.error));
      expect(NotificationType.values, contains(NotificationType.audioDeviceSwitch));
    });
  });
}
