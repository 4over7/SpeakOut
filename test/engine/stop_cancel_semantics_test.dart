import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 两条极易被"顺手统一"改坏的语义，都源自真实回归：
///   1. 取消路径一度跟着正常路径改用 provider.stopTimeout（OpenAI/Groq 是 35s）——
///      用户点了取消，状态机却被锁 35 秒，期间新录音全被非 idle 守卫拒掉。
///   2. 闪念笔记改 await 后，ChatService().addUserMessage 被排到 await 之后，
///      慢盘上退出时两份副本一起丢，比不 await 更糟。
///
/// 第一版断言用字符串窗口截取，被 codex 指出不可靠（锚点漂移即误报/漏报，
/// 且 cancelBlock 正则实际匹配到了隔壁的关音频 catch）。改用 AST 精确定位
/// 方法体，再在方法体内找 `.timeout(...)` 的实参。
void main() {
  final unit = parseFile(
    path: File('lib/engine/core_engine.dart').absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  /// 取指定方法体内所有 `xxx.timeout(arg, ...)` 的第一个实参源码
  List<String> timeoutArgsIn(String methodName) {
    final v = _MethodBodyVisitor(methodName);
    unit.accept(v);
    expect(v.body, isNotNull, reason: '没找到方法 $methodName');
    final t = _TimeoutArgVisitor();
    v.body!.accept(t);
    return t.args;
  }

  test('cancelRecording 必须用固定短超时，不得用 provider.stopTimeout', () {
    final args = timeoutArgsIn('cancelRecording');
    expect(args, isNotEmpty, reason: '取消路径没有任何 .timeout() 调用');
    for (final a in args) {
      expect(a.contains('stopTimeout'), isFalse,
          reason: '取消路径用了 provider.stopTimeout（OpenAI/Groq 是 35s），'
              '会把状态机锁在 stopping 最长 35 秒：$a');
    }
    expect(args.any((a) => a.contains('kAsrStopTimeout')), isTrue,
        reason: '取消路径应使用全局短超时，实际: $args');
  });

  test('stopRecording 必须用 provider 声明的 stopTimeout', () {
    final args = timeoutArgsIn('stopRecording');
    expect(args.any((a) => a.contains('stopTimeout')), isTrue,
        reason: '正常路径必须尊重批量识别 provider 的长超时，否则丢结果。实际: $args');
  });

  test('闪念笔记：ChatService 写入必须早于 await appendNote', () {
    final v = _MethodBodyVisitor('stopRecording');
    unit.accept(v);
    final body = v.body!.toSource();
    final chatAt = body.indexOf('ChatService().addUserMessage(finalText)');
    final noteAt = body.indexOf('DiaryService().appendNote(finalText)');
    expect(chatAt, greaterThan(-1), reason: '没找到 ChatService 写入');
    expect(noteAt, greaterThan(-1), reason: '没找到 appendNote');
    expect(chatAt, lessThan(noteAt),
        reason: 'ChatService 是兜底副本（dispose 会 await 它的 _pendingSave）。'
            '排在 await appendNote 之后的话，慢盘上退出会卡在 await，两份一起丢');
  });
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  FunctionBody? body;
  _MethodBodyVisitor(this.name);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body = node.body;
    super.visitMethodDeclaration(node);
  }
}

class _TimeoutArgVisitor extends RecursiveAstVisitor<void> {
  final List<String> args = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'timeout' &&
        node.argumentList.arguments.isNotEmpty) {
      args.add(node.argumentList.arguments.first.toSource());
    }
    super.visitMethodInvocation(node);
  }
}
