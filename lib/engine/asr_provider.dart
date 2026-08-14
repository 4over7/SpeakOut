import 'dart:typed_data';
import 'asr_result.dart';
import '../config/app_constants.dart';

/// Abstract interface for ASR (Automatic Speech Recognition) Providers
///
/// Designed to decouple CoreEngine from specific implementations (Sherpa/Aliyun).
/// Follows strict lifecycle: Initialize -> Start -> Stream Audio -> Stop -> Dispose.
abstract class ASRProvider {

  /// Stream for real-time partial transcription results
  Stream<String> get textStream;

  /// Initialize the engine with configuration
  /// [config] Map containing paths, keys, or other provider-specific settings
  Future<void> initialize(Map<String, dynamic> config);

  /// Start a new recognition session
  Future<void> start();

  /// Feed raw audio samples to the engine
  /// [samples] 16kHz Mono Float32 PCM
  void acceptWaveform(Float32List samples);

  /// Stop recognition and return the final ASR result (text + optional tokens/confidence)
  Future<ASRResult> stop();

  /// CoreEngine 等待 [stop] 的上限。
  ///
  /// 必须 ≥ provider 自己的网络超时，否则 Core 先超时丢弃结果，provider 还在干活 ——
  /// 用户看到的是「说了一段话，什么都没出来」。曾经 Core 固定等 6 秒，而
  /// OpenAI/Groq 批量识别自身超时 30 秒：Whisper 转写稍长的录音必然超 6 秒，
  /// 结果被静默丢掉。
  ///
  /// 默认取流式 provider 的口径；批量识别 provider 必须 override。
  Duration get stopTimeout => AppConstants.kAsrStopTimeout;

  /// Free resources
  Future<void> dispose();

  /// Check if the engine is ready
  bool get isReady;

  /// Get current engine type identifier
  String get type;
}
