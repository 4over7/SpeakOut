import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 编译并运行 native 剪贴板事务的**可执行**交错测试。
///
/// 为什么需要它：这个仓库里其余的 native 断言都是**源码级**的 ——
/// 它们能防「有人手滑删了一行」，但证不了「这段代码这么执行」。
/// 连续几轮 review 都能构造出骗过文本断言的写法（字符串诱饵、恒真条件、
/// `if(0)` 包起来、把语句挪进 else……）。这个宿主直接跑真实的 `tx_*` 函数
/// 并检查**最终剪贴板内容**，那类诱饵一个都骗不过去。
///
/// 两条安全前提（改动前务必确认仍然成立）：
///   1. 用 `pasteboardWithUniqueName`，**不碰用户的通用剪贴板**；
///   2. 宏掉 `CGEventPost`，**不往当前焦点窗口发任何按键**。
/// 二者都不需要改生产代码 —— 宿主直接 `#include` 实现文件拿到 static 函数。
void main() {
  test('native 剪贴板事务交错行为', () {
    final src = 'native_lib/tests/tx_harness.m';
    expect(File(src).existsSync(), isTrue, reason: '找不到测试宿主源码');

    // 安全前提是判据的一部分：宿主一旦碰真剪贴板或真发按键，
    // 跑测试就会污染用户环境，必须在这里拦住。
    final harness = File(src).readAsStringSync();
    expect(harness.contains('pasteboardWithUniqueName'), isTrue,
        reason: '宿主必须用独立 pasteboard，绝不能碰用户的通用剪贴板');
    expect(harness.contains('#define CGEventPost'), isTrue,
        reason: '宿主必须宏掉 CGEventPost，绝不能真发按键');
    expect(harness.contains('generalPasteboard'), isFalse,
        reason: '宿主里出现 generalPasteboard —— 会污染用户剪贴板');

    final out = Directory.systemTemp
        .createTempSync('speakout_tx_harness')
        .path;
    final bin = '$out/tx_harness';
    final build = Process.runSync('clang', [
      '-fobjc-arc',
      '-framework', 'Cocoa',
      '-framework', 'Carbon',
      '-framework', 'AVFoundation',
      '-framework', 'AudioToolbox',
      '-framework', 'CoreAudio',
      '-framework', 'Accelerate',
      '-o', bin,
      src,
    ]);
    expect(build.exitCode, 0, reason: '宿主编译失败:\n${build.stderr}');

    final run = Process.runSync(bin, []);
    final stdout = run.stdout as String;
    // 失败时把完整场景输出打出来，一眼能看到是哪个交错错了
    expect(run.exitCode, 0, reason: '事务行为不符：\n$stdout');
    expect(stdout.contains('ALL PASSED'), isTrue, reason: stdout);
  },
      // dylib 与 clang 都是 macOS 专属；其它平台跳过，不让本就该绿的 CI 变红
      skip: !Platform.isMacOS);
}
