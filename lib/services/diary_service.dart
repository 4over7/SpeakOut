import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_log.dart';
import 'notification_service.dart';
import 'config_service.dart';

/// Handles saving Flash Notes (Diary) to local file.
class DiaryService {
  static final DiaryService _instance = DiaryService._internal();
  factory DiaryService() => _instance;
  DiaryService._internal();

  /// macOS 沙盒版真正的目录授权是 AppDelegate 里的 security-scoped bookmark，
  /// 配置里的 `diary_directory` 只是另一半。两者不一致时写入必然被沙盒拒绝：
  /// 目录被移动、配置被手改、或者选目录时 Swift 已提交 bookmark 而 Dart 还没
  /// 写完配置就退出了，都会走到这一步。
  ///
  /// **在这里对账而不是在设置页**：设置页的写盘探测只有用户打开那一页才跑，
  /// 而闪念是快捷键直接触发的 —— 大量用户根本不会先去开设置页。
  /// 不一致就 fail-closed 并给出可操作提示，而不是等真实写入抛一个泛化错误。
  static const _channel = MethodChannel('com.SpeakOut/overlay');

  Future<String?> _authorizedDirectoryMismatch(String configured) async {
    if (!Platform.isMacOS) return null;
    try {
      final authorized =
          await _channel.invokeMethod<String>('resolvedDiaryDirectory');
      // 没有 bookmark（非沙盒版 / 用户还没选过目录）就没什么可对账的
      if (authorized == null || authorized.isEmpty) return null;
      if (authorized == configured) return null;
      AppLog.e('闪念目录不一致：配置=$configured 授权=$authorized');
      return authorized;
    } catch (_) {
      return null; // 旧壳工程没有这个 method，跳过对账
    }
  }

  /// Append text to the configured diary file.
  /// Format:
  /// - [HH:mm:ss] text...
  ///
  /// Returns null if success, or error message.
  Future<String?> appendNote(String text) async {
    if (text.trim().isEmpty) return "Empty text";
    
    final dirPath = ConfigService().diaryDirectory;
    if (dirPath.isEmpty) return "No directory configured";

    final mismatch = await _authorizedDirectoryMismatch(dirPath);
    if (mismatch != null) {
      const msg = "闪念目录未获授权，请在设置里重新选择保存目录";
      NotificationService().notifyError(msg);
      return msg;
    }

    try {
      final dir = Directory(dirPath);
      
      // Ensure directory exists
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final timeStr = DateFormat('HH:mm:ss').format(now);
      
      // Daily File: 2024-01-09.md
      final file = File("${dir.path}/$dateStr.md");
      
      String contentToAppend = "- **[$timeStr]** $text\n";
      
      await file.writeAsString(contentToAppend, mode: FileMode.append);
      return null; // Success
    } catch (e) {
      final msg = "Failed to save note: $e";
      NotificationService().notifyError(msg);
      return msg;
    }
  }
}
