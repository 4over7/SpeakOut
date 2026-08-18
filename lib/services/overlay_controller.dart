import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:speakout/config/app_log.dart';

/// Centralized controller for the recording overlay.
///
/// - **macOS**: 使用 MethodChannel 调用原生 NSPanel 悬浮窗
/// - **Windows/Linux**: 静默模式 (no-op)，录音状态通过主窗口 UI 显示
///
/// 未来 Windows/Linux 可通过 Flutter OverlayEntry 实现悬浮窗，
/// 但需要 BuildContext 支持，当前 CoreEngine 无法持有 context。
class OverlayController {
  static final OverlayController _instance = OverlayController._();
  factory OverlayController() => _instance;
  OverlayController._();

  static const _channel = MethodChannel('com.SpeakOut/overlay');

  /// Whether the current ASR is offline (no real-time subtitles)
  bool isOfflineMode = false;

  /// Current recording mode: "ptt", "diary", or "organize"
  String recordingMode = "ptt";

  int _statusGeneration = 0;

  /// Whether native overlay is available (macOS only)
  bool get _hasNativeOverlay => Platform.isMacOS;

  Future<void> show() async {
    if (!_hasNativeOverlay) return;
    _statusGeneration++;
    String mode = isOfflineMode ? "offline" : "streaming";
    if (recordingMode == "diary") mode = "diary";
    if (recordingMode == "organize") mode = "organize";
    await _invoke('showRecording', {"mode": mode});
  }

  Future<void> hide() async {
    if (!_hasNativeOverlay) return;
    _statusGeneration++;
    await _invoke('hideRecording');
  }

  void updateText(String text, {int maxLen = 12}) {
    if (!_hasNativeOverlay) return;
    _statusGeneration++;
    String display = text;
    if (display.length > maxLen) {
      display = "...${display.substring(display.length - maxLen)}";
    }
    unawaited(_invoke('updateStatus', {"text": display}));
  }

  void showSilenceHint(String text) {
    if (!_hasNativeOverlay) return;
    unawaited(_invoke('showSilenceHint', {"text": text}));
  }

  void hideSilenceHint() {
    if (!_hasNativeOverlay) return;
    unawaited(_invoke('hideSilenceHint'));
  }

  /// Show text on overlay, then clear after [delay].
  void showThenClear(String text, Duration delay) {
    if (!_hasNativeOverlay) return;
    final generation = ++_statusGeneration;
    unawaited(_invoke('updateStatus', {"text": text}));
    Future.delayed(delay, () {
      if (_statusGeneration != generation) return;
      unawaited(_invoke('updateStatus', {"text": ""}));
    });
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      AppLog.d("[OverlayController] $method error: $e");
    }
  }
}
