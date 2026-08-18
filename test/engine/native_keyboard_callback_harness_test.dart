import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EventTap 只能经受保护入口调用 Dart trampoline', () {
    final source = File('native_lib/native_input.m').readAsStringSync();
    expect(RegExp(r'\bdartCallback\s*\(').hasMatch(source), isFalse);
    expect(source, contains('emit_key_callback(mappedKeyCode'));
    expect(source, contains('emit_key_callback((int)keyCode'));
  });

  test('stop_keyboard_listener 等待在途 Dart trampoline', () async {
    if (!Platform.isMacOS) return;

    const source = 'native_lib/tests/keyboard_callback_harness.m';
    final outputDirectory = Directory.systemTemp.createTempSync(
      'speakout_keyboard_callback_harness_',
    );
    final binary = '${outputDirectory.path}/keyboard_callback_harness';

    try {
      final compile = await Process.run('clang', [
        '-fobjc-arc',
        '-framework',
        'Cocoa',
        '-framework',
        'Carbon',
        '-framework',
        'AVFoundation',
        '-framework',
        'AudioToolbox',
        '-framework',
        'CoreAudio',
        '-framework',
        'Accelerate',
        source,
        '-o',
        binary,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '编译失败：${compile.stdout}\n${compile.stderr}',
      );

      final run = await Process.run(binary, const []);
      expect(run.exitCode, 0, reason: '并发宿主失败：${run.stdout}\n${run.stderr}');
      expect(run.stdout, contains('ALL PASSED'));
    } finally {
      outputDirectory.deleteSync(recursive: true);
    }
  });
}
