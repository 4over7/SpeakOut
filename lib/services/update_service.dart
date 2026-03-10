import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_constants.dart';
import '../config/app_log.dart';
import 'notification_service.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  bool _hasChecked = false;
  String? latestVersion;
  String? downloadUrl;

  /// 启动时调用，fire-and-forget，不阻塞 UI
  Future<void> checkForUpdate() async {
    if (_hasChecked) return;
    _hasChecked = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // e.g. "1.5.1"

      // 主路径: GitHub Releases API
      var remote = await _checkGitHub();

      // 降级: Gateway /version
      remote ??= await _checkGateway();

      if (remote == null) {
        AppLog.d('UpdateService: version check failed (both sources)');
        return;
      }

      latestVersion = remote.version;
      downloadUrl = remote.url;

      if (isNewer(remote.version, localVersion)) {
        AppLog.d('UpdateService: new version available: ${remote.version} (local: $localVersion)');
        NotificationService().notifyWithAction(
          message: '发现新版本 ${remote.version}',
          actionLabel: '查看更新',
          onAction: () async {
            final uri = Uri.parse(remote!.url);
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          type: NotificationType.info,
          duration: const Duration(seconds: 10),
        );
      } else {
        AppLog.d('UpdateService: up to date ($localVersion)');
      }
    } catch (e) {
      AppLog.d('UpdateService: check failed: $e');
    }
  }

  Future<_RemoteVersion?> _checkGitHub() async {
    try {
      final resp = await http.get(
        Uri.parse(AppConstants.kGitHubReleasesApi),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(AppConstants.kUpdateCheckTimeout);

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?; // e.g. "v1.5.2"
      if (tag == null) return null;

      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final url = (json['html_url'] as String?) ?? AppConstants.kGitHubReleasesUrl;
      return _RemoteVersion(version, url);
    } catch (e) {
      AppLog.d('UpdateService: GitHub check failed: $e');
      return null;
    }
  }

  Future<_RemoteVersion?> _checkGateway() async {
    try {
      final resp = await http.get(
        Uri.parse(AppConstants.kGatewayVersionUrl),
      ).timeout(AppConstants.kUpdateCheckTimeout);

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final version = json['version'] as String?;
      if (version == null) return null;

      final url = (json['download_url'] as String?) ?? AppConstants.kGitHubReleasesUrl;
      return _RemoteVersion(version, url);
    } catch (e) {
      AppLog.d('UpdateService: Gateway check failed: $e');
      return null;
    }
  }

  /// 语义化版本比较: remote > local 返回 true
  static bool isNewer(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}

class _RemoteVersion {
  final String version;
  final String url;
  _RemoteVersion(this.version, this.url);
}
