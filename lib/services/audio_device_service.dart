import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import '../ffi/native_input_base.dart';
import 'config_service.dart';
import 'notification_service.dart';
import 'package:speakout/config/app_log.dart';

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
  
  /// Initialize the service and start listening for device changes
  void initialize() {
    AppLog.d('[AudioDeviceService] Initializing...');
    
    // Enumerate devices first
    refreshDevices();
    
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
    
    AppLog.d('[AudioDeviceService] Device change listener started: $success');
  }
  
  /// Native callback when device changes
  static void _onDeviceChanged(
    Pointer<Utf8> deviceId,
    Pointer<Utf8> deviceName,
    int isBluetooth,
  ) {
    // This is called from native, we need to dispatch to the service instance
    // Using a static approach since callbacks are static
    _instance?._handleDeviceChange(
      deviceId.toDartString(),
      deviceName.toDartString(),
      isBluetooth == 1,
    );
  }
  
  // Singleton pattern for static callback access
  static AudioDeviceService? _instance;
  static void setInstance(AudioDeviceService service) {
    _instance = service;
  }
  
  void _handleDeviceChange(String deviceId, String deviceName, bool isBluetooth) {
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

    // Emit event immediately
    _deviceChangeController.add(AudioDeviceEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      isBluetooth: isBluetooth,
    ));

    // Check if our preferred device is still available
    final savedId = ConfigService().audioInputDeviceId;
    if (savedId != null && savedId.isNotEmpty) {
      if (_nativeInput.isDeviceAvailable(savedId)) {
        AppLog.d('[AudioDeviceService] Preferred device still available, no action needed');
        return;
      }
      // Preferred device gone — clear config and C layer
      AppLog.d('[AudioDeviceService] Preferred device gone, clearing preference → system default');
      ConfigService().setAudioInputDeviceId(null);
      clearPreferredDevice();

      if (showSwitchNotifications) {
        NotificationService().notify('音频设备已断开，已切换到系统默认');
      }
      return;
    }

    // No preferred device — auto-manage Bluetooth if enabled
    if (autoManageEnabled && isBluetooth) {
      _handleBluetoothDetected(deviceName);
    }
  }

  void _handleBluetoothDetected(String bluetoothDeviceName) {
    AppLog.d('[AudioDeviceService] Bluetooth mic detected as system default, suggesting built-in...');

    if (showSwitchNotifications) {
      NotificationService().notifyWithAction(
        message: '检测到蓝牙麦克风，建议使用内置麦克风以获得更好的转写效果',
        actionLabel: '切换到内置麦克风',
        onAction: () {
          switchToBuiltinMic();
          NotificationService().notify('已切换到内置麦克风');
        },
        type: NotificationType.audioDeviceSwitch,
        duration: const Duration(seconds: 6),
      );
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
    
    // Also refresh current device
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
      refreshDevices();
    }
    return _currentDevice;
  }
  
  /// Get the built-in microphone
  AudioDevice? get builtInMicrophone {
    return devices.firstWhere(
      (d) => d.isBuiltIn,
      orElse: () => devices.isNotEmpty ? devices.first : AudioDevice(
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
    refreshDevices();
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
