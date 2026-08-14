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

    // 固定清单必跑：CI 用 actions/checkout@v4 默认浅克隆（fetch-tags: false），
    // `git tag -l` 返回空 —— 直接依赖 git 会让本来绿的 macOS/Linux CI 变红。
    // 这份清单覆盖仓库真实用过的全部版本形态，含被我第一版正则误拒的 RC。
    const historicalVersions = [
      '1.1.0-RC3', '1.1.0-RC4', '1.1.1', '1.1.2', '1.2.21', '1.2.28',
      '1.3.1', '1.5.1', '1.5.24', '1.6.0', '1.7.2', '1.8.0', '1.8.6',
      '1.9.0', '1.9.1', '1.10.0',
    ];

    test('全部历史发布版本必须过白名单', () {
      final rejected = historicalVersions
          .where((v) => !UpdateService.isValidRemoteVersion(v))
          .toList();
      expect(rejected, isEmpty,
          reason: '这些真实发布过的版本号会被白名单拒绝，'
              '更新检查会静默回落到旧版本：$rejected');
    });

    test('若环境有 git tag，则实际 tag 也必须全部过白名单', () {
      // 本地开发/完整 clone 才跑；浅克隆环境自动跳过，不把 CI 弄红。
      String out;
      try {
        out = Process.runSync('git', ['tag', '-l']).stdout as String;
      } catch (_) {
        return; // 没有 git 可执行文件
      }
      final versions = out
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .map((t) => t.startsWith('v') ? t.substring(1) : t)
          .toList();
      if (versions.isEmpty) return; // 浅克隆，无 tag refs
      final rejected =
          versions.where((v) => !UpdateService.isValidRemoteVersion(v)).toList();
      expect(rejected, isEmpty,
          reason: '仓库里存在白名单拒绝的 tag（固定清单该补了）：$rejected');
    });

    test('非 SemVer 形状被拒', () {
      for (final v in ['', 'v1.0.0', '1.0', '1.0.0.0', 'latest', '../../etc', '1.0.0-']) {
        expect(UpdateService.isValidRemoteVersion(v), isFalse, reason: v);
      }
    });

    // prerelease 现在过白名单了，版本比较就必须跟上 —— 否则 RC3/RC4 被判成
    // 同一个版本，1.1.0 稳定版相对 1.1.0-RC4 也永远"不是更新"，用户卡在 RC 上。
    test('SemVer prerelease 优先级（稳定版 > prerelease，RC4 > RC3）', () {
      expect(UpdateService.isNewer('1.1.0-RC4', '1.1.0-RC3'), isTrue);
      expect(UpdateService.isNewer('1.1.0-RC3', '1.1.0-RC4'), isFalse);
      expect(UpdateService.isNewer('1.1.0', '1.1.0-RC4'), isTrue,
          reason: '稳定版必须高于同版本的 prerelease');
      expect(UpdateService.isNewer('1.1.0-RC4', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('1.1.0-RC3', '1.1.0-RC3'), isFalse);
      // 数字段按数值比，且低于字母数字段
      expect(UpdateService.isNewer('1.0.0-alpha.2', '1.0.0-alpha.10'), isFalse);
      expect(UpdateService.isNewer('1.0.0-alpha.10', '1.0.0-alpha.2'), isTrue);
      expect(UpdateService.isNewer('1.0.0-alpha', '1.0.0-1'), isTrue);
      // 前缀相同则字段多的更大
      expect(UpdateService.isNewer('1.0.0-alpha.1', '1.0.0-alpha'), isTrue);
      // build metadata 不参与比较
      expect(UpdateService.isNewer('1.1.0+build.9', '1.1.0+build.1'), isFalse);
      // 主版本号仍然优先
      expect(UpdateService.isNewer('1.2.0-RC1', '1.1.0'), isTrue);
    });

    test('长度上限容得下 40 位 commit SHA 作 build metadata', () {
      final sha = 'a' * 40;
      expect(UpdateService.isValidRemoteVersion('1.0.0+$sha'), isTrue);
      expect(UpdateService.isValidRemoteVersion('1.0.0-${'b' * 64}'), isTrue);
      expect(UpdateService.isValidRemoteVersion('1.0.0-${'b' * 65}'), isFalse,
          reason: '超长后缀仍应拒绝 —— 版本号要进文件名');
    });

    test('注入串确实能骗过版本比较 —— 证明白名单不可省', () {
      expect(UpdateService.isNewer('999.0.0"; touch /tmp/pwned; #', '1.10.0'), isTrue);
    });
  });
}
