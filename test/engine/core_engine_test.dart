import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/core_engine.dart';
import 'package:speakout/engine/providers/dashscope_asr_provider.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // 1. DashScope 跨句重叠检测
  // ═══════════════════════════════════════════════════════════
  group('DashScope removeOverlap', () {
    test('无重叠 → 原文返回', () {
      expect(DashScopeASRProvider.removeOverlap('你好', '世界'), '世界');
    });

    test('完全重叠 → 返回空', () {
      expect(DashScopeASRProvider.removeOverlap('各种模式都支持', '各种模式都支持'), '');
    });

    test('部分重叠 → 返回非重叠部分', () {
      expect(DashScopeASRProvider.removeOverlap('各种模式都支持', '各种模式都支持很好'), '很好');
    });

    test('committed 为空 → 原文返回', () {
      expect(DashScopeASRProvider.removeOverlap('', '你好'), '你好');
    });

    test('newText 为空 → 返回空', () {
      expect(DashScopeASRProvider.removeOverlap('你好', ''), '');
    });

    test('单字重叠不触发 (≥2 才算)', () {
      expect(DashScopeASRProvider.removeOverlap('你好呀', '呀世界'), '呀世界');
    });

    test('2字重叠', () {
      expect(DashScopeASRProvider.removeOverlap('我说完了', '完了再来'), '再来');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. hasTerminalPunctuation — 末尾标点检测
  // ═══════════════════════════════════════════════════════════
  group('hasTerminalPunctuation', () {
    test('空字符串 → false', () {
      expect(CoreEngine.hasTerminalPunctuation(''), isFalse);
    });

    test('纯空格 → false', () {
      expect(CoreEngine.hasTerminalPunctuation('   '), isFalse);
    });

    test('无标点 → false', () {
      expect(CoreEngine.hasTerminalPunctuation('你好'), isFalse);
    });

    test('中文句号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('你好。'), isTrue);
    });

    test('中文问号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('你好？'), isTrue);
    });

    test('中文感叹号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('你好！'), isTrue);
    });

    test('英文句号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('Hello.'), isTrue);
    });

    test('英文问号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('Hello?'), isTrue);
    });

    test('英文感叹号 → true', () {
      expect(CoreEngine.hasTerminalPunctuation('Hello!'), isTrue);
    });

    test('中间有标点但结尾无 → false', () {
      expect(CoreEngine.hasTerminalPunctuation('你好。再见'), isFalse);
    });

    test('结尾有空格（trim后检测） → true', () {
      expect(CoreEngine.hasTerminalPunctuation('你好。  '), isTrue);
    });

    test('逗号不算终止标点 → false', () {
      expect(CoreEngine.hasTerminalPunctuation('你好，'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. RecordingState 枚举基础
  // ═══════════════════════════════════════════════════════════
  group('RecordingState enum', () {
    test('包含全部 5 种状态', () {
      expect(RecordingState.values.length, 5);
      expect(RecordingState.values, contains(RecordingState.idle));
      expect(RecordingState.values, contains(RecordingState.starting));
      expect(RecordingState.values, contains(RecordingState.recording));
      expect(RecordingState.values, contains(RecordingState.stopping));
      expect(RecordingState.values, contains(RecordingState.processing));
    });
  });

  group('RecordingMode enum', () {
    test('包含 ptt 和 diary', () {
      expect(RecordingMode.values.length, 2);
      expect(RecordingMode.values, contains(RecordingMode.ptt));
      expect(RecordingMode.values, contains(RecordingMode.diary));
    });
  });
}
