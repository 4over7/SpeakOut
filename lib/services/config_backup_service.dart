import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
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

  BackupResult({required this.success, this.totalEntries = 0, this.settingsCount = 0, this.credentialCount = 0, this.error});

  String get message {
    if (!success) return error ?? '操作失败';
    final parts = <String>[];
    if (settingsCount > 0) parts.add('$settingsCount 项设置');
    if (credentialCount > 0) parts.add('$credentialCount 项凭证');
    return parts.isEmpty ? '已完成' : '已恢复 ${parts.join("、")}';
  }
}

/// 配置备份与恢复服务
///
/// 导出：将所有 SharedPreferences 设置导出为 JSON 文件。
/// 导入：从 JSON 文件恢复所有设置。
/// 不包含离线模型文件（需重新下载）。
/// 默认不导出凭证（API key / AK·SK / token）；如需含凭证须显式 includeCredentials=true。
class ConfigBackupService {
  static const _kBackupVersion = 1;

  /// 导出所有配置到 JSON 文件。
  /// [includeCredentials] 为 false（默认）时排除所有敏感凭证 key，
  /// 避免明文密钥（含已删账户残留的 cloud_cred_*）泄露到备份文件。
  static Future<BackupResult> exportToFile(String filePath, {bool includeCredentials = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      int settingsCount = 0;
      int credentialCount = 0;
      final prefsData = <String, dynamic>{};
      for (final key in allKeys) {
        final isCred = _isCredentialKey(key);
        if (isCred && !includeCredentials) continue; // 默认跳过凭证
        final val = prefs.get(key);
        if (val != null) {
          prefsData[key] = {'type': _typeOf(val), 'value': val};
          if (isCred) {
            credentialCount++;
          } else {
            settingsCount++;
          }
        }
      }

      final backup = {
        'version': _kBackupVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'app': 'SpeakOut',
        'preferences': prefsData,
      };

      final file = File(filePath);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(backup));

      AppLog.d('[ConfigBackup] Exported ${prefsData.length} entries to $filePath');
      return BackupResult(success: true, totalEntries: prefsData.length, settingsCount: settingsCount, credentialCount: credentialCount);
    } catch (e) {
      AppLog.d('[ConfigBackup] Export failed: $e');
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// 从 JSON 文件导入配置
  static Future<BackupResult> importFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return BackupResult(success: false, error: '文件不存在');

      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      if (backup['app'] != 'SpeakOut') {
        return BackupResult(success: false, error: '不是有效的 SpeakOut 配置文件');
      }

      final prefs = await SharedPreferences.getInstance();
      int settingsCount = 0;
      int credentialCount = 0;

      final prefsData = backup['preferences'] as Map<String, dynamic>? ?? {};
      for (final entry in prefsData.entries) {
        final key = entry.key;
        final meta = entry.value as Map<String, dynamic>;
        final type = meta['type'] as String?;
        final value = meta['value'];

        switch (type) {
          case 'String':
            await prefs.setString(key, value as String);
          case 'int':
            await prefs.setInt(key, value as int);
          case 'double':
            await prefs.setDouble(key, (value as num).toDouble());
          case 'bool':
            await prefs.setBool(key, value as bool);
          case 'List<String>':
            await prefs.setStringList(key, (value as List).cast<String>());
        }

        if (_isCredentialKey(key)) {
          credentialCount++;
        } else {
          settingsCount++;
        }
      }

      // 重新加载各 service 的内存缓存，无需重启
      await ConfigService().reload();
      await CloudAccountService().reload();

      final total = settingsCount + credentialCount;
      AppLog.d('[ConfigBackup] Imported $total entries ($settingsCount settings, $credentialCount credentials)');
      return BackupResult(success: true, totalEntries: total, settingsCount: settingsCount, credentialCount: credentialCount);
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

  /// 判断 key 是否为敏感凭证（云账户凭证 / API key / 阿里云 AK·SK·appkey / token）。
  /// 用于导出时默认排除，避免明文密钥泄露。
  static bool _isCredentialKey(String key) {
    return key.contains('cred_') ||
        key.contains('api_key') ||
        key.contains('api_secret') ||
        key.contains('api_password') ||
        key.contains('ak_id') ||
        key.contains('ak_secret') ||
        key.contains('app_key') ||
        key.contains('token');
  }
}
