import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// Path Config
const dylibPath = "/Users/leon/Apps/speakout/build/macos/Build/Products/Release/SpeakOut.app/Contents/Frameworks";
const modelBasePath = "/Users/leon/Documents/speakout_models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20";
const audioPath = "/tmp/audio_dump.pcm"; // Created by v3.5.18+

void main() async {
  print("=== Offline ASR Analysis Tool ===");
  print("Audio: $audioPath");
  print("Model: $modelBasePath");
  
  if (!File(audioPath).existsSync()) {
    print("Error: Audio file not found. Please run the app and record something first.");
    return;
  }

  // 1. Init Bindings
  try {
    print("Initializing Bindings from: $dylibPath");
    sherpa.initBindings(dylibPath);
  } catch (e) {
    print("Binding Init Failed (ignore if already loaded): $e");
  }

  // 2. Config
  final config = sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: "$modelBasePath/encoder-epoch-99-avg-1.int8.onnx",
        decoder: "$modelBasePath/decoder-epoch-99-avg-1.int8.onnx",
        joiner: "$modelBasePath/joiner-epoch-99-avg-1.int8.onnx",
      ),
      tokens: "$modelBasePath/tokens.txt",
      numThreads: 1,
      provider: "cpu",
      debug: false,
      modelType: "zipformer",
    ),
    feat: const sherpa.FeatureConfig(sampleRate: 16000),
    enableEndpoint: true, // Same as App
  );

  // 3. Create Recognizer
  print("Creating Recognizer...");
  final recognizer = sherpa.OnlineRecognizer(config);
  final stream = recognizer.createStream();

  // 4. Load Audio & Apply Gain
  print("Loading Audio...");
  final bytes = File(audioPath).readAsBytesSync();
  final int16Data = bytes.buffer.asInt16List();
  print("Samples: ${int16Data.length} (${int16Data.length / 16000}s)");

  final floatSamples = Float32List(int16Data.length);
  double energy = 0;
  
  // Apply 5.0x Gain (Same as CoreEngine)
  for (int i = 0; i < int16Data.length; i++) {
    double sample = (int16Data[i] / 32768.0) * 5.0;
    // Hard clip
    if (sample > 1.0) sample = 1.0;
    if (sample < -1.0) sample = -1.0;
    floatSamples[i] = sample;
    energy += sample * sample;
  }
  
  print("Avg RMS (after 5.0x gain): ${energy / floatSamples.length}");

  // 5. Accept & Decode
  print("Decoding...");
  stream.acceptWaveform(samples: floatSamples, sampleRate: 16000);
  
  while (recognizer.isReady(stream)) {
    recognizer.decode(stream);
  }
  
  // 6. Padding (Same as SherpaProvider)
  print("Injecting Silence Padding (0.5s)...");
  final silence = Float32List(8000);
  stream.acceptWaveform(samples: silence, sampleRate: 16000);
  
  stream.inputFinished();
  
  while (recognizer.isReady(stream)) {
    recognizer.decode(stream);
  }

  // 7. Result
  final result = recognizer.getResult(stream);
  print("\n>>> FINAL RESULT: '${result.text}' <<<\n");
  
  stream.free();
}
