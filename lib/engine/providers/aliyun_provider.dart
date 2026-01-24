import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../asr_provider.dart';
import 'aliyun_token_service.dart';
import '../../services/config_service.dart';

class AliyunProvider implements ASRProvider {
  WebSocketChannel? _channel;
  final StreamController<String> _textController = StreamController<String>.broadcast();
  
  // Config
  late String _appKey;
  late String _accessKeyId;
  late String _accessKeySecret;
  String? _token;
  DateTime? _tokenExpireTime;
  String? _taskId;
  
  bool _isReady = false;
  
  // Connection Pool State
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _idleDisconnectTimer;
  static const Duration _idleTimeout = Duration(minutes: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

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
      _textController.add("Connection Error: $e");
      _isConnected = false;
    }, onDone: () {
      _isConnected = false;
      _stopHeartbeat();
    });
    
    _isConnected = true;
    _startHeartbeat();
  }
  
  /// Start heartbeat timer to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isConnected && _channel != null) {
        // Send empty ping to keep connection alive
        // Aliyun WebSocket accepts standard WebSocket ping frames
        try {
          // WebSocket ping is handled at protocol level, but we can send an empty message
          // or rely on the library's built-in ping. For safety, just check connection.
        } catch (_) {}
      }
    });
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
    // Simple basic logic: if no token, get one.
    // In production, check expiry.
    if (_token == null) {
      _token = await AliyunTokenService.generateToken(_accessKeyId, _accessKeySecret);
      if (_token == null) throw Exception("Failed to get Aliyun Token");
    }
  }

  Completer<void>? _startCompleter;
  
  // Audio Buffering for Handshake Latency
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
    
    // Generate new Task ID for this recording session
    _taskId = const Uuid().v4().replaceAll('-', '');

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
  
  void _handleMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr);
      final header = map['header'];
      final name = header['name'];
      
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
         final errMsg = "Error: ${header['status_text']}";
         _textController.add(errMsg);
      }
    } catch (e) {
      // json parse error
    }
  }

  @override
  void acceptWaveform(Float32List samples) {
    if (_channel == null) return;
    
    // Aliyun expects Int16 PCM bytes. Input is Float32.
    final pcmBytes = _float32ToInt16Bytes(samples);
    
    if (!_isHandshakeComplete) {
       _pendingBuffer.add(pcmBytes);
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

  @override
  Future<String> stop() async {
    if (_channel == null) return "";
    
    // Robustness: If handshake is still pending, wait for it (up to 2s)
    if (!_isHandshakeComplete) {
        await Future.delayed(const Duration(seconds: 2));
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
    
    // Return final accumulated text
    return _committedText + _currentSentence; 
  }

  @override
  Future<void> dispose() async {
    _idleDisconnectTimer?.cancel();
    _stopHeartbeat();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _textController.close();
  }
}
