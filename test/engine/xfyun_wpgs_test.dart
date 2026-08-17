import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/engine/providers/xfyun_asr_provider.dart';

/// 讯飞 wpgs（动态修正）的 segment 合并。
///
/// 旧实现在 rg 越界时有两个相反的坏结果：
/// - `end >= length`：删除循环一次都不跑，却照样 insert → **旧文本没删、新文本又插进去，重复**
/// - `start >= length`：整个分支被 `if` 挡住 → **这段识别结果直接丢掉**
///
/// 服务端按它自己的计数给 rg，和本地列表对不齐是正常的，不是异常输入。
void main() {
  group('追加模式', () {
    test('pgs 为 null 时追加', () {
      final segs = <String>['你好'];
      XfyunASRProvider.applyWpgs(segs, '世界', null, null);
      expect(segs, ['你好', '世界']);
    });

    test("pgs 为 'apd' 时追加", () {
      final segs = <String>['你好'];
      XfyunASRProvider.applyWpgs(segs, '世界', 'apd', [1, 1]);
      expect(segs, ['你好', '世界']);
    });

    test('rpl 但缺 rg 时退化为追加，不能丢文本', () {
      final segs = <String>['你好'];
      XfyunASRProvider.applyWpgs(segs, '世界', 'rpl', null);
      expect(segs, ['你好', '世界']);
    });
  });

  group('替换模式', () {
    test('替换单个 segment（rg 是 1-based 闭区间）', () {
      final segs = <String>['一', '二', '三'];
      XfyunASRProvider.applyWpgs(segs, '贰', 'rpl', [2, 2]);
      expect(segs, ['一', '贰', '三']);
    });

    test('替换连续多个 segment', () {
      final segs = <String>['一', '二', '三', '四'];
      XfyunASRProvider.applyWpgs(segs, '贰叁', 'rpl', [2, 3]);
      expect(segs, ['一', '贰叁', '四']);
    });

    test('替换到末尾', () {
      final segs = <String>['一', '二', '三'];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [1, 3]);
      expect(segs, ['新']);
    });
  });

  group('rg 越界', () {
    test('end 超出长度 → 夹到末尾，不得留下被替换的旧文本', () {
      final segs = <String>['一', '二'];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [1, 9]);
      expect(segs, ['新'], reason: '旧实现会得到 [新, 一, 二] —— 重复');
    });

    test('start 超出长度 → 追加到末尾，不得丢文本', () {
      final segs = <String>['一', '二'];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [7, 9]);
      expect(segs, ['一', '二', '新'], reason: '旧实现会把「新」整段丢掉');
    });

    test('start 为 0 或负（服务端给了 0-based）→ 夹到 0，不抛异常', () {
      final segs = <String>['一', '二'];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [0, 1]);
      expect(segs, ['新', '二']);
    });

    test('end < start → 不删任何东西，只插入', () {
      final segs = <String>['一', '二'];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [2, 1]);
      expect(segs, ['一', '新', '二']);
    });

    test('空列表上做替换不得抛异常', () {
      final segs = <String>[];
      XfyunASRProvider.applyWpgs(segs, '新', 'rpl', [1, 3]);
      expect(segs, ['新']);
    });
  });
}
