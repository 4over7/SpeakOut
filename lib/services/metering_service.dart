import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/license_service.dart';

/// 计量服务 (Usage Metering)
/// 负责本地累计使用时长，并定期上报给网关扣费
class MeteringService {
  static final MeteringService _instance = MeteringService._internal();
  factory MeteringService() => _instance;
  MeteringService._internal();

  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _flushTimer;
  bool _isShuttingDown = false;

  void init() {
    // 每 60 秒自动上报一次
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _flush();
    });
  }

  void dispose() {
    _isShuttingDown = true;
    _flushTimer?.cancel();
    _flush(); // Final flush
  }

  /// 记录一次使用
  /// [durationInSeconds]: 时长
  /// [taskId]: 任务ID (用于对账)
  void trackUsage(double durationInSeconds, String taskId) {
    // 只有 Pro 用户才需要计费 (且只针对 Cloud 模式，不过这是调用方决定的)
    if (!ConfigService().isProUser) return;
    
    if (durationInSeconds <= 0) return;

    // 存入本地 buffer
    _pendingEvents.add({
      "task_id": taskId,
      "seconds": durationInSeconds,
      "timestamp": DateTime.now().toIso8601String(),
    });

    if (kDebugMode) {
      print("[Metering] Tracked: ${durationInSeconds.toStringAsFixed(1)}s (Task: $taskId)");
    }
  }

  /// 立即上报 (Flush)
  Future<void> _flush() async {
    if (_pendingEvents.isEmpty) return;

    final List<Map<String, dynamic>> eventsToSend = List.from(_pendingEvents);
    _pendingEvents.clear(); // Clear local buffer immediately

    // Calculate total
    double totalSeconds = 0;
    for (var e in eventsToSend) {
      totalSeconds += (e['seconds'] as num).toDouble();
    }
    
    // Round up/down logic? Let's keep decimal precision or round to int.
    // Gateway expects seconds. Let's send integer for simplicity, or 1 decimal.
    final int secondsToDeduct = totalSeconds.ceil();

    final gatewayUrl = ConfigService().gatewayUrl;
    final licenseKey = ConfigService().licenseKey;

    if (gatewayUrl.isEmpty || licenseKey.isEmpty) {
      // Config missing, maybe user logged out. Re-queue? 
      // Nope, just drop to avoid memory leak.
      return; 
    }

    try {
      if (kDebugMode) print("[Metering] Flushing $secondsToDeduct seconds...");
      
      final body = {
        "total_seconds": secondsToDeduct,
        "details": eventsToSend // Protocol v1.1
      };

      final response = await http.post(
        Uri.parse('$gatewayUrl/report'),
        headers: {
          'Authorization': 'Bearer $licenseKey',
          'Content-Type': 'application/json'
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        if (kDebugMode) print("[Metering] Flush Failed: ${response.statusCode}");
        // Optional: Re-queue events if critical.
        // For now, simplicity first.
      } else {
        if (kDebugMode) print("[Metering] Flush Success.");
      }
    } catch (e) {
      if (kDebugMode) print("[Metering] Flush Error: $e");
    }
  }
}
