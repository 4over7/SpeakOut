import 'dart:async';
import 'dart:math';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';
import '../../services/app_service.dart';
import '../../services/config_service.dart';
import '../../services/notification_service.dart';
import 'windows_settings.dart';
import 'windows_chat.dart';

/// Windows 主页面
///
/// 布局与 macOS 版一致：中央麦克风按钮 + 品牌 + 状态提示 + 底部识别结果
class WindowsHomePage extends StatefulWidget {
  const WindowsHomePage({super.key});

  @override
  State<WindowsHomePage> createState() => _WindowsHomePageState();
}

class _WindowsHomePageState extends State<WindowsHomePage> with WidgetsBindingObserver {
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

  // Waveform
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
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: Text(loc?.appTitle ?? 'SpeakOut'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(FluentIcons.chat),
              onPressed: () => Navigator.of(context).push(
                FluentPageRoute(builder: (_) => const WindowsChatPage()),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(FluentIcons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  FluentPageRoute(builder: (_) => const WindowsSettingsPage()),
                );
                if (mounted) {
                  setState(() => _currentKeyName = ConfigService().pttKeyName);
                }
              },
            ),
          ],
        ),
      ),
      content: Stack(
        children: [
          // Error banner
          if (_lastError.isNotEmpty)
            Positioned(
              top: 16,
              left: 24,
              right: 24,
              child: InfoBar(
                title: Text(_lastError),
                severity: InfoBarSeverity.error,
              ),
            ),

          // Notification banner
          if (_currentNotification != null)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: InfoBar(
                  title: Text(_currentNotification!.message),
                  severity: _currentNotification!.type == NotificationType.error
                      ? InfoBarSeverity.error
                      : InfoBarSeverity.success,
                  action: _currentNotification!.actionLabel != null
                      ? HyperlinkButton(
                          child: Text(_currentNotification!.actionLabel!),
                          onPressed: () {
                            _currentNotification!.onAction?.call();
                            setState(() => _currentNotification = null);
                          },
                        )
                      : null,
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
                    color: _ready
                        ? const Color(0xFF2ECC71)
                        : Colors.grey[100],
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
                      : const Icon(FluentIcons.microphone, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 24),

                // Brand
                Text(
                  "子曰",
                  style: theme.typography.title?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 16),

                // Status
                Builder(builder: (_) {
                  if (_lastError.isNotEmpty) {
                    return Text(_lastError, style: TextStyle(color: Colors.red));
                  }
                  if (_isRecording) {
                    return Text(
                      loc?.recording ?? "录音中...",
                      style: const TextStyle(color: Color(0xFF2ECC71)),
                    );
                  }
                  if (!_ready) {
                    return Text(
                      _status,
                      style: TextStyle(color: Colors.grey[120]),
                    );
                  }
                  return Text(
                    loc?.readyTip(_currentKeyName) ?? "按住 $_currentKeyName 开始语音输入",
                    style: TextStyle(color: Colors.grey[120]),
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
                    color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
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
