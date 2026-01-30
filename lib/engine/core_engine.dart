import 'dart:async';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

// MethodChannel for native overlay control
const _overlayChannel = MethodChannel('com.SpeakOut/overlay');

class CoreEngine {
  static final CoreEngine _instance = CoreEngine._internal();
  
  // Simple singleton
  factory CoreEngine() => _instance;

  // Dependencies - Native Audio via FFI (replaces record package)
  late final NativeInputBase? _nativeInput;
  ffi.NativeCallable<AudioCallbackC>? _audioCallable;
  
  CoreEngine._internal() {
    try {
      _nativeInput = NativeInput();
    } catch (e) {
      print("[CoreEngine] Warning: Failed to init NativeInput: $e");
      _nativeInput = null;
    }
  }
  
  // ASR Provider abstraction
  ASRProvider? _asrProvider;
  
  // Metering State
  DateTime? _startTime;
  Timer? _watchdogTimer; // Safety mechanism

  // State
  bool _isRecording = false;
  bool _isInit = false;
  bool _isDiaryMode = false;
  
  // AGC State: Previous gain for sample-level interpolation
  double _lastAppliedGain = 1.0;
  
  // Keep Offline Punctuation & Debugging related fields
  sherpa.OfflinePunctuation? _punctuation;
  bool _punctuationEnabled = false;

  // Audio Logging + Offline ASR Comparison (Keep for debugging local engine)
  final List<Float32List> _audioBuffer = []; 
  String? _modelPath; // Cache for offline verification if using local
  IOSink? _audioDumpSink; // For raw audio dump
  
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
  
  bool get isRecording => _isRecording;
  
  /// Check if ASR provider is ready (model loaded)
  bool get isASRReady => _asrProvider != null && _asrProvider!.isReady;


  // Debug Logger
  void _log(String msg) {
    debugPrint("[CoreEngine] $msg");
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

  /// Check if accessibility permission is granted (for keyboard listener)
  bool checkAccessibilityPermission() {
    if (_nativeInput == null) {
      print("[CoreEngine] checkAccessibilityPermission: _nativeInput is NULL!");
      return false;
    }
    final result = _nativeInput!.checkPermission();
    print("[CoreEngine] checkAccessibilityPermission: $result");
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

    // 2. Init Native Listener
    _log("Setting up NativeCallable...");
    try {
      _nativeCallable = ffi.NativeCallable<KeyCallbackC>.listener(_onKeyStatic);
      if (_nativeInput != null && _nativeInput!.startListener(_nativeCallable!.nativeFunction)) {
        _isListenerRunning = true;
        _statusController.add("Keyboard Listener Started.");
        _log("Listener start success.");
        if (_nativeInput?.checkPermission() ?? false) _statusController.add("Accessibility Trusted: true");
      } else {
         _statusController.add("Failed to start Keyboard Listener.");
         _isListenerRunning = false;
      }
    } catch (e, stack) {
       _log("Listener Exception: $e\n$stack");
       _isListenerRunning = false;
       rethrow; // Let AppService handle it
    }

    _isInit = true;
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
      
      // CRITICAL FIX: Subscribe to new provider and forward to persistent controller
      // Added _deduplicateFinal to partial stream to fix real-time stuttering
      _asrSubscription = provider.textStream.listen((text) {
         if (!_partialTextController.isClosed) {
            _partialTextController.add(text);
         }
      });
      
      _isInit = true;
      _modelPath = modelPath; 
      
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
        if (await File(candidate).exists()) finalPath = candidate;
        else {
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

  void _handleKey(int keyCode, bool isDown) {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    if (isDown) _rawKeyController.add(keyCode);
    
    // Check PTT
    if (keyCode == pttKeyCode) {
      if (isDown) {
        if (!_pttKeyHeld) { // RISING EDGE
           _pttKeyHeld = true;
           if (!_isRecording) {
              _isDiaryMode = false;
              _log("[T+0ms] Key DOWN detected, calling startRecording");
              startRecording();
              _log("[T+${DateTime.now().millisecondsSinceEpoch - t0}ms] startRecording returned");
           }
        }
      } else {
        _pttKeyHeld = false; // FALLING EDGE
        if (_isRecording && !_isDiaryMode) {
          _log("[T+0ms] Key UP detected, calling stopRecording");
          stopRecording();
          _log("[T+${DateTime.now().millisecondsSinceEpoch - t0}ms] stopRecording returned");
        }
      }
      return;
    }
    
    // Check Diary
    if (ConfigService().diaryEnabled && keyCode == ConfigService().diaryKeyCode) {
      if (isDown) {
        if (!_diaryKeyHeld) { // RISING EDGE
           _diaryKeyHeld = true;
           if (!_isRecording) {
              _isDiaryMode = true;
              startRecording();
           }
        }
      } else {
        _diaryKeyHeld = false; // FALLING EDGE
        if (_isRecording && _isDiaryMode) stopRecording();
      }
    }
  }

  // NATIVE AUDIO PIPELINE (Replaces record package)
  Future<void> startRecording() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    _log("[T+0ms] startRecording() BEGIN");
    
    // 1. PERMISSION CHECK (Native FFI)
    if (_nativeInput == null || !_nativeInput!.checkMicrophonePermission()) {
        _log("Permission DENIED by native check.");
        _statusController.add("需要麦克风权限");
        return;
    }
    _log("[T+${DateTime.now().millisecondsSinceEpoch - t0}ms] Permission check done");

    if (_isRecording) {
      _log("Already recording, ignoring.");
      return;
    }
    _isRecording = true;
    _isStopping = false;
    _recordingController.add(true); 

    // Reset Audio Dump
    try {
      final f = File('/tmp/audio_dump.pcm');
      if (f.existsSync()) f.deleteSync();
      _audioDumpSink = f.openWrite();
    } catch (e) {
      _log("Audio Dump Init Failed: $e");
    }
    _log("[T+${DateTime.now().millisecondsSinceEpoch - t0}ms] Audio dump init done");

    // 2. UI FEEDBACK (Show Immediately)
    try { 
       if (_isDiaryMode) {
         _overlayChannel.invokeMethod('updateStatus', {"text": "📝 Note..."});
         _overlayChannel.invokeMethod('showRecording'); 
       } else {
         _overlayChannel.invokeMethod('showRecording'); 
       }
    } catch (e) {/*ignore*/}
    _log("[T+${DateTime.now().millisecondsSinceEpoch - t0}ms] showRecording invoked");

    // 3. AUDIO INIT via Native FFI
    try {
        // CRITICAL: Start ASR Provider FIRST (Creates internal stream)
        if (_asrProvider == null || !_asrProvider!.isReady) {
            _log("ASR Provider not ready!");
            // Show visible error on overlay BEFORE cleaning up
            try {
              _overlayChannel.invokeMethod('updateStatus', {"text": "❌ 请先下载语音模型"});
            } catch (_) {}
            _statusController.add("引擎未就绪 - 请下载模型");
            // Delay to let user see the message
            await Future.delayed(const Duration(seconds: 2));
            _cleanupRecordingState();
            return;
        }
        await _asrProvider!.start();
        _startTime = DateTime.now();
        _log("ASR Provider Started.");

        // 4. WATCHDOG TIMER (The "Safety Net")
        _watchdogTimer?.cancel();
        _watchdogTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
             if (!_isRecording) { timer.cancel(); return; }
             final targetKey = _isDiaryMode ? ConfigService().diaryKeyCode : pttKeyCode;
             bool isPhysicallyDown = _nativeInput?.isKeyPressed(targetKey) ?? false;
             if (!isPhysicallyDown) {
                 _log("🐶 Watchdog: Key $targetKey is UP physically but App is Recording. Forcing Stop.");
                 timer.cancel();
                 stopRecording();
             }
        });
        
        // 5. SETUP NATIVE AUDIO CALLBACK
        _setupNativeAudioCallback();
        
        // 6. START NATIVE RECORDING
        _log("Starting native audio recording...");
        final success = _nativeInput?.startAudioRecording(_audioCallable!.nativeFunction) ?? false;
        if (!success) {
            _log("Native audio start failed!");
            _cleanupRecordingState();
            _statusController.add("麦克风启动失败");
            return;
        }
        _audioStarted = true;
        _log("Native audio recording started successfully.");

    } catch (e) {
        _log("Start Fatal Error: $e");
        _cleanupRecordingState();
        _statusController.add("启动失败");
    }
  }
  
  /// Setup native audio callback (Int16 samples -> Float32 for ASR)
  void _setupNativeAudioCallback() {
    // Dispose previous callable if exists
    _audioCallable?.close();
    
    // Create new native callable for audio data
    _audioCallable = ffi.NativeCallable<AudioCallbackC>.listener(
      _onNativeAudioData,
    );
    _log("Native audio callback setup complete.");
  }
  
  /// Native audio callback handler - receives Int16 samples from AudioQueue
  static void _onNativeAudioData(ffi.Pointer<ffi.Int16> samplesPtr, int sampleCount) {
    final engine = CoreEngine._instance;
    if (!engine._isRecording || sampleCount <= 0) {
      // Still need to free even if not recording
      engine._nativeInput?.nativeFree(samplesPtr.cast<ffi.Void>());
      return;
    }
    
    // Convert Pointer<Int16> to Uint8List (matching old processAudioData interface)
    // Each Int16 is 2 bytes
    final byteCount = sampleCount * 2;
    final bytes = samplesPtr.cast<ffi.Uint8>().asTypedList(byteCount);
    
    // Process using existing pipeline
    // Uint8List.fromList creates a copy, so samplesPtr is safe to free after this
    engine._processAudioData(Uint8List.fromList(bytes));
    
    // CRITICAL: Free the malloced copy from native code
    engine._nativeInput?.nativeFree(samplesPtr.cast<ffi.Void>());
  }

  // Mutex for stopping state
  bool _isStopping = false;
  bool _audioStarted = false;
  
  void _processAudioData(Uint8List data) {
    if (!_isRecording) return;
    
    // RAW 16k Int16 -> Float32 with DYNAMIC GAIN (Prevention vs Clipping)
    final int sampleCount = data.length ~/ 2;
    final floatSamples = Float32List(sampleCount);
    final byteData = ByteData.sublistView(data);
    
    // 1. First Pass: Detect Peak in current 100ms buffer
    double rawPeak = 0;
    for (int i = 0; i < sampleCount; i++) {
      double s = byteData.getInt16(i * 2, Endian.little).abs() / 32768.0;
      if (s > rawPeak) rawPeak = s;
    }

    // 2. RAW SIGNAL TEST: Disable all digital gain (using constant 1.0x)
    // This allows us to see if the engine handles raw microphone levels better
    // without any risk of digital artifacts or truncation.
    const double dynamicGain = 1.0;
    
    double energy = 0;

    // 3. Process samples with NO gain
    for (int i = 0; i < sampleCount; i++) {
        double sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
        
        // No gain applied, direct raw signal
        floatSamples[i] = sample;
        energy += sample * sample;
    }
    
    // RMS Log
    if (DateTime.now().millisecond < 20) {
       _log("RMS: ${(energy / sampleCount).toStringAsFixed(5)} [RAW SIGNAL - NO GAIN]");
    }

    if (_asrProvider != null) {
      _asrProvider!.acceptWaveform(floatSamples);
    }
    
    if (_audioBuffer.length < 100) {
        _audioBuffer.add(floatSamples);
    }
    
    // Dump Raw Audio
    try {
      _audioDumpSink?.add(data);
    } catch (_) {}
  }

  void _cleanupRecordingState() {
     _isRecording = false;
     _isStopping = false;
     _audioStarted = false;
     _watchdogTimer?.cancel(); // Kill watchdog
     _recordingController.add(false);
     try { _overlayChannel.invokeMethod('hideRecording'); } catch(e) {}
     _isDiaryMode = false;
  }

  Future<void> _stopAudioSafely() async {
    if (_audioStarted) {
      try {
        _nativeInput?.stopAudioRecording();
        _audioStarted = false;
      } catch (e) { _log("Stop Audio Error: $e"); }
    }
  }

  Future<void> stopRecording() async {
    _isStopping = true;
    _isRecording = false;
    
    // 1. UI FIRST (Optimistic Update)
    // Don't wait for ANY hardware. Hide UI immediately.
    _recordingController.add(false); 
    _statusController.add("处理中...");
    
    // Fire and forget hide command - don't await native response
    _overlayChannel.invokeMethod('hideRecording').catchError((e) {
      _log("Overlay Hide Error: $e");
    });
    
    // Yield to event loop to ensure method channel message is dispatched 
    // before we hit any potential native blocking code
    await Future.delayed(const Duration(milliseconds: 10));
    
    // 2. HARDWARE SHUTDOWN (Native audio is synchronous, no timeout needed)
    try {
      await _stopAudioSafely();
    } catch (e) {
       _log("Audio Stop Error: $e");
    }
    
    try { await _audioDumpSink?.close(); _audioDumpSink = null; } catch(_) {}
    
    _isStopping = false;
    
    if (_asrProvider != null) {
      String text = "";
      try {
        // Enforce timeout on Provider Stop as well (Sherpa FFI could block)
        text = await _asrProvider!.stop().timeout(const Duration(seconds: 2), onTimeout: () {
             _log("⚠️ ASR Provider Stop Timeout!");
             return "";
        });
      } catch (e) {
        _log("Provider Stop Error: $e");
      }
      _log("Raw Text: '$text'");
      String finalText = text;

      // Post-processing: De-duplicate consecutive repeated characters
      if (finalText.isNotEmpty && ConfigService().deduplicationEnabled) {
        finalText = _deduplicateText(finalText);
        _log("After Dedup: '$finalText'");
      }

      // AI Correction Logic
      if (finalText.isNotEmpty && ConfigService().aiCorrectionEnabled) {
         _statusController.add("AI 优化中...");
         try { _overlayChannel.invokeMethod('updateStatus', {"text": "🤖 AI Optimizing..."}); } catch(_) {}
         
         try {
            finalText = await LLMService().correctText(finalText);
            _log("LLM Result: '$finalText'");
         } catch(e) {
            _log("Ai Correction Error: $e");
         }
      }
      
      // Fallback: Local Punctuation
      // Strategy: Trust LLM first. Only use local model if LLM failed to provide terminal punctuation.
      // AND only if using Local Engine (Sherpa). Cloud engines usually provide punctuation.
      final bool isLocalEngine = ConfigService().asrEngineType == 'sherpa';
      
      if (finalText.isNotEmpty && _punctuationEnabled && isLocalEngine) {
          if (!_hasTerminalPunctuation(finalText)) {
              final temp = addPunctuation(finalText);
              if (temp != finalText) {
                 finalText = temp;
                 _log("Local Punctuation Result (Fallback): '$finalText'");
              }
          }
      }

      _resultController.add(finalText);
      
      if (finalText.isNotEmpty) {
        if (_isDiaryMode) {
           // DIARY MODE: Save to file
           _statusController.add("Saving Note...");
           DiaryService().appendNote(finalText).then((err) {
               if (err == null) {
                 _statusController.add("✅ Saved Note");
                 try { _overlayChannel.invokeMethod('updateStatus', {"text": "✅ Saved Note"}); } catch (_) {}
                 // Hide overlay after delay
                 Future.delayed(const Duration(seconds: 2), () {
                    try { _overlayChannel.invokeMethod('updateStatus', {"text": ""}); } catch(_){}
                 });
               } else {
                 _statusController.add("❌ Save Failed");
                 _log("Diary Save Error: $err");
               }
           });
            // 1. Add to Unified Log
            ChatService().addUserMessage(finalText);
        } else {
           // STANDARD MODE: Inject
           _statusController.add("Ready");
           _nativeInput?.inject(finalText);
           
           // Unified History: Log dictation
           ChatService().addDictation(finalText);
        }
      } else {
        _statusController.add("🔇 No Speech");
      }
      _audioBuffer.clear();
    }
  }
  
  bool _hasTerminalPunctuation(String text) {
    if (text.trim().isEmpty) return false;
    final trimmed = text.trim();
    final lastChar = trimmed[trimmed.length - 1]; // standard string indexing
    const terminals = ['。', '？', '！', '.', '?', '!'];
    return terminals.contains(lastChar);
  }
}
