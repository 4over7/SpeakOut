import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/config/app_log.dart';
import 'package:speakout/services/app_service.dart';
import 'package:speakout/services/config_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = Directory.systemTemp.createTempSync(
      'speakout_app_service_log_test_',
    );
    PathProviderPlatform.instance = MockPathProviderPlatform(
      tempDirectory.path,
    );
    SharedPreferences.setMockInitialValues({
      'verbose_logging': false,
      'log_directory': '',
    });
    await ConfigService().reload();
  });

  tearDown(() async {
    await AppLog.dispose();
    AppLog.customLogDirectory = null;
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('清空日志目录后不再沿用旧的自定义目录', () async {
    AppLog.customLogDirectory = '${tempDirectory.path}/old';

    await AppService().applyVerboseLogging();

    expect(AppLog.customLogDirectory, isNull);
  });
}
