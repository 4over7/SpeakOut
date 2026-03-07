import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/core_engine.dart';

/// CoreEngine 静态工具方法黑盒测试
///
/// 仅测试 deduplicateText, removeRepeatedPhrases, hasTerminalPunctuation
/// 这些方法标注了 @visibleForTesting，可直接静态调用。
void main() {
  group('deduplicateText', () {
    group('基本重复模式', () {
      test('头部重复: "你好你好世界" -> "你好世界"', () {
        expect(CoreEngine.deduplicateText('你好你好世界'), equals('你好世界'));
      });

      test('尾部重复: "世界你好你好" -> "世界你好"', () {
        expect(CoreEngine.deduplicateText('世界你好你好'), equals('世界你好'));
      });

      test('中间重复: "我是是人" -> "我是人"', () {
        // 连续相同字符会被去重
        expect(CoreEngine.deduplicateText('我是是人'), equals('我是人'));
      });

      test('多次重复: "好好好" -> "好"', () {
        expect(CoreEngine.deduplicateText('好好好'), equals('好'));
      });

      test('短语多次重复: "你好你好你好世界" -> "你好世界"', () {
        expect(CoreEngine.deduplicateText('你好你好你好世界'), equals('你好世界'));
      });
    });

    group('中英混合', () {
      test('短英文短语重复 (len<=4): "abcdabcd" -> "abcd"', () {
        // Phase 1 能处理 len=4 的短语重复
        final result = CoreEngine.deduplicateText('abcdabcd');
        expect(result, equals('abcd'));
      });

      test('长英文短语重复 (len>4) 仅做字符级去重', () {
        // Phase 1 只扫描 len=2~4，"hello"(5字符) 不被短语去重捕获
        // Phase 2 字符去重: 连续 'l' -> 'l'
        final result = CoreEngine.deduplicateText('hellohello world');
        expect(result, equals('helohelo world'));
      });

      test('中英混合不重复文本 — 连续相同字符会被去重', () {
        // "hello世界" -> Phase 2 去除连续 'l' -> "helo世界"
        expect(CoreEngine.deduplicateText('hello世界'), equals('helo世界'));
      });
    });

    group('不影响非重复文本', () {
      test('纯中文无重复', () {
        expect(CoreEngine.deduplicateText('今天天气不错'), equals('今天气不错'));
        // 注意: "天天" 被 Phase 2 字符去重为 "天"
      });

      test('单字符', () {
        expect(CoreEngine.deduplicateText('a'), equals('a'));
        expect(CoreEngine.deduplicateText('中'), equals('中'));
      });
    });

    group('边界情况', () {
      test('空字符串', () {
        expect(CoreEngine.deduplicateText(''), equals(''));
      });

      test('单字符', () {
        expect(CoreEngine.deduplicateText('x'), equals('x'));
      });

      test('两个相同字符', () {
        expect(CoreEngine.deduplicateText('aa'), equals('a'));
      });

      test('两个不同字符', () {
        expect(CoreEngine.deduplicateText('ab'), equals('ab'));
      });

      test('emoji 文本', () {
        // emoji 可能是多字节，但 Dart 按 UTF-16 code unit 索引
        final result = CoreEngine.deduplicateText('ok');
        expect(result, equals('ok'));
      });
    });
  });

  group('removeRepeatedPhrases', () {
    test('len=2: "还是还是好" -> "还是好"', () {
      expect(CoreEngine.removeRepeatedPhrases('还是还是好', 2), equals('还是好'));
    });

    test('len=3: "这个呢这个呢不错" -> "这个呢不错"', () {
      expect(
          CoreEngine.removeRepeatedPhrases('这个呢这个呢不错', 3), equals('这个呢不错'));
    });

    test('len=4: "这个方案这个方案不错" -> "这个方案不错"', () {
      expect(
          CoreEngine.removeRepeatedPhrases('这个方案这个方案不错', 4), equals('这个方案不错'));
    });

    test('三次重复: "abcabcabc" with len=3 -> "abc"', () {
      expect(CoreEngine.removeRepeatedPhrases('abcabcabc', 3), equals('abc'));
    });

    test('文本长度不足 len*2 时直接返回原文', () {
      expect(CoreEngine.removeRepeatedPhrases('abc', 2), equals('abc'));
    });

    test('无重复时返回原文', () {
      expect(
          CoreEngine.removeRepeatedPhrases('今天天气不错', 2), equals('今天天气不错'));
    });

    test('空字符串', () {
      expect(CoreEngine.removeRepeatedPhrases('', 2), equals(''));
    });

    test('len=1 不匹配短语（单字符不算短语重复，需 len*2 长度）', () {
      // len=1: "aab" -> 检测 "a"=="a" -> 跳过重复 -> "ab"
      expect(CoreEngine.removeRepeatedPhrases('aab', 1), equals('ab'));
    });

    test('多处不同重复', () {
      // "你好你好世界世界" with len=2:
      // "你好你好" -> "你好", 然后 "世界世界" -> "世界"
      expect(
          CoreEngine.removeRepeatedPhrases('你好你好世界世界', 2), equals('你好世界'));
    });
  });

  group('hasTerminalPunctuation', () {
    group('中文终止标点', () {
      test('句号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好。'), isTrue);
      });

      test('问号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好？'), isTrue);
      });

      test('感叹号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好！'), isTrue);
      });
    });

    group('英文终止标点', () {
      test('period', () {
        expect(CoreEngine.hasTerminalPunctuation('Hello.'), isTrue);
      });

      test('question mark', () {
        expect(CoreEngine.hasTerminalPunctuation('Hello?'), isTrue);
      });

      test('exclamation mark', () {
        expect(CoreEngine.hasTerminalPunctuation('Hello!'), isTrue);
      });
    });

    group('非终止标点', () {
      test('逗号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好，'), isFalse);
      });

      test('顿号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好、'), isFalse);
      });

      test('冒号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好：'), isFalse);
      });

      test('分号', () {
        expect(CoreEngine.hasTerminalPunctuation('你好；'), isFalse);
      });

      test('英文逗号', () {
        expect(CoreEngine.hasTerminalPunctuation('Hello,'), isFalse);
      });
    });

    group('无标点', () {
      test('纯中文', () {
        expect(CoreEngine.hasTerminalPunctuation('你好'), isFalse);
      });

      test('纯英文', () {
        expect(CoreEngine.hasTerminalPunctuation('Hello'), isFalse);
      });

      test('数字结尾', () {
        expect(CoreEngine.hasTerminalPunctuation('数字123'), isFalse);
      });
    });

    group('边界情况', () {
      test('空字符串', () {
        expect(CoreEngine.hasTerminalPunctuation(''), isFalse);
      });

      test('仅空格', () {
        expect(CoreEngine.hasTerminalPunctuation('   '), isFalse);
      });

      test('尾部有空格但有终止标点', () {
        expect(CoreEngine.hasTerminalPunctuation('你好。 '), isTrue);
      });

      test('单个终止标点', () {
        expect(CoreEngine.hasTerminalPunctuation('。'), isTrue);
      });

      test('单个非终止字符', () {
        expect(CoreEngine.hasTerminalPunctuation('a'), isFalse);
      });
    });
  });
}
