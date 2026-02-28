import 'dart:async';
import 'dart:typed_data';
import 'package:speakout/engine/asr_provider.dart';

/// Fake ASR provider with programmable results.
/// Extracted from integration_test.dart for reuse.
class FakeASRProvider implements ASRProvider {
  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  bool isInitialized = false;
  List<Float32List> receivedSamples = [];

  /// The text that [stop] will return. Override to customize.
  String stopResult = 'Final transcription result';

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'fake_asr';

  @override
  bool get isReady => isInitialized;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    isInitialized = true;
  }

  @override
  Future<void> start() async {}

  @override
  void acceptWaveform(Float32List samples) {
    receivedSamples.add(samples);
    if (receivedSamples.length % 5 == 0) {
      _textController.add('partial text ${receivedSamples.length}');
    }
  }

  @override
  Future<String> stop() async => stopResult;

  @override
  Future<void> dispose() async {
    if (!_textController.isClosed) {
      await _textController.close();
    }
    isInitialized = false;
  }
}
