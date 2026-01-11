import 'dart:async';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../ffi/native_input.dart';
import '../ffi/native_input_base.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import 'asr_provider.dart';
import 'providers/sherpa_provider.dart';
import 'providers/aliyun_provider.dart';
import '../services/diary_service.dart';
import '../services/agent_service.dart';
import '../services/chat_service.dart';
import '../services/metering_service.dart';

// MethodChannel for native overlay control
const _overlayChannel = MethodChannel('com.SpeakOut/overlay');

class CoreEngine {
  static final CoreEngine _instance = CoreEngine._internal();
  
  // Simple singleton
  factory CoreEngine() => _instance;

  // Dependencies - always use real implementations
  late final NativeInputBase _nativeInput;
  AudioRecorder _audioRecorder = AudioRecorder();
  
  CoreEngine._internal() {
    _nativeInput = NativeInput();
    // _audioRecorder already initialized
  }
  
  // ASR Provider abstraction
  ASRProvider? _asrProvider;
  
  // Metering State
  DateTime? _startTime;

  // State
  bool _isRecording = false;
  bool _isInit = false;
  bool _isDiaryMode = false; // NEW: Track if current session is Diary
  
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
  
  final _recordingController = StreamController<bool>.broadcast();
  Stream<bool> get recordingStream => _recordingController.stream;
  
  final _rawKeyController = StreamController<int>.broadcast();
  Stream<int> get rawKeyEventStream => _rawKeyController.stream;

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;
  
  // NEW: Forward partial results from ASR provider for real-time display
  Stream<String>? get partialTextStream => _asrProvider?.textStream;
  
  bool get isRecording => _isRecording;

  // Debug Logger
  void _log(String msg) {
    try {
      final f = File('/tmp/SpeakOut_debug.log');
      final time = DateTime.now().toIso8601String();
      f.writeAsStringSync("[$time] [CoreEngine] $msg\n", mode: FileMode.append);
    } catch (e) {
      print("Log Failed: $e");
    }
  }

  // Device Listing
  Future<List<InputDevice>> listInputDevices() async {
    try {
      if (!await _audioRecorder.hasPermission()) return [];
      return await _audioRecorder.listInputDevices();
    } catch (e) {
      _log("Error listing devices: $e");
      return [];
    }
  }

  Future<void> init() async {
    _log("Init started [v3.5.0]. _isInit: $_isInit");
    if (_isInit) return;

    // 1. Check Native Perms
    _log("Checking permissions...");
    bool trusted = _nativeInput.checkPermission();
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
      if (_nativeInput.startListener(_nativeCallable!.nativeFunction)) {
        _statusController.add("Keyboard Listener Started.");
        _log("Listener start success.");
        if (_nativeInput.checkPermission()) _statusController.add("Accessibility Trusted: true");
      } else {
         _statusController.add("Failed to start Keyboard Listener.");
      }
    } catch (e, stack) {
       _log("Listener Exception: $e\n$stack");
    }

    _isInit = true;
    _log("Init complete.");
  }
  
  ffi.NativeCallable<KeyCallbackC>? _nativeCallable;
  
  // Cache for Input Device
  InputDevice? _cachedInputDevice;
  bool _deviceCacheValid = false;

  Future<void> refreshInputDevice() async {
     try {
       if (!await _audioRecorder.hasPermission()) return;
       final selectedId = ConfigService().audioInputDeviceId;
       if (selectedId == null) {
         _cachedInputDevice = null;
         _deviceCacheValid = true;
         return;
       }
       final devices = await _audioRecorder.listInputDevices();
       
       // 1. Try Exact Match by ID
       InputDevice? match = devices.cast<InputDevice?>().firstWhere((d) => d!.id == selectedId, orElse: () => null);
       
       // 2. If ID changed (common on macOS reboot), try Match by Name
       if (match == null) {
           final savedName = ConfigService().audioInputDeviceName;
           if (savedName != null) {
              match = devices.cast<InputDevice?>().firstWhere((d) => d!.label == savedName, orElse: () => null);
              if (match != null) {
                 _log("Recovered Device by Name: ${match.label} (New ID: ${match.id})");
                 // Optional: Update ID silently?
                 await ConfigService().setAudioInputDeviceId(match.id, name: match.label);
              }
           }
       }
       
       _cachedInputDevice = match;
       _deviceCacheValid = true;
     } catch (e) { 
       _deviceCacheValid = false; 
     }
  }

  // Switch Provider Logic
  Future<void> initASR(String modelPath, {String modelType = 'zipformer', String modelName = 'Local Model'}) async {
    // Determine provider type
    final type = ConfigService().asrEngineType;
    ASRProvider provider;
    
    // Dispose previous if any
    if (_asrProvider != null) {
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

  // Deduplication helper
  String _deduplicateFinal(String text) {
    if (text.isEmpty) return text;
    String result = text;
    for (int len = 4; len >= 2; len--) {
      final pattern = RegExp(r'(.{' + len.toString() + r'})\1+');
      result = result.replaceAllMapped(pattern, (m) => m.group(1)!);
    }
    result = result.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    return result;
  }

  // Key Handling
  static void _onKeyStatic(int keyCode, bool isDown) {
    CoreEngine()._handleKey(keyCode, isDown);
  }

  void _handleKey(int keyCode, bool isDown) {
    if (isDown) _rawKeyController.add(keyCode);
    
    // Check PTT
    if (keyCode == pttKeyCode) {
      if (isDown) {
        if (!_isRecording) {
           _isDiaryMode = false;
           startRecording();
        }
      } else {
        if (_isRecording && !_isDiaryMode) stopRecording();
      }
      return;
    }
    
    // Check Diary
    if (ConfigService().diaryEnabled && keyCode == ConfigService().diaryKeyCode) {
      if (isDown) {
        if (!_isRecording) {
           _isDiaryMode = true;
           startRecording();
        }
      } else {
        if (_isRecording && _isDiaryMode) stopRecording();
      }
    }
  }

  // REFACTORED AUDIO PIPELINE
  Future<void> startRecording() async {
    _log("Start Recording Called");
    
    // 1. PERMISSION CHECK (Using record package, not permission_handler)
    // permission_handler was found to BLOCK indefinitely on macOS.
    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
        _log("Permission DENIED by record.hasPermission().");
        _statusController.add("需要麦克风权限");
        return;
    }

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

    // 2. UI FEEDBACK (Show Immediately)
    // 2. UI FEEDBACK (Show Immediately)
    try { 
       if (_isDiaryMode) {
         _overlayChannel.invokeMethod('updateStatus', {"text": "📝 Note..."});
         _overlayChannel.invokeMethod('showRecording'); 
       } else {
         _overlayChannel.invokeMethod('showRecording'); 
       }
    } catch (e) {/*ignore*/}

    // 3. AUDIO INIT
    try {
        // CRITICAL: Start ASR Provider FIRST (Creates internal stream)
        if (_asrProvider == null || !_asrProvider!.isReady) {
            _log("ASR Provider not ready!");
            _cleanupRecordingState();
            _statusController.add("引擎未就绪");
            return;
        }
        await _asrProvider!.start();
        _startTime = DateTime.now(); // Mark start time for Metering
        _log("ASR Provider Started.");
        
        if (await _audioRecorder.isRecording()) {
            await _audioRecorder.stop();
        }
        
        InputDevice? device;
        if (_deviceCacheValid && _cachedInputDevice != null) {
            device = _cachedInputDevice;
            _log("Using Cached Device: ${device?.label ?? 'Unknown'}");
        } else {
            device = null; // OS Default
            _log("Using System Default Device");
        }

        await _attemptStartStream(device);

    } catch (e) {
        _log("Start Fatal Error: $e");
        _cleanupRecordingState();
        _statusController.add("启动失败");
    }
  }

  // Mutex for stopping state
  bool _isStopping = false;
  bool _audioStarted = false;

  Future<void> _attemptStartStream(InputDevice? device) async {
      _log("Stream Request: Device=${device?.label ?? 'OS Default'}, Rate=16000, Mode=Standard");
      
      try {
        final stream = await _audioRecorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000, 
            numChannels: 1,
            device: device,
            echoCancel: false, 
            autoGain: false, 
            noiseSuppress: false,
          ),
        );
        _audioStarted = true;
        _log("Stream Started (16k Standard).");

        stream.listen((data) {
           _processAudioData(data);
        }, onError: (e) {
          _log("Stream Error: $e");
          _cleanupRecordingState();
          _statusController.add("麦克风错误");
        }, onDone: () {
          _log("Stream Closed");
          if (_isRecording) _cleanupRecordingState();
        });
      } catch (e) {
         _log("Stream Creation Failed: $e");
         _cleanupRecordingState();
         _statusController.add("麦克风初始化失败");
      }
  }
  
  void _processAudioData(Uint8List data) {
    if (!_isRecording) return;
    
    // RAW 16k Int16 -> Float32 with DIGITAL GAIN
    final int sampleCount = data.length ~/ 2;
    final floatSamples = Float32List(sampleCount);
    final byteData = ByteData.sublistView(data);
    
    // GAIN CONFIGURATION (8x = +18dB)
    const double digitalGain = 8.0; 
    
    double energy = 0;

    for (int i = 0; i < sampleCount; i++) {
        double sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
        sample *= digitalGain;
        if (sample > 1.0) sample = 1.0;
        if (sample < -1.0) sample = -1.0;
        floatSamples[i] = sample;
        energy += sample * sample;
    }
    
    // RMS Log
    if (DateTime.now().millisecond < 20) {
       _log("RMS: ${(energy / sampleCount).toStringAsFixed(5)} [Gain: ${digitalGain}x]");
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
     _recordingController.add(false);
     _recordingController.add(false);
     try { _overlayChannel.invokeMethod('hideRecording'); } catch(e) {}
     _isDiaryMode = false;
  }

  Future<void> _stopAudioSafely() async {
    if (_audioStarted) {
      try {
        await _audioRecorder.stop();
        _audioStarted = false;
      } catch (e) { _log("Stop Audio Error: $e"); }
    }
  }

  Future<void> stopRecording() async {
    _isStopping = true;
    _isRecording = false;
    
    _recordingController.add(false); 
    _statusController.add("处理中...");
    
    try { await _overlayChannel.invokeMethod('hideRecording'); } catch (_) {}
    
    try { await _overlayChannel.invokeMethod('hideRecording'); } catch (_) {}
    
    await Future.delayed(const Duration(milliseconds: 500)); // Increased from 200ms to 500ms
    
    await _stopAudioSafely();
    
    try { await _audioDumpSink?.close(); _audioDumpSink = null; } catch(_) {}
    
    _isStopping = false;
    
    if (_asrProvider != null) {
      String text = "";
      try {
        text = await _asrProvider!.stop();
        
        // METERING LOGIC: Track Usage
        if (_asrProvider is AliyunProvider && _startTime != null) {
           final duration = DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
           final taskId = (_asrProvider as AliyunProvider).taskId ?? "unknown";
           MeteringService().trackUsage(duration, taskId);
           _startTime = null; // reset
        }
      } catch (e) {
        _log("Provider Stop Error: $e");
      }
      _log("Raw Text: '$text'");
      
      String finalText = text;

      // AI Correction Logic
      if (text.isNotEmpty && ConfigService().aiCorrectionEnabled) {
         _statusController.add("AI 优化中...");
         try { await _overlayChannel.invokeMethod('updateStatus', {"text": "🤖 AI Optimizing..."}); } catch(_) {}
         
         try {
            finalText = await LLMService().correctText(text);
            _log("LLM Result: '$finalText'");
         } catch(e) {
            _log("Ai Correction Error: $e");
         }
      }
      
      // Fallback: Local Punctuation
      // Strategy: Trust LLM first. Only use local model if LLM failed to provide terminal punctuation.
      // AND only if using Local Engine (Sherpa). Cloud engines usually provide punctuation.
      final bool isLocalEngine = ConfigService().asrEngineType == 'sherpa';
      
      if (text.isNotEmpty && _punctuationEnabled && isLocalEngine) {
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
            ChatService().addInfo(finalText);
            
            // 2. Parallel: Analyze intent for MCP commands
           AgentService().process(finalText);
        } else {
           // STANDARD MODE: Inject
           _statusController.add("Ready");
           _nativeInput.inject(finalText);
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
