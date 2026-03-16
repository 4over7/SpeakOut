import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Typedefs matching C
typedef StartKeyboardListenerC = Int32 Function(Pointer<NativeFunction<KeyCallbackC>> callback);
typedef StartKeyboardListenerDart = int Function(Pointer<NativeFunction<KeyCallbackC>> callback);

typedef StopKeyboardListenerC = Void Function();
typedef StopKeyboardListenerDart = void Function();

typedef InjectTextC = Void Function(Pointer<Utf8> text);
typedef InjectTextDart = void Function(Pointer<Utf8> text);

typedef CheckPermissionC = Bool Function();
typedef CheckPermissionDart = bool Function();

// Callback type: void callback(int keyCode, bool isDown, uint modifierFlags)
typedef KeyCallbackC = Void Function(Int32 keyCode, Bool isDown, Uint32 modifierFlags);

typedef CheckKeyPressedC = Int32 Function(Int32 keyCode);
typedef CheckKeyPressedDart = int Function(int keyCode);

// Audio Recording FFI Types (Ring Buffer API - no Dart callback)
typedef StartAudioRecordingC = Int32 Function();
typedef StartAudioRecordingDart = int Function();

typedef StopAudioRecordingC = Void Function();
typedef StopAudioRecordingDart = void Function();

typedef IsAudioRecordingC = Int32 Function();
typedef IsAudioRecordingDart = int Function();

typedef CheckMicrophonePermissionC = Int32 Function();
typedef CheckMicrophonePermissionDart = int Function();

typedef NativeFreeC = Void Function(Pointer<Void>);
typedef NativeFreeDart = void Function(Pointer<Void>);

// Ring Buffer polling types
typedef GetAvailableAudioSamplesC = Int32 Function();
typedef GetAvailableAudioSamplesDart = int Function();

typedef ReadAudioBufferC = Int32 Function(Pointer<Int16> outSamples, Int32 maxSamples);
typedef ReadAudioBufferDart = int Function(Pointer<Int16> outSamples, int maxSamples);

// Audio Device Management FFI Types
typedef GetAudioInputDevicesC = Pointer<Utf8> Function();
typedef GetAudioInputDevicesDart = Pointer<Utf8> Function();

typedef GetCurrentInputDeviceC = Pointer<Utf8> Function();
typedef GetCurrentInputDeviceDart = Pointer<Utf8> Function();

typedef SetInputDeviceC = Int32 Function(Pointer<Utf8> deviceUID);
typedef SetInputDeviceDart = int Function(Pointer<Utf8> deviceUID);

typedef SwitchToBuiltinMicC = Int32 Function();
typedef SwitchToBuiltinMicDart = int Function();

typedef IsCurrentInputBluetoothC = Int32 Function();
typedef IsCurrentInputBluetoothDart = int Function();

// Device change callback: void callback(const char* deviceId, const char* deviceName, int isBluetooth)
typedef DeviceChangeCallbackC = Void Function(Pointer<Utf8> deviceId, Pointer<Utf8> deviceName, Int32 isBluetooth);
typedef DeviceChangeCallbackDart = void Function(Pointer<Utf8> deviceId, Pointer<Utf8> deviceName, int isBluetooth);

typedef StartDeviceChangeListenerC = Int32 Function(Pointer<NativeFunction<DeviceChangeCallbackC>> callback);
typedef StartDeviceChangeListenerDart = int Function(Pointer<NativeFunction<DeviceChangeCallbackC>> callback);

typedef StopDeviceChangeListenerC = Void Function();
typedef StopDeviceChangeListenerDart = void Function();

typedef GetPreferredDeviceUidC = Pointer<Utf8> Function();
typedef GetPreferredDeviceUidDart = Pointer<Utf8> Function();

typedef SetPreferredDeviceUidC = Void Function(Pointer<Utf8> uid);
typedef SetPreferredDeviceUidDart = void Function(Pointer<Utf8> uid);

typedef IsDeviceAvailableC = Int32 Function(Pointer<Utf8> deviceUID);
typedef IsDeviceAvailableDart = int Function(Pointer<Utf8> deviceUID);

// Signal Quality Analysis FFI Types
typedef AnalyzeAudioQualityC = Pointer<Utf8> Function(Pointer<Int16> samples, Int32 sampleCount, Int32 sampleRate);
typedef AnalyzeAudioQualityDart = Pointer<Utf8> Function(Pointer<Int16> samples, int sampleCount, int sampleRate);

typedef IsLikelyTelephoneQualityC = Int32 Function();
typedef IsLikelyTelephoneQualityDart = int Function();

// Permission check types (reuse Int32 → int pattern)
typedef CheckInputMonitoringPermissionC = Int32 Function();
typedef CheckInputMonitoringPermissionDart = int Function();

typedef CheckAccessibilityPermissionC = Int32 Function();
typedef CheckAccessibilityPermissionDart = int Function();

typedef SetDebugLoggingC = Void Function(Int32 enabled);
typedef SetDebugLoggingDart = void Function(int enabled);

typedef SetLogDirectoryC = Void Function(Pointer<Utf8> dir);
typedef SetLogDirectoryDart = void Function(Pointer<Utf8> dir);

// Audio spectrum for waveform visualization
typedef GetAudioSpectrumC = Void Function(Pointer<Float> outBands, Int32 count);
typedef GetAudioSpectrumDart = void Function(Pointer<Float> outBands, int count);

// Audio level (RMS) for waveform visualization
typedef GetAudioLevelC = Float Function();
typedef GetAudioLevelDart = double Function();

// Terminal detection
typedef CheckIsTerminalAppC = Int32 Function();
typedef CheckIsTerminalAppDart = int Function();

// Clipboard streaming injection
typedef InjectClipboardBeginC = Void Function();
typedef InjectClipboardBeginDart = void Function();
typedef InjectClipboardChunkC = Void Function(Pointer<Utf8> text);
typedef InjectClipboardChunkDart = void Function(Pointer<Utf8> text);
typedef InjectClipboardEndC = Void Function();
typedef InjectClipboardEndDart = void Function();

abstract class NativeInputBase {
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback);
  void stopListener();
  void inject(String text);
  bool checkPermission();
  bool isKeyPressed(int keyCode);

  // Granular permission checks (macOS 10.15+)
  bool checkInputMonitoringPermission();
  bool checkAccessibilityPermission();
  
  // Audio Recording (Ring Buffer API)
  bool startAudioRecording();
  void stopAudioRecording();
  bool isAudioRecording();
  bool checkMicrophonePermission();
  void nativeFree(Pointer<Void> ptr);
  int getAvailableAudioSamples();
  int readAudioBuffer(Pointer<Int16> outSamples, int maxSamples);
  
  // Audio Device Management
  String getAudioInputDevices();
  String getCurrentInputDevice();
  bool setInputDevice(String deviceUID);
  bool switchToBuiltinMic();
  bool isCurrentInputBluetooth();
  bool startDeviceChangeListener(Pointer<NativeFunction<DeviceChangeCallbackC>> callback);
  void stopDeviceChangeListener();
  String getPreferredDeviceUid();
  void setPreferredDeviceUid(String uid);
  bool isDeviceAvailable(String deviceUID);
  void setDebugLogging(bool enabled);
  void setLogDirectory(String dir);
  
  // Signal Quality Analysis
  String analyzeAudioQuality(Pointer<Int16> samples, int sampleCount, int sampleRate);
  bool isLikelyTelephoneQuality();

  // Clipboard streaming injection (for typewriter effect)
  void injectClipboardBegin();
  void injectClipboardChunk(String text);
  void injectClipboardEnd();

  // Audio spectrum (7-band FFT for waveform visualization)
  void getAudioSpectrum(Pointer<Float> outBands, int count);

  // Audio level (RMS 0.0~1.0 for waveform amplitude)
  double getAudioLevel();

  // Check if frontmost app is a terminal emulator
  bool isTerminalApp();
}
