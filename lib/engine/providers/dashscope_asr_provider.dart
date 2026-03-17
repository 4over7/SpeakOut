import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'package:speakout/config/app_log.dart';

/// 阿里云百炼 ASR Provider (DashScope Realtime Transcription)
///
/// 支持 paraformer-v2, paraformer-realtime-v2 等模型。
/// 使用 WebSocket 流式协议，API Key 鉴权（与百炼 LLM 同一个 key）。
class DashScopeASRProvider implements ASRProvider {
  IOWebSocketChannel? _channel;
  StreamController<String> _textController = StreamController<String>.broadcast();

  late String _apiKey;
  late String _model;
  String? _taskId;

  bool _isReady = false;
  bool _isHandshakeComplete = false;

  // Audio buffering during handshake
  static const int _maxPendingBuffers = 200;
  final List<Uint8List> _pendingBuffer = [];

  // Text accumulation
  String _committedText = '';
  String _currentSentence = '';
  String? _lastError;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => 'dashscope';

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _apiKey = config['apiKey'] as String? ?? '';
    _model = config['model'] as String? ?? 'paraformer-realtime-v2';

    if (_apiKey.isEmpty) throw Exception('DashScope API Key missing');

    _isReady = true;
    _log('Initialized (model=$_model)');
  }

  @override
  Future<void> start() async {
    _pendingBuffer.clear();
    _isHandshakeComplete = false;
    _committedText = '';
    _currentSentence = '';
    _lastError = null;
    _taskId = const Uuid().v4().replaceAll('-', '');

    // Connect WebSocket with auth headers
    final url = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference/';
    _channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {
        'Authorization': 'bearer $_apiKey',
        'X-DashScope-DataInspection': 'enable',
      },
    );

    _channel!.stream.listen(
      (message) {
        if (message is String) _handleMessage(message);
      },
      onError: (e) {
        _log('WebSocket error: $e');
        },
      onDone: () {
      },
    );
    // Send run-task directive
    final runTask = {
      'header': {
        'action': 'run-task',
        'task_id': _taskId,
        'streaming': 'duplex',
      },
      'payload': {
        'task_group': 'audio',
        'task': 'asr',
        'function': 'recognition',
        'model': _model,
        'parameters': {
          'format': 'pcm',
          'sample_rate': 16000,
          'vocabulary_id': '',
          'disfluency_removal_enabled': false,
        },
        'input': {},
      },
    };
    _channel!.sink.add(jsonEncode(runTask));
    _log('run-task sent (model=$_model, task=$_taskId)');
  }

  void _handleMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final header = map['header'] as Map<String, dynamic>? ?? {};
      final event = header['event'] as String? ?? '';
      final payload = map['payload'] as Map<String, dynamic>? ?? {};
      final output = payload['output'] as Map<String, dynamic>? ?? {};

      switch (event) {
        case 'task-started':
          _isHandshakeComplete = true;
          // Flush pending audio
          for (final data in _pendingBuffer) {
            _sendAudioChunk(data);
          }
          _pendingBuffer.clear();
          _log('task-started, flushed ${_pendingBuffer.length} buffers');

        case 'result-generated':
          final sentence = output['sentence'] as Map<String, dynamic>? ?? {};
          final text = sentence['text'] as String? ?? '';
          final endTime = sentence['end_time'] as int? ?? -1;

          if (endTime >= 0) {
            // Sentence complete
            _committedText += text;
            _currentSentence = '';
          } else {
            // Intermediate result
            _currentSentence = text;
          }
          _textController.add(_committedText + _currentSentence);

        case 'task-finished':
          _log('task-finished');
          _textController.add(_committedText + _currentSentence);

        case 'task-failed':
          // DashScope 错误字段: error_code + error_message (非 message)
          final errorCode = header['error_code'] as String? ?? '';
          final errorMsg = header['error_message'] as String?
              ?? header['message'] as String?
              ?? 'Unknown error';
          final display = errorCode.isNotEmpty ? '$errorCode: $errorMsg' : errorMsg;
          _log('task-failed: $display (full header: $header)');
          _lastError = display;
          // 不向文本流发送错误，避免错误文字被当成识别结果注入
      }
    } catch (e) {
      _log('Message parse error: $e');
    }
  }

  void _sendAudioChunk(Uint8List data) {
    if (_channel == null) return;
    // DashScope expects binary audio frames
    _channel!.sink.add(data);
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_channel == null) return;

    final pcmBytes = _float32ToInt16Bytes(samples);

    if (!_isHandshakeComplete) {
      if (_pendingBuffer.length < _maxPendingBuffers) {
        _pendingBuffer.add(pcmBytes);
      }
    } else {
      _sendAudioChunk(pcmBytes);
    }
  }

  Uint8List _float32ToInt16Bytes(Float32List samples) {
    final buffer = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      var s = samples[i].clamp(-1.0, 1.0);
      buffer.setInt16(i * 2, (s * 32767).toInt(), Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  @override
  Future<ASRResult> stop() async {
    if (_channel == null) return ASRResult.textOnly('');

    // Wait for handshake
    if (!_isHandshakeComplete) {
      await Future.any([
        Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 100));
          return !_isHandshakeComplete;
        }),
        Future.delayed(const Duration(seconds: 2)),
      ]);
    }

    // Send finish-task
    final finishTask = {
      'header': {
        'action': 'finish-task',
        'task_id': _taskId,
        'streaming': 'duplex',
      },
      'payload': {
        'input': {},
      },
    };
    _channel!.sink.add(jsonEncode(finishTask));
    _log('finish-task sent');

    // Wait for final results
    await Future.delayed(const Duration(milliseconds: 500));

    // Close connection (DashScope doesn't support connection reuse across tasks)
    await _channel?.sink.close();
    _channel = null;

    if (_lastError != null && _committedText.isEmpty && _currentSentence.isEmpty) {
      return ASRResult.withError(_lastError!);
    }
    return ASRResult.textOnly(_committedText + _currentSentence);
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    await _channel?.sink.close();
    _channel = null;
    _textController.close();
    _textController = StreamController<String>.broadcast();
  }

  void _log(String msg) => AppLog.d('[DashScopeASR] $msg');
}
