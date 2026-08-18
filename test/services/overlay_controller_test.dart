import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/overlay_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.SpeakOut/overlay');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('MethodChannel 异步失败由 OverlayController 消化，不泄漏未处理异常', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'overlay_unavailable');
    });

    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await OverlayController().show();
      await Future<void>.delayed(Duration.zero);
    }, (error, _) {
      uncaught.add(error);
    });

    expect(uncaught, isEmpty,
        reason: '只用同步 try/catch 包 invokeMethod 捕不到 Future 上的 PlatformException');
  });

  test('旧提示的延迟清空不能擦掉下一次录音状态', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    final overlay = OverlayController();
    overlay.showThenClear('Saved', const Duration(milliseconds: 20));
    overlay.updateText('new recording');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final texts = calls
        .where((call) => call.method == 'updateStatus')
        .map((call) => (call.arguments as Map)['text'])
        .toList();
    expect(texts, ['Saved', '...ew recording']);
    expect(texts, isNot(contains('')),
        reason: '上一轮提示的 timer 不拥有新一轮状态，不能再发送清空');
  });
}
