import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized controller for the native recording overlay.
/// Single source of truth — all overlay updates go through here.
class OverlayController {
  static final OverlayController _instance = OverlayController._();
  factory OverlayController() => _instance;
  OverlayController._();

  static const _channel = MethodChannel('com.SpeakOut/overlay');

  Future<void> show() async {
    _invoke('showRecording');
  }

  Future<void> hide() async {
    _invoke('hideRecording');
  }

  void updateText(String text, {int maxLen = 12}) {
    String display = text;
    if (display.length > maxLen) {
      display = "...${display.substring(display.length - maxLen)}";
    }
    _invoke('updateStatus', {"text": display});
  }

  /// Show text on overlay, then clear after [delay].
  void showThenClear(String text, Duration delay) {
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
