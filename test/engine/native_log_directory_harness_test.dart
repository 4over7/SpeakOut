import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native 清空自定义日志目录后恢复默认路径', () {
    const source = 'native_lib/tests/log_directory_harness.m';
    expect(File(source).existsSync(), isTrue, reason: '找不到测试宿主源码');

    final outputDirectory = Directory.systemTemp.createTempSync(
      'speakout_log_directory_harness_',
    );
    addTearDown(() {
      if (outputDirectory.existsSync()) {
        outputDirectory.deleteSync(recursive: true);
      }
    });
    final binary = '${outputDirectory.path}/log_directory_harness';
    final build = Process.runSync('clang', [
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
      '-o',
      binary,
      source,
    ]);
    expect(build.exitCode, 0, reason: '宿主编译失败:\n${build.stderr}');

    final run = Process.runSync(binary, []);
    expect(run.exitCode, 0, reason: '日志目录行为不符：\n${run.stdout}');
    expect(run.stdout, contains('ALL PASSED'));
  }, skip: !Platform.isMacOS);
}
