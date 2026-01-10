import 'dart:io';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'config_service.dart';

/// Handles saving Flash Notes (Diary) to local file.
class DiaryService {
  static final DiaryService _instance = DiaryService._internal();
  factory DiaryService() => _instance;
  DiaryService._internal();

  /// Append text to the configured diary file.
  /// Format:
  /// - [HH:mm:ss] text...
  ///
  /// Returns null if success, or error message.
  Future<String?> appendNote(String text) async {
    if (text.trim().isEmpty) return "Empty text";
    
    final dirPath = ConfigService().diaryDirectory;
    if (dirPath.isEmpty) return "No directory configured";

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
