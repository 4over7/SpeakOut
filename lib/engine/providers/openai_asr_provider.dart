import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';

/// OpenAI / Groq Whisper ASR Provider (Non-streaming)
///
/// 支持 OpenAI Whisper, GPT-4o Transcribe, Groq Whisper 等。
/// 非流式：acceptWaveform() 累积音频，stop() 时 POST 到 REST API。
/// 兼容所有 OpenAI audio/transcriptions API 格式的服务。
class OpenAIASRProvider implements ASRProvider {
  StreamController<String> _textController = StreamController<String>.broadcast();

  late String _apiKey;
  late String _baseUrl;
  late String _model;

  bool _isReady = false;

  // Audio accumulation (16kHz mono Float32 PCM)
  final List<Float32List> _audioChunks = [];
  int _totalSamples = 0;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'openai_asr';

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _apiKey = config['apiKey'] as String? ?? '';
    _baseUrl = config['baseUrl'] as String? ?? 'https://api.openai.com/v1';
    _model = config['model'] as String? ?? 'whisper-1';

    if (_apiKey.isEmpty) throw Exception('API Key missing');

    _isReady = true;
    _log('Initialized (model=$_model, baseUrl=$_baseUrl)');
  }

  @override
  Future<void> start() async {
    _audioChunks.clear();
    _totalSamples = 0;
  }

  @override
  void acceptWaveform(Float32List samples) {
    _audioChunks.add(Float32List.fromList(samples));
    _totalSamples += samples.length;
  }

  @override
  Future<ASRResult> stop() async {
    if (_totalSamples == 0) return ASRResult.textOnly('');

    _log('Encoding ${_totalSamples} samples to WAV...');
    final wav = _encodeWav();
    _audioChunks.clear();
    _totalSamples = 0;

    _log('Uploading ${wav.length} bytes to $_baseUrl/audio/transcriptions...');

    try {
      final uri = Uri.parse('$_baseUrl/audio/transcriptions');
      final inputLang = ConfigService().inputLanguage;
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $_apiKey'
        ..fields['model'] = _model
        ..fields['response_format'] = 'json';
      // Only send language hint when explicitly set (auto = let Whisper detect)
      if (inputLang != 'auto') {
        // Map app lang codes to Whisper ISO-639-1 codes
        request.fields['language'] = switch (inputLang) {
          'zh' => 'zh',
          'en' => 'en',
          'ja' => 'ja',
          'ko' => 'ko',
          'yue' => 'zh', // Whisper doesn't have separate Cantonese code
          _ => inputLang,
        };
      }
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        wav,
        filename: 'audio.wav',
      ));

      final response = await request.send().timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        _log('API error ${response.statusCode}: $body');
        return ASRResult.textOnly('');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final text = json['text'] as String? ?? '';
      _log('Result: ${text.length} chars');
      _textController.add(text);
      return ASRResult.textOnly(text);
    } catch (e) {
      _log('Request failed: $e');
      return ASRResult.textOnly('');
    }
  }

  /// Encode accumulated Float32 PCM samples to WAV (16kHz mono 16-bit)
  Uint8List _encodeWav() {
    const sampleRate = 16000;
    const bitsPerSample = 16;
    const numChannels = 1;
    final dataSize = _totalSamples * 2; // 16-bit = 2 bytes per sample
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);
    int offset = 0;

    // RIFF header
    void writeStr(String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset++, s.codeUnitAt(i));
      }
    }
    writeStr('RIFF');
    buffer.setUint32(offset, fileSize - 8, Endian.little); offset += 4;
    writeStr('WAVE');

    // fmt sub-chunk
    writeStr('fmt ');
    buffer.setUint32(offset, 16, Endian.little); offset += 4; // sub-chunk size
    buffer.setUint16(offset, 1, Endian.little); offset += 2; // PCM format
    buffer.setUint16(offset, numChannels, Endian.little); offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little); offset += 4;
    buffer.setUint32(offset, sampleRate * numChannels * bitsPerSample ~/ 8, Endian.little); offset += 4;
    buffer.setUint16(offset, numChannels * bitsPerSample ~/ 8, Endian.little); offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little); offset += 2;

    // data sub-chunk
    writeStr('data');
    buffer.setUint32(offset, dataSize, Endian.little); offset += 4;

    // PCM data (Float32 → Int16)
    for (final chunk in _audioChunks) {
      for (int i = 0; i < chunk.length; i++) {
        final s = chunk[i].clamp(-1.0, 1.0);
        buffer.setInt16(offset, (s * 32767).toInt(), Endian.little);
        offset += 2;
      }
    }

    return buffer.buffer.asUint8List();
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    _audioChunks.clear();
    _totalSamples = 0;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }

  void _log(String msg) => AppLog.d('[OpenAIASR] $msg');
}
