import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speakout/services/config_backup_service.dart';

/// A3：配置导出默认排除凭证，避免明文密钥（含残留 cloud_cred_*）泄露
void main() {
  late Directory tmpDir;
  late String exportPath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('speakout_backup_test_');
    exportPath = '${tmpDir.path}/export.json';
    SharedPreferences.setMockInitialValues({
      'verbose_logging': true, // 普通设置
      'work_mode': 'offline', // 普通设置
      'llm_api_key': 'sk-secret', // 凭证
      'aliyun_ak_id': 'akId', // 凭证
      'aliyun_ak_secret': 'akSecret', // 凭证
      'aliyun_app_key': 'appKey', // 凭证
      'cloud_cred_acc1_api_key': 'k1', // 凭证（账户凭证）
      'gateway_token': 'tok', // 凭证（token）
    });
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> readExportedPrefs() {
    final json = jsonDecode(File(exportPath).readAsStringSync()) as Map<String, dynamic>;
    return json['preferences'] as Map<String, dynamic>;
  }

  group('ConfigBackupService 导出凭证排除', () {
    test('默认导出排除所有凭证 key，保留普通设置', () async {
      final r = await ConfigBackupService.exportToFile(exportPath);
      expect(r.success, true);
      final prefs = readExportedPrefs();
      // 普通设置保留
      expect(prefs.containsKey('verbose_logging'), true);
      expect(prefs.containsKey('work_mode'), true);
      // 凭证全部排除
      expect(prefs.containsKey('llm_api_key'), false);
      expect(prefs.containsKey('aliyun_ak_id'), false);
      expect(prefs.containsKey('aliyun_ak_secret'), false);
      expect(prefs.containsKey('aliyun_app_key'), false);
      expect(prefs.containsKey('cloud_cred_acc1_api_key'), false);
      expect(prefs.containsKey('gateway_token'), false);
      expect(r.credentialCount, 0);
    });

    test('includeCredentials=true 时包含凭证', () async {
      final r = await ConfigBackupService.exportToFile(exportPath, includeCredentials: true);
      expect(r.success, true);
      final prefs = readExportedPrefs();
      expect(prefs.containsKey('llm_api_key'), true);
      expect(prefs.containsKey('cloud_cred_acc1_api_key'), true);
      expect(prefs.containsKey('aliyun_ak_secret'), true);
      expect(r.credentialCount, greaterThanOrEqualTo(6));
    });
  });
}
