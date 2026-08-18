import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speakout/config/app_log.dart';

class _DelayedPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _DelayedPathProvider(this.path);

  final Future<String?> path;

  @override
  Future<String?> getApplicationSupportPath() => path;
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'speakout_log_lifecycle_test_',
    );
    AppLog.enabled = true;
  });

  tearDown(() async {
    await AppLog.dispose();
    AppLog.enabled = false;
    AppLog.customLogDirectory = null;
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('同一路径首次初始化失败后可以重试', () async {
    final logDirectoryPath = '${tempDirectory.path}/logs';
    final blocker = File(logDirectoryPath)..writeAsStringSync('not a dir');
    AppLog.customLogDirectory = logDirectoryPath;

    await AppLog.init();
    blocker.deleteSync();
    Directory(logDirectoryPath).createSync();

    await AppLog.init();
    AppLog.d('retry succeeded');
    await AppLog.flushForTest();

    final logFile = File('$logDirectoryPath/speakout.log');
    expect(logFile.existsSync(), isTrue);
    expect(logFile.readAsStringSync(), contains('retry succeeded'));
  });

  test('目录切换排队时 dispose 等待全部初始化并最终关闭 sink', () async {
    final defaultPath = Completer<String?>();
    PathProviderPlatform.instance = _DelayedPathProvider(defaultPath.future);
    AppLog.customLogDirectory = null;

    final firstInit = AppLog.init();
    final customPath = '${tempDirectory.path}/custom';
    AppLog.customLogDirectory = customPath;
    final secondInit = AppLog.init();
    final dispose = AppLog.dispose();

    defaultPath.complete(tempDirectory.path);
    await Future.wait([firstInit, secondInit, dispose]);

    AppLog.d('must stay closed');
    await AppLog.flushForTest();

    final customLog = File('$customPath/speakout.log');
    expect(customLog.existsSync(), isTrue);
    expect(customLog.readAsStringSync(), isNot(contains('must stay closed')));
  });
}
