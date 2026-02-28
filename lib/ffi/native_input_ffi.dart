import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'native_input_base.dart';

/// 通用 FFI 绑定基类
///
/// macOS / Windows / Linux 的 NativeInput 实现都继承此类，
/// 只需提供各自平台的动态库路径即可复用全部 FFI 绑定代码。
class NativeInputFFI implements NativeInputBase {
  late final DynamicLibrary _dylib;

  // Core bindings (bound eagerly)
  late final StartKeyboardListenerDart _startListener;
  late final StopKeyboardListenerDart _stopListener;
  late final InjectTextDart _injectText;
  late final CheckPermissionDart _checkPermissionSilent;

  // Lazy-bound groups
  bool _permBound = false;
  late CheckInputMonitoringPermissionDart _checkInputMonitoringPerm;
  late CheckAccessibilityPermissionDart _checkAccessibilityPerm;

  bool _watchdogBound = false;
  late CheckKeyPressedDart _checkKeyPressed;

  bool _audioBound = false;
  late StartAudioRecordingDart _startAudioRecording;
  late StopAudioRecordingDart _stopAudioRecording;
  late IsAudioRecordingDart _isAudioRecording;
  late CheckMicrophonePermissionDart _checkMicPermission;
  late NativeFreeDart _nativeFree;
  late GetAvailableAudioSamplesDart _getAvailableAudioSamples;
  late ReadAudioBufferDart _readAudioBuffer;

  bool _deviceBound = false;
  late GetAudioInputDevicesDart _getAudioInputDevices;
  late GetCurrentInputDeviceDart _getCurrentInputDevice;
  late SetInputDeviceDart _setInputDevice;
  late SwitchToBuiltinMicDart _switchToBuiltinMic;
  late IsCurrentInputBluetoothDart _isCurrentInputBluetooth;
  late StartDeviceChangeListenerDart _startDeviceChangeListener;
  late StopDeviceChangeListenerDart _stopDeviceChangeListener;
  late GetPreferredDeviceUidDart _getPreferredDeviceUid;
  late SetPreferredDeviceUidDart _setPreferredDeviceUid;

  bool _qualityBound = false;
  late AnalyzeAudioQualityDart _analyzeAudioQuality;
  late IsLikelyTelephoneQualityDart _isLikelyTelephoneQuality;

  void _log(String msg) {
    debugPrint("[NativeInputFFI] $msg");
  }

  /// 子类调用此方法完成初始化，传入已打开的 DynamicLibrary
  void initWithLibrary(DynamicLibrary dylib) {
    _dylib = dylib;

    try {
      _startListener = _dylib
          .lookup<NativeFunction<StartKeyboardListenerC>>('start_keyboard_listener')
          .asFunction();

      _stopListener = _dylib
          .lookup<NativeFunction<StopKeyboardListenerC>>('stop_keyboard_listener')
          .asFunction();

      _injectText = _dylib
          .lookup<NativeFunction<InjectTextC>>('inject_text')
          .asFunction();

      _checkPermissionSilent = _dylib
          .lookup<NativeFunction<CheckPermissionC>>('check_permission_silent')
          .asFunction();

      _log("Core FFI bindings SUCCESS");
    } catch (e) {
      _log("Core FFI bindings FAILED: $e");
      rethrow;
    }
  }

  // ============ CORE ============

  @override
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback) {
    _log("Calling start_keyboard_listener...");
    final result = _startListener(callback);
    _log("start_keyboard_listener returned $result");
    return result == 1;
  }

  @override
  void stopListener() {
    _log("Calling stop_keyboard_listener...");
    _stopListener();
  }

  @override
  void inject(String text) {
    final ptr = text.toNativeUtf8();
    _injectText(ptr);
    calloc.free(ptr);
  }

  @override
  bool checkPermission() {
    _log("Calling check_permission_silent...");
    final result = _checkPermissionSilent();
    _log("check_permission_silent returned $result");
    return result;
  }

  // ============ PERMISSIONS ============

  void _bindPermFunctions() {
    if (_permBound) return;
    try {
      _checkInputMonitoringPerm = _dylib
          .lookup<NativeFunction<CheckInputMonitoringPermissionC>>('check_input_monitoring_permission')
          .asFunction();
      _checkAccessibilityPerm = _dylib
          .lookup<NativeFunction<CheckAccessibilityPermissionC>>('check_accessibility_permission')
          .asFunction();
      _permBound = true;
      _log("Permission FFI bindings SUCCESS");
    } catch (e) {
      _log("Permission FFI bindings FAILED: $e");
    }
  }

  @override
  bool checkInputMonitoringPermission() {
    _bindPermFunctions();
    if (!_permBound) return false;
    final result = _checkInputMonitoringPerm();
    return result == 1;
  }

  @override
  bool checkAccessibilityPermission() {
    _bindPermFunctions();
    if (!_permBound) return false;
    final result = _checkAccessibilityPerm();
    return result == 1;
  }

  // ============ KEY STATE ============

  @override
  bool isKeyPressed(int keyCode) {
    if (!_watchdogBound) {
      try {
        _checkKeyPressed = _dylib
            .lookup<NativeFunction<CheckKeyPressedC>>('check_key_pressed')
            .asFunction();
        _watchdogBound = true;
      } catch (e) {
        _log("FAILED to bind check_key_pressed: $e");
        return false;
      }
    }
    return _checkKeyPressed(keyCode) == 1;
  }

  // ============ AUDIO RECORDING ============

  void _bindAudioFunctions() {
    if (_audioBound) return;
    try {
      _startAudioRecording = _dylib
          .lookup<NativeFunction<StartAudioRecordingC>>('start_audio_recording')
          .asFunction();
      _stopAudioRecording = _dylib
          .lookup<NativeFunction<StopAudioRecordingC>>('stop_audio_recording')
          .asFunction();
      _isAudioRecording = _dylib
          .lookup<NativeFunction<IsAudioRecordingC>>('is_audio_recording')
          .asFunction();
      _checkMicPermission = _dylib
          .lookup<NativeFunction<CheckMicrophonePermissionC>>('check_microphone_permission')
          .asFunction();
      _nativeFree = _dylib
          .lookup<NativeFunction<NativeFreeC>>('native_free')
          .asFunction();
      _getAvailableAudioSamples = _dylib
          .lookup<NativeFunction<GetAvailableAudioSamplesC>>('get_available_audio_samples')
          .asFunction();
      _readAudioBuffer = _dylib
          .lookup<NativeFunction<ReadAudioBufferC>>('read_audio_buffer')
          .asFunction();
      _audioBound = true;
      _log("Audio FFI bindings SUCCESS");
    } catch (e) {
      _log("Audio FFI bindings FAILED: $e");
    }
  }

  @override
  bool startAudioRecording() {
    _bindAudioFunctions();
    if (!_audioBound) return false;
    _log("Calling start_audio_recording...");
    final result = _startAudioRecording();
    _log("start_audio_recording returned $result");
    return result == 1;
  }

  @override
  void stopAudioRecording() {
    _bindAudioFunctions();
    if (!_audioBound) return;
    _stopAudioRecording();
  }

  @override
  bool isAudioRecording() {
    _bindAudioFunctions();
    if (!_audioBound) return false;
    return _isAudioRecording() == 1;
  }

  @override
  bool checkMicrophonePermission() {
    _bindAudioFunctions();
    if (!_audioBound) return false;
    final result = _checkMicPermission();
    return result == 1;
  }

  @override
  void nativeFree(Pointer<Void> ptr) {
    _bindAudioFunctions();
    if (!_audioBound) return;
    _nativeFree(ptr);
  }

  @override
  int getAvailableAudioSamples() {
    _bindAudioFunctions();
    if (!_audioBound) return 0;
    return _getAvailableAudioSamples();
  }

  @override
  int readAudioBuffer(Pointer<Int16> outSamples, int maxSamples) {
    _bindAudioFunctions();
    if (!_audioBound) return 0;
    return _readAudioBuffer(outSamples, maxSamples);
  }

  // ============ AUDIO DEVICE MANAGEMENT ============

  void _bindDeviceFunctions() {
    if (_deviceBound) return;
    try {
      _getAudioInputDevices = _dylib
          .lookup<NativeFunction<GetAudioInputDevicesC>>('get_audio_input_devices')
          .asFunction();
      _getCurrentInputDevice = _dylib
          .lookup<NativeFunction<GetCurrentInputDeviceC>>('get_current_input_device')
          .asFunction();
      _setInputDevice = _dylib
          .lookup<NativeFunction<SetInputDeviceC>>('set_input_device')
          .asFunction();
      _switchToBuiltinMic = _dylib
          .lookup<NativeFunction<SwitchToBuiltinMicC>>('switch_to_builtin_mic')
          .asFunction();
      _isCurrentInputBluetooth = _dylib
          .lookup<NativeFunction<IsCurrentInputBluetoothC>>('is_current_input_bluetooth')
          .asFunction();
      _startDeviceChangeListener = _dylib
          .lookup<NativeFunction<StartDeviceChangeListenerC>>('start_device_change_listener')
          .asFunction();
      _stopDeviceChangeListener = _dylib
          .lookup<NativeFunction<StopDeviceChangeListenerC>>('stop_device_change_listener')
          .asFunction();
      _getPreferredDeviceUid = _dylib
          .lookup<NativeFunction<GetPreferredDeviceUidC>>('get_preferred_device_uid')
          .asFunction();
      _setPreferredDeviceUid = _dylib
          .lookup<NativeFunction<SetPreferredDeviceUidC>>('set_preferred_device_uid')
          .asFunction();
      _deviceBound = true;
      _log("Device FFI bindings SUCCESS");
    } catch (e) {
      _log("Device FFI bindings FAILED: $e");
    }
  }

  @override
  String getAudioInputDevices() {
    _bindDeviceFunctions();
    if (!_deviceBound) return '[]';
    final ptr = _getAudioInputDevices();
    if (ptr == nullptr) return '[]';
    return ptr.toDartString();
  }

  @override
  String getCurrentInputDevice() {
    _bindDeviceFunctions();
    if (!_deviceBound) return '{}';
    final ptr = _getCurrentInputDevice();
    if (ptr == nullptr) return '{}';
    return ptr.toDartString();
  }

  @override
  bool setInputDevice(String deviceUID) {
    _bindDeviceFunctions();
    if (!_deviceBound) return false;
    final ptr = deviceUID.toNativeUtf8();
    final result = _setInputDevice(ptr);
    calloc.free(ptr);
    return result == 1;
  }

  @override
  bool switchToBuiltinMic() {
    _bindDeviceFunctions();
    if (!_deviceBound) return false;
    final result = _switchToBuiltinMic();
    return result == 1;
  }

  @override
  bool isCurrentInputBluetooth() {
    _bindDeviceFunctions();
    if (!_deviceBound) return false;
    return _isCurrentInputBluetooth() == 1;
  }

  @override
  bool startDeviceChangeListener(Pointer<NativeFunction<DeviceChangeCallbackC>> callback) {
    _bindDeviceFunctions();
    if (!_deviceBound) return false;
    return _startDeviceChangeListener(callback) == 1;
  }

  @override
  void stopDeviceChangeListener() {
    _bindDeviceFunctions();
    if (!_deviceBound) return;
    _stopDeviceChangeListener();
  }

  @override
  String getPreferredDeviceUid() {
    _bindDeviceFunctions();
    if (!_deviceBound) return '';
    final ptr = _getPreferredDeviceUid();
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  @override
  void setPreferredDeviceUid(String uid) {
    _bindDeviceFunctions();
    if (!_deviceBound) return;
    final ptr = uid.toNativeUtf8();
    _setPreferredDeviceUid(ptr);
    calloc.free(ptr);
  }

  // ============ SIGNAL QUALITY ANALYSIS ============

  void _bindQualityFunctions() {
    if (_qualityBound) return;
    try {
      _analyzeAudioQuality = _dylib
          .lookup<NativeFunction<AnalyzeAudioQualityC>>('analyze_audio_quality')
          .asFunction();
      _isLikelyTelephoneQuality = _dylib
          .lookup<NativeFunction<IsLikelyTelephoneQualityC>>('is_likely_telephone_quality')
          .asFunction();
      _qualityBound = true;
      _log("Quality analysis FFI bindings SUCCESS");
    } catch (e) {
      _log("Quality analysis FFI bindings FAILED: $e");
    }
  }

  @override
  String analyzeAudioQuality(Pointer<Int16> samples, int sampleCount, int sampleRate) {
    _bindQualityFunctions();
    if (!_qualityBound) return '{"error":"not bound"}';
    final ptr = _analyzeAudioQuality(samples, sampleCount, sampleRate);
    if (ptr == nullptr) return '{}';
    return ptr.toDartString();
  }

  @override
  bool isLikelyTelephoneQuality() {
    _bindQualityFunctions();
    if (!_qualityBound) return false;
    return _isLikelyTelephoneQuality() == 1;
  }
}
