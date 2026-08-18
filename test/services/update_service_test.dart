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

  group('UpdateService helper 脚本安全保护', () {
    test('prepareInstall 生成的脚本含签名校验 + 原子安装，且不先删旧 app', () {
      final service = UpdateService();
      service.latestVersion = '1.10.0';
      service.latestBuild = 241;
      final scriptPath = service.prepareInstall();
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
