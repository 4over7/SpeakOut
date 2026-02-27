import 'dart:async';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../ffi/native_input.dart';
import '../ffi/native_input_base.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import 'asr_provider.dart';
import 'providers/sherpa_provider.dart';
import 'providers/aliyun_provider.dart';
import '../services/diary_service.dart';
import '../services/chat_service.dart';
import '../services/audio_device_service.dart';
import '../services/overlay_controller.dart';

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
  static const int _pollBufferSamples = 16000;  // Max 1 second per poll (16kHz)
  
  // Audio Device Management
  AudioDeviceService? _audioDeviceService;
  AudioDeviceService? get audioDeviceService => _audioDeviceService;
  
  CoreEngine._internal() {
    try {
      _nativeInput = NativeInput();
      // Initialize AudioDeviceService with NativeInput
      _audioDeviceService = AudioDeviceService(_nativeInput as NativeInput);
      AudioDeviceService.setInstance(_audioDeviceService!);
    } catch (e) {
      debugPrint("[CoreEngine] Warning: Failed to init NativeInput: $e");
      _nativeInput = null;
    }
  }
  
  // ASR Provider abstraction
  ASRProvider? _asrProvider;
  
  Timer? _watchdogTimer; // Safety mechanism

  // Recording state machine (replaces _isRecording, _isStopping, _audioStarted, _isDiaryMode)
  RecordingState _recordingState = RecordingState.idle;
  RecordingMode _recordingMode = RecordingMode.ptt;
  bool _audioStarted = false; // hardware-level flag: native audio is running

  // Keep Offline Punctuation & Debugging related fields
  sherpa.OfflinePunctuation? _punctuation;
  bool _punctuationEnabled = false;

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
  
  final _rawKeyController = StreamController<int>.broadcast();
  Stream<int> get rawKeyEventStream => _rawKeyController.stream;

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

  // Debug Logger - writes to file asynchronously
  static final _logFile = File('/tmp/SpeakOut.log');
  static bool _logCleared = false;

  void _log(String msg) {
    // 每次启动清空旧日志，避免无限增长
    if (!_logCleared) {
      _logFile.writeAsStringSync('');
      _logCleared = true;
    }
    final line = "[${DateTime.now().toIso8601String()}] [CoreEngine] $msg\n";
    _logFile.writeAsStringSync(line, mode: FileMode.append);
  }

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
    _stopAudioPolling();
    if (_pollBuffer != null) {
      pkg_ffi.calloc.free(_pollBuffer!);
      _pollBuffer = null;
    }
    _asrProvider?.dispose();
  }

  /// De-duplicate repeated characters AND phrases
  /// Handles: "识识别" → "识别", "还是还是" → "还是", "一下一下" → "一下"
  String _deduplicateText(String text) {
    if (text.length < 2) return text;
    String result = text;
    
    // Phase 1: Remove repeated phrases (longest first: 4, 3, 2 chars)
    for (int phraseLen = 4; phraseLen >= 2; phraseLen--) {
      result = _removeRepeatedPhrases(result, phraseLen);
    }
    
    // Phase 2: Remove consecutive identical characters
    final buffer = StringBuffer();
    String? lastChar;
    for (int i = 0; i < result.length; i++) {
      final char = result[i];
      if (char != lastChar) {
        buffer.write(char);
        lastChar = char;
      }
    }
    return buffer.toString();
  }
  
  /// Remove immediately repeated phrases of given length
  /// e.g., for len=2: "还是还是好" → "还是好"
  String _removeRepeatedPhrases(String text, int len) {
    if (text.length < len * 2) return text;
    final buffer = StringBuffer();
    int i = 0;
    while (i < text.length) {
      if (i + len * 2 <= text.length) {
        final phrase1 = text.substring(i, i + len);
        final phrase2 = text.substring(i + len, i + len * 2);
        if (phrase1 == phrase2) {
          // Skip the repeated phrase
          buffer.write(phrase1);
          i += len * 2;
          // Continue skipping if more repetitions
          while (i + len <= text.length && text.substring(i, i + len) == phrase1) {
            i += len;
          }
          continue;
        }
      }
      buffer.write(text[i]);
      i++;
    }
    return buffer.toString();
  }

  // Device Listing - Using native permission check
  Future<bool> listInputDevices() async {
    // Native audio doesn't need device listing - uses system default
    return _nativeInput?.checkMicrophonePermission() ?? false;
  }

  /// Check if NativeInput (native library) loaded successfully
  bool get isNativeInputReady => _nativeInput != null;

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
    
    // Check for Bluetooth mic at startup
    if (_audioDeviceService?.isCurrentInputBluetooth == true) {
      _log("Warning: Bluetooth mic detected at startup. Switching to built-in...");
      _audioDeviceService?.switchToBuiltinMic();
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
  Future<void> initASR(String modelPath, {String modelType = 'zipformer', String modelName = 'Local Model'}) async {
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
    
    if (type == 'aliyun') {
      provider = AliyunProvider();
      config = {
        'accessKeyId': ConfigService().aliyunAccessKeyId,
        'accessKeySecret': ConfigService().aliyunAccessKeySecret,
        'appKey': ConfigService().aliyunAppKey,
      };
      _log("Initializing Aliyun Provider...");
      _statusController.add("☁️ 连接阿里云 (Connecting)...");
    } else {
      // Default: Sherpa Local
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
         if (_recordingState == RecordingState.recording && text.isNotEmpty) {
            _overlay.updateText(text);
         }
      });
      
  
      
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
  static void _onKeyStatic(int keyCode, bool isDown) {
    CoreEngine()._handleKey(keyCode, isDown);
  }

  // Key state debouncing
  bool _pttKeyHeld = false;
  bool _diaryKeyHeld = false;
  bool _deferredStop = false;

  void _handleKey(int keyCode, bool isDown) {
    // macOS 26+: Globe/Fn key sends keyCode 179 (kCGEventKeyDown) in addition
    // to legacy keyCode 63 (kCGEventFlagsChanged). Normalize so users who
    // configured Fn (63) still get matched when Globe (179) arrives.
    // NOTE: native_input.m also maps 179→63, but this Dart-side mapping is
    // retained as defense-in-depth in case native mapping is bypassed.
    if (keyCode == 179) keyCode = 63;

    _log("[KeyEvent] code=$keyCode, isDown=$isDown, pttKey=$pttKeyCode, state=$_recordingState");
    if (isDown) _rawKeyController.add(keyCode);

    // Match key to mode
    if (keyCode == pttKeyCode) {
      _handleModeKey(isDown, RecordingMode.ptt, _pttKeyHeld, (v) => _pttKeyHeld = v);
    } else if (ConfigService().diaryEnabled && keyCode == ConfigService().diaryKeyCode) {
      _handleModeKey(isDown, RecordingMode.diary, _diaryKeyHeld, (v) => _diaryKeyHeld = v);
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

      // 4. WATCHDOG (PTT only — diary has reliable key-up)
      _watchdogTimer?.cancel();
      if (mode == RecordingMode.ptt) {
        _watchdogTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
          if (_recordingState != RecordingState.recording) { timer.cancel(); return; }
          final isPhysicallyDown = _nativeInput.isKeyPressed(pttKeyCode);
          if (!isPhysicallyDown) {
            _log("Watchdog: Key UP physically, forcing stop.");
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

      // Transition: starting → recording
      _recordingState = RecordingState.recording;
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
    
    // Poll every 50ms — at 16kHz this means ~800 samples per poll
    _audioPollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
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
     _stopAudioPolling();
     _watchdogTimer?.cancel();
     _recordingController.add(false);
     _overlay.hide();
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
    await Future.delayed(const Duration(milliseconds: 200));
    _log("[PERF] +${sw.elapsedMilliseconds}ms — 200ms delay done");

    // HARDWARE SHUTDOWN
    try {
      await _stopAudioSafely();
    } catch (e) {
      _log("Audio Stop Error: $e");
    }
    _log("[PERF] +${sw.elapsedMilliseconds}ms — audio stopped");

    // Transition: stopping → processing
    _recordingState = RecordingState.processing;

    if (_asrProvider != null) {
      String text = "";
      try {
        text = await _asrProvider!.stop().timeout(const Duration(seconds: 2), onTimeout: () {
          _log("ASR Provider Stop Timeout!");
          return "";
        });
      } catch (e) {
        _log("Provider Stop Error: $e");
      }
      _log("[PERF] +${sw.elapsedMilliseconds}ms — ASR stop() returned: '${text.length > 30 ? '${text.substring(0, 30)}...' : text}'");

      String finalText = text;

      // Post-processing: De-duplicate
      if (finalText.isNotEmpty && ConfigService().deduplicationEnabled) {
        finalText = _deduplicateText(finalText);
        _log("[PERF] +${sw.elapsedMilliseconds}ms — dedup done");
      }

      // AI Correction
      if (finalText.isNotEmpty && ConfigService().aiCorrectionEnabled) {
        _statusController.add("AI 优化中...");
        _overlay.updateText("🤖 AI Optimizing...");
        _log("[PERF] +${sw.elapsedMilliseconds}ms — AI correction starting...");
        try {
          finalText = await LLMService().correctText(finalText);
          _log("[PERF] +${sw.elapsedMilliseconds}ms — AI correction done");
        } catch (e) {
          _log("[PERF] +${sw.elapsedMilliseconds}ms — AI correction error: $e");
        }
      }

      // Fallback: Local Punctuation (Sherpa only)
      final bool isLocalEngine = ConfigService().asrEngineType == 'sherpa';
      if (finalText.isNotEmpty && _punctuationEnabled && isLocalEngine) {
        if (!_hasTerminalPunctuation(finalText)) {
          final temp = addPunctuation(finalText);
          if (temp != finalText) {
            finalText = temp;
          }
        }
        _log("[PERF] +${sw.elapsedMilliseconds}ms — punctuation done");
      }

      _resultController.add(finalText);

      if (finalText.isNotEmpty) {
        if (mode == RecordingMode.diary) {
          _statusController.add("Saving Note...");
          DiaryService().appendNote(finalText).then((err) {
            if (err == null) {
              _statusController.add("✅ Saved Note");
              _overlay.showThenClear("✅ Saved Note", const Duration(seconds: 2));
            } else {
              _statusController.add("❌ Save Failed");
              _log("Diary Save Error: $err");
            }
          });
          ChatService().addUserMessage(finalText);
        } else {
          _nativeInput?.inject(finalText);
          ChatService().addDictation(finalText);
          _statusController.add("Ready");
        }
        _log("[PERF] +${sw.elapsedMilliseconds}ms — inject/save done");
      } else {
        _statusController.add("🔇 No Speech");
        _log("[PERF] +${sw.elapsedMilliseconds}ms — no speech detected");
      }
    }

    // Transition: processing → idle
    _recordingState = RecordingState.idle;
    _log("[PERF] +${sw.elapsedMilliseconds}ms — stopRecording END");
  }
  
  bool _hasTerminalPunctuation(String text) {
    if (text.trim().isEmpty) return false;
    final trimmed = text.trim();
    final lastChar = trimmed[trimmed.length - 1]; // standard string indexing
    const terminals = ['。', '？', '！', '.', '?', '!'];
    return terminals.contains(lastChar);
  }
}
