import 'dart:typed_data';

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
  
  /// Stop recognition and return the final text result
  Future<String> stop();
  
  /// Free resources
  Future<void> dispose();
  
  /// Check if the engine is ready
  bool get isReady;
  
  /// Get current engine type identifier
  String get type;
}
