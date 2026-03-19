import 'dart:async';
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
/// Uses async buffered IO — writeln() goes to memory buffer (~0 cost),
/// periodic flush every 500ms writes to disk without blocking main thread.
/// All errors are caught internally — logging never crashes the caller.
///
/// Usage:
///   AppLog.d('[MyService] something happened');
class AppLog {
  AppLog._();

  /// Runtime switch — set via AppService.applyVerboseLogging()
  static bool enabled = AppConstants.kVerboseLogging;

  static IOSink? _sink;
  static bool _initAttempted = false;
  // ignore: unused_field — held to prevent GC
  static Timer? _flushTimer;

  /// Initialize log file. Called once at startup.
  static Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/speakout.log');
      // Truncate if > 5MB to prevent unbounded growth
      if (file.existsSync() && file.lengthSync() > 5 * 1024 * 1024) {
        file.writeAsStringSync('');
      }
      _sink = file.openWrite(mode: FileMode.append);
      _sink!.writeln('\n=== SpeakOut started at ${DateTime.now().toIso8601String()} ===');
      // Periodic flush every 500ms
      _flushTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _safeFlush();
      });
    } catch (_) {
      _sink = null;
    }
  }

  static bool _flushing = false;

  static void _safeFlush() {
    if (_sink == null || _flushing) return;
    _flushing = true;
    _sink!.flush().then((_) {
      _flushing = false;
    }).catchError((_) {
      _flushing = false;
    });
  }

  static void d(String message) {
    if (!enabled) return;
    try {
      debugPrint(message);
      _sink?.writeln('${DateTime.now().toIso8601String()} $message');
    } catch (_) {
      // Logging must never crash the caller
    }
  }
}
