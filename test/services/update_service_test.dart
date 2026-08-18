import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/update_service.dart';

void main() {
  group('UpdateService 版本比较', () {
    test('远程更高 patch 版本', () {
      expect(UpdateService.isNewer('1.5.2', '1.5.1'), true);
    });

    test('远程更高 minor 版本', () {
      expect(UpdateService.isNewer('1.6.0', '1.5.9'), true);
    });

    test('远程更高 major 版本', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), true);
    });

    test('相同版本不触发', () {
      expect(UpdateService.isNewer('1.5.1', '1.5.1'), false);
    });

    test('远程更低版本不触发', () {
      expect(UpdateService.isNewer('1.5.0', '1.5.1'), false);
    });

    test('远程更低 major 不触发', () {
      expect(UpdateService.isNewer('1.0.0', '2.0.0'), false);
    });

    test('只有两段版本号', () {
      expect(UpdateService.isNewer('1.6', '1.5.1'), true);
    });

    test('只有一段版本号', () {
      expect(UpdateService.isNewer('2', '1.9.9'), true);
    });

    test('非数字段回退为 0', () {
      expect(UpdateService.isNewer('1.5.abc', '1.5.0'), false);
    });
  });

  group('UpdateService 断点文件与完成标记', () {
    test('超过 20MB 的中断下载不能冒充完整 DMG，续传完成后才晋升', () async {
      const firstResponseBytes = 21 * 1024 * 1024;
      const totalBytes = firstResponseBytes + 1024 * 1024;
      final chunk = List<int>.filled(64 * 1024, 0x5a);
      var requestCount = 0;

      Future<void> writeBytes(HttpResponse response, int count) async {
        var remaining = count;
        while (remaining > 0) {
          final size = remaining < chunk.length ? remaining : chunk.length;
          response.add(size == chunk.length ? chunk : chunk.sublist(0, size));
          remaining -= size;
        }
        await response.close();
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        requestCount++;
        final start = requestCount == 1 ? 0 : firstResponseBytes;
        final count = requestCount == 1
            ? firstResponseBytes
            : totalBytes - firstResponseBytes;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${start + count - 1}/$totalBytes');
        request.response.contentLength = count;
        await writeBytes(request.response, count);
      });

      final service = UpdateService();
      service.configureDownloadForTest(
        version: '99.0.0-partial-test',
        build: 1,
        dmgUrl: 'http://${server.address.address}:${server.port}/SpeakOut.dmg',
      );
      final completed = File(service.dmgPathForTest);
      final partial = File(service.partialDmgPathForTest);
      final marker = File(service.completionMarkerPathForTest);
      for (final file in [completed, partial, marker]) {
        if (file.existsSync()) file.deleteSync();
      }

      addTearDown(() async {
        await requests.cancel();
        await server.close(force: true);
        for (final file in [completed, partial, marker]) {
          if (file.existsSync()) file.deleteSync();
        }
      });

      expect(await service.downloadUpdate(), isFalse,
          reason: 'Content-Range 声明的总长尚未收齐，不能进入 ready');
      expect(completed.existsSync(), isFalse,
          reason: '中断数据只能留在 .part，最终 .dmg 名本身就是完成边界');
      expect(partial.lengthSync(), firstResponseBytes);
      expect(marker.existsSync(), isFalse);

      expect(await service.downloadUpdate(), isTrue);
      expect(requestCount, 2);
      expect(completed.lengthSync(), totalBytes);
      expect(partial.existsSync(), isFalse);
      expect(marker.readAsStringSync(), '$totalBytes');
      expect(service.isReadyToInstall, isTrue);
    });

    test('206 缺少 Content-Range 时，大于 20MB 的 partial 也不能晋升', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.add(List<int>.filled(1024, 1));
        await request.response.close();
      });

      final service = UpdateService();
      service.configureDownloadForTest(
        version: '99.0.0-invalid-range',
        build: 1,
        dmgUrl: 'http://${server.address.address}:${server.port}/SpeakOut.dmg',
      );
      final completed = File(service.dmgPathForTest);
      final partial = File(service.partialDmgPathForTest);
      final marker = File(service.completionMarkerPathForTest);
      for (final file in [completed, partial, marker]) {
        if (file.existsSync()) file.deleteSync();
      }
      partial.createSync(recursive: true);
      final sparse = partial.openSync(mode: FileMode.write);
      sparse.truncateSync(21 * 1024 * 1024);
      sparse.closeSync();

      addTearDown(() async {
        await requests.cancel();
        await server.close(force: true);
        for (final file in [completed, partial, marker]) {
          if (file.existsSync()) file.deleteSync();
        }
      });

      expect(await service.downloadUpdate(), isFalse);
      expect(service.state, UpdateState.failed);
      expect(completed.existsSync(), isFalse);
      expect(marker.existsSync(), isFalse);
      expect(partial.existsSync(), isTrue,
          reason: 'Range 元数据错误时保留 partial，用户重试后仍可从可信响应续传');
    });
  });

  group('UpdateService helper 脚本安全保护', () {
    test('native 拒绝启动时不进入 installing', () {
      final service = UpdateService();
      final stateBefore = service.state;
      String? scriptPath;

      final launched = service.launchInstall((path) {
        scriptPath = path;
        return false;
      });

      expect(launched, isFalse);
      expect(service.state, stateBefore);
      expect(service.errorMessage, isNotNull);
      if (scriptPath != null) {
        try { File(scriptPath!).deleteSync(); } catch (_) {}
      }
    });

    test('launchInstall 启动成功后才进入 installing，脚本含签名校验 + 原子安装', () {
      final service = UpdateService();
      service.latestVersion = '1.10.0';
      service.latestBuild = 241;
      late String scriptPath;
      final launched = service.launchInstall((path) {
        scriptPath = path;
        return true;
      });

      expect(launched, isTrue);
      expect(service.state, UpdateState.installing);
      expect(scriptPath, isNotEmpty, reason: 'github 渠道应生成 helper 脚本');
      final script = File(scriptPath).readAsStringSync();

      expect(script, contains('SpeakOut-update-1.10.0+241.dmg'),
          reason: '同版本的不同 build 不能复用同一个 DMG 缓存');

      // F2：签名 / TeamIdentifier / BundleIdentifier 校验
      expect(script, contains('codesign --verify'));
      expect(script, contains('TeamIdentifier'));
      expect(script, contains('CFBundleIdentifier'));
      expect(script, contains('UB9D55S724'), reason: '预期 Team ID');
      expect(script, contains('com.speakout.speakout'), reason: '预期 bundle id');
      // F2：去掉 -noverify，让 macOS 校验 DMG 完整性
      expect(script, isNot(contains('-noverify')));

      // F1：原子安装 — staging + backup + 回滚
      expect(script, contains(r'$APP_NAME.new'));
      expect(script, contains(r'$APP_NAME.backup'));
      expect(script, contains('rolling back'));

      // F3：安装目录可写性兜底
      expect(script, contains(r'-w "$INSTALL_DIR"'));

      // F1：不再"先删旧 app 再直接复制到安装目录"——复制目标必须是 staging
      expect(script, isNot(contains(r'cp -R "$APP_IN_DMG" "$INSTALL_DIR/"')));
      expect(script, contains(r'cp -R "$APP_IN_DMG" "$STAGING"'));

      try { File(scriptPath).deleteSync(); } catch (_) {}
    });
  });
}
