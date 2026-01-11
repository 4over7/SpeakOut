import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:speakout/services/config_service.dart';
import 'package:speakout/services/notification_service.dart';
import 'package:flutter/foundation.dart';

class LicenseService {
  static final LicenseService _instance = LicenseService._internal();
  factory LicenseService() => _instance;
  LicenseService._internal();

  // 您的 Cloudflare Gateway 地址 (部署后请替换此处或在 ConfigService 中配置)
  // For dev, user needs to fill this.
  String get _gatewayUrl => ConfigService().gatewayUrl; 

  bool get isPro => ConfigService().isProUser;
  String get licenseKey => ConfigService().licenseKey;

  /// 验证 License Key
  Future<bool> verifyLicense(String key) async {
    if (key.isEmpty) return false;
    if (_gatewayUrl.isEmpty) {
      NotificationService().notifyError('API Gateway URL not configured');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_gatewayUrl/verify'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['valid'] == true) {
          await ConfigService().setLicenseKey(key);
          await ConfigService().setProStatus(true);
          NotificationService().notifySuccess('Pro License Activated!\nBalance: ${data['balance']}');
          return true;
        }
      }
      
      final error = jsonDecode(response.body)['message'] ?? 'Unknown Error';
      NotificationService().notifyError('Activation Failed: $error');
      await ConfigService().setProStatus(false);
      return false;

    } catch (e) {
      NotificationService().notifyError('Network Error: $e');
      return false;
    }
  }

  /// 获取 Aliyun Token (Pro User Only)
  /// 返回: {token, app_key, expire_time}
  Future<Map<String, dynamic>?> fetchCloudToken() async {
    if (!isPro) return null;
    
    try {
      final response = await http.post(
        Uri.parse('$_gatewayUrl/token'),
        headers: {
          'Authorization': 'Bearer $licenseKey',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print('Token Fetch Error: $e');
    }
    return null;
  }
  
  /// 注销
  Future<void> logout() async {
    await ConfigService().setLicenseKey('');
    await ConfigService().setProStatus(false);
    NotificationService().notify('License Deactivated');
  }

  /// 充值兑换码
  Future<bool> redeemCode(String code) async {
    final licenseKey = ConfigService().licenseKey;
    final gatewayUrl = ConfigService().gatewayUrl;

    if (licenseKey.isEmpty || gatewayUrl.isEmpty) {
        NotificationService().notifyError("Please log in first.");
        return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$gatewayUrl/redeem'),
        headers: {
          'Authorization': 'Bearer $licenseKey',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({"code": code}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        NotificationService().notifySuccess("Added ${json['added']}s success!");
        await verifyLicense(licenseKey); 
        return true;
      } else {
        final json = jsonDecode(response.body);
        NotificationService().notifyError("Redeem Failed: ${json['error']}");
        return false;
      }
    } catch (e) {
      NotificationService().notifyError("Redeem Error: $e");
      return false;
    }
  }
}
