import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../asr_provider.dart';
import '../asr_result.dart';
import 'aliyun_token_service.dart';
import 'package:speakout/config/app_log.dart';
import '../../config/app_constants.dart';
class AliyunProvider implements ASRProvider {

  // ⚠️ 这里**不能**照搬其它 provider 的「录音代次」守卫。
  // 其它 WS provider 每次 start() 都新建连接与 listener，捕获连接时的代次即可
  // 区分新旧；但本 provider 在 initialize() 就预连接（_ensureConnectedAsync），
  // 且 start() 在 _isConnected 时**复用**该连接不重连 ——
  // listener 捕获的是 gen=0，start() 自增后变 1，守卫会把每条消息都挡掉，
  // 阿里云识别直接全废。（这个错我真写出来过，靠自查 initialize→start 时序发现。）
  // 复用连接场景下正确的判别依据是消息里的 task_id，而不是录音代次 ——
  // 那正是原始 review 里「Legacy Aliyun 不校验 task_id」那条独立 finding，
  // 需要改 _handleMessage 按 header.task_id 过滤，属独立改动。
  WebSocketChannel? _channel;
  StreamController<String> _textController = StreamController<String>.broadcast();
  
  // Config
  late String _appKey;
  late String _accessKeyId;
  late String _accessKeySecret;
  String? _token;
  DateTime? _tokenExpireTime;
  String? _taskId;

  /// 是否已经因 task_id 不匹配丢弃过帧。仅用于「首次丢弃打一条醒目日志」的安全阀，
  /// 让"服务端行为与文档不符导致消息全丢"这种情况一眼可诊断。
  bool _droppedStaleFrame = false;
  
  bool _isReady = false;
  
  // Connection Pool State
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _idleDisconnectTimer;
  static const Duration _idleTimeout = Duration(minutes: 5);

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  String get type => "aliyun";

  @override
  bool get isReady => _isReady;

  String? get taskId => _taskId;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _appKey = config['appKey'];
    _accessKeyId = config['accessKeyId'];
    _accessKeySecret = config['accessKeySecret'];
    
    // Validate config presence
    if (_appKey.isEmpty || _accessKeyId.isEmpty || _accessKeySecret.isEmpty) {
       throw Exception("Aliyun Config Missing");
    }
    
    _isReady = true;
    
    // Pre-connect at initialization (async, non-blocking)
    _ensureConnectedAsync();
  }
  
  /// Ensure WebSocket is connected (async, for background pre-connect)
  Future<void> _ensureConnectedAsync() async {
    if (_isConnected && _channel != null) return;
    
    try {
      await _refreshTokenIfNeeded();
      await _connectWebSocket();
    } catch (e) {
      // Silent failure for pre-connect, will retry on actual start()
    }
  }
  
  /// Connect WebSocket and setup listeners
  Future<void> _connectWebSocket() async {
    if (_isConnected && _channel != null) return;
    
    final url = "wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1?token=$_token";
    _channel = WebSocketChannel.connect(Uri.parse(url));
    
    _channel!.stream.listen((message) {
      if (message is String) {
        _handleMessage(message);
      }
    }, onError: (e) {
      // 错误经 _lastError 上报（stop() 转 ASRResult.error），不塞进文本流污染识别结果
      _lastError = "连接错误: $e";
      _isConnected = false;
    }, onDone: () {
      _isConnected = false;
      _stopHeartbeat();
    });
    
    _isConnected = true;
    _startHeartbeat();
  }
  
  /// Heartbeat is handled at WebSocket protocol level (auto ping/pong).
  /// No application-level heartbeat needed.
  void _startHeartbeat() {
    // Intentionally empty — WebSocket library handles ping/pong at protocol level.
    // Keeping method for API compatibility with _stopHeartbeat calls.
  }
  
  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// Reset idle disconnect timer (called on each recording)
  void _resetIdleTimer() {
    _idleDisconnectTimer?.cancel();
    _idleDisconnectTimer = Timer(_idleTimeout, () {
      _disconnectIfIdle();
    });
  }
  
  /// Disconnect after idle timeout
  void _disconnectIfIdle() {
    if (_isConnected && _channel != null) {
      _channel!.sink.close();
      _channel = null;
      _isConnected = false;
      _stopHeartbeat();
    }
  }

  Future<void> _refreshTokenIfNeeded() async {
    final now = DateTime.now();
    final expired = _tokenExpireTime != null && now.isAfter(_tokenExpireTime!);
    if (_token == null || expired) {
      _token = await AliyunTokenService.generateToken(_accessKeyId, _accessKeySecret);
      if (_token == null) throw Exception("Failed to get Aliyun Token");
      // Aliyun tokens are valid for 24h; refresh 1h before expiry
      _tokenExpireTime = now.add(const Duration(hours: 23));
    }
  }

  // Audio Buffering for Handshake Latency (capped to prevent OOM)
  static const int _maxPendingBuffers = 200; // ~10s of audio at 50ms chunks
  final List<Uint8List> _pendingBuffer = [];
  bool _isHandshakeComplete = false;

  @override
  Future<void> start() async {
    // Ensure connection is ready (reuse existing or create new)
    if (!_isConnected || _channel == null) {
      await _refreshTokenIfNeeded();
      await _connectWebSocket();
    }
    
    // Reset idle timer since we're actively using the connection
    _resetIdleTimer();
    
    // Reset state for new transcription task
    _pendingBuffer.clear();
    _isHandshakeComplete = false;
    _committedText = "";
    _currentSentence = "";
    _lastError = null;
    
    // Generate new Task ID for this recording session
    _taskId = const Uuid().v4().replaceAll('-', '');
    _droppedStaleFrame = false;

    // Send Start Directive (reusing existing connection)
    final startCmd = {
      "header": {
        "message_id": const Uuid().v4().replaceAll('-', ''),
        "task_id": _taskId,
        "namespace": "SpeechTranscriber",
        "name": "StartTranscription",
        "appkey": _appKey
      },
      "payload": {
        "format": "pcm",
        "sample_rate": 16000,
        "enable_intermediate_result": true,
        "enable_punctuation_prediction": true,
        "enable_inverse_text_normalization": true
      }
    };
    
    _channel!.sink.add(jsonEncode(startCmd));
  }

  String _committedText = "";
  String _currentSentence = "";
  String? _lastError; // 云端错误（鉴权/任务失败/连接错误），由 stop() 通过 ASRResult.error 上报
  
  void _handleMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr);
      final header = map['header'];
      final name = header['name'];

      // 按 task_id 过滤过期帧。
      //
      // 本 provider 复用连接（initialize 就预连接，start 在 _isConnected 时不重连），
      // 所以上一次录音的 SentenceEnd / ResultChanged 可能在下一次录音开始后才到 ——
      // 不过滤的话会把旧句子 append 进新会话的 _committedText，字幕直接串台。
      // stop() 只固定等 500ms，这个窗口很容易命中。
      //
      // 不能用其它 provider 那套「录音代次」：那是给「每次 start 都新建连接」
      // 设计的，套到复用连接上会把本次录音的消息也全挡掉（我试过，阿里云直接全废）。
      // task_id 每次 start() 重新生成并随 StartTranscription 下发，服务端原样回带，
      // 是复用连接下唯一可靠的会话标识。
      // 按 task_id 丢弃过期帧。
      //
      // 依据：阿里云 WebSocket 协议规定所有服务端响应都携带本次任务的 task_id，
      // 且保持客户端下发的原值（task_id 本就由客户端生成，服务端没有规范化的理由）。
      //
      // 曾经写成「先收到一条匹配帧、证实服务端会回带，之后才敢过滤」的自适应版本，
      // 动机是当时缺少这条 legacy 通道的实测报文（用户日志里 0 条阿里云记录），
      // 怕服务端做格式规范化导致全部消息被误丢 —— 那是我给 aliyun 加「录音代次」
      // 守卫时踩过的坑。但自适应版本自带一个窟窿：本轮首帧到达前的"确认窗口"里，
      // 上一轮的迟到 SentenceEnd 照样会被放行并写进本轮 _committedText。
      // 既然协议已有明确规定，就按规定过滤，不留这个窗口。
      //
      // 安全阀：首次丢弃时打一条醒目日志。万一服务端行为与文档不符导致消息全丢，
      // 日志会直接指出原因，而不是变成一个查不出来的"阿里云没反应"。
      final msgTaskId = header['task_id']?.toString();
      if (msgTaskId != null && _taskId != null && msgTaskId != _taskId) {
        if (!_droppedStaleFrame) {
          _droppedStaleFrame = true;
          AppLog.d('[AliyunProvider] 开始按 task_id 丢弃过期帧。'
              '若本次识别完全无输出，请核对服务端是否原样回带 task_id：'
              '收到 $msgTaskId / 下发 $_taskId');
        }
        AppLog.d('[AliyunProvider] 丢弃过期帧 $name '
            '(task ${msgTaskId.substring(0, 8)}… != 当前 ${_taskId!.substring(0, 8)}…)');
        return;
      }
      // msgTaskId 为 null 时放行：协议规定应当携带，缺失时无法归属，
      // 宁可放行也不误丢（间歇性缺失不会被当成过期帧）。
      
      if (name == 'TranscriptionStarted') {
        _isHandshakeComplete = true;
        // Flush buffer
        for (final data in _pendingBuffer) {
           _channel?.sink.add(data);
        }
        _pendingBuffer.clear();
        
      } else if (name == 'TranscriptionResultChanged') {
        final payload = map['payload'];
        final result = payload['result'];
        _currentSentence = result;
        // Emit Full Text = Committed + Current
        _textController.add(_committedText + _currentSentence);
        
      } else if (name == 'SentenceEnd') {
         // Sentence limit reached or pause detected
         final payload = map['payload'];
         final result = payload['result'];
         _committedText += result; // Append sentence
         _currentSentence = ""; // Reset current
         _textController.add(_committedText);
         
      } else if (name == 'TranscriptionCompleted') {
         // Task finished (usually after Stop)
         // Sometimes carries a final result, sometimes not?
         // Assuming SentenceEnd already handled the text.
         // Just ensure final state.
         _textController.add(_committedText + _currentSentence);
         
      } else if (name == 'TaskFailed') {
         // 任务失败（鉴权/参数/余额等）：记录到 _lastError，由 stop() 上报，不注入文本流
         _lastError = "识别失败: ${header['status_text']}";
      }
    } catch (e) {
      AppLog.d("[AliyunProvider] Message parse error: $e");
    }
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_channel == null) return;
    
    // Aliyun expects Int16 PCM bytes. Input is Float32.
    final pcmBytes = _float32ToInt16Bytes(samples);
    
    if (!_isHandshakeComplete) {
       if (_pendingBuffer.length < _maxPendingBuffers) {
         _pendingBuffer.add(pcmBytes);
       }
    } else {
       _channel!.sink.add(pcmBytes);
    }
  }

  Uint8List _float32ToInt16Bytes(Float32List samples) {
    final buffer = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
        var s = samples[i];
        if (s > 1.0) s = 1.0;
        if (s < -1.0) s = -1.0;
        int v = (s * 32767).toInt();
        buffer.setInt16(i * 2, v, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }
  // ...

  /// 流式识别：结果随说话陆续回来，stop 只等最后一帧，用全局默认即可。
  @override
  Duration get stopTimeout => AppConstants.kAsrStopTimeout;

  @override
  Future<ASRResult> stop() async {
    if (_channel == null) return ASRResult.textOnly("");

    // Wait for handshake to complete (up to 2s) before sending stop
    if (!_isHandshakeComplete) {
      await Future.any([
        Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 100));
          return !_isHandshakeComplete;
        }),
        Future.delayed(const Duration(seconds: 2)),
      ]);
    }

    // Send Stop (but DON'T close the connection - keep it for reuse)
    final stopCmd = {
      "header": {
        "message_id": const Uuid().v4().replaceAll('-', ''),
        "task_id": _taskId,
        "namespace": "SpeechTranscriber",
        "name": "StopTranscription",
        "appkey": _appKey
      }
    };

    _channel!.sink.add(jsonEncode(stopCmd));

    // Wait briefly for any final messages
    await Future.delayed(const Duration(milliseconds: 500));

    // Reset idle timer (connection stays open)
    _resetIdleTimer();

    // 有错误且无有效文本 → 通过 error 字段上报（CoreEngine 会显示，不当成"无语音"）
    final text = _committedText + _currentSentence;
    if (_lastError != null && text.isEmpty) {
      return ASRResult.withError(_lastError!);
    }
    return ASRResult.textOnly(text);
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    _idleDisconnectTimer?.cancel();
    _stopHeartbeat();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _textController.close();
    // Recreate controller so provider can be re-initialized
    _textController = StreamController<String>.broadcast();
  }
}
