import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// native 剪贴板会话状态的源码约束。
///
/// 真实事故（两次，都是我造成的）：
///  1. 重复 inject_clipboard_end 会清空用户剪贴板 —— clearContents 无条件执行，
///     只有 saved != nil 才写回，第二次调用时 saved 已被取走置 nil。
///  2. 修 1 时我拿 `_savedClipboardItems == nil` 当「无会话」哨兵 ——
///     但用户剪贴板本来为空时 begin 就会把快照设成 nil，
///     于是 end 误判早退，**注入的语音文本永久留在剪贴板**（口述内容泄漏）。
///
/// 结论：会话状态必须用独立标志，绝不能拿快照是否为空代表。
void main() {
  final src = File('native_lib/native_input.m').readAsStringSync();

  test('必须有独立的会话状态，不能拿快照是否为 nil 代表', () {
    expect(src.contains('_txHoldDepth'), isTrue, reason: '会话状态没有独立计数');
  });

  test('收尾的早退判据不得是「快照为 nil」', () {
    final finish =
        RegExp(r'static void tx_finish_locked\(NSPasteboard \*pb, uint64_t gen\) \{([\s\S]*?)\n\}')
            .firstMatch(src)
            ?.group(1);
    expect(finish, isNotNull, reason: '没找到 tx_finish_locked');
    expect(RegExp(r'if\s*\(\s*_txOriginal\s*==\s*nil\s*\)').hasMatch(finish!),
        isFalse,
        reason: '拿快照当会话哨兵：用户剪贴板为空时快照本来就是 nil，'
            '会误早退，注入文本永久留在剪贴板');
    expect(finish.contains('_txHoldDepth > 0'), isTrue,
        reason: '流式会话开着时必须挂起还原');
  });

  test('begin/end 必须成对增减会话深度', () {
    // 按函数名匹配，不写死返回类型（签名从 void 变成过 int，绊过多次）
    String fn(String name) {
      final m = RegExp(
              r'^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_ *]*\b' +
                  name +
                  r'\s*\([^)]*\)\s*\{([\s\S]*?)\n\}',
              multiLine: true)
          .firstMatch(src);
      expect(m, isNotNull, reason: '没找到 $name —— 断言已失效，先修扫描');
      return m!.group(1)!;
    }

    final begin = fn('inject_clipboard_begin');
    expect(begin.contains('_txHoldDepth++'), isTrue);
    final end = fn('inject_clipboard_end');
    expect(end.contains('_txHoldDepth--'), isTrue);
    expect(end.contains('_txHoldDepth == 0'), isTrue,
        reason: '无会话时 end 必须早退，否则 clearContents 会清空用户剪贴板');
  });

  test('空剪贴板必须走成功路径（这条分支正是事故来源）', () {
    // 原事故：拿 `_savedClipboardItems == nil` 当会话哨兵，
    // 用户剪贴板本来就空时快照就是 nil，end 误判成「无会话」直接返回，
    // 注入的语音文本永久留在剪贴板（口述内容泄漏）。
    //
    // 旧断言用「置位语句早于拍快照语句」当代理。那个代理现在失效了 ——
    // 快照可能失败，失败时**不能**开事务，所以置位必然在拍快照之后。
    // 代理没了，就直接断言真正的不变量：**空剪贴板算拍摄成功，不算失败。**
    final snap = RegExp(
            r'^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_ *]*\bsnapshot_pasteboard'
            r'\s*\([^)]*\)\s*\{([\s\S]*?)\n\}',
            multiLine: true)
        .firstMatch(src)
        ?.group(1);
    expect(snap, isNotNull, reason: '没找到 snapshot_pasteboard —— 断言已失效');
    // count == 0 分支必须 return YES，不能和读取失败混为一谈
    final emptyBranch = RegExp(r'count == 0\)\s*\{([\s\S]*?)\n\s*\}')
        .firstMatch(snap!)
        ?.group(1);
    expect(emptyBranch, isNotNull, reason: '没找到空剪贴板分支');
    expect(emptyBranch!.contains('return YES'), isTrue,
        reason: '空剪贴板必须算拍摄成功，否则整条注入会被误判为「拿不到快照」而中止');

    // 而 tx_snapshot_stable_locked 的成功路径不得再用「快照非空」做条件
    final stable = RegExp(
            r'^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_ *]*\btx_snapshot_stable_locked'
            r'\s*\([^)]*\)\s*\{([\s\S]*?)\n\}',
            multiLine: true)
        .firstMatch(src)
        ?.group(1);
    expect(stable, isNotNull);
    expect(RegExp(r'if\s*\(\s*snap\s*[!=]=\s*nil').hasMatch(stable!), isFalse,
        reason: '不得拿「快照是否为空」决定事务能不能开');
  });

  // 只在 macOS 跑：dylib 是 macOS 专属产物，且判据依赖 `strings`
  // （binutils）—— Windows runner 上没有这个命令，会让本就该绿的
  // Linux/Windows job 变红。CI 三个平台都会执行 flutter test。
  test('dylib 已随源码重新编译（内容判据，不看 mtime）', () {
    // 判据用「源码里的日志字面量是否已编进二进制」，**不能用 mtime**：
    // git clone 不保留 mtime，checkout 顺序决定先后 —— 本机三次 clone 都同秒，
    // 但 CI 上跨秒边界就会翻转，等于埋一颗随机变红的炸弹。
    // 日志字面量会原样进入 __cstring 段，改了源码没重编译就一定查不到。
    final src = File('native_lib/native_input.m').readAsStringSync();
    // 跳过含非 ASCII 的字面量：strings(1) 只提取连续 ASCII 序列，
    // 一个中文或破折号就会把整条切成两半，判据于是假阳性
    // （实测被这条绊过一次：日志里写了「—」）。
    final lits = RegExp(r'log_to_file\(\s*"([^"%\\]{20,})"')
        .allMatches(src)
        .map((m) => m.group(1)!)
        .where((l) => l.codeUnits.every((c) => c >= 0x20 && c < 0x7f))
        .toSet()
        .toList();
    expect(lits.length, greaterThan(3),
        reason: '没提取到足够的日志字面量，判据失效了');

    final out = Process.runSync('strings', ['native_lib/libnative_input.dylib']);
    expect(out.exitCode, 0, reason: 'strings 执行失败: ${out.stderr}');
    final binary = out.stdout as String;

    final missing = lits.where((l) => !binary.contains(l)).toList();
    expect(missing, isEmpty,
        reason: '这些日志字面量在源码里有、在 dylib 里没有 —— '
            '改了 native_input.m 却没重编译，跑的还是旧二进制。'
            '重编译命令见 native_lib/AGENTS.md：\n  ${missing.join("\n  ")}');
  }, skip: !Platform.isMacOS ? 'dylib 检查仅在 macOS 有意义（依赖 strings）' : null);
}
