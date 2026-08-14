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
      for (final v in ['', 'v1.0.0', '1.0', '1.0.0.0', 'latest', '1.0.0-beta', '../../etc']) {
        expect(UpdateService.isValidRemoteVersion(v), isFalse, reason: v);
      }
    });

    test('注入串确实能骗过版本比较 —— 证明白名单不可省', () {
      expect(UpdateService.isNewer('999.0.0"; touch /tmp/pwned; #', '1.10.0'), isTrue);
    });
  });
}
