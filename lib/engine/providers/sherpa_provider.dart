import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../asr_provider.dart';

class SherpaProvider implements ASRProvider {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _isInit = false;
  
  final StreamController<String> _textController = StreamController<String>.broadcast();
  
  @override
  Stream<String> get textStream => _textController.stream;
  
  @override
  String get type => "local_sherpa";
  
  @override
  bool get isReady => _isInit && _recognizer != null;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    final modelPath = config['modelPath'] as String;
    final modelType = config['modelType'] as String? ?? 'zipformer';
    
    // Ensure cleanup before re-init
    await dispose();
    
    _initSherpaBindings();

    sherpa.OnlineRecognizerConfig recognizerConfig;

    if (modelType == 'paraformer') {
      // Paraformer uses CTC-based decoding, less prone to repetition
      // Use default greedy_search and no blankPenalty
      recognizerConfig = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          paraformer: sherpa.OnlineParaformerModelConfig(
            encoder: "$modelPath/encoder.int8.onnx",
            decoder: "$modelPath/decoder.int8.onnx",
          ),
          tokens: "$modelPath/tokens.txt",
          numThreads: 2,
          provider: "cpu",
          debug: false,
          modelType: "paraformer",
        ),
        feat: const sherpa.FeatureConfig(sampleRate: 16000),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.2,
        rule3MinUtteranceLength: 20,
      );
    } else {
      // Default: Zipformer
      recognizerConfig = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: _findFile(modelPath, "encoder"),
            decoder: _findFile(modelPath, "decoder"),
            joiner: _findFile(modelPath, "joiner"),
          ),
          tokens: "$modelPath/tokens.txt",
          numThreads: 2,
          provider: "cpu",
          debug: false,
          modelType: "zipformer",
        ),
        feat: const sherpa.FeatureConfig(sampleRate: 16000),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.2,
        rule3MinUtteranceLength: 20,
        // Anti-repetition tuning
        decodingMethod: 'modified_beam_search',
        maxActivePaths: 4,
        blankPenalty: 5.0,
      );
    }
    
    try {
      _recognizer = sherpa.OnlineRecognizer(recognizerConfig);
      _isInit = true;
    } catch (e) {
      _isInit = false;
      throw Exception("Sherpa Init Failed: $e");
    }
  }
  
  void _initSherpaBindings() {
    try {
       final exeDir = File(Platform.resolvedExecutable).parent;
       final libFile = File("${exeDir.parent.path}/Frameworks/libsherpa-onnx-c-api.dylib");
       
       if (libFile.existsSync()) {
          sherpa.initBindings(libFile.parent.path);
       } else {
          sherpa.initBindings(); 
       }
    } catch (e) {
      print("[SherpaProvider] Bindings init warning: $e");
    }
  }

  @override
  Future<void> start() async {
    if (!_isInit || _recognizer == null) throw Exception("Sherpa not initialized");
    _stream = _recognizer!.createStream();
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_stream == null || _recognizer == null) return;
    
    try {
      _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
      
      // Active Decoding Loop
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      
      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _textController.add(result.text); // Emit partial result
      }
    } catch (e) {
      // Prevent FFI exceptions from crashing the app
      print("[SherpaProvider] acceptWaveform error: $e");
    }
  }

  @override
  Future<String> stop() async {
    if (_stream == null || _recognizer == null) return "";
    
    try {
      // Inject silence padding for Sherpa's decoder quirks
      // Padding (Increased to 0.8s to fix tail truncation)
      final silence = Float32List(12800); // 0.8s @ 16k
      acceptWaveform(silence);
      
      _stream!.inputFinished();
      
      // Final Decode
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      
      final result = _recognizer!.getResult(_stream!);
      final text = result.text.trim();
      
      _stream!.free();
      _stream = null;
      
      return text;
    } catch (e) {
      print("[SherpaProvider] stop error: $e");
      // Cleanup on error
      try { _stream?.free(); } catch (_) {}
      _stream = null;
      return "";
    }
  }

  String _findFile(String dirPath, String pattern) {
     final dir = Directory(dirPath);
     if (!dir.existsSync()) throw Exception("Model dir not found: $dirPath");
     
     // Specific precedence: int8 > onnx
     final files = dir.listSync();
     
     // 1. Try finding pattern + int8.onnx (preferred)
     try {
       final f = files.firstWhere((e) => e.path.contains(pattern) && e.path.endsWith("int8.onnx"));
       return f.path;
     } catch (_) {}

     // 2. Try finding pattern + .onnx
     try {
       final f = files.firstWhere((e) => e.path.contains(pattern) && e.path.endsWith(".onnx"));
       return f.path;
     } catch (_) {}
     
     throw Exception("Missing file for $pattern in $dirPath");
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
    _isInit = false;
    _textController.close();
  }
}
