import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'app_constants.dart';

/// Centralized logging utility.
///
/// Use [AppLog.d] instead of [debugPrint] throughout the codebase.
/// Controlled by [AppLog.enabled], which is initialized from ConfigService
/// at startup (see AppService.init). Defaults to [AppConstants.kVerboseLogging].
///
/// When enabled, logs are written to both stdout AND a log file at:
///   ~/Library/Application Support/com.speakout.speakout/speakout.log
///
/// Uses synchronous file append — each line is immediately committed to disk,
/// crash-safe, and no StreamSink conflicts (~0.1ms per write on SSD).
///
/// Usage:
///   AppLog.d('[MyService] something happened');
class AppLog {
  AppLog._();

  /// Runtime switch — set via AppService.applyVerboseLogging()
  static bool enabled = AppConstants.kVerboseLogging;

  static File? _logFile;
  static bool _initAttempted = false;

  /// Initialize log file. Called once at startup.
  static Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/speakout.log');
      // Truncate if > 5MB to prevent unbounded growth
      if (_logFile!.existsSync() && _logFile!.lengthSync() > 5 * 1024 * 1024) {
        _logFile!.writeAsStringSync('');
      }
      _logFile!.writeAsStringSync(
        '\n=== SpeakOut started at ${DateTime.now().toIso8601String()} ===\n',
        mode: FileMode.append,
      );
    } catch (_) {
      _logFile = null;
    }
  }

  static void d(String message) {
    if (enabled) {
      debugPrint(message);
      _logFile?.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
      );
    }
  }
}
