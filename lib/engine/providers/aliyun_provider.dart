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
    await _refreshTokenIfNeeded();
    
    // Reset state
    _startCompleter = Completer<void>();
    _pendingBuffer.clear();
    _isHandshakeComplete = false;
    _committedText = "";
    _currentSentence = "";
    
    final url = "wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1?token=$_token";
    _channel = WebSocketChannel.connect(Uri.parse(url));
    
    
    // Traceable Task ID Generation
    // Logic: MD5(LicenseKey).substring(0,8) + Random(24)
    // Benefit: Can identify user from Aliyun logs even without mapping table
    String prefix = "00000000";
    final license = ConfigService().licenseKey;
    if (license.isNotEmpty) {
       prefix = md5.convert(utf8.encode(license)).toString().substring(0, 8);
    }
    final randomPart = const Uuid().v4().replaceAll('-', '').substring(8);
    _taskId = prefix + randomPart;
    
    // Listen for messages
    _channel!.stream.listen((message) {
      if (message is String) {
        _handleMessage(message);
      }
    }, onError: (e) {
      _textController.add("Connection Error: $e");
    }, onDone: () {
      // closed
    });

    // Send Start Directive
    final startCmd = {
      "header": {
        "message_id": Uuid().v4().replaceAll('-', ''),
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
    
    // Non-blocking return! Logic continues to buffer in acceptWaveform
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
    // This ensures we don't close the channel before flushing the initial buffer
    if (!_isHandshakeComplete && _startCompleter != null) {
        try {
           await _startCompleter!.future.timeout(const Duration(seconds: 2));
        } catch (_) {
           // Timeout, assume failed. proceed to close.
        }
    }
    
    // Send Stop...
    final stopCmd = {
      "header": {
        "message_id": Uuid().v4().replaceAll('-', ''),
        "task_id": _taskId,
        "namespace": "SpeechTranscriber",
        "name": "StopTranscription",
        "appkey": _appKey
      }
    };
    
    _channel!.sink.add(jsonEncode(stopCmd));
    
    // Wait briefly for any final messages
    await Future.delayed(const Duration(milliseconds: 500));
    await _channel!.sink.close();
    _channel = null;
    
    // Return final accumulated text
    // If currentSentence is not empty, append it? 
    // Usually Cloud sends TranscriptionCompleted before closing.
    // unlikely to have partial left. But safer to return committed + current
    return _committedText + _currentSentence; 
  }

  @override
  Future<void> dispose() async {
    _channel?.sink.close();
    _textController.close();
  }
}
