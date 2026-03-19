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
/// Usage:
///   AppLog.d('[MyService] something happened');
class AppLog {
  AppLog._();

  /// Runtime switch — set via AppService.applyVerboseLogging()
  static bool enabled = AppConstants.kVerboseLogging;

  static IOSink? _sink;
  static bool _initAttempted = false;

  /// Initialize log file. Called once at startup.
  static Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/speakout.log');
      // Truncate if > 5MB to prevent unbounded growth
      if (file.existsSync() && file.lengthSync() > 5 * 1024 * 1024) {
        await file.writeAsString('');
      }
      _sink = file.openWrite(mode: FileMode.append);
      _sink!.writeln('\n=== SpeakOut started at ${DateTime.now().toIso8601String()} ===');
    } catch (_) {
      // Silently fail — logging should never crash the app
    }
  }

  static void d(String message) {
    if (enabled) {
      debugPrint(message);
      _sink?.writeln('${DateTime.now().toIso8601String()} $message');
    }
  }
}
