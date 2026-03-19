import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';

/// 讯飞实时语音听写 ASR Provider
///
/// WebSocket 协议：音频 Base64 编码嵌入 JSON 文本帧，结果 JSON 文本帧。
/// 鉴权：URL 参数签名 (HMAC-SHA256)。
/// 限制：单次最长 60 秒。
/// 文档：https://www.xfyun.cn/doc/asr/voicedictation/API.html
class XfyunASRProvider implements ASRProvider {
  IOWebSocketChannel? _channel;
  StreamController<String> _textController = StreamController<String>.broadcast();

  late String _appId;
  late String _apiKey;
  late String _apiSecret;

  bool _isReady = false;
  bool _isConnected = false;
  bool _firstFrameSent = false;

  // Audio buffering before connection
  final List<Uint8List> _pendingBuffer = [];
  static const int _maxPendingBuffers = 200;

  // Result tracking: 讯飞用 wpgs 动态修正，维护一个有序 segment 列表
  final List<String> _segments = [];
  String? _errorMessage;
  Completer<ASRResult>? _stopCompleter;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'xfyun_asr';

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _appId = config['appId'] as String? ?? '';
    _apiKey = config['apiKey'] as String? ?? '';
    _apiSecret = config['apiSecret'] as String? ?? '';

    if (_appId.isEmpty || _apiKey.isEmpty || _apiSecret.isEmpty) {
      throw Exception('Xfyun ASR: appId, apiKey, apiSecret required');
    }

    _isReady = true;
    _log('Initialized (appId=$_appId)');
  }

  @override
  Future<void> start() async {
    _segments.clear();
    _errorMessage = null;
    _firstFrameSent = false;
    _pendingBuffer.clear();
    _isConnected = false;
    _stopCompleter = Completer<ASRResult>();

    final url = _buildAuthUrl();
    _log('Connecting to Xfyun ASR...');

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
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

      // Send first frame with config + buffered audio
      _sendFirstFrame();
    } catch (e) {
      _log('Connection failed: $e');
      _errorMessage = e.toString();
    }
  }

  @override
  void acceptWaveform(Float32List samples) {
    final pcm = _float32ToInt16Bytes(samples);

    if (_isConnected && _firstFrameSent && _channel != null) {
      _sendAudioFrame(pcm, status: 1); // continue
    } else if (_pendingBuffer.length < _maxPendingBuffers) {
      _pendingBuffer.add(pcm);
    }
  }

  @override
  Future<ASRResult> stop() async {

    if (_channel != null && _isConnected) {
      // Send last frame (status=2)
      try {
        _sendAudioFrame(Uint8List(0), status: 2);
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
    _pendingBuffer.clear();
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }

  // ── 发送帧 ──

  void _sendFirstFrame() {
    if (_pendingBuffer.isEmpty) {
      _pendingBuffer.add(Uint8List(1280)); // 空帧占位
    }
    final audioBytes = _pendingBuffer.first;
    _pendingBuffer.removeAt(0);

    final inputLang = ConfigService().inputLanguage;
    String language = 'zh_cn';
    if (inputLang == 'en') language = 'en_us';

    final frame = {
      'common': {'app_id': _appId},
      'business': {
        'language': language,
        'domain': 'iat',
        'accent': 'mandarin',
        'ptt': 1,          // 标点
        'dwa': 'wpgs',     // 动态修正
        'vad_eos': 3000,   // 静音检测 3s
      },
      'data': {
        'status': 0, // first frame
        'format': 'audio/L16;rate=16000',
        'encoding': 'raw',
        'audio': base64Encode(audioBytes),
      },
    };

    _channel!.sink.add(jsonEncode(frame));
    _firstFrameSent = true;

    // Flush remaining pending
    for (final buf in _pendingBuffer) {
      _sendAudioFrame(buf, status: 1);
    }
    _pendingBuffer.clear();
  }

  void _sendAudioFrame(Uint8List pcm, {required int status}) {
    final frame = {
      'data': {
        'status': status,
        'format': 'audio/L16;rate=16000',
        'encoding': 'raw',
        'audio': base64Encode(pcm),
      },
    };
    try {
      _channel!.sink.add(jsonEncode(frame));
    } catch (_) {}
  }

  // ── 接收结果 ──

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final code = json['code'] as int? ?? 0;

      if (code != 0) {
        _errorMessage = json['message'] as String? ?? 'Error code=$code';
        _log('Error: $_errorMessage');
        _finishStop();
        return;
      }

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final status = data['status'] as int? ?? 0;
      final result = data['result'] as Map<String, dynamic>?;

      if (result != null) {
        _processResult(result);
      }

      // status=2 表示识别结束
      if (status == 2) {
        _log('Recognition complete');
        _finishStop();
      }
    } catch (e) {
      _log('Parse error: $e');
    }
  }

  void _processResult(Map<String, dynamic> result) {
    // 讯飞结果格式: ws[].cw[].w 嵌套拼接
    final ws = result['ws'] as List?;
    if (ws == null) return;

    final text = StringBuffer();
    for (final wsItem in ws) {
      final cw = (wsItem as Map<String, dynamic>)['cw'] as List?;
      if (cw == null) continue;
      for (final cwItem in cw) {
        text.write((cwItem as Map<String, dynamic>)['w'] ?? '');
      }
    }

    final segText = text.toString();
    final pgs = result['pgs'] as String?;

    if (pgs == 'rpl') {
      // 替换模式：用 rg 指定替换范围
      final rg = result['rg'] as List?;
      if (rg != null && rg.length >= 2) {
        final start = (rg[0] as int) - 1; // 讯飞 1-based
        final end = (rg[1] as int) - 1;
        if (start >= 0 && start < _segments.length) {
          // 替换 [start, end] 范围的 segments
          for (int i = end; i >= start && i < _segments.length; i--) {
            _segments.removeAt(i);
          }
          if (start < _segments.length) {
            _segments.insert(start, segText);
          } else {
            _segments.add(segText);
          }
        }
      }
    } else {
      // 追加模式 (pgs == 'apd' 或 null)
      _segments.add(segText);
    }

    final fullText = _segments.join('');
    _textController.add(fullText);
  }

  void _finishStop() {
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      _stopCompleter!.complete(_buildResult());
    }
    _isConnected = false;
    try { _channel?.sink.close(); } catch (_) {}
  }

  ASRResult _buildResult() {
    final text = _segments.join('');
    if (_errorMessage != null) {
      return ASRResult(text: text, error: _errorMessage);
    }
    return ASRResult.textOnly(text);
  }

  Uint8List _float32ToInt16Bytes(Float32List samples) {
    final bytes = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(i * 2, (s * 32767).toInt(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// 构建讯飞鉴权 URL (HMAC-SHA256 签名)
  String _buildAuthUrl() {
    final now = DateTime.now().toUtc();
    final dateStr = '${_weekday(now.weekday)}, ${now.day.toString().padLeft(2, '0')} ${_month(now.month)} ${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} GMT';

    const host = 'iat-api.xfyun.cn';
    final signatureOrigin = 'host: $host\ndate: $dateStr\nGET /v2/iat HTTP/1.1';

    final hmac = Hmac(sha256, utf8.encode(_apiSecret));
    final signatureSha = hmac.convert(utf8.encode(signatureOrigin));
    final signature = base64Encode(signatureSha.bytes);

    final authorizationOrigin = 'api_key="$_apiKey", algorithm="hmac-sha256", headers="host date request-line", signature="$signature"';
    final authorization = base64Encode(utf8.encode(authorizationOrigin));

    final encodedDate = Uri.encodeComponent(dateStr);
    final encodedAuth = Uri.encodeComponent(authorization);
    return 'wss://$host/v2/iat?authorization=$encodedAuth&date=$encodedDate&host=$host';
  }

  static String _weekday(int w) => const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w];
  static String _month(int m) => const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];

  void _log(String msg) => AppLog.d('[XfyunASR] $msg');
}
