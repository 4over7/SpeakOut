import 'dart:async';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../ffi/native_input_base.dart';
import '../ffi/native_input_factory.dart';
import '../config/app_constants.dart';
import '../services/billing_service.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/vocab_service.dart';
import '../services/notification_service.dart';
import 'asr_provider.dart';
import 'asr_result.dart';
import 'providers/sherpa_provider.dart';
import 'providers/offline_sherpa_provider.dart';
import 'providers/aliyun_provider.dart';
import 'providers/asr_provider_factory.dart';
import '../config/cloud_providers.dart';
import '../services/cloud_account_service.dart';
import '../services/diary_service.dart';
import '../services/chat_service.dart';
import '../services/audio_device_service.dart';
import '../services/overlay_controller.dart';
import 'package:speakout/config/app_log.dart';

/// Recording pipeline state machine
enum RecordingState { idle, starting, recording, stopping, processing }

/// Recording mode: PTT (push-to-talk) or diary (flash note)
enum RecordingMode { ptt, diary }

class CoreEngine {
  static final CoreEngine _instance = CoreEngine._internal();
  
  // Simple singleton
  factory CoreEngine() => _instance;

  // Dependencies - Native Audio via FFI (Ring Buffer + Polling)
  late final NativeInputBase? _nativeInput;
  Timer? _audioPollTimer;
  ffi.Pointer<ffi.Int16>? _pollBuffer;  // Reusable buffer for polling
  static const int _pollBufferSamples = AppConstants.kAudioPollBufferSamples;
  
  // Audio Device Management
  AudioDeviceService? _audioDeviceService;
  AudioDeviceService? get audioDeviceService => _audioDeviceService;
  
  CoreEngine._internal() {
    try {
      _nativeInput = createNativeInput();
      // Initialize AudioDeviceService
      _audioDeviceService = AudioDeviceService(_nativeInput!);
      AudioDeviceService.setInstance(_audioDeviceService!);
    } catch (e) {
      AppLog.d("[CoreEngine] Warning: Failed to init NativeInput: $e");
      _nativeInput = null;
    }
  }
  
  // ASR Provider abstraction
  ASRProvider? _asrProvider;
  bool _isOfflineASR = false;
  bool _activeModelHasPunctuation = false;
  
  Timer? _watchdogTimer; // Safety mechanism
  Timer? _silenceCheckTimer;
  int _silencePollCount = 0;
  DateTime? _lastSilenceNotify;

  // Recording state machine (replaces _isRecording, _isStopping, _audioStarted, _isDiaryMode)
  RecordingState _recordingState = RecordingState.idle;
  RecordingMode _recordingMode = RecordingMode.ptt;
  bool _audioStarted = false; // hardware-level flag: native audio is running

  // Keep Offline Punctuation & Debugging related fields
  sherpa.OfflinePunctuation? _punctuation;
  bool _punctuationEnabled = false;
  bool _typewriterInjected = false;
  DateTime? _recordingStartTime;
  bool _isOrganizing = false;
  /// 最近一次 ASR 原文（供 UI 做对比展示）
  String? lastAsrOriginal;
  /// 最近一次 LLM 润色是否成功（null=未调用，true=成功，false=失败）
  bool? lastLlmSuccess;

  // Configuration
  int pttKeyCode = 58; 
  
  // Streams
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  
  // Public helper for AppService
  void updateStatus(String msg) {
    _statusController.add(msg);
  }

  
  final _recordingController = StreamController<bool>.broadcast();
  Stream<bool> get recordingStream => _recordingController.stream;
  
  final _rawKeyController = StreamController<(int keyCode, int modifierFlags)>.broadcast();
  Stream<(int keyCode, int modifierFlags)> get rawKeyEventStream => _rawKeyController.stream;

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;
  
  // NEW: Persistent Partial Stream Controller
  // This acts as a hub. UI listens to this ONCE.
  // We forward data from whichever _asrProvider is currently active into this controller.
  final _partialTextController = StreamController<String>.broadcast();
  Stream<String> get partialTextStream => _partialTextController.stream;
  
  // Subscription to the current provider's stream
  StreamSubscription<String>? _asrSubscription;
  
  bool get isRecording => _recordingState == RecordingState.recording || _recordingState == RecordingState.starting;
  
  /// Check if ASR provider is ready (model loaded)
  bool get isASRReady => _asrProvider != null && _asrProvider!.isReady;


  final _overlay = OverlayController();

  void _log(String msg) => AppLog.d('[CoreEngine] $msg');

  /// Release all resources. Call when app is shutting down.
  void dispose() {
    _statusController.close();
    _recordingController.close();
    _rawKeyController.close();
    _resultController.close();
    _partialTextController.close();
    _asrSubscription?.cancel();
    _nativeCallable?.close();
    _watchdogTimer?.cancel();
    _toggleMaxTimer?.cancel();
    _stopAudioPolling();
    if (_pollBuffer != null) {
      pkg_ffi.calloc.free(_pollBuffer!);
      _pollBuffer = null;
    }
    _asrProvider?.dispose();
  }


  // Device Listing - Using native permission check
  Future<bool> listInputDevices() async {
    // Native audio doesn't need device listing - uses system default
    return _nativeInput?.checkMicrophonePermission() ?? false;
  }

  /// Check if NativeInput (native library) loaded successfully
  bool get isNativeInputReady => _nativeInput != null;

  /// Expose native input for debug logging control
  NativeInputBase? get nativeInput => _nativeInput;

  /// Check if input monitoring permission is granted (for keyboard listener)
  bool checkInputMonitoringPermission() {
    if (_nativeInput == null) {
      _log("checkInputMonitoringPermission: _nativeInput is NULL!");
      return false;
    }
    final result = _nativeInput.checkInputMonitoringPermission();
    _log("checkInputMonitoringPermission: $result");
    return result;
  }

  /// Check if accessibility permission is granted (for text injection)
  bool checkAccessibilityPermission() {
    if (_nativeInput == null) {
      _log("checkAccessibilityPermission: _nativeInput is NULL!");
      return false;
    }
    final result = _nativeInput.checkAccessibilityPermission();
    _log("checkAccessibilityPermission: $result");
    return result;
  }

  /// Check if microphone permission is granted (for audio recording)
  bool checkMicPermission() {
    return _nativeInput?.checkMicrophonePermission() ?? false;
  }

  bool _isListenerRunning = false;
  bool get isListenerRunning => _isListenerRunning;

  Future<void> init() async {
    _log("Init started. _isListenerRunning: $_isListenerRunning");
    // Only skip if keyboard listener is already running (not just ASR init)
    if (_isListenerRunning) {
      _log("Listener already running, skipping init.");
      return;
    }

    // 1. Check Native Perms
    _log("Checking permissions...");
    bool trusted = _nativeInput?.checkPermission() ?? false;
    _statusController.add("Accessibility Trusted: $trusted");
    if (!trusted) {
      _statusController.add("Error: Please grant Accessibility permissions in System Settings.");
    }
    
    // Warm up Audio Config
    await refreshInputDevice();
    
    // 2.5 Initialize Audio Device Service (Bluetooth detection)
    _audioDeviceService?.initialize();
    _log("Audio device service initialized. Auto-manage: ${_audioDeviceService?.autoManageEnabled}");

    // Restore user's preferred device from config
    final savedDeviceId = ConfigService().audioInputDeviceId;
    if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
      _log("Restoring preferred audio device: $savedDeviceId");
      if (_audioDeviceService != null && _nativeInput != null && _nativeInput.isDeviceAvailable(savedDeviceId)) {
        // Only set preferredDeviceUID in C layer — AudioQueue will use it at recording time
        _nativeInput.setPreferredDeviceUid(savedDeviceId);
        _log("Preferred device set: $savedDeviceId");
      } else {
        _log("Saved device '$savedDeviceId' not available, clearing preference → system default");
        await ConfigService().setAudioInputDeviceId(null);
        _audioDeviceService?.clearPreferredDevice();
      }
    }

    // Bluetooth auto-manage: only when user hasn't manually selected a device
    if (savedDeviceId == null && _audioDeviceService?.isCurrentInputBluetooth == true) {
      _log("Warning: Bluetooth mic detected as system default (no user preference). Notifying user.");
      // Don't force-switch — just log. The auto-manage handler in AudioDeviceService
      // will show a notification if a BT device becomes default during usage.
    }

    // 2. Init Native Listener
    _log("Setting up NativeCallable...");
    try {
      _nativeCallable = ffi.NativeCallable<KeyCallbackC>.listener(_onKeyStatic);
      _log("NativeCallable created. Calling startListener...");
      final hasNativeInput = _nativeInput != null;
      _log("_nativeInput is null: ${!hasNativeInput}");
      if (hasNativeInput) {
        final started = _nativeInput.startListener(_nativeCallable!.nativeFunction);
        _log("startListener returned: $started");
        if (started) {
          _isListenerRunning = true;
          _statusController.add("Keyboard Listener Started.");
          _log("Listener start success.");
          if (_nativeInput.checkPermission()) _statusController.add("Accessibility Trusted: true");
        } else {
           _statusController.add("Failed to start Keyboard Listener.");
           _log("Listener start FAILED.");
           _isListenerRunning = false;
        }
      } else {
        _log("Cannot start listener - _nativeInput is null");
        _isListenerRunning = false;
      }
    } catch (e, stack) {
       _log("Listener Exception: $e\n$stack");
       _isListenerRunning = false;
       rethrow; // Let AppService handle it
    }


    _log("Init complete.");
  }
  
  ffi.NativeCallable<KeyCallbackC>? _nativeCallable;
  
  // Native audio doesn't need device caching - uses system default
  // Keeping this stub for API compatibility
  Future<void> refreshInputDevice() async {
    _log("Native audio uses system default microphone");
  }

  // Switch Provider Logic
  Future<void> initASR(String modelPath, {String modelType = 'zipformer', String modelName = 'Local Model', bool hasPunctuation = false}) async {
    // Determine provider type
    final type = ConfigService().asrEngineType;
    ASRProvider provider;
    
    // Dispose previous if any
    if (_asrProvider != null) {
      // Cancel previous subscription to avoid memory leaks or dead stream listening
      await _asrSubscription?.cancel();
      _asrSubscription = null;
      
      await _asrProvider!.dispose();
      _asrProvider = null;
    }
    
    Map<String, dynamic> config = {};
    
    // Check if this is an offline model type
    final isOfflineModel = modelType == 'sense_voice' || modelType == 'offline_paraformer' || modelType == 'whisper' || modelType == 'fire_red_asr' || modelType == 'funasr_nano' || modelType == 'fire_red_asr_ctc' || modelType == 'moonshine' || modelType == 'telespeech_ctc' || modelType == 'dolphin';

    // Cloud Account path: use unified account system
    final accountId = ConfigService().selectedAsrAccountId;
    final asrModelId = ConfigService().selectedAsrModelId;
    if (type == 'aliyun' && accountId != null) {
      final account = CloudAccountService().getAccountById(accountId);
      final cloudProvider = account != null ? CloudProviders.getById(account.providerId) : null;
      if (account != null && cloudProvider != null && cloudProvider.asrModels.isNotEmpty) {
        // effectiveModel: 优先用已选模型，否则回退到第一个可用模型
        final asrModel = (asrModelId != null
            ? cloudProvider.asrModels.where((m) => m.id == asrModelId).firstOrNull
            : null) ?? cloudProvider.asrModels.first;
        provider = ASRProviderFactory.create(account.providerId);
        config = ASRProviderFactory.buildConfig(account, asrModel);
        _isOfflineASR = !asrModel.isStreaming;
        _log("Initializing ${cloudProvider.name} ASR (model=${asrModel.name})...");
        _statusController.add("☁️ 连接 ${cloudProvider.name}...");
        // Skip legacy path
        try {
          await provider.initialize(config);
          _asrProvider = provider;
          _asrSubscription = provider.textStream.listen((text) {
            if (!_partialTextController.isClosed) _partialTextController.add(text);
            if (_recordingState == RecordingState.recording && text.isNotEmpty) {
              _overlay.updateText(text);
            }
          });
          _activeModelHasPunctuation = true; // Cloud ASR has built-in punctuation
          _overlay.isOfflineMode = _isOfflineASR;
          _statusController.add("✅ ${cloudProvider.name} 就绪");
          _log("ASR Provider initialized: ${provider.type}");
        } catch (e) {
          _log("Cloud ASR Init Failed: $e");
          _statusController.add("❌ ${cloudProvider.name} 连接失败: $e");
          _asrProvider = null;
        }
        return;
      }
    }

    // Legacy Aliyun NLS path
    if (type == 'aliyun') {
      provider = AliyunProvider();
      config = {
        'accessKeyId': ConfigService().aliyunAccessKeyId,
        'accessKeySecret': ConfigService().aliyunAccessKeySecret,
        'appKey': ConfigService().aliyunAppKey,
      };
      _log("Initializing Aliyun Provider (legacy)...");
      _statusController.add("☁️ 连接阿里云 (Connecting)...");
    } else if (isOfflineModel) {
      // Offline Sherpa (non-streaming, batch recognition)
      provider = OfflineSherpaProvider();
      config = {
        'modelPath': modelPath,
        'modelType': modelType,
      };
      _log("Initializing Offline Sherpa Provider...");
      _statusController.add("⏳ 加载模型: $modelName...");
    } else {
      // Default: Sherpa Local (streaming)
      provider = SherpaProvider();
      config = {
        'modelPath': modelPath,
        'modelType': modelType,
      };
      _log("Initializing Sherpa Provider (Local)...");
      _statusController.add("⏳ 加载模型: $modelName...");
    }

    try {
      await provider.initialize(config);
      _asrProvider = provider;
      
      // Forward provider's partial text to persistent hub + overlay
      _asrSubscription = provider.textStream.listen((text) {
         if (!_partialTextController.isClosed) {
            _partialTextController.add(text);
         }
         // Update overlay with partial text (single source of truth)
         // Offline providers only emit on stop(), so this still works
         if (_recordingState == RecordingState.recording && text.isNotEmpty) {
            _overlay.updateText(text);
         }
      });

      _isOfflineASR = provider is OfflineSherpaProvider;
      _activeModelHasPunctuation = hasPunctuation;
      _overlay.isOfflineMode = _isOfflineASR;
      
  
      
      if (type == 'aliyun') {
         _statusController.add("✅ 阿里云就绪 (Aliyun Ready)");
      } else {
         _statusController.add("✅ 就绪: $modelName");
      }
      
      _log("ASR Provider initialized: ${provider.type}");
    } catch (e) {
      _log("Provider Init Failed: $e");
      if (type == 'aliyun') {
         _statusController.add("❌ 阿里云连接失败: $e");
      } else {
         _statusController.add("❌ 模型加载失败: $modelName ($e)");
      }
      _log("ASR Init Failed: $e");
      _asrProvider = null;
    }
  }

  Future<void> initPunctuation(String modelPath, {String activeModelName = ''}) async {
    try {
      String finalPath = modelPath;
      if (await Directory(modelPath).exists()) {
        final candidate = "$modelPath/model.onnx";
        if (await File(candidate).exists()) {
          finalPath = candidate;
        } else {
           final f = Directory(modelPath).listSync().firstWhere((e) => e.path.endsWith('.onnx'), orElse: () => File(""));
           if (f.path.isNotEmpty) finalPath = f.path;
        }
      }
      
      if (!await File(finalPath).exists()) throw "Model file not found";

      final config = sherpa.OfflinePunctuationConfig(
        model: sherpa.OfflinePunctuationModelConfig(ctTransformer: finalPath, numThreads: 2, debug: false),
      );
      _punctuation = sherpa.OfflinePunctuation(config: config);
      _punctuationEnabled = true;
      
      if (activeModelName.isNotEmpty) {
        _statusController.add("✅ 就绪: $activeModelName + 标点");
      } else {
        _statusController.add("✅ 就绪: 标点模型已加载");
      }
    } catch (e) {
      _punctuationEnabled = false;
      _log("[initPunctuation] Failed: $e");
      _statusController.add("❌ 标点加载失败: $e");
    }
  }
  
  String addPunctuation(String text) {
    if (!_punctuationEnabled || _punctuation == null || text.isEmpty) return text;
    try {
      return _punctuation!.addPunct(text);
    } catch (e) { return text; }
  }
  
  bool get isPunctuationEnabled => _punctuationEnabled;


  // Key Handling
  static void _onKeyStatic(int keyCode, bool isDown, int modifierFlags) {
    CoreEngine()._handleKey(keyCode, isDown, modifierFlags);
  }

  // Modifier flag constants (device-specific, from IOLLEvent.h)
  static const int kModLAlt = 0x0020;
  static const int kModRAlt = 0x0040;
  static const int kModLShift = 0x0002;
  static const int kModRShift = 0x0004;
  static const int kModLCmd = 0x0008;
  static const int kModRCmd = 0x0010;
  static const int kModLCtrl = 0x0001;
  static const int kModRCtrl = 0x2000;

  /// Mask for the trigger key itself (should be stripped before comparing required modifiers)
  static int _ownModifierMask(int keyCode) {
    switch (keyCode) {
      case 58: return kModLAlt;
      case 61: return kModRAlt;
      case 56: return kModLShift;
      case 60: return kModRShift;
      case 55: return kModLCmd;
      case 54: return kModRCmd;
      case 59: return kModLCtrl;
      case 62: return kModRCtrl;
      default: return 0;
    }
  }

  /// Check if the current modifier flags satisfy the required combo modifiers.
  /// Strips the trigger key's own modifier bit before comparison.
  bool _modifiersMatch(int keyCode, int currentFlags, int requiredFlags) {
    if (requiredFlags == 0) return true; // No combo required
    final stripped = currentFlags & ~_ownModifierMask(keyCode);
    return (stripped & requiredFlags) == requiredFlags;
  }

  // Quick translate override: non-null → this recording translates to the specified language
  String? _translateOverride;

  // Toggle mode state
  bool _isToggleMode = false;        // Current recording was started by toggle
  Timer? _toggleMaxTimer;            // Max recording duration timer
  DateTime? _keyDownTime;            // Shared-key press timestamp for PTT vs Toggle

  // Key state debouncing
  bool _pttKeyHeld = false;
  bool _diaryKeyHeld = false;
  bool _translateKeyHeld = false;
  bool _deferredStop = false;
  int? _activeHotkeyCode; // The key that started the current recording (for watchdog)

  void _handleKey(int keyCode, bool isDown, int modifierFlags) {
    // macOS 26+: Globe/Fn key sends keyCode 179 (kCGEventKeyDown) in addition
    // to legacy keyCode 63 (kCGEventFlagsChanged). Normalize so users who
    // configured Fn (63) still get matched when Globe (179) arrives.
    if (keyCode == 179) keyCode = 63;

    _log("[KeyEvent] code=$keyCode, isDown=$isDown, mods=0x${modifierFlags.toRadixString(16)}, pttKey=$pttKeyCode, state=$_recordingState, toggle=$_isToggleMode");
    if (isDown) _rawKeyController.add((keyCode, modifierFlags));

    final config = ConfigService();
    final toggleInputCode = config.toggleInputKeyCode;
    final toggleDiaryCode = config.toggleDiaryKeyCode;

    // Helper: check keyCode + modifier combo match
    bool matchKey(int code, int requiredMods) =>
        keyCode == code && _modifiersMatch(keyCode, modifierFlags, requiredMods);

    // 1. Toggle stop: if toggle recording is active and the same toggle key is pressed again
    if (isDown && _isToggleMode && _recordingState == RecordingState.recording) {
      if ((_recordingMode == RecordingMode.ptt && keyCode == toggleInputCode) ||
          (_recordingMode == RecordingMode.diary && keyCode == toggleDiaryCode)) {
        _log("[Toggle] Second tap → stopRecording");
        stopRecording();
        return;
      }
    }

    // 2. 即时翻译快捷键（最高优先级，覆盖 shared/PTT/toggle）
    final translateCode = config.translateKeyCode;
    if (config.translateEnabled && translateCode != 0 &&
        matchKey(translateCode, config.translateModifiers)) {
      if (isDown && _recordingState == RecordingState.idle) {
        _translateOverride = config.translateTargetLanguage;
        _activeHotkeyCode = translateCode;
        _log("[Translate] Quick translate → $_translateOverride, key=$translateCode");
      }
      _handleModeKey(isDown, RecordingMode.ptt, _translateKeyHeld, (v) => _translateKeyHeld = v);
      return;
    }

    // 2.5 Translate toggle stop: translate recording active, same key pressed again
    if (isDown && _translateKeyHeld && _recordingState == RecordingState.recording) {
      _log("[Translate] Key re-pressed during recording → ignore (hold to record)");
    }

    // 3. Shared key: toggle key == PTT/diary key → use time-threshold logic
    final bool isSharedPtt = toggleInputCode != 0 && toggleInputCode == pttKeyCode && keyCode == pttKeyCode;
    final bool isSharedDiary = toggleDiaryCode != 0 && config.diaryEnabled && toggleDiaryCode == config.diaryKeyCode && keyCode == config.diaryKeyCode;

    if (isSharedPtt) {
      _handleSharedKey(isDown, RecordingMode.ptt, _pttKeyHeld, (v) => _pttKeyHeld = v);
      return;
    }
    if (isSharedDiary) {
      _handleSharedKey(isDown, RecordingMode.diary, _diaryKeyHeld, (v) => _diaryKeyHeld = v);
      return;
    }

    // 4. Independent toggle keys (not shared with PTT/diary)
    if (isDown && toggleInputCode != 0 && matchKey(toggleInputCode, config.toggleInputModifiers)) {
      _handleToggleKey(RecordingMode.ptt);
      return;
    }
    if (isDown && toggleDiaryCode != 0 && matchKey(toggleDiaryCode, config.toggleDiaryModifiers)) {
      _handleToggleKey(RecordingMode.diary);
      return;
    }

    // 5. AI 梳理快捷键（仅 keyDown，不涉及录音状态机）
    final organizeCode = config.organizeKeyCode;
    if (isDown && config.organizeEnabled && organizeCode != 0 &&
        matchKey(organizeCode, config.organizeModifiers)) {
      _handleOrganize();
      return;
    }

    // 6. Pure PTT / diary keys (existing logic)
    // Guard: if toggle mode is active, ignore keyUp from PTT/diary keys
    // to prevent the keyUp from a toggle-start tap from stopping recording.
    if (_isToggleMode && !isDown) return;

    final bool pttMatch = matchKey(pttKeyCode, config.pttModifiers);
    final bool diaryMatch = config.diaryEnabled && matchKey(config.diaryKeyCode, config.diaryModifiers);

    if (pttMatch) {
      if (isDown && _recordingState == RecordingState.idle) _activeHotkeyCode = pttKeyCode;
      _handleModeKey(isDown, RecordingMode.ptt, _pttKeyHeld, (v) => _pttKeyHeld = v);
    } else if (diaryMatch) {
      _handleModeKey(isDown, RecordingMode.diary, _diaryKeyHeld, (v) => _diaryKeyHeld = v);
    }
  }

  /// AI 梳理：选中文字 → Cmd+C → LLM → 光标到末尾 → 换行 → 粘贴结果
  Future<void> _handleOrganize() async {
    if (_isOrganizing || _recordingState != RecordingState.idle) return;
    final ni = _nativeInput;
    if (ni == null) return;
    _isOrganizing = true;
    _log("[Organize] 开始梳理");

    final overlay = OverlayController();

    try {
      // 1. 保存剪贴板 + Cmd+C 复制选中文字
      ni.injectClipboardBegin();
      ni.copySelection();
      await Future.delayed(const Duration(milliseconds: 150));

      // 2. 读取剪贴板
      final clipData = await Clipboard.getData('text/plain');
      final selectedText = clipData?.text?.trim() ?? '';
      if (selectedText.isEmpty) {
        _log("[Organize] 未检测到选中文字");
        ni.injectClipboardEnd();
        overlay.recordingMode = "organize";
        overlay.updateText("未检测到选中文字");
        await overlay.show();
        await Future.delayed(const Duration(seconds: 2));
        await overlay.hide();
        return;
      }
      _log("[Organize] 获取到 ${selectedText.length} 字");

      // 3. 显示悬浮窗
      overlay.recordingMode = "organize";
      overlay.updateText("梳理中...");
      await overlay.show();

      // 4. 调用 LLM
      final result = await LLMService().organizeText(selectedText)
          .timeout(AppConstants.kOrganizeTimeout);

      if (result.isEmpty) {
        _log("[Organize] LLM 返回空结果");
        overlay.updateText("梳理失败");
        await Future.delayed(const Duration(seconds: 2));
        ni.injectClipboardEnd();
        await overlay.hide();
        return;
      }

      // 5. 光标移到选区末尾 → 换行 → 粘贴结果
      ni.pressKey(124, 0); // → 键，取消选区
      await Future.delayed(const Duration(milliseconds: 50));
      ni.pressKey(36, 0);  // Return 换行
      await Future.delayed(const Duration(milliseconds: 50));
      ni.injectClipboardChunk(result);
      await Future.delayed(const Duration(milliseconds: 100));
      ni.injectClipboardEnd();

      overlay.updateText("✓");
      _log("[Organize] 完成，输出 ${result.length} 字");
      await Future.delayed(const Duration(seconds: 1));
      await overlay.hide();
    } catch (e) {
      _log("[Organize] 错误: $e");
      try { ni.injectClipboardEnd(); } catch (_) {}
      overlay.updateText("梳理失败");
      await Future.delayed(const Duration(seconds: 2));
      await overlay.hide();
    } finally {
      _isOrganizing = false;
    }
  }

  /// Handle independent toggle key (only responds to keyDown)
  void _handleToggleKey(RecordingMode mode) {
    if (_recordingState == RecordingState.idle) {
      _log("[Toggle] Independent key → startRecording (mode=${mode.name})");
      _isToggleMode = true;
      startRecording(mode: mode);
      _startToggleMaxTimer();
    }
    // If already recording in toggle mode, stop is handled at the top of _handleKey
  }

  /// Handle shared key (toggle key == PTT/diary key) with time-threshold
  void _handleSharedKey(bool isDown, RecordingMode mode, bool wasHeld, void Function(bool) setHeld) {
    if (isDown) {
      if (!wasHeld) {
        setHeld(true);
        _keyDownTime = DateTime.now();
        if (_recordingState == RecordingState.idle) {
          _log("[Shared] Key down → startRecording (mode=${mode.name})");
          startRecording(mode: mode);
        }
      }
    } else {
      setHeld(false);
      if (_recordingMode == mode && (_recordingState == RecordingState.recording || _recordingState == RecordingState.starting)) {
        final holdMs = _keyDownTime != null
            ? DateTime.now().difference(_keyDownTime!).inMilliseconds
            : AppConstants.kToggleThresholdMs; // default to PTT if no timestamp
        _keyDownTime = null;

        if (holdMs < AppConstants.kToggleThresholdMs) {
          // Short press → toggle mode (keep recording)
          _log("[Shared] Short press (${holdMs}ms) → Toggle mode");
          _isToggleMode = true;
          _watchdogTimer?.cancel(); // No watchdog for toggle
          _startToggleMaxTimer();
        } else {
          // Long press → PTT mode (stop recording)
          _log("[Shared] Long press (${holdMs}ms) → PTT stop");
          if (_recordingState == RecordingState.recording) {
            stopRecording();
          } else if (_recordingState == RecordingState.starting) {
            _deferredStop = true;
          }
        }
      }
    }
  }

  /// Start max duration timer for toggle mode
  void _startToggleMaxTimer() {
    _toggleMaxTimer?.cancel();
    final maxSec = ConfigService().toggleMaxDuration;
    if (maxSec > 0) {
      _toggleMaxTimer = Timer(Duration(seconds: maxSec), () {
        if (_isToggleMode && _recordingState == RecordingState.recording) {
          _log("[Toggle] Max duration ($maxSec s) reached → auto stop");
          stopRecording();
        }
      });
    }
  }

  /// Unified edge detection for PTT and diary keys
  void _handleModeKey(bool isDown, RecordingMode mode, bool wasHeld, void Function(bool) setHeld) {
    if (isDown) {
      if (!wasHeld) {
        setHeld(true);
        if (_recordingState == RecordingState.idle) {
          _log("[${mode.name}] RISING EDGE → startRecording");
          startRecording(mode: mode);
        }
      }
    } else {
      setHeld(false);
      if (_recordingMode == mode) {
        if (_recordingState == RecordingState.recording) {
          _log("[${mode.name}] FALLING EDGE → stopRecording");
          stopRecording();
        } else if (_recordingState == RecordingState.starting) {
          // Key released during async startup — schedule stop after startup completes
          _log("[${mode.name}] FALLING EDGE during starting → deferred stop");
          _deferredStop = true;
        }
      }
    }
  }

  // NATIVE AUDIO PIPELINE
  Future<void> startRecording({required RecordingMode mode}) async {
    _log("startRecording(mode=${mode.name}) BEGIN, state=$_recordingState");

    // Guard: only start from idle
    if (_recordingState != RecordingState.idle) {
      _log("Not idle (state=$_recordingState), ignoring.");
      return;
    }

    // 1. PERMISSION CHECK
    if (_nativeInput == null || !_nativeInput.checkMicrophonePermission()) {
      _log("Permission DENIED by native check.");
      _statusController.add("需要麦克风权限");
      return;
    }

    // Transition: idle → starting
    _recordingState = RecordingState.starting;
    _recordingMode = mode;
    _recordingController.add(true);

    // 2. UI FEEDBACK (fire-and-forget)
    _overlay.recordingMode = mode == RecordingMode.diary ? "diary" : "ptt";
    if (mode == RecordingMode.diary) {
      _overlay.updateText("📝 Note...");
    }
    _overlay.show();

    // 3. AUDIO INIT via Native FFI
    try {
      if (_asrProvider == null || !_asrProvider!.isReady) {
        _log("ASR Provider not ready!");
        _overlay.updateText("❌ 请先下载语音模型");
        _statusController.add("引擎未就绪 - 请下载模型");
        await Future.delayed(const Duration(seconds: 2));
        _cleanupRecordingState();
        return;
      }
      await _asrProvider!.start();
      _log("ASR Provider Started.");

      // 4. WATCHDOG (PTT only — diary/toggle/translate have reliable key-up)
      // Skip watchdog for translate: modifier keys (Shift/Option/etc) don't report
      // reliably via CGEventSourceKeyState, causing false "key up" detection.
      _watchdogTimer?.cancel();
      if (mode == RecordingMode.ptt && !_isToggleMode && _translateOverride == null) {
        final watchKeyCode = _activeHotkeyCode ?? pttKeyCode;
        _watchdogTimer = Timer.periodic(Duration(milliseconds: AppConstants.kKeyWatchdogIntervalMs), (timer) {
          if (_recordingState != RecordingState.recording) { timer.cancel(); return; }
          final isPhysicallyDown = _nativeInput.isKeyPressed(watchKeyCode);
          if (!isPhysicallyDown) {
            _log("Watchdog: Key $watchKeyCode UP physically, forcing stop.");
            timer.cancel();
            stopRecording();
          }
        });
      }

      // 5. START NATIVE RECORDING (Ring Buffer)
      _log("Starting native audio recording (ring buffer)...");
      final success = _nativeInput.startAudioRecording();
      if (!success) {
        _log("Native audio start failed!");
        _cleanupRecordingState();
        _statusController.add("麦克风启动失败");
        return;
      }
      _audioStarted = true;

      // 6. START POLLING
      _startAudioPolling();

      // 7. SILENCE DETECTION — soft reminder if mic captures nothing for 2s
      _silenceCheckTimer?.cancel();
      _silencePollCount = 0;
      _lastSilenceNotify = null;
      _silenceCheckTimer = Timer.periodic(Duration(milliseconds: AppConstants.kSilenceCheckIntervalMs), (timer) {
        if (_recordingState != RecordingState.recording) { timer.cancel(); return; }
        final level = _nativeInput.getAudioLevel();
        if (level < 0.01) {
          _silencePollCount++;
        } else {
          if (_silencePollCount >= AppConstants.kSilenceThresholdCount) {
            // Was silent, now got audio — hide hint
            _overlay.hideSilenceHint();
          }
          _silencePollCount = 0;
        }
        // 8. OFFLINE DURATION WARNING — toggle mode + offline model + exceeds threshold
        if (_isToggleMode && _isOfflineASR && _recordingStartTime != null) {
          final elapsed = DateTime.now().difference(_recordingStartTime!).inSeconds;
          if (elapsed == AppConstants.kOfflineModelDurationWarningSeconds) {
            _overlay.updateText("⚠️ 超过30秒，识别效果可能下降");
            NotificationService().notify('离线模型超过30秒识别效果可能下降，建议切换到流式模型');
          }
        }

        // 2 seconds continuous silence (10 × 200ms), with 10s cooldown
        if (_silencePollCount >= AppConstants.kSilenceThresholdCount) {
          final now = DateTime.now();
          if (_lastSilenceNotify == null ||
              now.difference(_lastSilenceNotify!).inSeconds >= 10) {
            _lastSilenceNotify = now;
            _log("Silence detected for 2s — mic may be unavailable");
            _overlay.showSilenceHint();
            NotificationService().notify('未检测到声音，请检查麦克风是否可用');
          }
        }
      });

      // Transition: starting → recording
      _recordingState = RecordingState.recording;
      _recordingStartTime = DateTime.now();
      _log("Recording started (mode=${mode.name}).");

      // Handle deferred stop (key released during async startup)
      if (_deferredStop) {
        _deferredStop = false;
        _log("Deferred stop triggered.");
        stopRecording();
        return;
      }
    } catch (e) {
      _log("Start Fatal Error: $e");
      _cleanupRecordingState();
      _statusController.add("启动失败");
    }
  }
  
  /// Start polling the C ring buffer for audio data
  void _startAudioPolling() {
    _stopAudioPolling(); // Cancel any existing timer
    
    // Allocate a reusable native buffer for polling
    _pollBuffer ??= pkg_ffi.calloc<ffi.Int16>(_pollBufferSamples);
    
    _audioPollTimer = Timer.periodic(Duration(milliseconds: AppConstants.kAudioPollIntervalMs), (_) {
      _pollAudioRingBuffer();
    });
  }
  
  /// Stop polling and free the poll buffer
  void _stopAudioPolling() {
    _audioPollTimer?.cancel();
    _audioPollTimer = null;
    // Note: _pollBuffer is intentionally kept allocated for reuse
    // It will be freed when the engine is disposed
  }
  
  /// Poll the C ring buffer and feed audio to ASR pipeline
  void _pollAudioRingBuffer() {
    if (_recordingState != RecordingState.recording || _nativeInput == null || _pollBuffer == null) return;
    
    final samplesRead = _nativeInput.readAudioBuffer(_pollBuffer!, _pollBufferSamples);
    if (samplesRead <= 0) return;
    
    // Convert Pointer<Int16> to Uint8List (matching _processAudioData interface)
    final byteCount = samplesRead * 2;
    final bytes = _pollBuffer!.cast<ffi.Uint8>().asTypedList(byteCount);
    
    // Uint8List.fromList creates a copy, safe to reuse _pollBuffer next poll
    _processAudioData(Uint8List.fromList(bytes));
  }

  void _processAudioData(Uint8List data) {
    if (_recordingState != RecordingState.recording) return;
    
    // RAW 16k Int16 -> Float32 (direct passthrough, no gain)
    final int sampleCount = data.length ~/ 2;
    final floatSamples = Float32List(sampleCount);
    final byteData = ByteData.sublistView(data);

    for (int i = 0; i < sampleCount; i++) {
      floatSamples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }

    if (_asrProvider != null) {
      _asrProvider!.acceptWaveform(floatSamples);
    }
  }

  void _cleanupRecordingState() {
     _recordingState = RecordingState.idle;
     _audioStarted = false;
     _deferredStop = false;
     _isToggleMode = false;
     _activeHotkeyCode = null;
     _toggleMaxTimer?.cancel();
     _toggleMaxTimer = null;
     _stopAudioPolling();
     _watchdogTimer?.cancel();
     _silenceCheckTimer?.cancel();
     _recordingController.add(false);
     _overlay.hide();
  }

  /// Save recording WAV for debugging. Keeps last 10 files, rotating.
  void _saveDebugRecording() {
    final ni = _nativeInput;
    if (ni == null) return;
    final dir = Directory('${Platform.environment['HOME']}/Library/Application Support/com.speakout.speakout/recordings');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // Rotate: keep last 10
    final existing = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    while (existing.length >= 10) {
      existing.removeAt(0).deleteSync();
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final path = '${dir.path}/rec_$timestamp.wav';
    if (ni.saveRecordingWav(path)) {
      _log("Debug recording saved: $path");
    }
  }

  Future<void> _stopAudioSafely() async {
    _stopAudioPolling();  // Stop polling BEFORE stopping AudioQueue
    if (_audioStarted) {
      try {
        _nativeInput?.stopAudioRecording();
        _audioStarted = false;
      } catch (e) { _log("Stop Audio Error: $e"); }
    }
  }

  Future<void> stopRecording() async {
    // Guard: only stop from recording state (prevents watchdog + key-up race)
    if (_recordingState != RecordingState.recording) return;

    final sw = Stopwatch()..start();
    _log("[PERF] stopRecording BEGIN");

    // Clean up toggle state
    _isToggleMode = false;
    _toggleMaxTimer?.cancel();
    _toggleMaxTimer = null;

    // Transition: recording → stopping
    _recordingState = RecordingState.stopping;
    final mode = _recordingMode; // capture before cleanup

    // 1. UI FIRST (Optimistic Update)
    _recordingController.add(false);
    _statusController.add("处理中...");
    _overlay.hide();

    // Yield to event loop so method channel message is dispatched
    await Future(() {});
    _log("[PERF] +${sw.elapsedMilliseconds}ms — yield done");

    // Give ASR time to process the last audio chunks before stopping hardware
    await Future.delayed(Duration(milliseconds: AppConstants.kEngineShutdownDelayMs));
    _log("[PERF] +${sw.elapsedMilliseconds}ms — shutdown delay done");

    // HARDWARE SHUTDOWN
    try {
      await _stopAudioSafely();
    } catch (e) {
      _log("Audio Stop Error: $e");
    }

    // Save recording for debugging (developer mode only)
    if (AppLog.enabled) {
      try {
        _saveDebugRecording();
      } catch (e) {
        _log("Save recording error: $e");
      }
    }
    _log("[PERF] +${sw.elapsedMilliseconds}ms — audio stopped");

    // Transition: stopping → processing
    _recordingState = RecordingState.processing;

    // Wrap entire processing in try/finally to guarantee state recovery
    try {
    if (_asrProvider != null) {
      ASRResult asrResult = ASRResult.textOnly("");
      try {
        asrResult = await _asrProvider!.stop().timeout(AppConstants.kAsrStopTimeout, onTimeout: () {
          _log("ASR Provider Stop Timeout!");
          return ASRResult.textOnly("");
        });
      } catch (e) {
        _log("Provider Stop Error: $e");
      }
      _log("[PERF] +${sw.elapsedMilliseconds}ms — ASR stop() returned (${asrResult.text.length}字): '${asrResult.text}'");

      // 云端 ASR 错误（鉴权失败、配额超限等）
      if (asrResult.error != null) {
        _log("ASR Error: ${asrResult.error}");
        _statusController.add("❌ ${asrResult.error}");
        _overlay.showThenClear("❌ ${asrResult.error}", AppConstants.kErrorDisplayDuration);
        return; // finally block handles cleanup
      }

      String finalText = asrResult.text;
      final originalAsrText = asrResult.text; // 保留 ASR 原文用于 UI 对比
      lastLlmSuccess = null; // 重置

      // AI Polish (with vocab hints injected into LLM prompt)
      // Skip LLM for trivial input: pure punctuation, whitespace, or ≤2 chars
      final trimmedForCheck = finalText.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
      final isQuickTranslate = _translateOverride != null;
      final shouldCallLlm = finalText.isNotEmpty && trimmedForCheck.length > 2 &&
          (ConfigService().aiCorrectionEnabled || isQuickTranslate);
      if (shouldCallLlm) {
        _statusController.add(isQuickTranslate ? "翻译中..." : "AI 润色中...");
        _overlay.updateText(isQuickTranslate ? "🌐 Translating..." : "🤖 AI Polishing...");
        _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish starting...");
        bool typewriterBegan = false;
        try {
          List<String>? vocabHints;
          if (ConfigService().vocabEnabled) {
            vocabHints = VocabService().getVocabHints();
            _log("[PERF] vocab hints: ${vocabHints.length} terms");
          }

          final useTypewriter = mode != RecordingMode.diary
              && ConfigService().typewriterEnabled;
          final llmTimeout = AppConstants.kLlmPolishTimeout;

          if (useTypewriter) {
            // Typewriter mode (alpha): streaming LLM + clipboard injection
            final streamBuffer = StringBuffer();
            final batchBuffer = StringBuffer();
            bool firstChunk = true;
            bool streamInjected = false;
            var lastInjectTime = DateTime.now();
            const batchInterval = Duration(milliseconds: AppConstants.kTypewriterBatchIntervalMs);

            _nativeInput?.injectClipboardBegin();
            typewriterBegan = true;
            _log("[PERF] +${sw.elapsedMilliseconds}ms — typewriter mode: clipboard begin");

            // Wrap stream with timeout: if no data for 15s, abort
            bool timedOut = false;
            await for (final chunk in LLMService().correctTextStream(finalText, vocabHints: vocabHints, translateTo: _translateOverride).timeout(llmTimeout, onTimeout: (sink) {
              timedOut = true;
              _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish stream TIMEOUT (${llmTimeout.inSeconds}s)");
              sink.close();
            })) {
              streamBuffer.write(chunk);
              batchBuffer.write(chunk);
              if (firstChunk) {
                _log("[PERF] +${sw.elapsedMilliseconds}ms — first token received");
                firstChunk = false;
              }

              // Flush batch via clipboard paste
              final now = DateTime.now();
              if (now.difference(lastInjectTime) >= batchInterval && batchBuffer.isNotEmpty) {
                _nativeInput?.injectClipboardChunk(batchBuffer.toString());
                batchBuffer.clear();
                lastInjectTime = now;
                streamInjected = true;
              }
            }

            // Flush remaining batch
            if (batchBuffer.isNotEmpty) {
              _nativeInput?.injectClipboardChunk(batchBuffer.toString());
              streamInjected = true;
            }
            _nativeInput?.injectClipboardEnd();
            typewriterBegan = false;

            var polished = streamBuffer.toString().trim();
            // 清洗 <think>...</think> 推理标签
            polished = polished.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();
            polished = polished.replaceAll(RegExp(r'</?think>', caseSensitive: false), '').trim();
            if (polished.isNotEmpty) {
              finalText = polished;
            } else if (timedOut) {
              // Timeout with no data: fall back to raw ASR text
              _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish timeout, using raw ASR text");
            }
            if (streamInjected) {
              _typewriterInjected = true;
            }
            _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish stream done (typewriter), len=${finalText.length}");
          } else if (mode != RecordingMode.diary) {
            // Normal mode: non-streaming LLM, inject once at end
            finalText = await LLMService().correctText(finalText, vocabHints: vocabHints, translateTo: _translateOverride).timeout(llmTimeout, onTimeout: () {
              _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish TIMEOUT (${llmTimeout.inSeconds}s), using raw ASR text");
              return finalText;
            });
            _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish done (${finalText.length}字): '$finalText'");
          } else {
            // Diary mode: non-streaming (need complete text for file save)
            finalText = await LLMService().correctText(finalText, vocabHints: vocabHints, translateTo: _translateOverride).timeout(llmTimeout, onTimeout: () {
              _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish TIMEOUT (${llmTimeout.inSeconds}s), using raw ASR text");
              return finalText;
            });
            _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish done (${finalText.length}字): '$finalText'");
          }
        } catch (e) {
          _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish error: $e");
          // Ensure typewriter clipboard session is properly ended
          if (typewriterBegan) {
            try { _nativeInput?.injectClipboardEnd(); } catch (_) {}
          }
        }
        lastLlmSuccess = LLMService().lastCallSucceeded;
      } else if (finalText.isNotEmpty && ConfigService().aiCorrectionEnabled && trimmedForCheck.length <= 2) {
        _log("[PERF] +${sw.elapsedMilliseconds}ms — AI polish skipped (trivial input: '$finalText')");
      } else if (finalText.isNotEmpty && ConfigService().vocabEnabled) {
        // Offline fallback: direct replacement when AI is disabled
        finalText = VocabService().applyReplacements(finalText);
        _log("[PERF] +${sw.elapsedMilliseconds}ms — vocab fallback replacement done");
      }

      // Fallback: Local Punctuation (Sherpa only, skip if model has built-in punctuation)
      final bool isLocalEngine = ConfigService().asrEngineType == 'sherpa';
      if (finalText.isNotEmpty && _punctuationEnabled && isLocalEngine && !_activeModelHasPunctuation) {
        if (!hasTerminalPunctuation(finalText)) {
          final temp = addPunctuation(finalText);
          if (temp != finalText) {
            finalText = temp;
          }
        }
        _log("[PERF] +${sw.elapsedMilliseconds}ms — punctuation done");
      }

      // 保存 ASR 原文供主界面对比（仅当 LLM 有改动时）
      lastAsrOriginal = (originalAsrText != finalText) ? originalAsrText : null;
      _resultController.add(finalText);

      if (finalText.isNotEmpty) {
        if (mode == RecordingMode.diary) {
          _statusController.add("Saving Note...");
          DiaryService().appendNote(finalText).then((err) {
            if (err == null) {
              _statusController.add("✅ Saved Note");
              _overlay.showThenClear("✅ Saved Note", AppConstants.kSuccessDisplayDuration);
            } else {
              _statusController.add("❌ Save Failed");
              _log("Diary Save Error: $err");
            }
          });
          ChatService().addUserMessage(finalText);
        } else {
          if (!_typewriterInjected) {
            _nativeInput?.inject(finalText);
          }
          _typewriterInjected = false;
          ChatService().addDictation(finalText, asrOriginal: originalAsrText);
          _statusController.add("Ready");
        }
        _log("[PERF] +${sw.elapsedMilliseconds}ms — inject/save done");
      } else {
        _statusController.add("🔇 No Speech");
        _log("[PERF] +${sw.elapsedMilliseconds}ms — no speech detected");
      }
    }
    } finally {
      // Report usage for billing (only when cloud services were consumed)
      if (_recordingStartTime != null) {
        final recordingSeconds = DateTime.now().difference(_recordingStartTime!).inSeconds;
        final usedCloud = ConfigService().workMode == 'cloud' ||
            (ConfigService().workMode == 'smart' && ConfigService().aiCorrectionEnabled);
        if (usedCloud && recordingSeconds > 0) {
          BillingService().reportUsage(recordingSeconds);
        }
        _recordingStartTime = null;
      }
      // Clear quick translate override
      _translateOverride = null;
      // Guarantee state recovery — no matter what happens above
      _cleanupRecordingState();
      _log("[PERF] +${sw.elapsedMilliseconds}ms — stopRecording END");
    }
  }
  
  @visibleForTesting
  static bool hasTerminalPunctuation(String text) {
    if (text.trim().isEmpty) return false;
    final trimmed = text.trim();
    final lastChar = trimmed[trimmed.length - 1]; // standard string indexing
    const terminals = ['。', '？', '！', '.', '?', '!'];
    return terminals.contains(lastChar);
  }
}
