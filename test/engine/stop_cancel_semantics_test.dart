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

  test('闪念笔记：appendNote 必须被 await，且 ChatService 写入排在它之前', () {
    final v = _MethodBodyVisitor('stopRecording');
    unit.accept(v);
    expect(v.found, 1, reason: 'CoreEngine 里应恰好有一个 stopRecording');

    final a = _AppendNoteVisitor();
    v.body!.accept(a);
    expect(a.node, isNotNull, reason: '没找到 DiaryService().appendNote 调用');
    expect(a.awaited, isTrue,
        reason: 'appendNote 退回 fire-and-forget 的话，识别完立刻从托盘退出'
            '（dispose 后紧跟 exit(0)）会丢掉这条闪念');

    final body = v.body!.toSource();
    final chatAt = body.indexOf('ChatService().addUserMessage(finalText)');
    expect(chatAt, greaterThan(-1), reason: '没找到 ChatService 写入');
    expect(chatAt, lessThan(body.indexOf('DiaryService().appendNote')),
        reason: 'ChatService 是兜底副本（dispose 会 await 它的 _pendingSave）。'
            '排在 await appendNote 之后的话，慢盘上退出会卡在 await，两份一起丢');
  });
}

/// 只在 CoreEngine 类里找方法 —— 不限定类的话，文件里新增同名方法
/// （另一个 class / extension）会覆盖掉目标，断言悄悄指向别处。
class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  FunctionBody? body;
  int _found = 0;
  _MethodBodyVisitor(this.name);

  int get found => _found;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.name.lexeme != 'CoreEngine') return; // 不递归进其它类
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) {
      body = node.body;
      _found++;
    }
    super.visitMethodDeclaration(node);
  }
}

/// 只收 `_asrProvider…stop().timeout(...)` 的第一个实参。
/// 不校验 receiver 的话，方法体里任何别的 .timeout()（含嵌套闭包里的）
/// 都会被算进来，把真正改错的那处掩盖掉。
class _TimeoutArgVisitor extends RecursiveAstVisitor<void> {
  final List<String> args = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'timeout' &&
        node.argumentList.arguments.isNotEmpty) {
      final recv = node.target?.toSource() ?? '';
      if (recv.contains('_asrProvider') && recv.contains('stop()')) {
        args.add(node.argumentList.arguments.first.toSource());
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// 找 DiaryService().appendNote(...) 并判断它是否处在 await 表达式下
class _AppendNoteVisitor extends RecursiveAstVisitor<void> {
  MethodInvocation? node;
  bool awaited = false;

  @override
  void visitMethodInvocation(MethodInvocation n) {
    if (n.methodName.name == 'appendNote' &&
        (n.target?.toSource() ?? '').contains('DiaryService')) {
      node = n;
      for (AstNode? p = n.parent; p != null; p = p.parent) {
        if (p is AwaitExpression) {
          awaited = true;
          break;
        }
        if (p is FunctionBody) break; // 越过函数体就不算同一个 await
      }
    }
    super.visitMethodInvocation(n);
  }
}
