import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/asr_result.dart';

/// ASRResult 数据类黑盒测试
void main() {
  group('完整构造函数', () {
    test('所有字段均正确赋值', () {
      final result = ASRResult(
        text: '你好世界',
        tokens: ['你', '好', '世', '界'],
        timestamps: [0.0, 0.5, 1.0, 1.5],
        tokenConfidence: [-0.1, -0.2, -0.05, -0.3],
      );

      expect(result.text, equals('你好世界'));
      expect(result.tokens, equals(['你', '好', '世', '界']));
      expect(result.timestamps, equals([0.0, 0.5, 1.0, 1.5]));
      expect(result.tokenConfidence, equals([-0.1, -0.2, -0.05, -0.3]));
    });

    test('空文本和空列表', () {
      final result = ASRResult(
        text: '',
        tokens: [],
        timestamps: [],
      );

      expect(result.text, equals(''));
      expect(result.tokens, isEmpty);
      expect(result.timestamps, isEmpty);
      expect(result.tokenConfidence, isNull);
    });

    test('长文本', () {
      final longText = 'a' * 10000;
      final result = ASRResult(text: longText);
      expect(result.text.length, equals(10000));
    });
  });

  group('默认值', () {
    test('tokens 默认为空列表', () {
      final result = ASRResult(text: '测试');
      expect(result.tokens, equals(const <String>[]));
    });

    test('timestamps 默认为空列表', () {
      final result = ASRResult(text: '测试');
      expect(result.timestamps, equals(const <double>[]));
    });

    test('tokenConfidence 默认为 null', () {
      final result = ASRResult(text: '测试');
      expect(result.tokenConfidence, isNull);
    });
  });

  group('textOnly 工厂方法', () {
    test('text 正确赋值', () {
      final result = ASRResult.textOnly('你好');
      expect(result.text, equals('你好'));
    });

    test('tokens 应为空列表', () {
      final result = ASRResult.textOnly('你好');
      expect(result.tokens, isEmpty);
    });

    test('timestamps 应为空列表', () {
      final result = ASRResult.textOnly('你好');
      expect(result.timestamps, isEmpty);
    });

    test('tokenConfidence 应为 null', () {
      final result = ASRResult.textOnly('你好');
      expect(result.tokenConfidence, isNull);
    });

    test('空字符串', () {
      final result = ASRResult.textOnly('');
      expect(result.text, equals(''));
      expect(result.tokens, isEmpty);
      expect(result.timestamps, isEmpty);
      expect(result.tokenConfidence, isNull);
    });

    test('含特殊字符', () {
      final result = ASRResult.textOnly('Hello 世界! 123 @#\$');
      expect(result.text, equals('Hello 世界! 123 @#\$'));
    });
  });

  group('tokenConfidence 可选性', () {
    test('显式传入 null', () {
      final result = ASRResult(
        text: '测试',
        tokenConfidence: null,
      );
      expect(result.tokenConfidence, isNull);
    });

    test('传入非空列表', () {
      final result = ASRResult(
        text: '测试',
        tokens: ['测', '试'],
        tokenConfidence: [-0.5, -0.3],
      );
      expect(result.tokenConfidence, isNotNull);
      expect(result.tokenConfidence!.length, equals(2));
    });

    test('传入空列表 (区别于 null)', () {
      final result = ASRResult(
        text: '测试',
        tokenConfidence: [],
      );
      expect(result.tokenConfidence, isNotNull);
      expect(result.tokenConfidence, isEmpty);
    });
  });

  group('不可变性', () {
    test('const 构造函数可用', () {
      // 验证 const 构造正常工作
      const result = ASRResult(text: '常量');
      expect(result.text, equals('常量'));
    });

    test('const 构造带默认值', () {
      const result = ASRResult(text: '常量');
      expect(result.tokens, isEmpty);
      expect(result.timestamps, isEmpty);
      expect(result.tokenConfidence, isNull);
    });
  });
}
