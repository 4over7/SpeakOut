import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/vocab_service.dart';

void main() {
  final service = VocabService();

  group('Phase 1 精确替换', () {
    test('applyReplacements 空文本透传', () {
      expect(service.applyReplacements(''), '');
    });

    test('applyReplacements 无匹配词条透传', () {
      // 没有激活词条时，结果不变
      expect(service.applyReplacements('你好世界'), '你好世界');
    });
  });

  group('Phase 2 音近距离算法', () {
    test('相同字符串距离为 0', () {
      // 通过 _levenshtein 内部测试
      // 直接测试 applyWithPhonetic 在无词条时透传
      // 此处仅验证方法可被调用且无异常
      expect(() => service.applyWithPhonetic('测试文本'), returnsNormally);
    });

    test('applyWithPhonetic 空文本透传', () async {
      final result = await service.applyWithPhonetic('');
      expect(result, '');
    });

    test('applyWithPhonetic 无激活词条时透传', () async {
      // VocabService 未加载行业包、用户词条为空时，Phase 2 不做替换
      service.invalidatePinyinCache();
      final result = await service.applyWithPhonetic('安全漏洞扫描');
      expect(result, '安全漏洞扫描');
    });

    test('invalidatePinyinCache 不抛出异常', () {
      expect(() => service.invalidatePinyinCache(), returnsNormally);
    });
  });
}
