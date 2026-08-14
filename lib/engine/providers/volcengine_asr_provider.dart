import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';
import '../../config/app_constants.dart';

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
  int _frameDebugCount = 0;
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

  /// 流式识别：结果随说话陆续回来，stop 只等最后一帧，用全局默认即可。
  @override
  Duration get stopTimeout => AppConstants.kAsrStopTimeout;

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
        // 用 full 而非 single：官方对 single 的定义是「增量结果返回，即不返回之前分句的结果」，
        // 而本类是覆盖式赋值（_finalText = text），只在累积语义下才成立。
        // 文档另一处又称 result.text 是「整个音频的识别结果文本」，两处说法打架；
        // full 是全量返回、语义无歧义，代价只是每帧多传些字节。
        'result_type': 'full',
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

    // 服务端响应带序列号。实测帧布局（火山 豆包 Seed-ASR）：
    //   11 91 10 00 | 00 00 00 01 | 00 00 00 6e | 7b 22 ...
    //   └ header 4 ┘ └ sequence 4┘ └ p_size 4 ┘ └ payload(0x6e=110) ┘  总长 122
    // header_size 取自 byte0 低 4 位（单位 4 字节 word，实测 1）；
    // byte1 低 4 位是 flags，bit0 置位表示其后跟 4 字节 sequence。
    // 早先没处理 sequence，payload_size 读成了序列号（值 1），payload 只截到 1 字节。
    // 保留少量帧头采样：协议一旦变更（header_size / flags 位），
    // 有这几行就能立刻定位，而且只有字节头、不含识别内容
    if (_frameDebugCount < 5) {
      _frameDebugCount++;
      final head = data.sublist(0, data.length < 20 ? data.length : 20)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      _log('FRAME#$_frameDebugCount len=${data.length} head20=[$head]');
    }

    final headerSize = (data[0] & 0xF) * 4;
    final flags = data[1] & 0xF;
    var offset = headerSize;
    if (flags & 0x1 != 0) offset += 4; // sequence number
    if (headerSize < 4 || data.length < offset + 4) {
      _log('Bad frame: header_size=$headerSize flags=$flags len=${data.length}');
      return;
    }

    // 错误帧布局与普通响应不同：Header [+Sequence] + ErrorCode(4) + ErrorSize(4) + ErrorPayload。
    // 早先统一按「第一个 uint32 = payload_size」解析，错误码（如 45000001）被当成长度，
    // 必然撞上下面的长度检查而静默 return —— 于是鉴权失败/配额超限等错误全被吞掉，
    // 用户只能等超时拿到空结果。错误帧必须在长度检查之前单独走。
    if (msgType == _msgServerError) {
      _handleErrorFrame(data, offset, compression);
      return;
    }

    final payloadSize =
        ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
    offset += 4;
    if (data.length < offset + payloadSize) {
      _log('Truncated frame: need ${offset + payloadSize}, got ${data.length}');
      return;
    }

    var payload = data.sublist(offset, offset + payloadSize);

    // Decompress if gzip
    if (compression == 0x1) {
      try {
        payload = Uint8List.fromList(gzip.decode(payload));
      } catch (e) {
        _log('Gzip decompress failed: $e');
        return;
      }
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

  /// 错误帧：Header [+Sequence] + ErrorCode(4) + ErrorSize(4) + ErrorPayload
  void _handleErrorFrame(Uint8List data, int offset, int compression) {
    var code = 0;
    var detail = '';
    try {
      if (data.length >= offset + 8) {
        code = ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
        final size =
            ByteData.sublistView(data, offset + 4, offset + 8).getUint32(0, Endian.big);
        final start = offset + 8;
        if (size > 0 && data.length >= start + size) {
          var body = data.sublist(start, start + size);
          if (compression == 0x1) {
            body = Uint8List.fromList(gzip.decode(body));
          }
          final text = utf8.decode(body, allowMalformed: true);
          try {
            final json = jsonDecode(text) as Map<String, dynamic>;
            detail = (json['message'] ?? json['error'] ?? text).toString();
          } catch (_) {
            detail = text;
          }
        }
      }
    } catch (e) {
      detail = 'unparseable ($e)';
    }
    // 宁可给个含错误码的粗糙消息，也不能像以前那样静默丢弃
    _errorMessage = detail.isEmpty ? 'Server error (code=$code)' : '[$code] $detail';
    _log('Server error: $_errorMessage');
    _finishStop();
  }

  void _processResponse(Map<String, dynamic> json) {
    // result 实测是 Map（早先按 List 取，报 _Map is not a subtype of List）。
    // 两种形态都兼容，避免服务端版本差异再次踩坑。
    final raw = json['result'];
    String text = '';
    if (raw is Map) {
      text = (raw['text'] as String?) ?? '';
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      text = ((raw.first as Map)['text'] as String?) ?? '';
    }
    if (text.isEmpty) return;

    // 流式响应回的是累积文本，没有 type 字段时一律当作最新结果
    final type = json['type'] as String? ?? '';
    if (type.isEmpty || type == 'final' || type == 'interim') {
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
