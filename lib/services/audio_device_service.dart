import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../ffi/native_input.dart';
import '../ffi/native_input_base.dart';
import 'notification_service.dart';

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
  final NativeInput _nativeInput;
  
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
  
  // Last detected Bluetooth device name (for undo)
  String? _lastBluetoothDeviceName;
  
  AudioDeviceService(this._nativeInput);
  
  /// Initialize the service and start listening for device changes
  void initialize() {
    debugPrint('[AudioDeviceService] Initializing...');
    
    // Enumerate devices first
    refreshDevices();
    
    // Start listening for device changes
    _startListening();
    
    debugPrint('[AudioDeviceService] Initialized. Current device: $_currentDevice');
  }
  
  void _startListening() {
    // Create native callable for device change callback
    _deviceChangeCallable = NativeCallable<DeviceChangeCallbackC>.listener(
      _onDeviceChanged,
    );
    
    final success = _nativeInput.startDeviceChangeListener(
      _deviceChangeCallable!.nativeFunction,
    );
    
    debugPrint('[AudioDeviceService] Device change listener started: $success');
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
    debugPrint('[AudioDeviceService] Device changed: $deviceName (bluetooth=$isBluetooth)');
    
    // Refresh cached devices
    refreshDevices();
    
    // Emit event
    final event = AudioDeviceEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      isBluetooth: isBluetooth,
    );
    _deviceChangeController.add(event);
    
    // Auto-manage: switch away from Bluetooth mic if enabled
    if (autoManageEnabled && isBluetooth) {
      _handleBluetoothMicDetected(deviceName);
    }
  }
  
  void _handleBluetoothMicDetected(String bluetoothDeviceName) {
    debugPrint('[AudioDeviceService] Bluetooth mic detected, auto-switching to built-in...');
    
    _lastBluetoothDeviceName = bluetoothDeviceName;
    final success = switchToBuiltinMic();
    
    if (success && showSwitchNotifications) {
      NotificationService().notifyWithAction(
        message: '已自动切换到高质量麦克风，转写更准确',
        actionLabel: '仍用耳机麦',
        onAction: () {
          switchToBluetoothMic();
          NotificationService().notify('已切换回耳机麦克风');
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
      debugPrint('[AudioDeviceService] Failed to parse devices: $e');
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
      debugPrint('[AudioDeviceService] Failed to parse current device: $e');
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
      debugPrint('[AudioDeviceService] Switched to built-in mic');
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
      debugPrint('[AudioDeviceService] No Bluetooth device found');
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
    _nativeInput.stopDeviceChangeListener();
    _deviceChangeCallable?.close();
    _deviceChangeController.close();
    debugPrint('[AudioDeviceService] Disposed');
  }
}
