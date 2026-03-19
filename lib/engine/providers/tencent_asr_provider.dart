import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/config_service.dart';

/// 腾讯云实时语音识别 ASR Provider
///
/// WebSocket 协议：音频直接发 binary 帧，结果收 JSON 文本帧。
/// 鉴权：URL 签名 (HMAC-SHA1)。
/// 文档：https://cloud.tencent.com/document/product/1093/48982
class TencentASRProvider implements ASRProvider {
  IOWebSocketChannel? _channel;
  StreamController<String> _textController = StreamController<String>.broadcast();

  late String _secretId;
  late String _secretKey;
  late String _appId;
  late String _engineModel;

  bool _isReady = false;
  bool _isConnected = false;

  // Audio buffering before connection is ready
  final List<Uint8List> _pendingBuffer = [];
  static const int _maxPendingBuffers = 200;

  // Result tracking
  String _finalText = '';
  String? _errorMessage;
  final Completer<ASRResult> _stopCompleter = Completer<ASRResult>();

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'tencent_asr';

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _secretId = config['secretId'] as String? ?? '';
    _secretKey = config['secretKey'] as String? ?? '';
    _appId = config['appId'] as String? ?? '';
    _engineModel = config['model'] as String? ?? '16k_zh';

    if (_secretId.isEmpty || _secretKey.isEmpty || _appId.isEmpty) {
      throw Exception('Tencent ASR: secretId, secretKey, appId required');
    }

    _isReady = true;
    _log('Initialized (appId=$_appId, model=$_engineModel)');
  }

  @override
  Future<void> start() async {
    _finalText = '';
    _errorMessage = null;
    _pendingBuffer.clear();
    _isConnected = false;

    final url = _buildSignedUrl();
    _log('Connecting to Tencent ASR...');

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

      // Flush pending audio
      for (final buf in _pendingBuffer) {
        _channel!.sink.add(buf);
      }
      _pendingBuffer.clear();
    } catch (e) {
      _log('Connection failed: $e');
      _errorMessage = e.toString();
    }
  }

  @override
  void acceptWaveform(Float32List samples) {
    // Convert Float32 → Int16 PCM bytes
    final pcm = _float32ToInt16Bytes(samples);

    if (_isConnected && _channel != null) {
      _channel!.sink.add(pcm);
    } else if (_pendingBuffer.length < _maxPendingBuffers) {
      _pendingBuffer.add(pcm);
    }
  }

  @override
  Future<ASRResult> stop() async {

    if (_channel != null && _isConnected) {
      // Send end signal
      try {
        _channel!.sink.add(jsonEncode({'type': 'end'}));
      } catch (_) {}
    }

    // Wait for server to finish or timeout
    return _stopCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _log('Stop timeout, returning current text');
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

  // ── 内部方法 ──

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final code = json['code'] as int? ?? 0;

      if (code != 0) {
        _errorMessage = json['message'] as String? ?? 'Unknown error (code=$code)';
        _log('Error: $_errorMessage');
        _finishStop();
        return;
      }

      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return;

      final sliceType = result['slice_type'] as int? ?? 0;
      final voiceText = result['voice_text_str'] as String? ?? '';

      if (sliceType == 2) {
        // 段结束（稳定结果）
        _finalText = voiceText;
        _textController.add(voiceText);
        _log('Final segment: ${voiceText.length} chars');
      } else {
        // 临时结果
        _textController.add(voiceText);
      }

      // 检查是否结束
      final finalVal = json['final'] as int? ?? 0;
      if (finalVal == 1) {
        _log('Recognition complete');
        _finishStop();
      }
    } catch (e) {
      _log('Parse error: $e');
    }
  }

  void _finishStop() {
    if (!_stopCompleter.isCompleted) {
      _stopCompleter.complete(_buildResult());
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

  /// 构建带签名的 WebSocket URL
  String _buildSignedUrl() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = Random().nextInt(1000000);
    final expired = timestamp + 86400;

    // 语言提示
    final inputLang = ConfigService().inputLanguage;
    String engineModel = _engineModel;
    if (inputLang == 'en') {
      engineModel = '16k_en';
    } else if (inputLang != 'auto' && inputLang != 'zh') {
      engineModel = '16k_zh'; // 默认中文
    }

    final params = {
      'secretid': _secretId,
      'timestamp': '$timestamp',
      'expired': '$expired',
      'nonce': '$nonce',
      'engine_model_type': engineModel,
      'voice_id': const Uuid().v4().replaceAll('-', ''),
      'voice_format': '1', // PCM
      'needvad': '1',
      'filter_dirty': '1',
      'filter_punc': '0', // 保留标点
      'convert_num_mode': '1',
    };

    // 按 key 字典序排列
    final sortedKeys = params.keys.toList()..sort();
    final queryString = sortedKeys.map((k) => '$k=${params[k]}').join('&');

    // 签名: HMAC-SHA1(secretKey, "asr.cloud.tencent.com/asr/v2/$appId?$queryString")
    final signStr = 'asr.cloud.tencent.com/asr/v2/$_appId?$queryString';
    final hmac = Hmac(sha1, utf8.encode(_secretKey));
    final signature = base64Encode(hmac.convert(utf8.encode(signStr)).bytes);

    final encodedSig = Uri.encodeComponent(signature);
    return 'wss://asr.cloud.tencent.com/asr/v2/$_appId?$queryString&signature=$encodedSig';
  }

  void _log(String msg) => AppLog.d('[TencentASR] $msg');
}
