import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_log.dart';
import 'config_service.dart';
import 'cloud_account_service.dart';

/// 配置备份与恢复服务
///
/// 导出：将所有 SharedPreferences 设置导出为 JSON 文件。
/// 导入：从 JSON 文件恢复所有设置。
/// 不包含离线模型文件（需重新下载）。
/// 安全性由用户自行保障（导出文件含明文凭证）。
class ConfigBackupService {
  static const _kBackupVersion = 1;

  /// 导出所有配置到 JSON 文件
  /// 返回导出的条目数量，失败返回 -1
  static Future<int> exportToFile(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      final prefsData = <String, dynamic>{};
      for (final key in allKeys) {
        final val = prefs.get(key);
        if (val != null) {
          prefsData[key] = {'type': _typeOf(val), 'value': val};
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
      return prefsData.length;
    } catch (e) {
      AppLog.d('[ConfigBackup] Export failed: $e');
      return -1;
    }
  }

  /// 从 JSON 文件导入配置
  /// 返回导入的条目数量，失败返回 -1
  static Future<int> importFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return -1;

      final content = await file.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      if (backup['app'] != 'SpeakOut') {
        AppLog.d('[ConfigBackup] Invalid backup file: not a SpeakOut backup');
        return -1;
      }

      final prefs = await SharedPreferences.getInstance();
      int restored = 0;

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
        restored++;
      }

      // 重新加载各 service 的内存缓存，无需重启
      await ConfigService().reload();
      await CloudAccountService().reload();

      AppLog.d('[ConfigBackup] Imported $restored entries from $filePath');
      return restored;
    } catch (e) {
      AppLog.d('[ConfigBackup] Import failed: $e');
      return -1;
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
}
