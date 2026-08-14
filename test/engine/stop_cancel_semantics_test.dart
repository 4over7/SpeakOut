import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 两条容易被"顺手统一"改坏的语义，用源码级断言钉住。
/// 都源自真实回归：
///   1. 取消路径一度跟着正常路径改用 provider.stopTimeout，
///      OpenAI/Groq 是 35s —— 用户点了取消，状态机却被锁 35 秒，
///      期间 startRecording 的非 idle 守卫拒掉所有新录音。
///   2. 闪念笔记改成 await 后，ChatService().addUserMessage 被排到 await 之后，
///      慢盘上退出时两份副本一起丢 —— 比改之前更糟。
void main() {
  final src = File('lib/engine/core_engine.dart').readAsStringSync();

  test('取消路径必须用固定短超时，不得用 provider.stopTimeout', () {
    final cancelBlock = RegExp(r'\[Cancel\][\s\S]{0,400}?\}').firstMatch(src);
    // 取消路径附近那次 stop().timeout(...) 的参数
    final idx = src.indexOf('[Cancel] ASR stop error');
    expect(idx, greaterThan(0), reason: '没找到取消路径');
    final window = src.substring((idx - 600).clamp(0, src.length), idx);
    expect(window.contains('_asrProvider!.stopTimeout'), isFalse,
        reason: '取消路径用了 provider.stopTimeout（OpenAI/Groq 是 35s），'
            '会把状态机锁在 stopping 最长 35 秒，期间无法开始新录音');
    expect(window.contains('AppConstants.kAsrStopTimeout'), isTrue,
        reason: '取消路径应使用全局短超时');
    expect(cancelBlock, isNotNull);
  });

  test('闪念笔记：ChatService 写入必须早于 await appendNote', () {
    final chatAt = src.indexOf('ChatService().addUserMessage(finalText)');
    final noteAt = src.indexOf('await DiaryService().appendNote(finalText)');
    expect(chatAt, greaterThan(0), reason: '没找到 ChatService 写入');
    expect(noteAt, greaterThan(0), reason: '没找到 appendNote');
    expect(chatAt, lessThan(noteAt),
        reason: 'ChatService 是这条内容的兜底副本（dispose 会 flush 它的队列）。'
            '排在 await appendNote 之后的话，慢盘上退出会卡在 await，'
            '笔记和聊天两份一起丢 —— 比不 await 更糟');
  });

  test('正常识别路径仍使用 provider 声明的 stopTimeout', () {
    expect(src.contains('_asrProvider!.stopTimeout'), isTrue,
        reason: '正常路径必须尊重批量识别 provider 的长超时，否则丢结果');
  });
}
