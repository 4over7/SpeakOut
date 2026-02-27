import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../asr_provider.dart';

/// Offline (non-streaming) ASR Provider using sherpa-onnx OfflineRecognizer.
///
/// Accumulates audio during recording, then performs batch recognition on stop().
/// Higher accuracy than streaming for PTT workflows.
class OfflineSherpaProvider implements ASRProvider {
  sherpa.OfflineRecognizer? _recognizer;
  bool _isInit = false;

  // Accumulate audio chunks during recording
  final List<Float32List> _audioChunks = [];

  StreamController<String> _textController = StreamController<String>.broadcast();

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => "local_sherpa_offline";

  @override
  bool get isReady => _isInit && _recognizer != null;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    final modelPath = config['modelPath'] as String;
    final modelType = config['modelType'] as String? ?? 'sense_voice';

    // Ensure cleanup before re-init
    await dispose();

    _initSherpaBindings();

    sherpa.OfflineModelConfig modelConfig;

    if (modelType == 'sense_voice') {
      modelConfig = sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: "$modelPath/model.int8.onnx",
          useInverseTextNormalization: true,
        ),
        tokens: "$modelPath/tokens.txt",
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else if (modelType == 'whisper') {
      final encoder = _findFile(modelPath, "encoder");
      final decoder = _findFile(modelPath, "decoder");
      modelConfig = sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: "zh",
          task: "transcribe",
        ),
        tokens: _findTokens(modelPath),
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else if (modelType == 'fire_red_asr') {
      final encoder = _findFile(modelPath, "encoder");
      final decoder = _findFile(modelPath, "decoder");
      modelConfig = sherpa.OfflineModelConfig(
        fireRedAsr: sherpa.OfflineFireRedAsrModelConfig(
          encoder: encoder,
          decoder: decoder,
        ),
        tokens: "$modelPath/tokens.txt",
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else {
      // offline_paraformer
      modelConfig = sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(
          model: "$modelPath/model.int8.onnx",
        ),
        tokens: "$modelPath/tokens.txt",
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    }

    final recognizerConfig = sherpa.OfflineRecognizerConfig(
      model: modelConfig,
      feat: const sherpa.FeatureConfig(sampleRate: 16000),
    );

    try {
      _recognizer = sherpa.OfflineRecognizer(recognizerConfig);
      _isInit = true;
    } catch (e) {
      _isInit = false;
      throw Exception("Offline Sherpa Init Failed: $e");
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
      debugPrint("[OfflineSherpaProvider] Bindings init warning: $e");
    }
  }

  @override
  Future<void> start() async {
    if (!_isInit || _recognizer == null) throw Exception("Offline Sherpa not initialized");
    _audioChunks.clear();
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_recognizer == null) return;
    // Accumulate audio — no real-time decoding
    _audioChunks.add(Float32List.fromList(samples));
  }

  @override
  Future<String> stop() async {
    if (_recognizer == null) return "";

    try {
      // Merge all audio chunks into a single buffer
      int totalSamples = 0;
      for (final chunk in _audioChunks) {
        totalSamples += chunk.length;
      }

      if (totalSamples == 0) return "";

      final merged = Float32List(totalSamples);
      int offset = 0;
      for (final chunk in _audioChunks) {
        merged.setAll(offset, chunk);
        offset += chunk.length;
      }
      _audioChunks.clear();

      // Create offline stream, feed audio, decode
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: merged, sampleRate: 16000);

      _recognizer!.decode(stream);

      final result = _recognizer!.getResult(stream);
      final text = result.text.trim();

      stream.free();

      // Emit final result on textStream
      if (text.isNotEmpty && !_textController.isClosed) {
        _textController.add(text);
      }

      return text;
    } catch (e) {
      debugPrint("[OfflineSherpaProvider] stop error: $e");
      _audioChunks.clear();
      return "";
    }
  }

  /// Find a file matching [pattern] in [dirPath], preferring int8 variants.
  String _findFile(String dirPath, String pattern) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) throw Exception("Model dir not found: $dirPath");

    final files = dir.listSync();

    // 1. Try int8.onnx
    try {
      final f = files.firstWhere((e) => e.path.contains(pattern) && e.path.endsWith("int8.onnx"));
      return f.path;
    } catch (_) {}

    // 2. Try .onnx (non-weights)
    try {
      final f = files.firstWhere((e) =>
          e.path.contains(pattern) && e.path.endsWith(".onnx") && !e.path.endsWith(".weights"));
      return f.path;
    } catch (_) {}

    throw Exception("Missing file for $pattern in $dirPath");
  }

  /// Find tokens file in [dirPath] (may be prefixed, e.g. large-v3-tokens.txt).
  String _findTokens(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) throw Exception("Model dir not found: $dirPath");

    try {
      final f = dir.listSync().firstWhere((e) => e.path.endsWith("tokens.txt"));
      return f.path;
    } catch (_) {}

    throw Exception("tokens.txt not found in $dirPath");
  }

  @override
  Future<void> dispose() async {
    _audioChunks.clear();
    _recognizer?.free();
    _recognizer = null;
    _isInit = false;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }
}
