import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native 音频停止状态回传', () {
    const src = 'native_lib/tests/audio_stop_harness.m';
    expect(File(src).existsSync(), isTrue, reason: '找不到测试宿主源码');

    final harness = File(src).readAsStringSync();
    expect(harness.contains('#define AudioQueueStop'), isTrue,
        reason: '宿主不得操作真实 AudioQueue');
    expect(harness.contains('#define AudioQueueDispose'), isTrue,
        reason: '宿主不得释放真实 AudioQueue');

    final out = Directory.systemTemp.createTempSync('speakout_audio_stop_harness');
    try {
      final bin = '${out.path}/audio_stop_harness';
      final build = Process.runSync('clang', [
        '-fobjc-arc',
        '-framework', 'Cocoa',
        '-framework', 'Carbon',
        '-framework', 'AVFoundation',
        '-framework', 'AudioToolbox',
        '-framework', 'CoreAudio',
        '-framework', 'Accelerate',
        '-o', bin,
        src,
      ]);
      expect(build.exitCode, 0, reason: '宿主编译失败:\n${build.stderr}');

      final run = Process.runSync(bin, []);
      expect(run.exitCode, 0, reason: '音频停止行为不符:\n${run.stdout}');
      expect((run.stdout as String).contains('ALL PASSED'), isTrue,
          reason: run.stdout as String);
    } finally {
      out.deleteSync(recursive: true);
    }
  }, skip: !Platform.isMacOS ? 'AudioQueue 测试仅在 macOS 可用' : null);
}
