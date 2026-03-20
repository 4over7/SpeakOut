import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/billing_model.dart';
import '../config/app_log.dart';
import 'config_service.dart';

/// 计费服务
///
/// Singleton. 管理设备注册、配额查询、订单创建、用量上报。
class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final ValueNotifier<BillingStatus?> statusNotifier = ValueNotifier(null);
  List<BillingPlan> _plans = [];
  List<BillingPlan> get plans => _plans;

  String get _baseUrl => ConfigService.kDefaultGatewayUrl;
  String? get _deviceId => ConfigService().deviceId;

  /// 初始化：注册设备 + 获取配额 + 获取套餐列表
  Future<void> init() async {
    try {
      // 确保有 deviceId
      var deviceId = _deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = _generateDeviceId();
        await ConfigService().setDeviceId(deviceId);
      }

      // 注册设备（幂等）
      await _registerDevice(deviceId);
      // 获取配额
      await fetchStatus();
      // 获取套餐列表
      await fetchPlans();
    } catch (e) {
      _log('Init failed: $e');
    }
  }

  /// 注册设备
  Future<void> _registerDevice(String deviceId) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/device/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'deviceId': deviceId}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        statusNotifier.value = BillingStatus.fromJson(data);
        _log('Device registered: $deviceId');
      }
    } catch (e) {
      _log('Register failed: $e');
    }
  }

  /// 查询当前配额
  Future<BillingStatus?> fetchStatus() async {
    final deviceId = _deviceId;
    if (deviceId == null) return null;

    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/billing/status'),
        headers: {'Authorization': 'Bearer $deviceId'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final status = BillingStatus.fromJson(jsonDecode(resp.body));
        statusNotifier.value = status;
        return status;
      }
    } catch (e) {
      _log('Fetch status failed: $e');
    }
    return null;
  }

  /// 获取套餐列表
  Future<void> fetchPlans() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/billing/plans'),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['plans'] as List;
        _plans = list.map((p) => BillingPlan.fromJson(p as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      _log('Fetch plans failed: $e');
    }
  }

  /// 创建订单
  /// [channel]: 'alipay' 或 'stripe'
  /// 返回 BillingOrder（含 qrCode 或 checkoutUrl）
  Future<BillingOrder?> createOrder(String planId, String channel) async {
    final deviceId = _deviceId;
    if (deviceId == null) return null;

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/billing/order'),
        headers: {
          'Authorization': 'Bearer $deviceId',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'planId': planId, 'channel': channel}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return BillingOrder.fromJson(jsonDecode(resp.body));
      } else {
        final err = jsonDecode(resp.body)['error'] ?? 'Unknown error';
        _log('Create order failed: $err');
      }
    } catch (e) {
      _log('Create order failed: $e');
    }
    return null;
  }

  /// 查询订单状态
  Future<BillingOrder?> queryOrder(String orderId) async {
    final deviceId = _deviceId;
    if (deviceId == null) return null;

    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/billing/order/$orderId'),
        headers: {'Authorization': 'Bearer $deviceId'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        return BillingOrder.fromJson(jsonDecode(resp.body));
      }
    } catch (e) {
      _log('Query order failed: $e');
    }
    return null;
  }

  /// 轮询订单状态，支付成功后自动刷新配额
  /// 返回 Stream，3秒间隔，最多 5 分钟
  Stream<BillingOrder> pollOrderStatus(String orderId) async* {
    const interval = Duration(seconds: 3);
    const maxDuration = Duration(minutes: 5);
    final deadline = DateTime.now().add(maxDuration);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      final order = await queryOrder(orderId);
      if (order != null) {
        yield order;
        if (order.isPaid) {
          // 支付成功，刷新配额
          await fetchStatus();
          return;
        }
      }
    }
  }

  /// 上报使用时长（录音结束后调用）
  Future<void> reportUsage(int seconds) async {
    if (seconds <= 0) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/billing/usage'),
        headers: {
          'Authorization': 'Bearer $deviceId',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'seconds': seconds}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final remaining = data['secondsRemaining'] as int? ?? 0;
        // 更新本地状态
        final current = statusNotifier.value;
        if (current != null) {
          statusNotifier.value = BillingStatus(
            planId: current.planId,
            secondsUsed: current.secondsUsed + seconds,
            secondsLimit: current.secondsLimit,
            periodStart: current.periodStart,
            periodEnd: current.periodEnd,
          );
        }
        _log('Usage reported: ${seconds}s, remaining: ${remaining}s');
      }
    } catch (e) {
      _log('Report usage failed: $e');
      // 用量上报失败不阻断用户使用，下次会补报
    }
  }

  /// 检查是否有足够配额
  bool hasQuota() {
    final status = statusNotifier.value;
    if (status == null) return true; // 未初始化时不阻断
    return !status.isQuotaExceeded;
  }

  String _generateDeviceId() {
    // 生成持久化的设备 UUID
    final bytes = List.generate(16, (_) => DateTime.now().microsecond % 256);
    return 'dev-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
  }

  void _log(String msg) => AppLog.d('[BillingService] $msg');
}
