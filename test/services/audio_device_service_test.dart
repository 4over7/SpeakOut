import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/ffi/native_input_base.dart';
import 'package:speakout/services/audio_device_service.dart';
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/notification_service.dart';

class _FakeNativeInput implements NativeInputBase {
  String devicesJson = '[]';
  String currentDeviceJson = '{}';
  bool listenerStartResult = true;
  bool deviceAvailable = true;
  bool setInputResult = true;
  bool switchToBuiltinResult = true;

  int deviceEnumerationCount = 0;
  int currentDeviceQueryCount = 0;
  int listenerStartCount = 0;
  int listenerStopCount = 0;
  int nativeFreeCount = 0;
  final List<String> preferredDeviceUids = [];
  Pointer<NativeFunction<DeviceChangeCallbackC>>? deviceChangeCallback;

  @override
  String getAudioInputDevices() {
    deviceEnumerationCount++;
    return devicesJson;
  }

  @override
  String getCurrentInputDevice() {
    currentDeviceQueryCount++;
    return currentDeviceJson;
  }

  @override
  bool startDeviceChangeListener(
    Pointer<NativeFunction<DeviceChangeCallbackC>> callback,
  ) {
    listenerStartCount++;
    deviceChangeCallback = callback;
    return listenerStartResult;
  }

  @override
  void stopDeviceChangeListener() {
    listenerStopCount++;
    deviceChangeCallback = null;
  }

  @override
  void nativeFree(Pointer<Void> ptr) {
    nativeFreeCount++;
    calloc.free(ptr);
  }

  @override
  bool isDeviceAvailable(String deviceUID) => deviceAvailable;

  @override
  void setPreferredDeviceUid(String uid) => preferredDeviceUids.add(uid);

  @override
  bool setInputDevice(String deviceUID) => setInputResult;

  @override
  bool switchToBuiltinMic() {
    if (switchToBuiltinResult) preferredDeviceUids.add('builtin-mic');
    return switchToBuiltinResult;
  }

  @override
  bool isCurrentInputBluetooth() => false;

  @override
  String getPreferredDeviceUid() =>
      preferredDeviceUids.isEmpty ? '' : preferredDeviceUids.last;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigService().init();
    await ConfigService().setAudioInputDeviceId(null);
    await ConfigService().setBluetoothMicReminderEnabled(true);
    await ConfigService().setAppLanguage('system');
  });

  test('当前设备查询失败时清掉旧缓存', () {
    final native = _FakeNativeInput()
      ..currentDeviceJson =
          '{"id":"mic-1","name":"Mic 1","isBluetooth":false,'
          '"isBuiltIn":true,"sampleRate":48000}';
    final service = AudioDeviceService(native);

    service.refreshDevices();
    expect(service.currentDevice?.id, 'mic-1');

    native.currentDeviceJson = '{}';
    service.refreshDevices();
    expect(service.currentDevice, isNull);
  });

  test('清除偏好不触发可能阻塞的全设备枚举', () {
    final native = _FakeNativeInput();
    final service = AudioDeviceService(native);

    service.clearPreferredDevice();

    expect(native.preferredDeviceUids, ['']);
    expect(native.deviceEnumerationCount, 0);
    expect(native.currentDeviceQueryCount, 0);
  });

  test('初始化成功后幂等，dispose 也只拆一次 listener', () {
    final native = _FakeNativeInput();
    final service = AudioDeviceService(native);

    service.initialize();
    service.initialize();

    expect(native.listenerStartCount, 1);
    expect(native.deviceEnumerationCount, 0);
    expect(native.currentDeviceQueryCount, 1);

    service.dispose();
    service.dispose();
    expect(native.listenerStopCount, 1);
  });

  test('初始化恢复蓝牙麦克风提醒开关', () async {
    await ConfigService().setBluetoothMicReminderEnabled(false);
    final native = _FakeNativeInput();
    final service = AudioDeviceService(native);

    service.initialize();

    expect(service.autoManageEnabled, isFalse);
    service.dispose();
  });

  test('listener 启动失败先清 native 指针并允许重试', () {
    final native = _FakeNativeInput()..listenerStartResult = false;
    final service = AudioDeviceService(native);

    service.initialize();
    expect(native.listenerStartCount, 1);
    expect(native.listenerStopCount, 1);

    native.listenerStartResult = true;
    service.initialize();
    expect(native.listenerStartCount, 2);

    service.dispose();
    expect(native.listenerStopCount, 2);
  });

  test('设备回调清理失效偏好时不重新枚举设备', () async {
    await ConfigService().setAudioInputDeviceId('missing-mic');
    final native = _FakeNativeInput()..deviceAvailable = false;
    final service = AudioDeviceService(native);
    service.initialize();
    final enumerationCount = native.deviceEnumerationCount;
    final event = service.deviceChanges.first;

    final id = 'system-mic'.toNativeUtf8();
    final name = 'System Mic'.toNativeUtf8();
    native.deviceChangeCallback!.asFunction<DeviceChangeCallbackDart>()(
      id,
      name,
      0,
    );

    expect((await event).deviceId, 'system-mic');
    await Future<void>.delayed(Duration.zero);
    expect(native.deviceEnumerationCount, enumerationCount);
    expect(native.preferredDeviceUids.last, '');
    expect(ConfigService().audioInputDeviceId, isNull);
    expect(native.nativeFreeCount, 2);

    service.dispose();
  });

  test('蓝牙切换失败不谎报成功，通知遵循应用语言', () async {
    await ConfigService().setAppLanguage('en');
    final native = _FakeNativeInput()..switchToBuiltinResult = false;
    final service = AudioDeviceService(native);
    service.initialize();
    final suggestionFuture = NotificationService().stream.first.timeout(
      const Duration(seconds: 1),
    );

    final id = 'bluetooth-mic'.toNativeUtf8();
    final name = 'Bluetooth Mic'.toNativeUtf8();
    native.deviceChangeCallback!.asFunction<DeviceChangeCallbackDart>()(
      id,
      name,
      1,
    );

    final suggestion = await suggestionFuture;
    expect(suggestion.message, startsWith('Bluetooth microphone detected'));
    expect(suggestion.actionLabel, 'Switch to built-in microphone');

    final failureFuture = NotificationService().stream.first.timeout(
      const Duration(seconds: 1),
    );
    suggestion.onAction!();
    final failure = await failureFuture;
    expect(failure.message, 'Failed to switch audio input device');
    expect(failure.type, NotificationType.error);

    service.dispose();
  });

  test('蓝牙提醒的一键切换成功后持久化内置麦克风', () async {
    await ConfigService().setAppLanguage('en');
    final native = _FakeNativeInput();
    final service = AudioDeviceService(native);
    service.initialize();
    final suggestionFuture = NotificationService().stream.first.timeout(
      const Duration(seconds: 1),
    );

    final id = 'bluetooth-mic'.toNativeUtf8();
    final name = 'Bluetooth Mic'.toNativeUtf8();
    native.deviceChangeCallback!.asFunction<DeviceChangeCallbackDart>()(
      id,
      name,
      1,
    );

    final suggestion = await suggestionFuture;
    final successFuture = NotificationService().stream.first.timeout(
      const Duration(seconds: 1),
    );
    suggestion.onAction!();
    final success = await successFuture;

    expect(success.message, 'Switched to built-in microphone');
    expect(ConfigService().audioInputDeviceId, 'builtin-mic');

    service.dispose();
  });
}
