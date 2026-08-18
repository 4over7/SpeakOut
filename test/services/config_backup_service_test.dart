import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:speakout/services/config_backup_service.dart';
import 'package:speakout/services/config_service.dart';

class _FailOnceWriteStore extends InMemorySharedPreferencesStore {
  _FailOnceWriteStore(super.data, this.keyToFail) : super.withData();

  final String keyToFail;
  bool _failed = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (!_failed && key == keyToFail) {
      _failed = true;
      return Future.error(StateError('injected write failure'));
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late String backupPath;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('speakout_backup_test_');
    backupPath = '${tmpDir.path}/backup.json';
    SharedPreferences.setMockInitialValues({});
    await ConfigService().reload();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<void> writeBackup(
    Map<String, Object?> preferences, {
    int version = 1,
  }) async {
    await File(backupPath).writeAsString(
      jsonEncode({
        'version': version,
        'app': 'SpeakOut',
        'preferences': preferences,
      }),
    );
  }

  Map<String, dynamic> readExportedPreferences() {
    final json =
        jsonDecode(File(backupPath).readAsStringSync()) as Map<String, dynamic>;
    return json['preferences'] as Map<String, dynamic>;
  }

  group('导出安全边界', () {
    test('永不导出凭证与本机标识，保留普通设置', () async {
      SharedPreferences.setMockInitialValues({
        'verbose_logging': true,
        'work_mode': 'offline',
        'llm_api_key': 'sk-secret',
        'cloud_cred_acc1_api_key': 'k1',
        'tencent_secret_id': 'secret-id',
        'tencent_secret_key': 'secret-key',
        'gateway_token': 'token',
        'license_key': 'license',
        'billing_device_id': 'machine-id',
        'diary_directory': '/machine/local',
      });
      await ConfigService().reload();

      final result = await ConfigBackupService.exportToFile(backupPath);

      expect(result.success, isTrue);
      final preferences = readExportedPreferences();
      expect(preferences.keys, containsAll(['verbose_logging', 'work_mode']));
      expect(preferences.keys, isNot(contains('llm_api_key')));
      expect(preferences.keys, isNot(contains('cloud_cred_acc1_api_key')));
      expect(preferences.keys, isNot(contains('tencent_secret_id')));
      expect(preferences.keys, isNot(contains('tencent_secret_key')));
      expect(preferences.keys, isNot(contains('gateway_token')));
      expect(preferences.keys, isNot(contains('license_key')));
      expect(preferences.keys, isNot(contains('billing_device_id')));
      expect(preferences.keys, isNot(contains('diary_directory')));
      expect(result.credentialCount, 0);
    });
  });

  group('导入格式验证', () {
    test('支持的五种类型完整恢复', () async {
      await writeBackup({
        'string_value': {'type': 'String', 'value': 'text'},
        'int_value': {'type': 'int', 'value': 7},
        'double_value': {'type': 'double', 'value': 1.5},
        'bool_value': {'type': 'bool', 'value': true},
        'list_value': {
          'type': 'List<String>',
          'value': ['a', 'b'],
        },
      });

      final result = await ConfigBackupService.importFromFile(backupPath);

      expect(result.success, isTrue);
      final values = ConfigService().snapshotPreferencesForBackup();
      expect(values['string_value'], 'text');
      expect(values['int_value'], 7);
      expect(values['double_value'], 1.5);
      expect(values['bool_value'], isTrue);
      expect(values['list_value'], ['a', 'b']);
    });

    test('后置条目类型错误时一个条目也不写入', () async {
      SharedPreferences.setMockInitialValues({'first': 'old'});
      await ConfigService().reload();
      await writeBackup({
        'first': {'type': 'String', 'value': 'new'},
        'broken': {'type': 'int', 'value': 'not-an-int'},
      });

      final result = await ConfigBackupService.importFromFile(backupPath);

      expect(result.success, isFalse);
      final values = ConfigService().snapshotPreferencesForBackup();
      expect(values['first'], 'old');
      expect(values.containsKey('broken'), isFalse);
    });

    test('未知类型与未来版本均拒绝', () async {
      await writeBackup({
        'value': {'type': 'Map', 'value': <String, Object>{}},
      });
      expect(
        (await ConfigBackupService.importFromFile(backupPath)).success,
        isFalse,
      );

      await writeBackup({}, version: 2);
      expect(
        (await ConfigBackupService.importFromFile(backupPath)).success,
        isFalse,
      );
    });

    test('损坏的云账户结构在写入前拒绝', () async {
      SharedPreferences.setMockInitialValues({'cloud_accounts': '[]'});
      await ConfigService().reload();
      await writeBackup({
        'cloud_accounts': {'type': 'String', 'value': '{broken'},
      });

      final result = await ConfigBackupService.importFromFile(backupPath);

      expect(result.success, isFalse);
      expect(
        ConfigService().snapshotPreferencesForBackup()['cloud_accounts'],
        '[]',
      );
    });
  });

  test('持久化中途失败会恢复已写入条目', () async {
    SharedPreferences.resetStatic();
    final store = _FailOnceWriteStore({
      'flutter.first': 'old',
    }, 'flutter.second');
    SharedPreferencesStorePlatform.instance = store;
    await ConfigService().reload();
    await writeBackup({
      'first': {'type': 'String', 'value': 'new'},
      'second': {'type': 'String', 'value': 'will-fail'},
    });

    final result = await ConfigBackupService.importFromFile(backupPath);

    expect(result.success, isFalse);
    expect(ConfigService().snapshotPreferencesForBackup()['first'], 'old');
    final stored = await store.getAll();
    expect(stored['flutter.first'], 'old');
    expect(stored.containsKey('flutter.second'), isFalse);
  });
}
