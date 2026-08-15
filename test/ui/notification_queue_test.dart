import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:speakout/services/notification_service.dart';
import 'package:speakout/ui/notification_overlay.dart';

/// 通知队列的行为测试（不是源码断言）—— 这块逻辑全是新写的。
///
/// 事故来源：DiaryService 写盘失败自己先发一条红色 5 秒 error，
/// 调用方紧接着再发一条 info。旧消费端直接替换 _currentNotification，
/// 用户根本看不到那条错误。
void main() {
  Future<void> pumpOverlay(WidgetTester t) async {
    await t.pumpWidget(MacosApp(
      builder: (_, child) =>
          NotificationOverlay(child: child ?? const SizedBox.shrink()),
      home: const SizedBox.shrink(),
    ));
    await t.pump();
  }

  testWidgets('低优先级不得顶掉尚未过期的 error', (t) async {
    await pumpOverlay(t);
    NotificationService().notifyError('磁盘写入失败');
    await t.pump();
    await t.pump();
    expect(find.text('磁盘写入失败'), findsOneWidget);

    NotificationService().notify('保存失败');  // 同一事件循环紧随其后
    await t.pump();
    expect(find.text('磁盘写入失败'), findsOneWidget,
        reason: '错误被后来的 info 顶掉了，用户看不到真正的原因');
    expect(find.text('保存失败'), findsNothing);

    await t.pump(const Duration(seconds: 6)); // error 过期
    expect(find.text('保存失败'), findsOneWidget, reason: '排队的通知没有接上');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('出队按优先级而非先进先出', (t) async {
    await pumpOverlay(t);
    NotificationService().notifyError('错误');
    await t.pump();
    NotificationService().notify('普通信息');            // 先入队，优先级低
    NotificationService().notifyWithAction(              // 后入队，优先级高
      message: '设备已切换',
      actionLabel: '撤销',
      onAction: () {},
      type: NotificationType.audioDeviceSwitch,
      duration: const Duration(seconds: 2),
    );
    await t.pump();

    await t.pump(const Duration(seconds: 6)); // 错误过期
    expect(find.text('设备已切换'), findsOneWidget,
        reason: 'FIFO 会先弹「普通信息」，让时效敏感的设备提示排在后面');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('队列有上限，不会积压成长时间连播', (t) async {
    await pumpOverlay(t);
    NotificationService().notifyError('错误');
    await t.pump();
    for (var i = 0; i < 10; i++) {
      NotificationService().notify('消息$i');
    }
    await t.pump();
    await t.pump(const Duration(seconds: 6));

    // 精确计数，不留 off-by-one 容差：上限 3 → 错误过期后恰好再弹 3 条。
    // 原来「多 pump 几次再断言为空」的写法，上限就算错成 4 也照样通过。
    //
    // 采样步长必须小于通知时长：我最初用 6 秒一步，结果一次 pump 里
    // 「弹出→过期→弹下一条」全跑完了，中间那条永远采不到（实测只数到 2 条）。
    final seen = <String>{};
    for (var i = 0; i < 120; i++) {
      final f = find.textContaining('消息').evaluate();
      if (f.isNotEmpty) seen.add((f.first.widget as Text).data!);
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(seen.length, 3,
        reason: '排队展示了 ${seen.length} 条（$seen），应恰好等于 _maxQueue=3。'
            '多于 3 说明上限失效，少于 3 说明该排的没排上');
  });
}
