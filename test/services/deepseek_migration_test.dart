import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/config_service.dart';

/// DeepSeek 旧模型别名映射。
///
/// deepseek-chat / deepseek-reasoner 已于 2026-07-24 15:59 UTC 被官方永久停用
/// （无宽限期、无软重定向），存量用户保存的这两个名字会直接调用失败。
///
/// 官方映射：两个旧别名**都**落到 v4-flash 且价格不变；
/// v4-pro 是另一档、单价约 3 倍 —— 把 reasoner 迁到 pro 会让账单翻三倍，
/// 所以这里显式断言"不得为 pro"。
void main() {
  const map = ConfigService.mapRetiredDeepSeekModel;

  test('deepseek-chat → v4-flash', () {
    expect(map('deepseek-chat'), 'deepseek-v4-flash');
  });

  test('deepseek-reasoner → v4-flash，而不是 pro（pro 单价约 3 倍）', () {
    expect(map('deepseek-reasoner'), 'deepseek-v4-flash');
    expect(map('deepseek-reasoner'), isNot('deepseek-v4-pro'));
  });

  test('已是 v4 系列的不改动', () {
    expect(map('deepseek-v4-flash'), 'deepseek-v4-flash');
    expect(map('deepseek-v4-pro'), 'deepseek-v4-pro',
        reason: '用户主动选了 pro 就该保留，迁移不能替用户降档');
  });

  test('其他厂商模型不受影响', () {
    for (final m in ['qwen-turbo', 'glm-4-flash', 'gpt-4o', 'claude-3-5-sonnet']) {
      expect(map(m), m);
    }
  });

  test('null 安全', () {
    expect(map(null), isNull);
  });
}
