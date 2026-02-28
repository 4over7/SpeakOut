import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/core_engine.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // 1. deduplicateText — 去重算法
  //    注意: 此去重仅用于流式 ASR (SherpaProvider 实时模式)，
  //    离线模型 (SenseVoice/Whisper/FireRedASR) 和云端 (Aliyun) 不走此逻辑。
  //    以下测试验证算法本身的正确性。
  // ═══════════════════════════════════════════════════════════
  group('deduplicateText', () {
    test('空字符串 → 不变', () {
      expect(CoreEngine.deduplicateText(''), '');
    });

    test('单字符 → 不变', () {
      expect(CoreEngine.deduplicateText('好'), '好');
    });

    test('无重复 → 不变', () {
      expect(CoreEngine.deduplicateText('你好世界'), '你好世界');
    });

    test('单字重复: "识识别" → "识别"', () {
      expect(CoreEngine.deduplicateText('识识别'), '识别');
    });

    test('全部重复: "啊啊啊" → "啊"', () {
      expect(CoreEngine.deduplicateText('啊啊啊'), '啊');
    });

    test('二字短语重复: "还是还是好" → "还是好"', () {
      expect(CoreEngine.deduplicateText('还是还是好'), '还是好');
    });

    test('二字短语三次重复: "一下一下一下" → "一下"', () {
      expect(CoreEngine.deduplicateText('一下一下一下'), '一下');
    });

    test('三字短语重复: "然后呢然后呢" → "然后呢"', () {
      expect(CoreEngine.deduplicateText('然后呢然后呢'), '然后呢');
    });

    test('四字短语重复: "怎么回事怎么回事" → "怎么回事"', () {
      expect(CoreEngine.deduplicateText('怎么回事怎么回事'), '怎么回事');
    });

    test('混合重复: "识识别还是还是好" → "识别还是好"', () {
      expect(CoreEngine.deduplicateText('识识别还是还是好'), '识别还是好');
    });

    test('英文字符重复: "hheello" → "helo"', () {
      expect(CoreEngine.deduplicateText('hheello'), 'helo');
    });

    test('长文本中嵌入重复', () {
      expect(
        CoreEngine.deduplicateText('今天天气很好好的'),
        '今天气很好的',
      );
    });

    test('数字重复: "112233" → "123"', () {
      expect(CoreEngine.deduplicateText('112233'), '123');
    });

    test('标点不受影响: "你好。" → "你好。"', () {
      expect(CoreEngine.deduplicateText('你好。'), '你好。');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. removeRepeatedPhrases — 短语去重子函数
  // ═══════════════════════════════════════════════════════════
  group('removeRepeatedPhrases', () {
    test('短于 2*len → 不变', () {
      expect(CoreEngine.removeRepeatedPhrases('ab', 2), 'ab');
    });

    test('len=2 无重复 → 不变', () {
      expect(CoreEngine.removeRepeatedPhrases('abcd', 2), 'abcd');
    });

    test('len=2 有重复: "abab" → "ab"', () {
      expect(CoreEngine.removeRepeatedPhrases('abab', 2), 'ab');
    });

    test('len=3 有重复: "abcabc" → "abc"', () {
      expect(CoreEngine.removeRepeatedPhrases('abcabc', 3), 'abc');
    });

    test('len=2 部分重复: "ababcd" → "abcd"', () {
      expect(CoreEngine.removeRepeatedPhrases('ababcd', 2), 'abcd');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. hasTerminalPunctuation — 末尾标点检测
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
  // 4. RecordingState 枚举基础
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
