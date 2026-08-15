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

  test('必须有独立的会话标志', () {
    expect(src.contains('_clipboardSessionActive'), isTrue,
        reason: '会话状态没有独立标志');
  });

  test('end 的早退判据不得是 _savedClipboardItems == nil', () {
    final end = RegExp(r'void inject_clipboard_end\(void\) \{([\s\S]*?)\n\}')
        .firstMatch(src)
        ?.group(1);
    expect(end, isNotNull, reason: '没找到 inject_clipboard_end');
    expect(RegExp(r'if\s*\(\s*_savedClipboardItems\s*==\s*nil\s*\)').hasMatch(end!),
        isFalse,
        reason: '拿快照当会话哨兵：用户剪贴板为空时 begin 就把它设成 nil，'
            'end 会误早退，注入文本永久留在剪贴板');
    expect(end.contains('!_clipboardSessionActive'), isTrue,
        reason: 'end 必须按独立标志早退');
  });

  test('begin 必须置位、end 必须清位', () {
    final begin = RegExp(r'void inject_clipboard_begin\(void\) \{([\s\S]*?)\n\}')
        .firstMatch(src)!
        .group(1)!;
    expect(begin.contains('_clipboardSessionActive = true'), isTrue);
    final end = RegExp(r'void inject_clipboard_end\(void\) \{([\s\S]*?)\n\}')
        .firstMatch(src)!
        .group(1)!;
    expect(end.contains('_clipboardSessionActive = false'), isTrue);
  });

  test('空剪贴板仍会开启会话（这条分支正是事故来源）', () {
    final begin = RegExp(r'void inject_clipboard_begin\(void\) \{([\s\S]*?)\n\}')
        .firstMatch(src)!
        .group(1)!;
    // 置位必须在「快照是否为空」的分支之前，否则空剪贴板路径可能漏置
    final flagAt = begin.indexOf('_clipboardSessionActive = true');
    final branchAt = begin.indexOf('oldContents.count > 0');
    expect(flagAt, greaterThanOrEqualTo(0));
    expect(branchAt, greaterThanOrEqualTo(0));
    expect(flagAt, lessThan(branchAt),
        reason: '置位必须早于空/非空分支，否则空剪贴板时会漏置');
  });

  test('dylib 已随源码重新编译', () {
    final m = File('native_lib/native_input.m').lastModifiedSync();
    final so = File('native_lib/libnative_input.dylib').lastModifiedSync();
    expect(so.isAfter(m) || so.isAtSameMomentAs(m), isTrue,
        reason: 'dylib 比 native_input.m 旧 —— 改了原生代码没重编译，'
            '跑的还是旧二进制');
  });
}
