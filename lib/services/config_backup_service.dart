import 'dart:convert';
import 'dart:io';
import '../config/app_log.dart';
import 'config_service.dart';
import 'cloud_account_service.dart';

/// 配置备份导入结果
class BackupResult {
  final bool success;
  final int totalEntries;
  final int settingsCount;
  final int credentialCount;
  final String? error;

  BackupResult({
    required this.success,
    this.totalEntries = 0,
    this.settingsCount = 0,
    this.credentialCount = 0,
    this.error,
  });
}

/// 配置备份与恢复服务
///
/// 导出：将所有 SharedPreferences 设置导出为 JSON 文件。
/// 导入：从 JSON 文件恢复所有设置。
/// 不包含离线模型文件（需重新下载）。
/// 永不导出凭证（API key / AK·SK / token / license）。
class ConfigBackupService {
  static const _kBackupVersion = 1;

  /// 导出所有配置到 JSON 文件。
  /// 所有敏感凭证 key 均排除，避免明文密钥（含已删账户残留的 cloud_cred_*）泄露。
  static Future<BackupResult> exportToFile(String filePath) async {
    try {
      final preferences = ConfigService().snapshotPreferencesForBackup();

      int settingsCount = 0;
      final prefsData = <String, dynamic>{};
      for (final entry in preferences.entries) {
        final key = entry.key;
        if (_isMachineLocalKey(key)) continue; // 换机器无意义，见下方说明
        if (_isCredentialKey(key)) continue;
        final value = entry.value;
        prefsData[key] = {'type': _typeOf(value), 'value': value};
        settingsCount++;
      }

      final backup = {
        'version': _kBackupVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'app': 'SpeakOut',
        'preferences': prefsData,
      };

      final file = File(filePath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(backup),
      );

      AppLog.d(
        '[ConfigBackup] Exported ${prefsData.length} entries to $filePath',
      );
      return BackupResult(
        success: true,
        totalEntries: prefsData.length,
        settingsCount: settingsCount,
      );
    } catch (e) {
      AppLog.d('[ConfigBackup] Export failed: $e');
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// 从 JSON 文件导入配置
  static Future<BackupResult> importFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return BackupResult(success: false, error: '文件不存在');
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return BackupResult(success: false, error: '不是有效的 SpeakOut 配置文件');
      }
      final backup = decoded;

      if (backup['app'] != 'SpeakOut' || backup['version'] != _kBackupVersion) {
        return BackupResult(success: false, error: '不是有效的 SpeakOut 配置文件');
      }

      int settingsCount = 0;
      int credentialCount = 0;
      final values = <String, Object>{};

      final rawPreferences = backup['preferences'];
      if (rawPreferences is! Map<String, dynamic>) {
        return BackupResult(success: false, error: '配置文件缺少 preferences');
      }
      final prefsData = rawPreferences;
      for (final entry in prefsData.entries) {
        final key = entry.key;
        if (_isMachineLocalKey(key)) continue; // 旧备份里可能还带着，导入侧也要挡
        final rawMeta = entry.value;
        if (rawMeta is! Map<String, dynamic>) {
          throw FormatException('配置项 $key 格式无效');
        }
        final meta = rawMeta;
        final type = meta['type'] as String?;
        final value = meta['value'];
        final validated = _validatedValue(key, type, value);
        if (key == 'cloud_accounts') {
          CloudAccountService.validateStoredAccountsJson(validated as String);
        }
        values[key] = validated;

        if (_isCredentialKey(key)) {
          credentialCount++;
        } else {
          settingsCount++;
        }
      }

      await ConfigService().restorePreferencesFromBackup(values);
      await CloudAccountService().reload();

      final total = settingsCount + credentialCount;
      AppLog.d(
        '[ConfigBackup] Imported $total entries ($settingsCount settings, $credentialCount credentials)',
      );
      return BackupResult(
        success: true,
        totalEntries: total,
        settingsCount: settingsCount,
        credentialCount: credentialCount,
      );
    } catch (e) {
      AppLog.d('[ConfigBackup] Import failed: $e');
      return BackupResult(success: false, error: e.toString());
    }
  }

  static String _typeOf(dynamic val) {
    if (val is String) return 'String';
    if (val is int) return 'int';
    if (val is double) return 'double';
    if (val is bool) return 'bool';
    if (val is List<String>) return 'List<String>';
    return 'String';
  }

  static Object _validatedValue(String key, String? type, Object? value) {
    switch (type) {
      case 'String':
        if (value is String) return value;
      case 'int':
        if (value is int) return value;
      case 'double':
        if (value is num) return value.toDouble();
      case 'bool':
        if (value is bool) return value;
      case 'List<String>':
        if (value is List && value.every((item) => item is String)) {
          return List<String>.from(value);
        }
    }
    throw FormatException('配置项 $key 的类型或值无效');
  }

  /// 绑定在本机、不能随配置迁移的 key。
  ///
  /// `diary_directory` 在 macOS 沙盒版下**只是一半状态**：真正的授权是
  /// AppDelegate 存的 security-scoped bookmark，那东西不可移植、也不在这份备份里。
  /// 把路径导过去，另一台机器上就是「配置指着一个没有授权的目录」——
  /// 用户看到的是闪念保存失败，却完全不知道原因。宁可让他重新选一次目录。
  static bool _isMachineLocalKey(String key) {
    return key == 'diary_directory' || key == 'billing_device_id';
  }

  /// 判断 key 是否为敏感凭证（云账户凭证 / API key / 阿里云 AK·SK·appkey / token）。
  /// 用于导出时默认排除，避免明文密钥泄露。
  static bool _isCredentialKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('cred_') ||
        normalized.contains('credential') ||
        normalized.contains('api_key') ||
        normalized.contains('api_secret') ||
        normalized.contains('password') ||
        normalized.contains('access_key') ||
        normalized.contains('ak_id') ||
        normalized.contains('ak_secret') ||
        normalized.contains('app_key') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('license');
  }
}
