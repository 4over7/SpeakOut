import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/app_service.dart';

void main() {
  test('启动 Ready 必须同时满足键盘监听与 ASR 可用', () {
    expect(
      AppService.startupHealthIsReady(
        listenerRunning: true,
        asrReady: true,
      ),
      isTrue,
    );
    expect(
      AppService.startupHealthIsReady(
        listenerRunning: true,
        asrReady: false,
      ),
      isFalse,
      reason: '只启动 CGEventTap 就显示 Ready，会掩盖模型下载或初始化失败',
    );
    expect(
      AppService.startupHealthIsReady(
        listenerRunning: false,
        asrReady: true,
      ),
      isFalse,
    );
  });
}
