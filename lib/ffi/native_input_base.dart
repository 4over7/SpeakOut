import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Typedefs matching C
typedef StartKeyboardListenerC = Int32 Function(Pointer<NativeFunction<KeyCallbackC>> callback);
typedef StartKeyboardListenerDart = int Function(Pointer<NativeFunction<KeyCallbackC>> callback);

typedef StopKeyboardListenerC = Void Function();
typedef StopKeyboardListenerDart = void Function();

typedef NativeAbiVersionC = Int32 Function();
typedef NativeAbiVersionDart = int Function();

typedef InjectTextC = Int32 Function(Pointer<Utf8> text);
typedef InjectTextDart = int Function(Pointer<Utf8> text);

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

typedef MicrophonePermissionStatusC = Int32 Function();
typedef MicrophonePermissionStatusDart = int Function();

typedef RequestMicrophonePermissionC = Void Function();
typedef RequestMicrophonePermissionDart = void Function();

typedef CheckScreenRecordingPermissionC = Int32 Function();
typedef CheckScreenRecordingPermissionDart = int Function();

typedef NativeFreeC = Void Function(Pointer<Void>);
typedef NativeFreeDart = void Function(Pointer<Void>);

typedef SaveRecordingWavC = Int32 Function(Pointer<Utf8> path);
typedef SaveRecordingWavDart = int Function(Pointer<Utf8> path);

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

// Auto-update: launch external script
typedef LaunchUpdaterC = Void Function(Pointer<Utf8> scriptPath);
typedef LaunchUpdaterDart = void Function(Pointer<Utf8> scriptPath);

// AI 梳理: copy selection (Cmd+C) and press key
typedef ClipboardRestoreFailuresC = Uint32 Function();
typedef ClipboardRestoreFailuresDart = int Function();

typedef CopySelectionTextC = Pointer<Utf8> Function();
typedef CopySelectionTextDart = Pointer<Utf8> Function();

typedef CopySelectionC = Int32 Function();
typedef CopySelectionDart = int Function();
typedef PressKeyC = Int32 Function(Int32 keyCode, Int32 modifierFlags);
typedef PressKeyDart = int Function(int keyCode, int modifierFlags);

// Clipboard streaming injection
typedef InjectClipboardBeginC = Int32 Function();
typedef InjectClipboardBeginDart = int Function();
typedef InjectClipboardChunkC = Int32 Function(Pointer<Utf8> text);
typedef InjectClipboardChunkDart = int Function(Pointer<Utf8> text);
typedef InjectClipboardEndC = Void Function();
typedef InjectClipboardEndDart = void Function();

// AI 报告: activate app + get frontmost app info
typedef ActivateAppC = Int32 Function(Pointer<Utf8> bundleId);
typedef ActivateAppDart = int Function(Pointer<Utf8> bundleId);
typedef GetFrontmostAppInfoC = Pointer<Utf8> Function();
typedef GetFrontmostAppInfoDart = Pointer<Utf8> Function();

abstract class NativeInputBase {
  bool startListener(Pointer<NativeFunction<KeyCallbackC>> callback);
  void stopListener();
  /// 返回是否真的把文字粘贴出去了。
  /// **false 必须让用户看见** —— 注入失败等于他刚口述的整段话没了，
  /// 静默吞掉的话他只会对着没变化的输入框发愣。
  bool inject(String text);
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

  /// 当前麦克风授权状态，取值对齐 `AVAuthorizationStatus`：
  /// 0=未决定 1=受限 2=已拒绝 3=已授权。**只查询，不弹窗、不阻塞。**
  int microphonePermissionStatus();

  /// 仅在「未决定」时弹系统授权框，立即返回。
  /// 结果不通过返回值给出 —— 调用方轮询 [microphonePermissionStatus]。
  void requestMicrophonePermission();

  bool checkScreenRecordingPermission();
  void nativeFree(Pointer<Void> ptr);
  int getAvailableAudioSamples();
  int readAudioBuffer(Pointer<Int16> outSamples, int maxSamples);
  bool saveRecordingWav(String path);

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

  // AI 梳理: copy selection and simulate keypress
  /// 返回剪贴板是否确实因为这次 Cmd+C 变了。
  /// **false 必须中止梳理** —— 否则会把剪贴板里的旧内容（可能完全无关、
  /// 甚至敏感）当成用户选中的文字发给 LLM。
  bool copySelection();

  /// 复制选中文字**并直接返回它**。失败返回 null。
  ///
  /// **不要退回「copySelection() + 自己读剪贴板」那两步写法** ——
  /// 中间有两个窗口会读到别的内容（native 观察到的 changeCount 变化未必来自
  /// 我们的 Cmd+C；返回后到 Dart 读取之间剪贴板还可能再变）。任一命中，
  /// 送进 LLM 的就是无关内容，甚至是用户剪贴板里的敏感信息。
  String? copySelectionText();

  /// 剪贴板还原**最终失败**的累计次数。
  /// 还原是注入之后 800ms 的异步任务，没法用返回值上报 ——
  /// 失败意味着用户的剪贴板被清空了，不让他知道是不可接受的。
  int clipboardRestoreFailures();
  /// 返回按键是否已投递。梳理靠它移动光标/换行，
  /// 失败却继续的话结果会插到错误位置、甚至覆盖用户原来的选区。
  bool pressKey(int keyCode, int modifierFlags);

  // Clipboard streaming injection (for typewriter effect)
  /// 返回会话是否真的开启了。false 时**不要**继续发 chunk：
  /// native 那边没有 hold 罩着，每个 chunk 都会变成孤儿各自收尾，
  /// 文字会在 chunk 之间被还原掉。
  bool injectClipboardBegin();
  /// 返回这段 chunk 是否真的粘贴出去了。
  /// 和 [inject] 同理：静默失败会让整段流式注入被当成成功。
  bool injectClipboardChunk(String text);
  void injectClipboardEnd();

  // Audio spectrum (7-band FFT for waveform visualization)
  void getAudioSpectrum(Pointer<Float> outBands, int count);

  // Audio level (RMS 0.0~1.0 for waveform amplitude)
  double getAudioLevel();

  // Check if frontmost app is a terminal emulator
  bool isTerminalApp();

  // Launch external updater script (for auto-update)
  void launchUpdater(String scriptPath);

  // AI 报告: activate app by bundle ID, get frontmost app info
  bool activateApp(String bundleId);
  String getFrontmostAppInfo();
}
