import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/app_service.dart';
import '../../services/config_service.dart';
import '../../services/notification_service.dart';
import 'linux_settings.dart';
import 'linux_chat.dart';

/// Linux 主页面
///
/// Material Design 3 风格，布局与 macOS/Windows 一致。
class LinuxHomePage extends StatefulWidget {
  const LinuxHomePage({super.key});

  @override
  State<LinuxHomePage> createState() => _LinuxHomePageState();
}

class _LinuxHomePageState extends State<LinuxHomePage> with WidgetsBindingObserver {
  final AppService _appService = AppService();

  String _status = "初始化中...";
  bool _ready = false;
  String _lastError = "";
  bool _isRecording = false;
  String _currentKeyName = "";
  String _recognizedText = "";

  AppNotification? _currentNotification;
  Timer? _notificationTimer;

  StreamSubscription<String>? _statusSub;
  StreamSubscription<AppNotification>? _notifSub;
  StreamSubscription<bool>? _recordingSub;
  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;

  final List<double> _waveHeights = List.generate(7, (_) => 0.3);
  Timer? _waveTimer;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentKeyName = ConfigService().pttKeyName;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _appService.init();
    });

    _statusSub = _appService.engine.statusStream.listen((msg) {
      if (!mounted) return;
      setState(() {
        if (msg.startsWith("Error")) {
          _lastError = msg;
          _ready = false;
        } else if (msg.contains("Trusted: true") ||
            msg.contains("Listener Started") ||
            msg.contains("就绪") ||
            msg.contains("Ready")) {
          _lastError = "";
          _ready = true;
          _subscribeToPartialResults();
        }
        _status = msg;
      });
    });

    _notifSub = NotificationService().stream.listen((n) {
      if (!mounted) return;
      setState(() => _currentNotification = n);
      _notificationTimer?.cancel();
      _notificationTimer = Timer(n.duration, () {
        if (mounted && _currentNotification == n) {
          setState(() => _currentNotification = null);
        }
      });
    });

    _recordingSub = _appService.engine.recordingStream.listen((isRecording) {
      if (!mounted) return;
      setState(() {
        _isRecording = isRecording;
        if (isRecording) _recognizedText = "";
      });
    });

    _resultSub = _appService.engine.resultStream.listen((text) {
      if (!mounted || text.isEmpty) return;
      setState(() => _recognizedText = text);
      final captured = text;
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _recognizedText == captured && !_isRecording) {
          setState(() => _recognizedText = "");
        }
      });
    });
  }

  void _subscribeToPartialResults() {
    if (_partialSub != null) return;
    _partialSub = _appService.engine.partialTextStream.listen((partialText) {
      if (mounted && _isRecording && partialText.isNotEmpty) {
        setState(() => _recognizedText = partialText);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveTimer?.cancel();
    _notificationTimer?.cancel();
    _statusSub?.cancel();
    _notifSub?.cancel();
    _recordingSub?.cancel();
    _resultSub?.cancel();
    _partialSub?.cancel();
    super.dispose();
  }

  void _startWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted && _isRecording) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            _waveHeights[i] = 0.17 + _random.nextDouble() * 0.83;
          }
        });
      }
    });
  }

  Widget _buildWaveform() {
    if (_waveTimer == null || !_waveTimer!.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startWaveAnimation());
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final height = 8.0 + 40.0 * _waveHeights[i];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: 5,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2.5),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.appTitle ?? 'SpeakOut'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinuxChatPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LinuxSettingsPage()),
              );
              if (mounted) {
                setState(() => _currentKeyName = ConfigService().pttKeyName);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Error banner
          if (_lastError.isNotEmpty)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: MaterialBanner(
                content: Text(_lastError),
                backgroundColor: theme.colorScheme.errorContainer,
                leading: Icon(Icons.error, color: theme.colorScheme.error),
                actions: [
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () => setState(() => _lastError = ""),
                  ),
                ],
              ),
            ),

          // Notification
          if (_currentNotification != null)
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  color: _currentNotification!.type == NotificationType.error
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      _currentNotification!.message,
                      style: TextStyle(
                        color: _currentNotification!.type == NotificationType.error
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mic button
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ready ? accentColor : Colors.grey,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isRecording
                      ? _buildWaveform()
                      : const Icon(Icons.mic, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 24),

                // Brand
                Text(
                  "子曰",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 16),

                // Status
                Builder(builder: (_) {
                  if (_lastError.isNotEmpty) {
                    return Text(_lastError, style: TextStyle(color: theme.colorScheme.error));
                  }
                  if (_isRecording) {
                    return Text(
                      loc?.recording ?? "录音中...",
                      style: TextStyle(color: accentColor),
                    );
                  }
                  if (!_ready) {
                    return Text(_status, style: theme.textTheme.bodyMedium);
                  }
                  return Text(
                    loc?.readyTip(_currentKeyName) ?? "按住 $_currentKeyName 开始语音输入",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }),
              ],
            ),
          ),

          // Result display
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              opacity: _recognizedText.isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  constraints: const BoxConstraints(maxWidth: 500),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _recognizedText.isEmpty ? " " : _recognizedText,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
