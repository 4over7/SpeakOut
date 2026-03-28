import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_constants.dart';
import '../config/app_log.dart';
import '../config/distribution.dart';

enum UpdateState { idle, checking, downloading, readyToInstall, installing, failed }

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  bool _hasChecked = false;
  String? latestVersion;
  String? downloadUrl;
  String? _dmgAssetUrl; // Direct DMG download URL from GitHub assets
  bool hasUpdate = false;

  UpdateState _state = UpdateState.idle;
  UpdateState get state => _state;
  String? errorMessage;

  // Download progress (0.0 ~ 1.0)
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get downloadProgress => _progressController.stream;
  double _lastProgress = 0;
  double get lastProgress => _lastProgress;

  // State change notifications
  final _stateController = StreamController<UpdateState>.broadcast();
  Stream<UpdateState> get stateChanges => _stateController.stream;

  // 使用系统临时目录（沙盒兼容）
  static String get _dmgPath => '${Directory.systemTemp.path}/SpeakOut-update.dmg';
  static String get _helperPath => '${Directory.systemTemp.path}/speakout_update.sh';

  void dispose() {
    _progressController.close();
    _stateController.close();
  }

  void _setState(UpdateState s) {
    _state = s;
    _stateController.add(s);
  }

  /// 重置检查状态，允许再次手动检查
  void resetCheck() {
    _hasChecked = false;
    if (_state == UpdateState.failed) {
      _setState(UpdateState.idle);
      errorMessage = null;
    }
  }

  /// 启动时调用，fire-and-forget，不阻塞 UI
  Future<void> checkForUpdate() async {
    if (!Distribution.supportsUpdateCheck) return;
    if (_hasChecked) return;
    _hasChecked = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;

      // 主路径: Gateway（私有仓库 GitHub API 不返回 assets）
      var remote = await _checkGateway();

      // 降级: GitHub Releases API
      remote ??= await _checkGitHub();

      if (remote == null) {
        AppLog.d('UpdateService: version check failed (both sources)');
        return;
      }

      latestVersion = remote.version;
      downloadUrl = remote.url;
      _dmgAssetUrl = remote.dmgUrl;

      if (isNewer(remote.version, localVersion)) {
        hasUpdate = true;
        AppLog.d('UpdateService: new version available: ${remote.version} (local: $localVersion), dmg: ${remote.dmgUrl ?? "none"}');
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
      final tag = json['tag_name'] as String?;
      if (tag == null) return null;

      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      final url = (json['html_url'] as String?) ?? AppConstants.kGitHubReleasesUrl;

      // Extract .dmg asset URL
      String? dmgUrl;
      final assets = json['assets'] as List<dynamic>?;
      if (assets != null) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.dmg')) {
            dmgUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      return _RemoteVersion(version, url, dmgUrl: dmgUrl);
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
      final dmgUrl = json['dmg_url'] as String?;
      return _RemoteVersion(version, url, dmgUrl: dmgUrl);
    } catch (e) {
      AppLog.d('UpdateService: Gateway check failed: $e');
      return null;
    }
  }

  /// Download the DMG update file
  Future<bool> downloadUpdate() async {
    if (_dmgAssetUrl == null) {
      errorMessage = 'No DMG download URL available';
      _setState(UpdateState.failed);
      return false;
    }

    _setState(UpdateState.downloading);
    _lastProgress = 0;
    _progressController.add(0);

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_dmgAssetUrl!));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        errorMessage = 'Download failed: HTTP ${response.statusCode}';
        _setState(UpdateState.failed);
        client.close();
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final file = File(_dmgPath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _lastProgress = receivedBytes / totalBytes;
          _progressController.add(_lastProgress);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      AppLog.d('UpdateService: DMG downloaded to $_dmgPath ($receivedBytes bytes)');
      _setState(UpdateState.readyToInstall);
      return true;
    } catch (e) {
      errorMessage = 'Download error: $e';
      AppLog.d('UpdateService: download failed: $e');
      _setState(UpdateState.failed);
      // Clean up partial download
      try { File(_dmgPath).deleteSync(); } catch (_) {}
      return false;
    }
  }

  /// Write the update helper script and return its path
  String _writeHelperScript() {
    // Get the current app's bundle path
    final appPath = Platform.resolvedExecutable;
    // Navigate up from: SpeakOut.app/Contents/MacOS/speakout → SpeakOut.app
    final appBundle = File(appPath).parent.parent.parent.path;
    final appName = appBundle.split('/').last; // e.g. "子曰 SpeakOut.app"
    final installDir = File(appBundle).parent.path; // e.g. "/Applications"

    final script = '''#!/bin/bash
# SpeakOut Auto-Update Helper
# Wait for the app to exit
sleep 2

# Mount the DMG (suppress any UI)
MOUNT_POINT=\$(hdiutil attach "$_dmgPath" -nobrowse -noverify -noautoopen 2>/dev/null | grep "/Volumes/" | awk '{print \$NF}')

if [ -z "\$MOUNT_POINT" ]; then
  # Try reading the mount point differently (multi-word volume names)
  MOUNT_POINT=\$(hdiutil attach "$_dmgPath" -nobrowse -noverify -noautoopen 2>/dev/null | tail -1 | sed 's/.*\\(\\/Volumes\\/.*\\)/\\1/')
fi

if [ -z "\$MOUNT_POINT" ]; then
  echo "Failed to mount DMG"
  # Fallback: open DMG for manual install
  open "$_dmgPath"
  exit 1
fi

# Find the .app in the mounted volume
APP_IN_DMG=\$(find "\$MOUNT_POINT" -maxdepth 1 -name "*.app" -print -quit)

if [ -z "\$APP_IN_DMG" ]; then
  echo "No .app found in DMG"
  hdiutil detach "\$MOUNT_POINT" -quiet
  open "$_dmgPath"
  exit 1
fi

# Remove old app and copy new one
rm -rf "$installDir/$appName"
cp -R "\$APP_IN_DMG" "$installDir/"

# Unmount DMG
hdiutil detach "\$MOUNT_POINT" -quiet

# Clean up
rm -f "$_dmgPath"
rm -f "$_helperPath"

# Relaunch
open "$installDir/$appName"
''';

    File(_helperPath).writeAsStringSync(script);
    // Make executable
    Process.runSync('chmod', ['+x', _helperPath]);
    AppLog.d('UpdateService: helper script written to $_helperPath');
    return _helperPath;
  }

  /// Install update and restart the app (GitHub distribution only).
  /// Returns the helper script path; caller should launch it via FFI then exit.
  String prepareInstall() {
    if (!Distribution.supportsAutoUpdate) return '';
    _setState(UpdateState.installing);
    return _writeHelperScript();
  }

  /// Check if a DMG has been downloaded and is ready
  bool get isReadyToInstall => _state == UpdateState.readyToInstall && File(_dmgPath).existsSync();

  /// Whether we can do in-app update (have a direct DMG URL)
  bool get canAutoUpdate => Distribution.supportsAutoUpdate && _dmgAssetUrl != null;

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
  final String? dmgUrl;
  _RemoteVersion(this.version, this.url, {this.dmgUrl});
}
