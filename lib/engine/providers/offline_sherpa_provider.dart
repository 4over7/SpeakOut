import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';

/// Offline (non-streaming) ASR Provider using sherpa-onnx OfflineRecognizer.
///
/// Accumulates audio during recording, then performs batch recognition on stop().
/// Higher accuracy than streaming for PTT workflows.
class OfflineSherpaProvider implements ASRProvider {
  sherpa.OfflineRecognizer? _recognizer;
  bool _isInit = false;

  // Accumulate audio chunks during recording
  final List<Float32List> _audioChunks = [];


  // Pre-segmented recognition: decode during pauses to reduce final wait time
  final List<String> _segmentResults = [];
  int _lastVoiceChunkIndex = -1;
  bool _isSegmentDecoding = false;

  StreamController<String> _textController = StreamController<String>.broadcast();

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => "local_sherpa_offline";

  @override
  bool get isReady => _isInit && _recognizer != null;

  String _activeModelInfo = '';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    final modelPath = config['modelPath'] as String;
    final modelType = config['modelType'] as String? ?? 'sense_voice';
    _activeModelInfo = '$modelType (${modelPath.split('/').last})';
    AppLog.d("[OfflineSherpaProvider] Initializing: $_activeModelInfo");

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
      final whisperLang = ConfigService().inputLanguage;
      modelConfig = sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: whisperLang == 'auto' ? '' : whisperLang,
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
    } else if (modelType == 'funasr_nano') {
      final encoderAdaptor = _findFile(modelPath, "encoder_adaptor");
      final llm = _findFile(modelPath, "llm");
      final embedding = _findFile(modelPath, "embedding");
      // tokenizer.json 在 Qwen3-0.6B/ 子目录里，递归查找
      final tokenizerFile = _findFileRecursive(modelPath, "tokenizer.json");
      AppLog.d("[OfflineSherpaProvider] FunASR Nano paths: encoderAdaptor=$encoderAdaptor, llm=$llm, embedding=$embedding, tokenizer=$tokenizerFile");
      modelConfig = sherpa.OfflineModelConfig(
        funasrNano: sherpa.OfflineFunAsrNanoModelConfig(
          encoderAdaptor: encoderAdaptor,
          llm: llm,
          embedding: embedding,
          tokenizer: tokenizerFile,
        ),
        tokens: "",
        numThreads: 2,
        provider: "cpu",
        debug: true,
      );
    } else if (modelType == 'fire_red_asr_ctc') {
      final model = _findFile(modelPath, "model");
      modelConfig = sherpa.OfflineModelConfig(
        fireRedAsrCtc: sherpa.OfflineFireRedAsrCtcModelConfig(
          model: model,
        ),
        tokens: "$modelPath/tokens.txt",
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else if (modelType == 'moonshine') {
      // Moonshine 中文版文件: encoder_model.ort + decoder_model_merged.ort
      // 标准 Moonshine: preprocessor.onnx + encoder.onnx + uncached_decoder.onnx + cached_decoder.onnx
      final encoder = _findFileAny(modelPath, ["preprocess", "encoder_model", "encoder"]);
      final decoder = _findFileAny(modelPath, ["decoder_model_merged", "uncached"]);
      // 如果是 merged decoder 格式（只有 encoder + merged decoder），用 mergedDecoder
      final isMergedFormat = decoder.contains("merged");
      modelConfig = sherpa.OfflineModelConfig(
        moonshine: sherpa.OfflineMoonshineModelConfig(
          preprocessor: isMergedFormat ? "" : encoder,
          encoder: isMergedFormat ? encoder : _findFileAny(modelPath, ["encode"]),
          uncachedDecoder: isMergedFormat ? "" : decoder,
          cachedDecoder: isMergedFormat ? "" : _findFileAny(modelPath, ["cached"]),
          mergedDecoder: isMergedFormat ? decoder : "",
        ),
        tokens: _findTokens(modelPath),
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else if (modelType == 'telespeech_ctc') {
      final model = _findFile(modelPath, "model");
      modelConfig = sherpa.OfflineModelConfig(
        telespeechCtc: model,
        tokens: "$modelPath/tokens.txt",
        numThreads: 2,
        provider: "cpu",
        debug: false,
      );
    } else if (modelType == 'dolphin') {
      final model = _findFile(modelPath, "model");
      modelConfig = sherpa.OfflineModelConfig(
        dolphin: sherpa.OfflineDolphinModelConfig(
          model: model,
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
      AppLog.d("[OfflineSherpaProvider] Bindings init warning: $e");
    }
  }

  @override
  Future<void> start() async {
    if (!_isInit || _recognizer == null) throw Exception("Offline Sherpa not initialized");
    _audioChunks.clear();

    _segmentResults.clear();
    _lastVoiceChunkIndex = -1;
    _isSegmentDecoding = false;
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_recognizer == null) return;
    // Accumulate audio — no real-time decoding
    _audioChunks.add(Float32List.fromList(samples));

  }

  /// Mark current latest chunk as "has voice" (called by CoreEngine silence check)
  void markLastVoiceChunk() {
    if (_audioChunks.isNotEmpty) {
      _lastVoiceChunkIndex = _audioChunks.length - 1;
    }
  }

  /// Pre-segment: decode accumulated audio up to the last voice chunk.
  /// Called when a pause (e.g. 3s silence) is detected during recording.
  /// The cut point is at the pause START (last voice chunk), not the detection moment,
  /// so we never clip into newly resumed speech.
  Future<void> flushSegment() async {
    if (_audioChunks.isEmpty || _isSegmentDecoding || _recognizer == null) return;
    if (_lastVoiceChunkIndex < 0) return;

    _isSegmentDecoding = true;
    try {
      final cutPoint = _lastVoiceChunkIndex + 1;
      if (cutPoint > _audioChunks.length) return;

      // Split: [0..cutPoint) → decode now, [cutPoint..] → keep for next segment
      final segmentChunks = _audioChunks.sublist(0, cutPoint);
      final remainingChunks = _audioChunks.sublist(cutPoint);

      _audioChunks.clear();
      _audioChunks.addAll(remainingChunks);
      _lastVoiceChunkIndex = -1;

      int totalSamples = 0;
      for (final chunk in segmentChunks) {
        totalSamples += chunk.length;
      }

      if (totalSamples == 0) return;

      final merged = Float32List(totalSamples);
      int offset = 0;
      for (final chunk in segmentChunks) {
        merged.setAll(offset, chunk);
        offset += chunk.length;
      }

      final durationSec = (totalSamples / 16000.0).toStringAsFixed(1);
      AppLog.d("[OfflineSherpaProvider] PreSegment #${_segmentResults.length + 1}: "
          "decoding $totalSamples samples (${durationSec}s)...");

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: merged, sampleRate: 16000);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      final text = result.text.trim();
      stream.free();

      if (text.isNotEmpty) {
        _segmentResults.add(text);
        AppLog.d("[OfflineSherpaProvider] PreSegment #${_segmentResults.length}: "
            "(${text.length}字, ${durationSec}s): '$text'");
      }
    } catch (e) {
      AppLog.d("[OfflineSherpaProvider] PreSegment error: $e");
    } finally {
      _isSegmentDecoding = false;
    }
  }

  @override
  Future<ASRResult> stop() async {
    if (_recognizer == null) return ASRResult.textOnly("");

    try {
      // Wait for any in-progress segment decoding to finish
      while (_isSegmentDecoding) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Decode remaining audio (the last segment since the last flush)
      int totalSamples = 0;
      for (final chunk in _audioChunks) {
        totalSamples += chunk.length;
      }

      String lastSegmentText = '';
      if (totalSamples > 0) {
        final durationSec = (totalSamples / 16000.0).toStringAsFixed(1);
        AppLog.d("[OfflineSherpaProvider] Decoding final segment [$_activeModelInfo]: "
            "${_audioChunks.length} chunks, $totalSamples samples (${durationSec}s)");

        final merged = Float32List(totalSamples);
        int offset = 0;
        for (final chunk in _audioChunks) {
          merged.setAll(offset, chunk);
          offset += chunk.length;
        }
        _audioChunks.clear();

        final stream = _recognizer!.createStream();
        stream.acceptWaveform(samples: merged, sampleRate: 16000);
        _recognizer!.decode(stream);
        final result = _recognizer!.getResult(stream);
        lastSegmentText = result.text.trim();
        stream.free();

        final fullDurationSec = durationSec;
        AppLog.d("[OfflineSherpaProvider] Final segment (${lastSegmentText.length}字, ${fullDurationSec}s): '$lastSegmentText'");
      } else {
        _audioChunks.clear();
      }

      // Concatenate all pre-decoded segments + final segment
      final hasPreSegments = _segmentResults.isNotEmpty;
      if (lastSegmentText.isNotEmpty) {
        _segmentResults.add(lastSegmentText);
      }
      final fullText = _segmentResults.join('');
      final segmentCount = _segmentResults.length;
      _segmentResults.clear();

      if (hasPreSegments) {
        AppLog.d("[OfflineSherpaProvider] Merged $segmentCount segments → (${fullText.length}字): '$fullText'");
      } else if (fullText.isNotEmpty) {
        AppLog.d("[OfflineSherpaProvider] Result (${fullText.length}字): '$fullText'");
      } else {
        AppLog.d("[OfflineSherpaProvider] No audio accumulated (0 chunks)");
      }

      // Emit final result on textStream
      if (fullText.isNotEmpty && !_textController.isClosed) {
        _textController.add(fullText);
      }

      return ASRResult(
        text: fullText,
        tokens: [],
        timestamps: [],
        tokenConfidence: null,
      );
    } catch (e) {
      AppLog.d("[OfflineSherpaProvider] stop error: $e");
      _audioChunks.clear();
      _segmentResults.clear();
      return ASRResult.textOnly("");
    }
  }

  /// Find a file matching any of [patterns] in [dirPath], supports .onnx and .ort.
  String _findFileAny(String dirPath, List<String> patterns) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) throw Exception("Model dir not found: $dirPath");
    final files = dir.listSync().whereType<File>().toList();
    for (final pattern in patterns) {
      // Try int8.onnx, .onnx, .ort
      for (final ext in ['.int8.onnx', '.onnx', '.ort']) {
        final match = files.where((f) => f.path.contains(pattern) && f.path.endsWith(ext)).firstOrNull;
        if (match != null) return match.path;
      }
    }
    throw Exception("Missing file for ${patterns.join('/')} in $dirPath");
  }

  /// Find a file by exact name recursively in [dirPath] and subdirectories.
  String _findFileRecursive(String dirPath, String fileName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) throw Exception("Model dir not found: $dirPath");
    // Check root first
    final rootFile = File('$dirPath/$fileName');
    if (rootFile.existsSync()) return rootFile.path;
    // Search subdirectories
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith(fileName)) {
        return entity.path;
      }
    }
    throw Exception("Missing file $fileName in $dirPath (recursive)");
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
    _segmentResults.clear();
    _lastVoiceChunkIndex = -1;
    _isSegmentDecoding = false;
    _recognizer?.free();
    _recognizer = null;
    _isInit = false;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }
}
