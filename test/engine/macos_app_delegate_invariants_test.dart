import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

  group('macOS 录音浮窗原生库', () {
    test('安装包与普通 Flutter 构建路径都可解析', () {
      expect(
        source,
        contains('/Contents/MacOS/native_lib/libnative_input.dylib'),
      );
      expect(
        source,
        contains('/Contents/Frameworks/App.framework/Versions/A/Resources/'),
      );
      expect(
        source,
        contains('flutter_assets/native_lib/libnative_input.dylib'),
      );
      expect(
        source,
        contains('FileManager.default.fileExists(atPath: dylibPath)'),
      );
      expect(source, contains('audioDylibHandle = handle'));
      expect(source, contains('dlclose(handle)'));
    });

    test('重复 show 不会叠加波形定时器', () {
      final method = RegExp(
        r'private func startWaveAnimation\(\) \{([\s\S]*?)\n  \}',
      ).firstMatch(source)?.group(1);
      expect(method, isNotNull);
      final invalidateAt = method!.indexOf('waveTimer?.invalidate()');
      final scheduleAt = method.indexOf('Timer.scheduledTimer');
      expect(invalidateAt, greaterThanOrEqualTo(0));
      expect(scheduleAt, greaterThan(invalidateAt));
    });
  });

  group('macOS 原生 UI 隐私与本地化', () {
    test('启动回调保留 Flutter 插件生命周期转发', () {
      final method = RegExp(
        r'override func applicationDidFinishLaunching\([^}]+\}',
      ).firstMatch(source)?.group(0);
      expect(method, isNotNull);
      expect(
        method,
        contains('super.applicationDidFinishLaunching(notification)'),
      );
    });

    test('日志不输出识别文本或用户目录', () {
      final logs = RegExp(r'NSLog\([\s\S]*?\)').allMatches(source);
      for (final log in logs) {
        final statement = log.group(0)!;
        expect(statement, isNot(contains('initialText')));
        expect(statement, isNot(contains('.path')));
      }
      expect(source, isNot(contains('details: url.path')));
    });

    test('文件面板不覆盖系统本地化按钮与提示', () {
      expect(source, isNot(contains('panel.prompt = "')));
      expect(source, isNot(contains('panel.message = "')));
    });

    test('系统权限说明同时打包中英文', () {
      final project = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(project, contains('InfoPlist.strings in Resources'));
      expect(project, contains('zh-Hans.lproj/InfoPlist.strings'));

      for (final path in [
        'macos/Runner/en.lproj/InfoPlist.strings',
        'macos/Runner/zh-Hans.lproj/InfoPlist.strings',
      ]) {
        final strings = File(path).readAsStringSync();
        expect(strings, contains('NSMicrophoneUsageDescription'));
        expect(strings, contains('NSAccessibilityUsageDescription'));
      }
    });
  });
}
