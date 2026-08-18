import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import '../ffi/native_input_base.dart';
import 'config_service.dart';
import 'notification_service.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';

/// Represents an audio input device
class AudioDevice {
  final String id;
  final String name;
  final bool isBluetooth;
  final bool isBuiltIn;
  final double sampleRate;
  
  AudioDevice({
    required this.id,
    required this.name,
    required this.isBluetooth,
    required this.isBuiltIn,
    required this.sampleRate,
  });
  
  factory AudioDevice.fromJson(Map<String, dynamic> json) {
    return AudioDevice(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isBluetooth: json['isBluetooth'] ?? false,
      isBuiltIn: json['isBuiltIn'] ?? false,
      sampleRate: (json['sampleRate'] ?? 0).toDouble(),
    );
  }
  
  @override
  String toString() => 'AudioDevice($name, bluetooth=$isBluetooth, builtIn=$isBuiltIn)';
}

/// Event when audio device changes
class AudioDeviceEvent {
  final String deviceId;
  final String deviceName;
  final bool isBluetooth;
  
  AudioDeviceEvent({
    required this.deviceId,
    required this.deviceName,
    required this.isBluetooth,
  });
}

/// Service for managing audio input devices
/// Automatically detects Bluetooth microphones and switches to high-quality mic
class AudioDeviceService {
  final NativeInputBase _nativeInput;
  
  // Stream controller for device change events
  final _deviceChangeController = StreamController<AudioDeviceEvent>.broadcast();
  
  // Settings
  bool autoManageEnabled = true;
  bool showSwitchNotifications = true;
  
  // Cached devices
  AudioDevice? _currentDevice;
  List<AudioDevice> _devices = [];
  
  // Native callback holder
  NativeCallable<DeviceChangeCallbackC>? _deviceChangeCallable;

  /// NativeCallable.listener 异步投递：stop 之前 native 已发出的那次回调，
  /// 消息可能在 dispose 关掉 controller 之后才被 isolate 处理。见
  /// _handleDeviceChange 入口的说明。
  bool _disposed = false;
  
  AudioDeviceService(this._nativeInput);

  AppLocalizations get _loc {
    final configured = ConfigService().appLanguage;
    final locale = configured == 'system'
        ? PlatformDispatcher.instance.locale
        : Locale(configured);
    return lookupAppLocalizations(
        Locale(locale.languageCode == 'zh' ? 'zh' : 'en'));
  }
  
  /// Initialize the service and start listening for device changes
  void initialize() {
    if (_disposed || _deviceChangeCallable != null) {
      AppLog.d('[AudioDeviceService] Already initialized or disposed, skipping');
      return;
    }
    AppLog.d('[AudioDeviceService] Initializing...');

    autoManageEnabled = ConfigService().bluetoothMicReminderEnabled;
    
    // 启动只取当前默认设备。全量枚举留到设置页按需读取，避免应用恰好在
    // 蓝牙协商期间启动时阻塞主 isolate。
    _refreshCurrentDevice();
    
    // Start listening for device changes
    _startListening();
    
    AppLog.d('[AudioDeviceService] Initialized. Current device: $_currentDevice');
  }
  
  void _startListening() {
    // Create native callable for device change callback
    _deviceChangeCallable = NativeCallable<DeviceChangeCallbackC>.listener(
      _onDeviceChanged,
    );
    
    final success = _nativeInput.startDeviceChangeListener(
      _deviceChangeCallable!.nativeFunction,
    );

    if (!success) {
      // native 会先保存 callback 再注册系统 listener；注册失败时也要先 stop
      // 清掉 native 指针，之后才能安全释放 trampoline，并允许下次重试。
      _nativeInput.stopDeviceChangeListener();
      _deviceChangeCallable?.close();
      _deviceChangeCallable = null;
    }
    
    AppLog.d('[AudioDeviceService] Device change listener started: $success');
  }
  
  /// Native callback when device changes
  void _onDeviceChanged(
    Pointer<Utf8> deviceId,
    Pointer<Utf8> deviceName,
    int isBluetooth,
  ) {
    // native 侧 strdup 过（见 native_input.m 里 deviceChangeCallback 的说明：
    // NativeCallable.listener 异步投递，直接传 UTF8String 会是悬垂指针），
    // 这里读完必须释放，否则每次设备变化漏两块内存。
    // try/finally：toDartString 抛异常时也要释放。
    try {
      unawaited(_handleDeviceChange(
        deviceId.toDartString(),
        deviceName.toDartString(),
        isBluetooth == 1,
      ));
    } finally {
      _nativeInput.nativeFree(deviceId.cast());
      _nativeInput.nativeFree(deviceName.cast());
    }
  }
  
  Future<void> _handleDeviceChange(
      String deviceId, String deviceName, bool isBluetooth) async {
    // 与 native 那把锁互补，两者都不能少：
    // 锁保证 stop 返回后没有 native 回调在途；但 NativeCallable.listener 是
    // **异步投递**的 —— stop 之前 native 已经调过一次的话，那条消息还排在
    // isolate 队列里，会在 dispose 关掉 controller 之后才被处理，
    // 届时 add() 抛 StateError（Bad state: Cannot add new events after close）。
    if (_disposed || _deviceChangeController.isClosed) return;

    AppLog.d('[AudioDeviceService] Device changed: $deviceName (bluetooth=$isBluetooth)');

    // Invalidate cache — will be lazily rebuilt next time devices are accessed
    // (e.g. when user opens settings). Do NOT call refreshDevices() here:
    // enumerating all devices while Bluetooth is negotiating blocks the main
    // thread for minutes, freezing CGEventTap keyboard events.
    _devices = [];
    _currentDevice = null;

    // Check if our preferred device is still available
    final savedId = ConfigService().audioInputDeviceId;
    if (savedId != null && savedId.isNotEmpty) {
      if (_nativeInput.isDeviceAvailable(savedId)) {
        AppLog.d('[AudioDeviceService] Preferred device still available, no action needed');
      } else {
        // Preferred device gone — clear config and C layer
        AppLog.d('[AudioDeviceService] Preferred device gone, clearing preference → system default');
        await ConfigService().setAudioInputDeviceId(null);
        if (_disposed) return;
        clearPreferredDevice();

        if (showSwitchNotifications) {
          NotificationService().notify(_loc.audioDeviceDisconnected);
        }
      }
    } else if (autoManageEnabled && isBluetooth) {
      // No preferred device — auto-manage Bluetooth if enabled
      _handleBluetoothDetected(deviceName);
    }

    // 订阅者收到事件后会立刻重读配置并更新 UI；必须放在状态处理之后，
    // 否则设备断开时 UI 可能先读到尚未清掉的旧偏好。
    if (_disposed || _deviceChangeController.isClosed) return;
    _deviceChangeController.add(AudioDeviceEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      isBluetooth: isBluetooth,
    ));
  }

  void _handleBluetoothDetected(String bluetoothDeviceName) {
    AppLog.d('[AudioDeviceService] Bluetooth mic detected as system default: $bluetoothDeviceName');

    if (showSwitchNotifications) {
      NotificationService().notifyWithAction(
        message: _loc.bluetoothMicDetected,
        actionLabel: _loc.switchToBuiltinMicAction,
        onAction: () {
          unawaited(_switchToBuiltinFromNotification());
        },
        type: NotificationType.audioDeviceSwitch,
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _switchToBuiltinFromNotification() async {
    if (!switchToBuiltinMic()) {
      NotificationService().notifyError(_loc.audioDeviceSwitchFailed);
      return;
    }

    final uid = getPreferredDeviceUid();
    if (uid.isEmpty) {
      NotificationService().notifyError(_loc.audioDeviceSwitchFailed);
      return;
    }

    try {
      await ConfigService().setAudioInputDeviceId(uid);
      if (_disposed) return;
      NotificationService().notify(_loc.switchedToBuiltinMic);
    } catch (e) {
      AppLog.d('[AudioDeviceService] Failed to persist built-in mic: $e');
      if (_disposed) return;
      clearPreferredDevice();
      NotificationService().notifyError(_loc.audioDeviceSwitchFailed);
    }
  }
  
  /// Refresh the list of available devices
  void refreshDevices() {
    final jsonStr = _nativeInput.getAudioInputDevices();
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      _devices = list.map((e) => AudioDevice.fromJson(e)).toList();
    } catch (e) {
      AppLog.d('[AudioDeviceService] Failed to parse devices: $e');
      _devices = [];
    }
    
    _refreshCurrentDevice();
  }

  void _refreshCurrentDevice() {
    _currentDevice = null;
    final currentJsonStr = _nativeInput.getCurrentInputDevice();
    try {
      final Map<String, dynamic> json = jsonDecode(currentJsonStr);
      if (json.isNotEmpty) {
        _currentDevice = AudioDevice.fromJson(json);
      }
    } catch (e) {
      AppLog.d('[AudioDeviceService] Failed to parse current device: $e');
    }
  }
  
  /// Get all available input devices
  List<AudioDevice> get devices {
    if (_devices.isEmpty) {
      refreshDevices();
    }
    return _devices;
  }
  
  /// Get the current input device
  AudioDevice? get currentDevice {
    if (_currentDevice == null) {
      _refreshCurrentDevice();
    }
    return _currentDevice;
  }
  
  /// Get the built-in microphone
  AudioDevice? get builtInMicrophone {
    final availableDevices = devices;
    return availableDevices.firstWhere(
      (d) => d.isBuiltIn,
      orElse: () => availableDevices.isNotEmpty ? availableDevices.first : AudioDevice(
        id: '', name: 'Unknown', isBluetooth: false, isBuiltIn: false, sampleRate: 0,
      ),
    );
  }
  
  /// Check if current input is a Bluetooth device
  bool get isCurrentInputBluetooth => _nativeInput.isCurrentInputBluetooth();
  
  /// Stream of device change events
  Stream<AudioDeviceEvent> get deviceChanges => _deviceChangeController.stream;
  
  /// Whether the user chose "System Default" (no preferred device)
  /// Uses ConfigService as single source of truth, not C layer.
  bool get isUsingSystemDefault {
    final savedId = ConfigService().audioInputDeviceId;
    return savedId == null || savedId.isEmpty;
  }

  /// Clear preferred device — follow system default
  void clearPreferredDevice() {
    _nativeInput.setPreferredDeviceUid('');
    AppLog.d('[AudioDeviceService] Cleared preferred device, following system default');
  }

  /// Set input device by UID
  bool setInputDevice(String deviceId) {
    final success = _nativeInput.setInputDevice(deviceId);
    if (success) {
      refreshDevices();
    }
    return success;
  }
  
  /// Switch to built-in microphone
  bool switchToBuiltinMic() {
    final success = _nativeInput.switchToBuiltinMic();
    if (success) {
      refreshDevices();
      AppLog.d('[AudioDeviceService] Switched to built-in mic');
    }
    return success;
  }
  
  /// Switch back to Bluetooth microphone (user chose to use it)
  bool switchToBluetoothMic() {
    final bluetoothDevice = devices.firstWhere(
      (d) => d.isBluetooth,
      orElse: () => AudioDevice(
        id: '', name: '', isBluetooth: false, isBuiltIn: false, sampleRate: 0,
      ),
    );
    
    if (bluetoothDevice.id.isEmpty) {
      AppLog.d('[AudioDeviceService] No Bluetooth device found');
      return false;
    }
    
    return setInputDevice(bluetoothDevice.id);
  }
  
  /// Get preferred high-quality device UID
  String getPreferredDeviceUid() => _nativeInput.getPreferredDeviceUid();
  
  /// Set preferred high-quality device UID
  void setPreferredDeviceUid(String uid) => _nativeInput.setPreferredDeviceUid(uid);
  
  /// Dispose the service
  void dispose() {
    if (_disposed) return;
    _disposed = true; // 先立旗，再拆 —— 拆的过程中来的回调也要挡住
    _nativeInput.stopDeviceChangeListener();

    // 可以安全 close()：native 侧的 stop_device_change_listener() 现在会持锁
    // 清空回调指针，若此刻有回调在途就阻塞到它跑完。函数返回即保证
    // 「没有回调在途，也不会再有新的」，此时释放 trampoline 不会 UAF。
    //
    // 之前两版都不对，记在这里免得有人改回去：
    //   v1 直接 close() —— native 把指针捕获进局部变量后还要做 4 次 CoreAudio
    //      查询才调用，而 AudioObjectRemovePropertyListener 不等在途回调，UAF。
    //   v2 不 close 只置 keepIsolateAlive=false —— 躲开了 UAF，但那是拿一种
    //      未定义行为换另一种（文档只对 close 后调用有明确说法），
    //      而且 listener 默认会把 isolate 钉住：实测默认 6 秒不退出被 kill，
    //      置 false 后 434ms 退出。躲问题不如把 native 那把锁补上。
    _deviceChangeCallable?.close();
    _deviceChangeCallable = null;

    _deviceChangeController.close();
    AppLog.d('[AudioDeviceService] Disposed');
  }
}
