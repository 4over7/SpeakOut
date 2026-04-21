import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../engine/core_engine.dart';
import '../../theme.dart';
import '../settings_shared.dart';

/// 热键 modal 的返回值
class HotkeyRecorderResult {
  final int keyCode;
  final int modifiers;
  final String displayName;

  const HotkeyRecorderResult(this.keyCode, this.modifiers, this.displayName);
}

/// 弹出热键录制 modal（半透明蒙层 + 居中卡片 + 倒计时 15s）
///
/// 返回 [HotkeyRecorderResult] 或 null（用户按 ESC 取消 / 超时）。
Future<HotkeyRecorderResult?> showHotkeyRecorder(
  BuildContext context, {
  String? title,
  String? subtitle,
}) {
  return showDialog<HotkeyRecorderResult>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => HotkeyRecorderModal(
      title: title ?? '录制快捷键',
      subtitle: subtitle ?? '请按下您想要设置的按键或组合键',
    ),
  );
}

class HotkeyRecorderModal extends StatefulWidget {
  final String title;
  final String subtitle;

  const HotkeyRecorderModal({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  State<HotkeyRecorderModal> createState() => _HotkeyRecorderModalState();
}

class _HotkeyRecorderModalState extends State<HotkeyRecorderModal> {
  static const int _totalSeconds = 15;

  HotkeyCapturer? _capturer;
  Timer? _tickTimer;
  int _secondsLeft = _totalSeconds;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _capturer = HotkeyCapturer(
      keyStream: CoreEngine().rawKeyEventStream,
      timeout: const Duration(seconds: _totalSeconds),
      onCaptured: _onCaptured,
      onTimeout: _onTimeout,
    )..start();

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 0) return;
      setState(() => _secondsLeft--);
    });
  }

  void _onCaptured(int keyCode, int modifierFlags) {
    // Escape → 取消
    if (keyCode == 53) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final requiredMods = stripOwnModifier(keyCode, modifierFlags);
    final name = mapKeyCodeToString(keyCode);
    final display = requiredMods != 0 ? comboKeyName(keyCode, requiredMods) : name;
    if (mounted) {
      Navigator.of(context).pop(HotkeyRecorderResult(keyCode, requiredMods, display));
    }
  }

  void _onTimeout() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _capturer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.getAccent(context);
    final progress = _secondsLeft / _totalSeconds;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          decoration: BoxDecoration(
            color: AppTheme.getCardBackground(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.getBorder(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosIcon(CupertinoIcons.keyboard, size: 44, color: accent),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.getTextSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              // 倒计时进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AppTheme.getBorder(context),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_secondsLeft 秒后自动取消 · 按 ESC 立即退出',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.getInputBackground(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '推荐',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Right Option · Fn · F13–F19',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.getTextPrimary(context),
                        fontFamily: 'SF Mono',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '避开 Cmd / Ctrl 等常被系统应用占用的组合键',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.getTextSecondary(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
