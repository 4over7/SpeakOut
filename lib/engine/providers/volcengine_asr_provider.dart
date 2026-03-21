import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';

/// 火山引擎 Seed-ASR Provider (V3 BigModel)
///
/// WebSocket 协议：自定义二进制帧 (4B Header + 4B PayloadSize + Payload)。
/// 鉴权：HTTP Headers (X-Api-App-Key, X-Api-Access-Key, X-Api-Resource-Id)。
/// 文档：https://www.volcengine.com/docs/6561/1354869
class VolcengineASRProvider implements ASRProvider {
  IOWebSocketChannel? _channel;
  StreamController<String> _textController = StreamController<String>.broadcast();

  late String _apiKey;

  bool _isReady = false;
  bool _isConnected = false;
  bool _handshakeDone = false;

  // Audio buffering before handshake completes
  final List<Uint8List> _pendingBuffer = [];
  static const int _maxPendingBuffers = 200;

  // Result tracking
  String _finalText = '';
  String? _errorMessage;
  Completer<ASRResult>? _stopCompleter;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'volcengine_asr';

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _apiKey = config['apiKey'] as String? ?? '';

    if (_apiKey.isEmpty) {
      throw Exception('Volcengine ASR: apiKey required');
    }

    _isReady = true;
    _log('Initialized');
  }

  @override
  Future<void> start() async {
    _finalText = '';
    _errorMessage = null;
    _handshakeDone = false;
    _pendingBuffer.clear();
    _isConnected = false;
    _stopCompleter = Completer<ASRResult>();

    const url = 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel';
    _log('Connecting to Volcengine ASR...');

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: {
          'X-Api-Key': _apiKey,
          'X-Api-Resource-Id': 'volc.seedasr.sauc.duration',
        },
      );
      _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          _log('WebSocket error: $e');
          _errorMessage = e.toString();
          _finishStop();
        },
        onDone: () {
          _log('WebSocket closed');
          _finishStop();
        },
      );
      _isConnected = true;

      // Send FullClientRequest (handshake with config)
      _sendFullClientRequest();
    } catch (e) {
      _log('Connection failed: $e');
      _errorMessage = e.toString();
    }
  }

  @override
  void acceptWaveform(Float32List samples) {
    final pcm = _float32ToInt16Bytes(samples);

    if (_isConnected && _handshakeDone && _channel != null) {
      _sendAudioFrame(pcm, isLast: false);
    } else if (_pendingBuffer.length < _maxPendingBuffers) {
      _pendingBuffer.add(pcm);
    }
  }

  @override
  Future<ASRResult> stop() async {

    if (_channel != null && _isConnected) {
      // Send last audio frame with finish flag
      try {
        _sendAudioFrame(Uint8List(0), isLast: true);
      } catch (_) {}
    }

    return (_stopCompleter?.future ?? Future.value(_buildResult())).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _log('Stop timeout');
        return _buildResult();
      },
    );
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    _isConnected = false;
    _handshakeDone = false;
    _pendingBuffer.clear();
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }

  // ── 二进制帧协议 ──

  // Header byte layout (V3 protocol):
  // Byte 0: version(4bit) | header_size(4bit)  → 0x11 (v1, 1 word header)
  // Byte 1: message_type(4bit) | flags(4bit)
  // Byte 2: serialization(4bit) | compression(4bit)
  // Byte 3: reserved → 0x00

  // Message types:
  static const int _msgFullClient = 0x1;   // FullClientRequest (JSON config + first audio)
  static const int _msgAudioOnly = 0x2;    // AudioOnlyRequest (audio data)
  static const int _msgServerResponse = 0x9; // Server response
  static const int _msgServerError = 0xF;   // Server error

  // Serialization: 0x1 = JSON
  // Compression: 0x0 = none, 0x1 = gzip

  Uint8List _buildFrame(int msgType, int flags, Uint8List payload, {int serialization = 0x1, int compression = 0x0}) {
    final headerSize = 1; // 1 word = 4 bytes
    final byte0 = (0x1 << 4) | (headerSize & 0xF);
    final byte1 = ((msgType & 0xF) << 4) | (flags & 0xF);
    final byte2 = ((serialization & 0xF) << 4) | (compression & 0xF);
    final byte3 = 0x00;

    final payloadSize = payload.length;
    final frame = ByteData(4 + 4 + payloadSize);
    frame.setUint8(0, byte0);
    frame.setUint8(1, byte1);
    frame.setUint8(2, byte2);
    frame.setUint8(3, byte3);
    frame.setUint32(4, payloadSize, Endian.big);

    for (int i = 0; i < payloadSize; i++) {
      frame.setUint8(8 + i, payload[i]);
    }

    return frame.buffer.asUint8List();
  }

  void _sendFullClientRequest() {
    final inputLang = ConfigService().inputLanguage;
    String language = 'zh-CN';
    if (inputLang == 'en') language = 'en-US';

    final config = {
      'user': {'uid': 'speakout_user'},
      'audio': {
        'format': 'pcm',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
        'language': language,
      },
      'request': {
        'model_name': 'bigmodel',
        'enable_punc': true,
        'result_type': 'single',
      },
    };

    final jsonPayload = Uint8List.fromList(utf8.encode(jsonEncode(config)));
    // FullClientRequest: msgType=0x1, flags=0b0000 (not last)
    final frame = _buildFrame(_msgFullClient, 0x0, jsonPayload);
    _channel!.sink.add(frame);
    _log('Sent FullClientRequest');

    // 假设握手成功（V3 协议在首帧响应中确认）
    _handshakeDone = true;

    // Flush pending audio
    for (final buf in _pendingBuffer) {
      _sendAudioFrame(buf, isLast: false);
    }
    _pendingBuffer.clear();
  }

  void _sendAudioFrame(Uint8List pcm, {required bool isLast}) {
    final flags = isLast ? 0x2 : 0x0; // 0b0010 = last frame
    // AudioOnly: msgType=0x2, serialization=0 (raw audio), compression=0
    final frame = _buildFrame(_msgAudioOnly, flags, pcm, serialization: 0x0);
    try {
      _channel!.sink.add(frame);
    } catch (_) {}
  }

  // ── 接收响应 ──

  void _onMessage(dynamic message) {
    if (message is! List<int>) {
      _log('Unexpected text message: $message');
      return;
    }

    final data = Uint8List.fromList(message);
    if (data.length < 8) return;

    final byte1 = data[1];
    final msgType = (byte1 >> 4) & 0xF;
    final byte2 = data[2];
    final compression = byte2 & 0xF;

    final payloadSize = ByteData.sublistView(data, 4, 8).getUint32(0, Endian.big);
    if (data.length < 8 + payloadSize) return;

    var payload = data.sublist(8, 8 + payloadSize);

    // Decompress if gzip
    if (compression == 0x1) {
      try {
        payload = Uint8List.fromList(gzip.decode(payload));
      } catch (e) {
        _log('Gzip decompress failed: $e');
        return;
      }
    }

    if (msgType == _msgServerError) {
      try {
        final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
        _errorMessage = json['message'] as String? ?? 'Server error';
        _log('Server error: $_errorMessage');
      } catch (_) {
        _errorMessage = 'Server error (unparseable)';
      }
      _finishStop();
      return;
    }

    if (msgType == _msgServerResponse) {
      try {
        final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
        _processResponse(json);
      } catch (e) {
        _log('Response parse error: $e');
      }
    }
  }

  void _processResponse(Map<String, dynamic> json) {
    final resultList = json['result'] as List?;
    if (resultList == null || resultList.isEmpty) return;

    final result = resultList[0] as Map<String, dynamic>;
    final text = result['text'] as String? ?? '';
    final type = json['type'] as String? ?? '';

    if (type == 'final' || type == 'interim') {
      _finalText = text;
      _textController.add(text);
    }

    if (type == 'final') {
      _log('Final result: ${text.length} chars');
    }

    // 检查是否结束
    final isEnd = json['is_end'] as bool? ?? false;
    if (isEnd) {
      _log('Recognition complete');
      _finishStop();
    }
  }

  void _finishStop() {
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete(_buildResult());
    }
    _isConnected = false;
    try { _channel?.sink.close(); } catch (_) {}
  }

  ASRResult _buildResult() {
    if (_errorMessage != null) {
      return ASRResult(text: _finalText, error: _errorMessage);
    }
    return ASRResult.textOnly(_finalText);
  }

  Uint8List _float32ToInt16Bytes(Float32List samples) {
    final bytes = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(i * 2, (s * 32767).toInt(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  void _log(String msg) => AppLog.d('[VolcengineASR] $msg');
}
