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

  /// 是否在日志中记录完整敏感内容（语音原文 / LLM 输入输出 / 错误响应体）。
  /// 默认 false：仅记长度 + 短 hash，避免 speakout.log 与导出日志包泄露邮件/账号/会议等隐私。
  /// 需用户在「开发者选项」显式开启。由 AppService.applyVerboseLogging() 同步。
  static bool logSensitive = false;

  static IOSink? _sink;
  static bool _initAttempted = false;
  static String? _activeLogDirectory; // 当前生效的日志目录
  // ignore: unused_field — held to prevent GC
  static Timer? _flushTimer;

  /// 自定义日志目录（来自设置页"日志输出目录"）
  static String? customLogDirectory;

  /// Initialize log file. Called at startup and when log directory changes.
  static Future<void> init() async {
    // 如果目录没变且已初始化，跳过
    if (_initAttempted && customLogDirectory == _activeLogDirectory) return;
    // 关闭旧 sink
    if (_sink != null) {
      try { await _sink!.flush(); _sink!.close(); } catch (_) {}
      _sink = null;
    }
    // 取消旧 flush timer（切换日志目录重建时避免 timer 泄漏 + 重复 flush）
    _flushTimer?.cancel();
    _flushTimer = null;
    _initAttempted = true;
    _activeLogDirectory = customLogDirectory;
    try {
      final Directory dir;
      if (customLogDirectory != null && customLogDirectory!.isNotEmpty) {
        dir = Directory(customLogDirectory!);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
      } else {
        dir = await getApplicationSupportDirectory();
      }
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

  static Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_sink != null) {
      try { await _sink!.flush(); _sink!.close(); } catch (_) {}
      _sink = null;
    }
    _initAttempted = false;
  }

  /// 脱敏包装：logSensitive=true 时返回原文，否则返回 `<N字 #hash>` 形式的摘要。
  /// 用于语音原文 / LLM 输入输出 / 错误体等敏感字段的日志。
  static String redact(String text) {
    if (logSensitive) return "'$text'";
    if (text.isEmpty) return '<空>';
    return '<${text.length}字 #${(text.hashCode & 0xffffff).toRadixString(16)}>';
  }

  /// 仅供测试：把日志接到指定文件，用来验证「哪些通道会落盘」。
  @visibleForTesting
  static Future<void> initForTest(File file) async {
    await _sink?.flush();
    await _sink?.close();
    _sink = file.openWrite(mode: FileMode.append);
  }

  /// 仅供测试：等待缓冲写出，避免断言时文件还是空的。
  @visibleForTesting
  static Future<void> flushForTest() async => _sink?.flush();

  static void d(String message) {
    if (!enabled) return;
    _write(message);
  }

  /// 错误日志：**不受 verbose 开关控制**，默认配置下也会落盘。
  ///
  /// d() 在 enabled=false（生产默认，见 AppConstants.kVerboseLogging）时首行就
  /// return —— 用它记「回滚失败」「凭证残留」「悬空引用」这类兜底，
  /// 等于什么都没记：用户真遇到时磁盘处于混合状态，却没有任何线索。
  /// 这类事件稀少且必须可诊断，所以单开一个不看开关的通道。
  /// 注意：调用方仍要自己用 redact() 处理敏感内容，这里不做脱敏。
  static void e(String message) => _write('[ERROR] $message');

  static void _write(String message) {
    try {
      debugPrint(message);
      _sink?.writeln('${DateTime.now().toIso8601String()} $message');
    } catch (_) {
      // Logging must never crash the caller
    }
  }
}
