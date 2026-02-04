import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'native_input_base.dart';

class NativeInput implements NativeInputBase {
  late DynamicLibrary _dylib;

  late StartKeyboardListenerDart _startListener;
  late StopKeyboardListenerDart _stopListener;
  late InjectTextDart _injectText;
  late CheckPermissionDart _checkPermission;
  late CheckPermissionDart _checkPermissionSilent;

  // Debug Logger
  void _log(String msg) {
    debugPrint("[NativeInput] $msg");
  }

  NativeInput() {
    _log("Initializing NativeInput...");
    
    // Correct Path Resolution for App Bundle vs Debug
    var path = 'native_lib/libnative_input.dylib';
    
    // Check if we are in an App Bundle (Contents/MacOS/SpeakOut)
    final exeDir = File(Platform.resolvedExecutable).parent;
    _log("ExeDir: ${exeDir.path}");
    
    // Path 1: Contents/MacOS/native_lib (old location, manual script)
    final bundleLibPath = '${exeDir.path}/native_lib/libnative_input.dylib';
    _log("Checking Bundle Path: $bundleLibPath");
    
    // Path 2: flutter_assets inside App.framework (Release build location)
    final appDir = exeDir.parent; // Contents/
    final flutterAssetsPath = '${appDir.path}/Frameworks/App.framework/Versions/A/Resources/flutter_assets/native_lib/libnative_input.dylib';
    _log("Checking flutter_assets Path: $flutterAssetsPath");
    
    // Normalize path to verify
    try {
      if (File(bundleLibPath).existsSync()) {
        path = bundleLibPath;
        _log("Found in Bundle MacOS: $path");
      } else if (File(flutterAssetsPath).existsSync()) {
        path = flutterAssetsPath;
        _log("Found in flutter_assets: $path");
      } else if (!File(path).existsSync()) {
         // Fallback for terminal 'dart run' from root
         path = '${Directory.current.path}/native_lib/libnative_input.dylib';
         _log("Fallback to CWD: $path");
      }
    } catch (e) {
       _log("Path Verify Error: $e");
    }
    
    // Safety check
    if (!File(path).existsSync()) {
       _log("CRITICAL: File Not Found at $path");
    }

    try {
       _dylib = DynamicLibrary.open(path);
       _log("DynamicLibrary.open($path) SUCCESS");
    } catch (e) {
       _log("DynamicLibrary.open FAILED: $e");
       rethrow;
    }

    try {
      _startListener = _dylib
          .lookup<NativeFunction<StartKeyboardListenerC>>('start_keyboard_listener')
          .asFunction();
      _log("Lookup start_keyboard_listener SUCCESS");

      _stopListener = _dylib
          .lookup<NativeFunction<StopKeyboardListenerC>>('stop_keyboard_listener')
          .asFunction();

      _injectText = _dylib
          .lookup<NativeFunction<InjectTextC>>('inject_text')
          .asFunction();

      _checkPermission = _dylib
          .lookup<NativeFunction<CheckPermissionC>>('check_permission')
          .asFunction();

      _checkPermissionSilent = _dylib
          .lookup<NativeFunction<CheckPermissionC>>('check_permission_silent')
          .asFunction();
          
    } catch (e) {
      _log("Symbol Lookup FAILED: $e");
      rethrow;
    }
  }

  @override
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback) {
    _log("Dart: Calling start_keyboard_listener...");
    final result = _startListener(callback);
    _log("Dart: start_keyboard_listener returned $result");
    return result == 1;
  }

  @override
  void stopListener() {
    _log("Dart: Calling stop_keyboard_listener...");
    _stopListener();
  }

  @override
  void inject(String text) {
    // _log("Dart: Injecting text...");
    final ptr = text.toNativeUtf8();
    _injectText(ptr);
    calloc.free(ptr);
  }

  @override
  bool checkPermission() {
    // Use silent check (no prompt) - for refreshing status
    _log("Dart: Calling check_permission_silent...");
    final result = _checkPermissionSilent();
    _log("Dart: check_permission_silent returned $result");
    return result;  // result is already bool, not int!
  }

  // New Watchdog binding
  late CheckKeyPressedDart _checkKeyPressed;
  bool _watchdogBound = false;

  @override
  bool isKeyPressed(int keyCode) {
    if (!_watchdogBound) {
       try {
         _checkKeyPressed = _dylib.lookup<NativeFunction<CheckKeyPressedC>>('check_key_pressed').asFunction();
         _watchdogBound = true;
       } catch (e) {
         _log("FAILED to bind check_key_pressed: $e");
         return false;
       }
    }
    return _checkKeyPressed(keyCode) == 1;
  }
  
  // ============ AUDIO RECORDING ============
  late StartAudioRecordingDart _startAudioRecording;
  late StopAudioRecordingDart _stopAudioRecording;
  late IsAudioRecordingDart _isAudioRecording;
  late CheckMicrophonePermissionDart _checkMicPermission;
  late NativeFreeDart _nativeFree;
  bool _audioBound = false;
  
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
      _audioBound = true;
      _log("Audio FFI bindings SUCCESS");
    } catch (e) {
      _log("Audio FFI bindings FAILED: $e");
    }
  }
  
  @override
  bool startAudioRecording(Pointer<NativeFunction<AudioCallbackC>> callback) {
    _bindAudioFunctions();
    if (!_audioBound) return false;
    _log("Dart: Calling start_audio_recording...");
    final result = _startAudioRecording(callback);
    _log("Dart: start_audio_recording returned $result");
    return result == 1;
  }
  
  @override
  void stopAudioRecording() {
    _bindAudioFunctions();
    if (!_audioBound) return;
    _log("Dart: Calling stop_audio_recording...");
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
    _log("Dart: Calling check_microphone_permission...");
    final result = _checkMicPermission();
    _log("Dart: check_microphone_permission returned $result");
    return result == 1;
  }

  @override
  void nativeFree(Pointer<Void> ptr) {
    _bindAudioFunctions();
    if (!_audioBound) return;
    _nativeFree(ptr);
  }
  
  // ============ AUDIO DEVICE MANAGEMENT ============
  late GetAudioInputDevicesDart _getAudioInputDevices;
  late GetCurrentInputDeviceDart _getCurrentInputDevice;
  late SetInputDeviceDart _setInputDevice;
  late SwitchToBuiltinMicDart _switchToBuiltinMic;
  late IsCurrentInputBluetoothDart _isCurrentInputBluetooth;
  late StartDeviceChangeListenerDart _startDeviceChangeListener;
  late StopDeviceChangeListenerDart _stopDeviceChangeListener;
  late GetPreferredDeviceUidDart _getPreferredDeviceUid;
  late SetPreferredDeviceUidDart _setPreferredDeviceUid;
  bool _deviceBound = false;
  
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
    _log("Dart: Calling switch_to_builtin_mic...");
    final result = _switchToBuiltinMic();
    _log("Dart: switch_to_builtin_mic returned $result");
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
    _log("Dart: Starting device change listener...");
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
  late AnalyzeAudioQualityDart _analyzeAudioQuality;
  late IsLikelyTelephoneQualityDart _isLikelyTelephoneQuality;
  bool _qualityBound = false;
  
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
