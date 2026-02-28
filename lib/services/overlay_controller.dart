import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Whether native overlay is available (macOS only)
  bool get _hasNativeOverlay => Platform.isMacOS;

  Future<void> show() async {
    if (!_hasNativeOverlay) return;
    _invoke('showRecording', {"mode": isOfflineMode ? "offline" : "streaming"});
  }

  Future<void> hide() async {
    if (!_hasNativeOverlay) return;
    _invoke('hideRecording');
  }

  void updateText(String text, {int maxLen = 12}) {
    if (!_hasNativeOverlay) return;
    String display = text;
    if (display.length > maxLen) {
      display = "...${display.substring(display.length - maxLen)}";
    }
    _invoke('updateStatus', {"text": display});
  }

  /// Show text on overlay, then clear after [delay].
  void showThenClear(String text, Duration delay) {
    if (!_hasNativeOverlay) return;
    _invoke('updateStatus', {"text": text});
    Future.delayed(delay, () {
      _invoke('updateStatus', {"text": ""});
    });
  }

  void _invoke(String method, [Map<String, dynamic>? args]) {
    try {
      _channel.invokeMethod(method, args);
    } catch (e) {
      debugPrint("[OverlayController] $method error: $e");
    }
  }
}
