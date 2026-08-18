import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/llm_service.dart';

/// 流式 `<think>` 剥离。
///
/// 为什么必须在流里做：打字机模式**边收 delta 边往用户文档里粘**。
/// 引擎那边收完后确实会用正则清一遍，但它清的是留档用的 `finalText` ——
/// 已经粘进用户文档的字撤不回来。thinking 模型一开就会把
/// `<think>…</think>` 直接打进用户的输入框。
///
/// 标签会被 delta 切成任意两半，所以这是个状态机，不是一次性正则。
void main() {
  /// 把整段文本按给定切法喂进去，返回最终输出
  String run(List<String> deltas) {
    final f = ThinkTagFilter();
    final out = StringBuffer();
    for (final d in deltas) {
      out.write(f.add(d));
    }
    out.write(f.flush());
    return out.toString();
  }

  group('无 think 标签', () {
    test('原样透传', () {
      expect(run(['你好', '世界']), '你好世界');
    });

    test('包含尖括号但不是 think 标签', () {
      expect(run(['a<b>c']), 'a<b>c');
    });

    test('以 < 结尾也要吐出来 —— 不能永久扣住', () {
      expect(run(['结果是 5 < ']), '结果是 5 < ');
    });
  });

  group('完整 think 段', () {
    test('开头一段思考，只留正文', () {
      expect(run(['<think>让我想想</think>你好']), '你好');
    });

    test('正文中间夹一段思考', () {
      expect(run(['前<think>嗯</think>后']), '前后');
    });

    test('多段思考', () {
      expect(run(['<think>a</think>1<think>b</think>2']), '12');
    });

    test('大小写不敏感', () {
      expect(run(['<THINK>x</Think>正文']), '正文');
    });
  });

  group('标签被 delta 切开（真实流式形态）', () {
    test('开标签逐字到达', () {
      expect(run(['<', 't', 'h', 'i', 'n', 'k', '>', '想', '</think>', 'ok']), 'ok');
    });

    test('闭标签逐字到达', () {
      expect(run(['<think>想', '<', '/', 't', 'h', 'i', 'n', 'k', '>', '正文']), '正文');
    });

    test('正文 + 半个开标签，后续补齐', () {
      expect(run(['你好<thi', 'nk>思考</think>再见']), '你好再见');
    });

    test('半个标签最终没补齐 → 当普通文本吐出来，不能吞掉', () {
      expect(run(['你好<thi']), '你好<thi');
    });
  });

  group('异常形态', () {
    test('未闭合的 think 段整体丢弃 —— 那是思考内容，不该进用户文档', () {
      expect(run(['<think>想到一半就断了']), '');
    });

    test('思考段里断在半个闭标签上 —— flush 不能把那半个标签当正文吐出来', () {
      // 这条专门盯 flush() 里的 `_inThink ? '' : ...`：
      // 扣在 _buf 里的 '</thi' 是个残缺标签，不是内容
      expect(run(['<think>思考中</thi']), '');
    });

    test('思考段里的内容不得随 flush 泄漏', () {
      // 专门盯 inThink 分支里「丢弃 work、只留疑似闭标签后缀」那一步
      expect(run(['<think>大段思考', '还在思考']), '');
    });

    test('只有闭标签（服务端异常）不该吞正文', () {
      expect(run(['正文</think>更多']), '正文更多');
    });

    test('空 think 段', () {
      expect(run(['a<think></think>b']), 'ab');
    });
  });

  test('正文不被延迟到 flush 才出来 —— 打字机要的是即时性', () {
    final f = ThinkTagFilter();
    // 没有任何疑似标签前缀时，喂进去就该立刻出来
    expect(f.add('立刻输出'), '立刻输出');
  });

  test('think 段里的内容一个字都不许提前泄漏', () {
    final f = ThinkTagFilter();
    f.add('<think>');
    expect(f.add('这是思考内容不该出现'), '');
    expect(f.add('</think>正文'), '正文');
  });
}
