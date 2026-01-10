import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/asr_provider.dart';

// Mock Implementation to verify interface stability
class MockCloudProvider implements ASRProvider {
  final _controller = StreamController<String>();
  bool startCalled = false;
  bool stopCalled = false;
  List<Float32List> audioChunks = [];

  @override
  Stream<String> get textStream => _controller.stream;

  @override
  String get type => "mock_cloud";
  
  @override
  bool get isReady => true;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Mock init
  }

  @override
  Future<void> start() async {
    startCalled = true;
    _controller.add("Started");
  }

  @override
  void acceptWaveform(Float32List samples) {
    audioChunks.add(samples);
    // Simulate cloud return
    _controller.add("Received ${samples.length} samples");
  }

  @override
  Future<String> stop() async {
    stopCalled = true;
    return "Final Result";
  }

  @override
  Future<void> dispose() async {
    _controller.close();
  }
}

void main() {
  group('ASRProvider Contract', () {
    late MockCloudProvider provider;

    setUp(() {
      provider = MockCloudProvider();
    });

    test('should handle lifecycle', () async {
      await provider.initialize({});
      expect(provider.isReady, true);
      
      await provider.start();
      expect(provider.startCalled, true);
      
      provider.acceptWaveform(Float32List(1600));
      expect(provider.audioChunks.length, 1);
      
      // Verify stream emission
      expectLater(provider.textStream, emitsInOrder(["Started", "Received 1600 samples"]));
      
      final result = await provider.stop();
      expect(result, "Final Result");
      expect(provider.stopCalled, true);
    });
  });
}
