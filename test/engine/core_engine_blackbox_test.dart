import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/core_engine.dart';

/// CoreEngine 静态工具方法黑盒测试
///
/// 测试 hasTerminalPunctuation — 标注了 @visibleForTesting，可直接静态调用。
void main() {
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
