import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/app_log.dart';

/// P2-3 日志脱敏防回归：默认不得把语音原文/LLM 内容写进日志。
void main() {
  group('AppLog.redact 脱敏', () {
    tearDown(() => AppLog.logSensitive = false);

    test('默认（logSensitive=false）只输出长度+hash，绝不含原文', () {
      AppLog.logSensitive = false;
      final out = AppLog.redact('我的银行卡密码是123456');
      expect(out, isNot(contains('银行卡')));
      expect(out, isNot(contains('123456')));
      expect(out, contains('字')); // 含长度摘要
    });

    test('开启 logSensitive 后才输出完整原文', () {
      AppLog.logSensitive = true;
      expect(AppLog.redact('敏感内容'), contains('敏感内容'));
    });

    test('空字符串 → <空>', () {
      AppLog.logSensitive = false;
      expect(AppLog.redact(''), '<空>');
    });

    test('相同输入产生相同摘要（hash 稳定，便于关联日志）', () {
      AppLog.logSensitive = false;
      expect(AppLog.redact('abc'), AppLog.redact('abc'));
    });

    test('不同输入摘要不同（长度或 hash 区分）', () {
      AppLog.logSensitive = false;
      expect(AppLog.redact('abc'), isNot(AppLog.redact('abcd')));
    });
  });
}
