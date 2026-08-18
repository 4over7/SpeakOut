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
  bool _lastCheckSucceeded = false;
  String? latestVersion;
  int? latestBuild;
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
  // DMG 路径带版本号和 Gateway build，避免同版本重新发包时复用旧缓存。
  String get _dmgPath {
    final v = latestVersion ?? 'unknown';
    final revision = latestBuild == null ? v : '$v+$latestBuild';
    return '${Directory.systemTemp.path}/SpeakOut-update-$revision.dmg';
  }
  static String get _helperPath => '${Directory.systemTemp.path}/speakout_update.sh';

  /// 最小合理 DMG 大小（B）。低于此值视为损坏/未完成下载。
  /// 当前 SpeakOut.dmg 约 53 MB，保守设 20 MB。
  static const int _minValidDmgBytes = 20 * 1024 * 1024;

  /// 清理旧版本的 DMG 缓存文件（保留当前 latestVersion 的）
  void _cleanupStaleDmgs() {
    try {
      final tempDir = Directory(Directory.systemTemp.path);
      final keep = latestVersion == null ? null : File(_dmgPath).uri.pathSegments.last;
      for (final entity in tempDir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('SpeakOut-update-') || !name.endsWith('.dmg')) continue;
        if (keep != null && name == keep) continue;
        try {
          entity.deleteSync();
          AppLog.d('UpdateService: cleaned stale DMG: $name');
        } catch (_) {}
      }
      // 顺便删掉旧路径（无版本号的那个）
      final legacy = File('${Directory.systemTemp.path}/SpeakOut-update.dmg');
      if (legacy.existsSync()) {
        try { legacy.deleteSync(); } catch (_) {}
      }
    } catch (_) {}
  }

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
    _lastCheckSucceeded = false;
    if (_state == UpdateState.failed) {
      _setState(UpdateState.idle);
      errorMessage = null;
    }
  }

  /// 启动时调用，fire-and-forget，不阻塞 UI
  Future<bool> checkForUpdate() async {
    if (!Distribution.supportsUpdateCheck) return false;
    if (_hasChecked) return _lastCheckSucceeded;
    _hasChecked = true;
    _lastCheckSucceeded = false;

    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;
      final localBuild = int.tryParse(info.buildNumber);

      // 主路径: Gateway（私有仓库 GitHub API 不返回 assets）
      var remote = await _checkGateway();

      // 降级: GitHub Releases API
      remote ??= await _checkGitHub();

      if (remote == null) {
        AppLog.d('UpdateService: version check failed (both sources)');
        return false;
      }

      latestVersion = remote.version;
      latestBuild = remote.build;
      downloadUrl = remote.url;
      _dmgAssetUrl = remote.dmgUrl;

      hasUpdate = isNewer(
        remote.version,
        localVersion,
        remoteBuild: remote.build,
        localBuild: localBuild,
      );
      if (hasUpdate) {
        AppLog.d('UpdateService: new version available: ${remote.version} (local: $localVersion), dmg: ${remote.dmgUrl ?? "none"}');
        // 清理旧版 DMG 缓存 + 检测本次版本是否已下载过
        _cleanupStaleDmgs();
        final cached = File(_dmgPath);
        if (cached.existsSync() && cached.lengthSync() >= _minValidDmgBytes) {
          AppLog.d('UpdateService: reusing cached DMG: $_dmgPath (${cached.lengthSync()} bytes)');
          _lastProgress = 1.0;
          _setState(UpdateState.readyToInstall);
        }
      } else {
        AppLog.d('UpdateService: up to date ($localVersion)');
        // 本地已是最新，清掉所有残留缓存
        _cleanupStaleDmgs();
      }
      _lastCheckSucceeded = true;
      return true;
    } catch (e) {
      AppLog.d('UpdateService: check failed: $e');
      return false;
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

      return _RemoteVersion.tryCreate(version, url, dmgUrl: dmgUrl);
    } catch (e) {
      AppLog.d('UpdateService: GitHub check failed: $e');
      return null;
    }
  }

  Future<_RemoteVersion?> _checkGateway() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final checkUrl = '${AppConstants.kGatewayVersionUrl}?v=${info.version}&b=${info.buildNumber}';
      final resp = await http.get(
        Uri.parse(checkUrl),
      ).timeout(AppConstants.kUpdateCheckTimeout);

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final version = json['version'] as String?;
      if (version == null) return null;

      final url = (json['download_url'] as String?) ?? AppConstants.kGitHubReleasesUrl;
      final dmgUrl = json['dmg_url'] as String?;
      final buildValue = json['build'];
      final build = buildValue is int && buildValue >= 0 ? buildValue : null;
      return _RemoteVersion.tryCreate(version, url, build: build, dmgUrl: dmgUrl);
    } catch (e) {
      AppLog.d('UpdateService: Gateway check failed: $e');
      return null;
    }
  }

  /// Download the DMG update file，支持断点续传
  ///
  /// 断点续传原理：
  /// - 已有部分文件 → 发 HTTP `Range: bytes=N-`，服务器返 206 + 从 N 开始的内容
  /// - Azure Blob（GitHub Release 实际 CDN）原生支持 Range 请求
  /// - append 模式打开文件继续写
  ///
  /// 防损坏：
  /// - 下载完后用 Content-Range/Content-Length 校验总大小
  /// - 总大小不匹配 → 删掉重下
  /// - HTTPS 兜底传输完整性
  /// - hdiutil attach 时 macOS 自动做 DMG 头部 CRC 校验
  Future<bool> downloadUpdate() async {
    // 防并发：已经在下载中直接 return
    if (_state == UpdateState.downloading) {
      AppLog.d('UpdateService: download already in progress, skip');
      return false;
    }
    // 缓存复用：DMG 已下载过且文件合理，直接跳到 readyToInstall 不重下
    final cached = File(_dmgPath);
    if (cached.existsSync() && cached.lengthSync() >= _minValidDmgBytes) {
      AppLog.d('UpdateService: DMG already cached, skip download: $_dmgPath (${cached.lengthSync()} bytes)');
      _lastProgress = 1.0;
      _progressController.add(1.0);
      _setState(UpdateState.readyToInstall);
      return true;
    }

    if (_dmgAssetUrl == null) {
      errorMessage = 'No DMG download URL available';
      _setState(UpdateState.failed);
      return false;
    }

    _setState(UpdateState.downloading);

    // 计算断点位置（partial file 已有字节数）
    final file = File(_dmgPath);
    var resumeFrom = 0;
    if (file.existsSync()) {
      resumeFrom = file.lengthSync();
      AppLog.d('UpdateService: resuming from byte $resumeFrom');
    }

    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(_dmgAssetUrl!));
      request.followRedirects = true;
      request.maxRedirects = 5;
      if (resumeFrom > 0) {
        request.headers['Range'] = 'bytes=$resumeFrom-';
      }

      // 连接建立超时：30s 内拿不到响应头视为失败
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

      // 200 = 完整下载；206 = 断点续传成功
      final isPartial = response.statusCode == 206;
      if (response.statusCode != 200 && response.statusCode != 206) {
        // 416 Range Not Satisfiable = partial file 已经等于或超过全长，删掉重来
        if (response.statusCode == 416) {
          AppLog.d('UpdateService: HTTP 416 (Range Not Satisfiable), partial file stale, wipe + retry');
          try { file.deleteSync(); } catch (_) {}
          errorMessage = 'Resume failed (file stale), please retry';
          _setState(UpdateState.failed);
          client.close();
          return false;
        }
        errorMessage = 'Download failed: HTTP ${response.statusCode}';
        AppLog.d('UpdateService: download failed: HTTP ${response.statusCode} from $_dmgAssetUrl');
        _setState(UpdateState.failed);
        client.close();
        return false;
      }

      // 总大小（用于进度）：
      // - 206: Content-Range: bytes N-M/TOTAL，取 TOTAL
      // - 200: Content-Length
      int totalBytes = 0;
      if (isPartial) {
        final contentRange = response.headers['content-range'] ?? '';
        final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(contentRange);
        if (match != null) {
          totalBytes = int.tryParse(match.group(1) ?? '') ?? 0;
        }
      } else {
        totalBytes = response.contentLength ?? 0;
        // 服务器忽略了 Range → 当作完整响应，truncate 现有 partial
        if (resumeFrom > 0) {
          AppLog.d('UpdateService: server ignored Range, restart from 0');
          resumeFrom = 0;
        }
      }

      var receivedBytes = resumeFrom;
      // Partial: 追加；Full: 覆盖
      sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);

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
      sink = null;
      client.close();

      // 大小校验：下载完文件大小应等于 totalBytes
      final finalSize = file.lengthSync();
      if (totalBytes > 0 && finalSize != totalBytes) {
        errorMessage = 'Size mismatch: got $finalSize, expected $totalBytes';
        AppLog.d('UpdateService: $errorMessage (retry to resume)');
        _setState(UpdateState.failed);
        return false;
      }
      if (finalSize < _minValidDmgBytes) {
        errorMessage = 'DMG too small: $finalSize bytes';
        AppLog.d('UpdateService: $errorMessage');
        try { file.deleteSync(); } catch (_) {}
        _setState(UpdateState.failed);
        return false;
      }

      AppLog.d('UpdateService: DMG ready: $_dmgPath ($finalSize bytes)');
      _lastProgress = 1.0;
      _progressController.add(1.0);
      _setState(UpdateState.readyToInstall);
      return true;
    } catch (e) {
      errorMessage = 'Download error: $e';
      AppLog.d('UpdateService: download failed: $e');
      try { await sink?.close(); } catch (_) {}
      try { client.close(); } catch (_) {}
      _setState(UpdateState.failed);
      // 保留 partial 文件，下次重试可续传
      return false;
    }
  }

  /// Helper 日志路径，用户可在出问题时查
  static String get helperLogPath {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/Library/Logs/speakout-updater.log';
  }

  /// Write the update helper script and return its path
  String _writeHelperScript() {
    // Get the current app's bundle path
    final appPath = Platform.resolvedExecutable;
    // Navigate up from: SpeakOut.app/Contents/MacOS/speakout → SpeakOut.app
    final appBundle = File(appPath).parent.parent.parent.path;
    final appName = appBundle.split('/').last; // e.g. "子曰 SpeakOut.app"
    final installDir = File(appBundle).parent.path; // e.g. "/Applications"
    final logPath = helperLogPath;

    // 预期签名身份（用于校验更新包，防止 DMG 来源被替换/配置错误）
    // 这些是公开信息（包含在已签名 app 的 codesign 输出里），硬编码校验是标准做法。
    const expectedTeamId = 'UB9D55S724';
    const expectedBundleId = 'com.speakout.speakout';

    // 安全自更新流程（v1.8.7）：
    // - 原子安装 + 回滚：先 copy-to-staging（.new），验证通过后才把旧 app mv 到 .backup、
    //   staging mv 成正式名；任一步失败回滚旧 app。新 app 验证前绝不删除旧 app（修 F1）。
    // - 签名校验：挂载后去掉 -noverify，并对 DMG 内 app 与复制后的 staging 双重校验
    //   codesign --verify + TeamIdentifier + CFBundleIdentifier（修 F2）。
    // - 名字归一：staging 最终 mv 成当前 appName，无论 DMG 内 app 叫什么，relaunch 永远一致（修 F7）。
    // - 可写性兜底：安装目录不可写直接打开 DMG 手动安装（修 F3 脚本侧）。
    // - mount-point 解析沿用 v1.8.2 的 -plist grep + mount 兜底（支持空格/unicode）。
    final script = '''#!/bin/bash
# SpeakOut Auto-Update Helper

LOG="$logPath"
mkdir -p "\$(dirname "\$LOG")"
exec >> "\$LOG" 2>&1

EXPECTED_TEAM="$expectedTeamId"
EXPECTED_BUNDLE="$expectedBundleId"
DMG="$_dmgPath"
INSTALL_DIR="$installDir"
APP_NAME="$appName"
TARGET="\$INSTALL_DIR/\$APP_NAME"
STAGING="\$INSTALL_DIR/\$APP_NAME.new"
BACKUP="\$INSTALL_DIR/\$APP_NAME.backup"

echo ""
echo "=========================================="
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] update helper start"
echo "DMG:    \$DMG"
echo "Target: \$TARGET"
echo "=========================================="

# Wait for the app to exit
sleep 2

# Install dir 可写性检查：不可写直接走手动安装（避免进入删除/复制流程）
if [ ! -w "\$INSTALL_DIR" ]; then
  echo "  install dir not writable: \$INSTALL_DIR, fallback to manual"
  open "\$DMG"
  exit 1
fi

# 校验 app 签名 + TeamIdentifier + CFBundleIdentifier
verify_app() {
  local app="\$1"
  if ! codesign --verify --deep --strict "\$app"; then
    echo "  codesign --verify failed: \$app"
    return 1
  fi
  local team
  team=\$(codesign -dv "\$app" 2>&1 | grep -E '^TeamIdentifier=' | cut -d= -f2)
  if [ "\$team" != "\$EXPECTED_TEAM" ]; then
    echo "  team mismatch: got '\$team' expected '\$EXPECTED_TEAM'"
    return 1
  fi
  local bid
  bid=\$(defaults read "\$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
  if [ "\$bid" != "\$EXPECTED_BUNDLE" ]; then
    echo "  bundle id mismatch: got '\$bid' expected '\$EXPECTED_BUNDLE'"
    return 1
  fi
  echo "  verify ok: team=\$team bundle=\$bid"
  return 0
}

# Pre-cleanup: detach any existing SpeakOut volumes
# 否则 hdiutil 会自动起名 "SpeakOut 1"、"SpeakOut 2"
for mp in /Volumes/SpeakOut*; do
  if [ -d "\$mp" ]; then
    echo "  pre-detach: \$mp"
    hdiutil detach "\$mp" -force 2>&1 || true
  fi
done

# Attach DMG with -plist for reliable parsing（不再跳过校验，让 macOS 校验 DMG 完整性）
echo ">> hdiutil attach -plist"
ATTACH_PLIST=\$(hdiutil attach "\$DMG" -plist -nobrowse -noautoopen 2>&1)
ATTACH_RC=\$?
echo "  exit=\$ATTACH_RC"

if [ \$ATTACH_RC -ne 0 ]; then
  echo "  hdiutil attach failed:"
  echo "\$ATTACH_PLIST"
  echo "<< fallback: open DMG for manual install"
  open "\$DMG"
  exit 1
fi

# Parse mount point from plist (主：从 <string>/Volumes/...</string> 直接 grep)
# 这种方式天然支持空格、unicode，不依赖列/字段分隔
MOUNT_POINT=\$(echo "\$ATTACH_PLIST" | grep -o '<string>/Volumes/[^<]*</string>' | head -1 | sed -E 's|<string>(.*)</string>|\\1|')

# Fallback: 从 `mount` 命令找新挂载的 SpeakOut volume
if [ -z "\$MOUNT_POINT" ]; then
  MOUNT_POINT=\$(mount | grep -E 'on /Volumes/SpeakOut' | tail -1 | sed -E 's|.*on (/Volumes/SpeakOut[^(]*) \\(.*|\\1|' | sed -E 's/[[:space:]]+\$//')
fi

echo "  mount-point: '\$MOUNT_POINT'"

if [ -z "\$MOUNT_POINT" ] || [ ! -d "\$MOUNT_POINT" ]; then
  echo "  could not determine mount point, fallback to manual"
  open "\$DMG"
  exit 1
fi

# Find the .app in the mounted volume
APP_IN_DMG=\$(find "\$MOUNT_POINT" -maxdepth 1 -name "*.app" -print -quit)
echo ">> find .app: '\$APP_IN_DMG'"

if [ -z "\$APP_IN_DMG" ]; then
  echo "  no .app in DMG, fallback to manual"
  hdiutil detach "\$MOUNT_POINT" -force 2>&1 || true
  open "\$DMG"
  exit 1
fi

# 校验 DMG 内 app（签名 + team + bundle id），失败直接放弃自动安装
echo ">> verify source app"
if ! verify_app "\$APP_IN_DMG"; then
  echo "  source app verification failed, abort auto-install"
  hdiutil detach "\$MOUNT_POINT" -force 2>&1 || true
  open "\$DMG"
  exit 1
fi

# 原子安装第 1 步：copy-to-staging（不动旧 app）
echo ">> copy to staging: \$STAGING"
rm -rf "\$STAGING"
cp -R "\$APP_IN_DMG" "\$STAGING"
CP_RC=\$?
echo "  cp exit=\$CP_RC"

# Unmount DMG（复制完即可卸载）
hdiutil detach "\$MOUNT_POINT" -force 2>&1 || true

if [ \$CP_RC -ne 0 ]; then
  echo "  copy to staging failed, fallback to manual"
  rm -rf "\$STAGING"
  open "\$DMG"
  exit 1
fi

# 复制后再校验一次 staging（防复制过程损坏）
echo ">> verify staged app"
if ! verify_app "\$STAGING"; then
  echo "  staged app verification failed, fallback to manual"
  rm -rf "\$STAGING"
  open "\$DMG"
  exit 1
fi

# 原子安装第 2 步：swap。旧 app -> backup（mv，可回滚），staging -> 正式名
if [ -e "\$TARGET" ]; then
  rm -rf "\$BACKUP"
  if ! mv "\$TARGET" "\$BACKUP"; then
    echo "  backup old app failed, fallback to manual"
    rm -rf "\$STAGING"
    open "\$DMG"
    exit 1
  fi
fi

if ! mv "\$STAGING" "\$TARGET"; then
  echo "  promote staging failed, rolling back"
  rm -rf "\$STAGING"
  if [ -e "\$BACKUP" ]; then
    mv "\$BACKUP" "\$TARGET" || echo "  ROLLBACK FAILED, backup at \$BACKUP"
  fi
  open "\$DMG"
  exit 1
fi

# 成功：清理 backup + DMG + helper
echo ">> install ok, cleanup"
rm -rf "\$BACKUP"
rm -f "\$DMG"
rm -f "$_helperPath"

# Relaunch
echo ">> relaunch"
open "\$TARGET"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] update helper done"
''';

    File(_helperPath).writeAsStringSync(script);
    // Make executable
    Process.runSync('chmod', ['+x', _helperPath]);
    AppLog.d('UpdateService: helper script written to $_helperPath, log=$logPath');
    return _helperPath;
  }

  /// 生成并启动安装 helper。只有 native 明确确认进程已启动，才进入 installing。
  bool launchInstall(bool Function(String scriptPath) launcher) {
    if (!Distribution.supportsAutoUpdate) return false;

    late final String scriptPath;
    try {
      scriptPath = _writeHelperScript();
    } catch (e, stackTrace) {
      errorMessage = 'Failed to prepare update helper';
      AppLog.e('UpdateService: failed to prepare helper: $e\n$stackTrace');
      return false;
    }

    try {
      if (!launcher(scriptPath)) {
        errorMessage = 'Failed to launch update helper';
        AppLog.e('UpdateService: native helper launch failed');
        return false;
      }
    } catch (e, stackTrace) {
      errorMessage = 'Failed to launch update helper';
      AppLog.e('UpdateService: helper launcher threw: $e\n$stackTrace');
      return false;
    }

    errorMessage = null;
    _setState(UpdateState.installing);
    return true;
  }

  /// Check if a DMG has been downloaded and is ready
  bool get isReadyToInstall => _state == UpdateState.readyToInstall && File(_dmgPath).existsSync();

  /// Whether we can do in-app update (have a direct DMG URL)
  bool get canAutoUpdate => Distribution.supportsAutoUpdate && _dmgAssetUrl != null;

  /// 语义化版本比较: remote > local 返回 true
  /// 远端版本号最终会拼进 `_dmgPath`，再原样写进 update helper 的 shell 脚本
  /// （`DMG="$_dmgPath"`）。含引号的版本号能闭合引号执行任意命令，且注入发生在
  /// codesign 校验之前 —— 签名兜不住。
  ///
  /// 不能指望 [isNewer] 拦住：`_parseVersion` 对非数字段静默兜底为 0，
  /// `999.0.0"; cmd; #` 会被解析成 [999,0,0] 并判定为新版本。
  ///
  /// 必须接受 prerelease：本仓库真实发过 `v1.1.0-RC3` / `v1.1.0-RC4`。
  /// 只收三段数字会把它们误判成脏数据，而脏数据与「源不可达」共用 null 兜底 ——
  /// 结果是 gateway 的 RC 版被丢弃、回落到 GitHub 的旧稳定版，用户被告知"已是最新"。
  /// SemVer 自身的 prerelease/build 语法只允许 [0-9A-Za-z-] 和点，天然不含
  /// 引号、`$`、反引号、空格、换行，进 shell 是安全的。
  /// 长度上限只为兜住畸形输入（版本号要进文件名），不是 SemVer 语义的一部分：
  /// 放到 63 是为了容得下 40 位 commit SHA 作 build metadata。
  /// SemVer 2.0.0 官方文法（§9 禁前导零与空标识符）。
  /// 上一版用 `[0-9A-Za-z][0-9A-Za-z.-]{0,63}` 图省事，把 `1.0.0-alpha..2`、
  /// `1.0.0-01` 这类非法串也放行了 —— 而 _comparePrerelease 会把空标识符
  /// 当成字母数字段判为「高于数字段」，得出错误的「有更新」。
  static final RegExp _semverPattern = RegExp(
      r'^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})'
      r'(-((0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
      r'(\.(0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?'
      r'(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$');

  /// 版本号最终要进 DMG 文件名，再长的合法 SemVer 也不该无限接受。
  static const int _maxVersionLength = 96;

  static bool isValidRemoteVersion(String version) =>
      version.length <= _maxVersionLength && _semverPattern.hasMatch(version);

  static bool isNewer(String remote, String local, {int? remoteBuild, int? localBuild}) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    // 主版本号相同 → 比 prerelease。白名单放行了 prerelease（仓库真发过
    // v1.1.0-RC3/RC4），如果这里还只比三段数字，RC3 和 RC4 会被判成同一个版本，
    // 而 1.1.0 稳定版相对 1.1.0-RC4 也永远"不是更新" —— 用户卡在 RC 上收不到正式版。
    final prereleaseComparison = _comparePrerelease(
        _prereleaseOf(remote), _prereleaseOf(local));
    if (prereleaseComparison != 0) return prereleaseComparison > 0;
    if (remoteBuild != null && localBuild != null) {
      return remoteBuild > localBuild;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    // 先切掉 build metadata 和 prerelease，避免 '0-RC3' 这种段被静默解析成 0
    final core = v.split('+').first.split('-').first;
    final parts = core.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }

  /// 取 prerelease 部分（不含 build metadata）。稳定版返回空串。
  static String _prereleaseOf(String v) {
    final noBuild = v.split('+').first;
    final dash = noBuild.indexOf('-');
    return dash < 0 ? '' : noBuild.substring(dash + 1);
  }

  /// SemVer 2.0.0 §11 优先级：稳定版 > 同版本的 prerelease；
  /// prerelease 之间按点分标识符逐个比，纯数字段按数值比且低于字母数字段，
  /// 前缀相同则字段多的更大。返回 >0 表示 a 更新。
  static int _comparePrerelease(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return 1; // 稳定版更新
    if (b.isEmpty) return -1;
    final ai = a.split('.'), bi = b.split('.');
    for (var i = 0; i < ai.length && i < bi.length; i++) {
      if (ai[i] == bi[i]) continue;
      // 用 BigInt 而非 int：SemVer 对数字标识符没有位数上限，而 Dart Native 的
      // int 是 64 位 —— `1.0.0-9999999999999999999` 会让 int.tryParse 返回 null，
      // 该段被误判成字母数字段，进而得出反的优先级。
      final an = BigInt.tryParse(ai[i]), bn = BigInt.tryParse(bi[i]);
      if (an != null && bn != null) return an.compareTo(bn);
      if (an != null) return -1; // 数字段低于字母数字段
      if (bn != null) return 1;
      return ai[i].compareTo(bi[i]);
    }
    return ai.length.compareTo(bi.length);
  }
}

class _RemoteVersion {
  final String version;
  final String url;
  final int? build;
  final String? dmgUrl;
  _RemoteVersion(this.version, this.url, {this.build, this.dmgUrl});

  /// 两个来源（gateway / GitHub tag）的唯一收口点：非法版本号一律当作
  /// 「没拿到更新信息」，而不是带着脏串继续走下载安装流程。
  static _RemoteVersion? tryCreate(String version, String url,
      {int? build, String? dmgUrl}) {
    if (!UpdateService.isValidRemoteVersion(version)) {
      AppLog.d('UpdateService: rejected malformed remote version: '
          '${AppLog.redact(version)}');
      return null;
    }
    return _RemoteVersion(version, url, build: build, dmgUrl: dmgUrl);
  }
}
