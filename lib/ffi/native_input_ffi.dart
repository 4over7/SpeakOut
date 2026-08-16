import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_input_base.dart';
import 'package:speakout/config/app_log.dart';

/// 通用 FFI 绑定基类
///
/// macOS / Windows / Linux 的 NativeInput 实现都继承此类，
/// 只需提供各自平台的动态库路径即可复用全部 FFI 绑定代码。
/// 与三个平台的 `SPEAKOUT_NATIVE_ABI_VERSION` 必须一致。
/// **它是导出签名指纹的前 6 位十六进制，不是手动递增的序号** ——
/// 手动递增靠自觉，而我漏过一次（改了 inject_clipboard_begin 的签名却没升，
/// 正好是这个握手要防的情形）。现在版本是签名的函数，只改一半不可能。
/// 数值由 test/engine/native_batch5_invariants_test.dart 的指纹锁给出。
const int kExpectedNativeAbiVersion = 0x7d0948;

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
  // 可选：macOS only。Windows/Linux dylib 尚未导出这两个 symbol
  MicrophonePermissionStatusDart? _micPermissionStatus;
  RequestMicrophonePermissionDart? _requestMicPermission;
  // 可选：macOS only。Windows/Linux dylib 可能不导出此 symbol
  CheckScreenRecordingPermissionDart? _checkScreenRecordingPermission;
  late NativeFreeDart _nativeFree;
  late GetAvailableAudioSamplesDart _getAvailableAudioSamples;
  late ReadAudioBufferDart _readAudioBuffer;
  late SaveRecordingWavDart _saveRecordingWav;

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
  late IsDeviceAvailableDart _isDeviceAvailable;

  bool _qualityBound = false;
  late AnalyzeAudioQualityDart _analyzeAudioQuality;
  late IsLikelyTelephoneQualityDart _isLikelyTelephoneQuality;

  late SetDebugLoggingDart _setDebugLogging;
  late SetLogDirectoryDart _setLogDirectory;

  void _log(String msg) {
    AppLog.d("[NativeInputFFI] $msg");
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

      _setDebugLogging = _dylib
          .lookup<NativeFunction<SetDebugLoggingC>>('set_debug_logging')
          .asFunction();
      _setLogDirectory = _dylib
          .lookup<NativeFunction<SetLogDirectoryC>>('set_log_directory')
          .asFunction();

      // ABI 握手：旧 dylib 没有这个 symbol，或版本对不上，都要**明确报错**。
      // 不校验的话，按 Int32 去调一个还是 void 的旧 inject_text 不会崩，
      // 只会读到返回寄存器里的垃圾 —— 「注入成功了吗」变成掷骰子。
      try {
        final abi = _dylib
            .lookup<NativeFunction<NativeAbiVersionC>>('native_input_abi_version')
            .asFunction<NativeAbiVersionDart>()();
        if (abi != kExpectedNativeAbiVersion) {
          throw StateError(
              'native dylib ABI $abi != expected $kExpectedNativeAbiVersion');
        }
        _log("Native ABI v$abi OK");
      } on ArgumentError catch (_) {
        throw StateError('native dylib 太旧：没有 native_input_abi_version '
            '(期望 ABI v$kExpectedNativeAbiVersion)');
      }

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
  bool inject(String text) {
    final ptr = text.toNativeUtf8();
    final ok = _injectText(ptr);
    calloc.free(ptr);
    return ok == 1;
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
      _saveRecordingWav = _dylib
          .lookup<NativeFunction<SaveRecordingWavC>>('save_recording_wav')
          .asFunction();
      _audioBound = true;
      _log("Audio FFI bindings SUCCESS");

      // 可选绑定（macOS only，Windows/Linux dylib 可能没有此 symbol）
      try {
        _checkScreenRecordingPermission = _dylib
            .lookup<NativeFunction<CheckScreenRecordingPermissionC>>('check_screen_recording_permission')
            .asFunction();
      } catch (_) {
        _checkScreenRecordingPermission = null;
      }
      try {
        _micPermissionStatus = _dylib
            .lookup<NativeFunction<MicrophonePermissionStatusC>>('microphone_permission_status')
            .asFunction();
        _requestMicPermission = _dylib
            .lookup<NativeFunction<RequestMicrophonePermissionC>>('request_microphone_permission')
            .asFunction();
      } catch (_) {
        _micPermissionStatus = null;
        _requestMicPermission = null;
      }
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
  int microphonePermissionStatus() {
    _bindAudioFunctions();
    if (!_audioBound) return 2; // 绑不上就当没权限，不要谎报已授权
    final fn = _micPermissionStatus;
    // 老 dylib 没导出细分状态：只能退化成「授权 / 已拒绝」两态
    if (fn == null) return checkMicrophonePermission() ? 3 : 2;
    return fn();
  }

  @override
  void requestMicrophonePermission() {
    _bindAudioFunctions();
    if (!_audioBound) return;
    _requestMicPermission?.call();
  }

  @override
  bool checkScreenRecordingPermission() {
    _bindAudioFunctions();
    final fn = _checkScreenRecordingPermission;
    if (fn == null) return true; // 非 macOS 平台：默认允许（该平台不需要此权限）
    return fn() == 1;
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

  @override
  bool saveRecordingWav(String path) {
    _bindAudioFunctions();
    if (!_audioBound) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _saveRecordingWav(pathPtr) == 1;
    } finally {
      calloc.free(pathPtr);
    }
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
      _isDeviceAvailable = _dylib
          .lookup<NativeFunction<IsDeviceAvailableC>>('is_device_available')
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

  @override
  bool isDeviceAvailable(String deviceUID) {
    _bindDeviceFunctions();
    if (!_deviceBound) return false;
    final ptr = deviceUID.toNativeUtf8();
    final result = _isDeviceAvailable(ptr);
    calloc.free(ptr);
    return result == 1;
  }

  @override
  void setDebugLogging(bool enabled) {
    _setDebugLogging(enabled ? 1 : 0);
  }

  @override
  void setLogDirectory(String dir) {
    final ptr = dir.toNativeUtf8();
    _setLogDirectory(ptr);
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

  // ============ AI ORGANIZE (copy_selection / press_key) ============

  bool _organizeBound = false;
  CopySelectionTextDart? _copySelectionText;
  ClipboardRestoreFailuresDart? _clipboardRestoreFailures;
  late CopySelectionDart _copySelection;
  late PressKeyDart _pressKey;

  void _bindOrganizeFunctions() {
    if (_organizeBound) return;
    try {
      _copySelection = _dylib
          .lookup<NativeFunction<CopySelectionC>>('copy_selection')
          .asFunction();
      _pressKey = _dylib
          .lookup<NativeFunction<PressKeyC>>('press_key')
          .asFunction();
      try {
        _copySelectionText = _dylib
            .lookup<NativeFunction<CopySelectionTextC>>('copy_selection_text')
            .asFunction();
        _clipboardRestoreFailures = _dylib
            .lookup<NativeFunction<ClipboardRestoreFailuresC>>(
                'clipboard_restore_failures')
            .asFunction();
      } catch (_) {
        _copySelectionText = null; // 老 dylib 没有；调用方会回退
        _clipboardRestoreFailures = null;
      }
      _organizeBound = true;
      _log("Organize FFI bindings SUCCESS");
    } catch (e) {
      _log("Organize FFI bindings FAILED: $e");
    }
  }

  @override
  int clipboardRestoreFailures() {
    _bindOrganizeFunctions();
    return _clipboardRestoreFailures?.call() ?? 0;
  }

  @override
  String? copySelectionText() {
    _bindOrganizeFunctions();
    if (!_organizeBound) return null;
    final fn = _copySelectionText;
    if (fn == null) return null;
    final ptr = fn();
    if (ptr == nullptr) return null;
    // try/finally：toDartString 抛异常（非法 UTF-8 等）时也要释放，
    // 否则每失败一次漏一块 native 内存。
    try {
      return ptr.toDartString();
    } finally {
      nativeFree(ptr.cast());
    }
  }

  @override
  bool copySelection() {
    _bindOrganizeFunctions();
    if (!_organizeBound) return false;
    return _copySelection() == 1;
  }

  @override
  bool pressKey(int keyCode, int modifierFlags) {
    _bindOrganizeFunctions();
    if (!_organizeBound) return false;
    return _pressKey(keyCode, modifierFlags) == 1;
  }

  // ============ CLIPBOARD STREAMING INJECTION ============

  bool _clipboardBound = false;
  late InjectClipboardBeginDart _injectClipboardBegin;
  late InjectClipboardChunkDart _injectClipboardChunk;
  late InjectClipboardEndDart _injectClipboardEnd;

  void _bindClipboardFunctions() {
    if (_clipboardBound) return;
    try {
      _injectClipboardBegin = _dylib
          .lookup<NativeFunction<InjectClipboardBeginC>>('inject_clipboard_begin')
          .asFunction();
      _injectClipboardChunk = _dylib
          .lookup<NativeFunction<InjectClipboardChunkC>>('inject_clipboard_chunk')
          .asFunction();
      _injectClipboardEnd = _dylib
          .lookup<NativeFunction<InjectClipboardEndC>>('inject_clipboard_end')
          .asFunction();
      _clipboardBound = true;
      _log("Clipboard streaming FFI bindings SUCCESS");
    } catch (e) {
      _log("Clipboard streaming FFI bindings FAILED: $e");
    }
  }

  @override
  bool injectClipboardBegin() {
    _bindClipboardFunctions();
    if (!_clipboardBound) return false;
    return _injectClipboardBegin() == 1;
  }

  @override
  bool injectClipboardChunk(String text) {
    _bindClipboardFunctions();
    // 绑不上就是没注入 —— 不能 return 出去让调用方以为成功
    if (!_clipboardBound) return false;
    final ptr = text.toNativeUtf8();
    final ok = _injectClipboardChunk(ptr);
    calloc.free(ptr);
    return ok == 1;
  }

  @override
  void injectClipboardEnd() {
    _bindClipboardFunctions();
    if (!_clipboardBound) return;
    _injectClipboardEnd();
  }

  // --- Audio Spectrum ---
  late GetAudioSpectrumDart _getAudioSpectrum;
  bool _spectrumBound = false;

  @override
  void getAudioSpectrum(Pointer<Float> outBands, int count) {
    if (!_spectrumBound) {
      try {
        _getAudioSpectrum = _dylib
            .lookup<NativeFunction<GetAudioSpectrumC>>('get_audio_spectrum')
            .asFunction();
        _spectrumBound = true;
      } catch (e) {
        _log("Spectrum FFI binding FAILED: $e");
        return;
      }
    }
    _getAudioSpectrum(outBands, count);
  }

  // --- Audio Level ---
  late GetAudioLevelDart _getAudioLevel;
  bool _audioLevelBound = false;

  @override
  double getAudioLevel() {
    if (!_audioLevelBound) {
      try {
        _getAudioLevel = _dylib
            .lookup<NativeFunction<GetAudioLevelC>>('get_audio_level')
            .asFunction();
        _audioLevelBound = true;
      } catch (e) {
        _log("AudioLevel FFI binding FAILED: $e");
        return 0.0;
      }
    }
    return _getAudioLevel();
  }

  // --- Terminal Detection ---
  late CheckIsTerminalAppDart _checkIsTerminalApp;
  bool _terminalCheckBound = false;

  @override
  bool isTerminalApp() {
    if (!_terminalCheckBound) {
      try {
        _checkIsTerminalApp = _dylib
            .lookup<NativeFunction<CheckIsTerminalAppC>>('check_is_terminal_app')
            .asFunction();
        _terminalCheckBound = true;
      } catch (e) {
        _log("TerminalCheck FFI binding FAILED: $e");
        return false;
      }
    }
    return _checkIsTerminalApp() == 1;
  }

  // --- AI Report ---
  bool _aiReportBound = false;
  late ActivateAppDart _activateApp;
  late GetFrontmostAppInfoDart _getFrontmostAppInfo;

  // --- Auto-Update ---
  late LaunchUpdaterDart _launchUpdater;
  bool _updaterBound = false;

  @override
  void launchUpdater(String scriptPath) {
    if (!_updaterBound) {
      try {
        _launchUpdater = _dylib
            .lookup<NativeFunction<LaunchUpdaterC>>('launch_updater')
            .asFunction();
        _updaterBound = true;
      } catch (e) {
        _log("LaunchUpdater FFI binding FAILED: $e");
        return;
      }
    }
    final ptr = scriptPath.toNativeUtf8();
    _launchUpdater(ptr);
    calloc.free(ptr);
  }

  // ============ AI REPORT ============

  void _bindAiReportFunctions() {
    if (_aiReportBound) return;
    try {
      _activateApp = _dylib
          .lookup<NativeFunction<ActivateAppC>>('activate_app')
          .asFunction();
      _getFrontmostAppInfo = _dylib
          .lookup<NativeFunction<GetFrontmostAppInfoC>>('get_frontmost_app_info')
          .asFunction();
      _aiReportBound = true;
      _log("AI Report FFI bindings SUCCESS");
    } catch (e) {
      _log("AI Report FFI bindings FAILED: $e");
    }
  }

  @override
  bool activateApp(String bundleId) {
    _bindAiReportFunctions();
    if (!_aiReportBound) return false;
    final ptr = bundleId.toNativeUtf8();
    final result = _activateApp(ptr);
    calloc.free(ptr);
    return result == 1;
  }

  @override
  String getFrontmostAppInfo() {
    _bindAiReportFunctions();
    if (!_aiReportBound) return '{}';
    final ptr = _getFrontmostAppInfo();
    if (ptr == nullptr) return '{}';
    final result = ptr.toDartString();
    // get_frontmost_app_info 返回 strdup(malloc) 内存，用配对的 native_free 释放（而非 ffi calloc.free）
    nativeFree(ptr.cast<Void>());
    return result;
  }
}
