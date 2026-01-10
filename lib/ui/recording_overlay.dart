import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

/// 录音状态悬浮提示 - 现代毛玻璃设计
class RecordingOverlay extends StatefulWidget {
  final bool isRecording;
  final String? statusText;
  
  const RecordingOverlay({
    super.key,
    required this.isRecording,
    this.statusText,
  });

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay> {
  final List<double> _barHeights = List.generate(7, (_) => 0.3);
  Timer? _waveTimer;
  final Random _random = Random();

  @override
  void didUpdateWidget(RecordingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _startWaveAnimation();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _stopWaveAnimation();
    }
  }

  void _startWaveAnimation() {
    // Wave animation - lightweight, just updating 7 heights every 80ms
    _waveTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) {
        setState(() {
          for (int i = 0; i < _barHeights.length; i++) {
            _barHeights[i] = 0.15 + _random.nextDouble() * 0.85;
          }
        });
      }
    });
  }

  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
    if (mounted) {
      setState(() {
        for (int i = 0; i < _barHeights.length; i++) {
          _barHeights[i] = 0.3;
        }
      });
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.statusText != null && widget.statusText!.isNotEmpty;
    // Show overlay when recording OR when there's text to display
    if (!widget.isRecording && !hasText) return const SizedBox.shrink();

    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              constraints: const BoxConstraints(
                minWidth: 120,
                maxWidth: 400,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Waveform bars only (no indicator dot)
                  SizedBox(
                    width: 70,
                    height: 28,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(7, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          curve: Curves.easeInOut,
                          width: 5,
                          height: 28 * _barHeights[index],
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        );
                      }),
                    ),
                  ),
                  // Text area with more spacing
                  if (hasText) ...[
                    const SizedBox(width: 20),
                    Flexible(
                      child: Text(
                        widget.statusText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
