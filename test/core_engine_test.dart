import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:speakout/engine/core_engine.dart';
import 'package:speakout/ffi/native_input_base.dart';

import 'package:record/record.dart';
import 'dart:typed_data';

// Annotations to generate Mocks (unused here as we manually fake to handle specific ABI issues)
@GenerateMocks([AudioRecorder])
class MockNativeInput extends Mock implements NativeInputBase {
  @override
  bool checkPermission() => true;
  @override
  bool startListener(dynamic callback) => true; 
}

// Manually implementing MockNativeInput
class FakeNativeInput implements NativeInputBase {
  bool permission = true;
  bool listenerStarted = false;
  String? lastInjected;

  @override
  bool checkPermission() => permission;

  @override
  void inject(String text) {
    lastInjected = text;
  }

  @override
  bool startListener(dynamic callback) {
    listenerStarted = true;
    return true;
  }

  @override
  void stopListener() {
    listenerStarted = false;
  }
}

class FakeAudioRecorder extends Mock implements AudioRecorder {
  bool hasPerm = true;
  bool recording = false;
  
  @override
  Future<bool> hasPermission() async => hasPerm;
  
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    recording = true;
    return const Stream.empty(); 
  }
  
  @override
  Future<String?> stop() async {
    recording = false;
    return null; // Stop returns path usually
  }
  
  @override
  Future<void> dispose() async {}
}

void main() {
  late CoreEngine engine;
  late FakeNativeInput mockInput;
  late FakeAudioRecorder mockRecorder;

  setUp(() {
    mockInput = FakeNativeInput();
    mockRecorder = FakeAudioRecorder();
    engine = CoreEngine.test(mockInput, mockRecorder);
    CoreEngine.setInstanceForTesting(engine);
  });

  test('Init emits status events', () async {
    // Assert status stream emits messages
    expectLater(engine.statusStream, emitsThrough(contains("Trusted")));
    await engine.init();
  });

  test('Init checks permission and starts listener', () async {
    await engine.init();
    expect(mockInput.listenerStarted, isTrue);
  });
}
