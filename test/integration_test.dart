import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/asr_provider.dart';
import 'dart:typed_data';
import 'dart:async';

// === MOCKS ===

class FakeASRProvider implements ASRProvider {
  final StreamController<String> _textController = StreamController<String>.broadcast();
  bool isInitialized = false;
  List<Float32List> receivedSamples = [];
  
  @override
  Stream<String> get textStream => _textController.stream;
  
  @override
  String get type => "fake_asr";
  
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
    // Simulate partial results
    if (receivedSamples.length % 5 == 0) {
      _textController.add("partial text ${receivedSamples.length}");
    }
  }

  @override
  Future<String> stop() async {
    return "Final transcription result";
  }

  @override
  Future<void> dispose() async {
    await _textController.close();
    isInitialized = false;
  }
}

// === TESTS ===

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ASR Provider Tests', () {
    test('acceptWaveform with empty samples', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      
      // Should not throw
      provider.acceptWaveform(Float32List(0));
      expect(provider.receivedSamples.length, 1);
      expect(provider.receivedSamples[0].isEmpty, isTrue);
      
      await provider.dispose();
    });

    test('acceptWaveform with very large samples (10 seconds)', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      
      // 10 seconds of audio at 16kHz = 160000 samples
      final largeSamples = Float32List(160000);
      
      // Should not throw
      provider.acceptWaveform(largeSamples);
      expect(provider.receivedSamples.length, 1);
      expect(provider.receivedSamples[0].length, 160000);
      
      await provider.dispose();
    });

    test('Rapid partial results emission', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      
      final results = <String>[];
      provider.textStream.listen((text) => results.add(text));
      
      // Send 25 waveforms to trigger 5 partial results
      for (int i = 0; i < 25; i++) {
        provider.acceptWaveform(Float32List(1600));
      }
      
      // Wait for async stream delivery
      await Future.delayed(Duration(milliseconds: 50));
      
      expect(results.length, 5);
      expect(results.last, contains("25"));
      
      await provider.dispose();
    });

    test('ASRProvider handles stop returning correct result', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      await provider.start();
      
      provider.acceptWaveform(Float32List(1600));
      
      final result = await provider.stop();
      expect(result, "Final transcription result");
      
      await provider.dispose();
    });
  });

  group('Stress Tests', () {
    test('Rapid provider init/dispose cycles (50 iterations)', () async {
      for (int i = 0; i < 50; i++) {
        final provider = FakeASRProvider();
        await provider.initialize({});
        provider.acceptWaveform(Float32List(1600));
        await provider.dispose();
      }
      // If we get here without exception, test passes
      expect(true, isTrue);
    });

    test('Many waveforms in single session', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      
      // Simulate 5 minutes of audio (300 x 100ms chunks)
      for (int i = 0; i < 300; i++) {
        provider.acceptWaveform(Float32List(1600));
      }
      
      expect(provider.receivedSamples.length, 300);
      
      final result = await provider.stop();
      expect(result, isNotEmpty);
      
      await provider.dispose();
    });
  });

  group('Edge Cases', () {
    test('ASRProvider handles multiple dispose calls', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      
      // First dispose
      await provider.dispose();
      
      // Second dispose should not throw
      // (StreamController.close() is idempotent)
      try {
        await provider.dispose();
      } catch (e) {
        // Expected: stream already closed
      }
      
      expect(provider.isReady, isFalse);
    });

    test('ASRProvider stop returns value without start', () async {
      final provider = FakeASRProvider();
      await provider.initialize({});
      // Don't call start()
      
      final result = await provider.stop();
      expect(result, isNotEmpty);
      
      await provider.dispose();
    });
  });
}
