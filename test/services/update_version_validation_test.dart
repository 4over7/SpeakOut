import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/update_service.dart';

/// 远端版本号会拼进 _dmgPath，再原样写进 update helper 的 shell 脚本
/// （`DMG="$_dmgPath"`）。含引号的版本号可闭合引号执行任意命令。
/// isNewer 的 _parseVersion 对非数字段静默兜底为 0，所以脏串能通过版本比较——
/// 这就是为什么必须在入口做白名单，而不能指望比较逻辑拦住。
void main() {
  group('远端版本号 SemVer 白名单', () {
    test('合法 SemVer 放行', () {
      for (final v in ['1.10.0', '0.0.1', '99999.0.0', '2.3.4']) {
        expect(UpdateService.isValidRemoteVersion(v), isTrue, reason: v);
      }
    });

    test('prerelease / build metadata 放行 —— 本仓库真发过 v1.1.0-RC3/RC4', () {
      for (final v in [
        '1.1.0-RC3', '1.1.0-RC4', '1.11.0-beta.1', '1.0.0-alpha', '1.0.0+build.5',
        '1.0.0-rc.1+exp.sha.5114f85',
      ]) {
        expect(UpdateService.isValidRemoteVersion(v), isTrue, reason: v);
      }
    });

    test('仓库全部历史 tag 都必须过白名单 —— 防止再次误拒真实版本', () {
      final tags = Process.runSync('git', ['tag', '-l']).stdout as String;
      final versions = tags
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .map((t) => t.startsWith('v') ? t.substring(1) : t)
          .toList();
      expect(versions, isNotEmpty, reason: '没读到 git tag，测试环境异常');
      final rejected =
          versions.where((v) => !UpdateService.isValidRemoteVersion(v)).toList();
      expect(rejected, isEmpty,
          reason: '这些真实发布过的版本号会被白名单拒绝，'
              '导致更新检查静默回落到旧版本：$rejected');
    });

    test('命令注入串被拒', () {
      const payloads = [
        '999.0.0"; touch /tmp/pwned; #',
        '1.0.0"; rm -rf ~; "',
        r'1.0.0$(whoami)',
        '1.0.0`id`',
        "1.0.0'; echo x; '",
        '1.0.0\nrm -rf /',
      ];
      for (final v in payloads) {
        expect(UpdateService.isValidRemoteVersion(v), isFalse, reason: v);
      }
    });

    test('非 SemVer 形状被拒', () {
      for (final v in ['', 'v1.0.0', '1.0', '1.0.0.0', 'latest', '../../etc', '1.0.0-']) {
        expect(UpdateService.isValidRemoteVersion(v), isFalse, reason: v);
      }
    });

    test('注入串确实能骗过版本比较 —— 证明白名单不可省', () {
      expect(UpdateService.isNewer('999.0.0"; touch /tmp/pwned; #', '1.10.0'), isTrue);
    });
  });
}
