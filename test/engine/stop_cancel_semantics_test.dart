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
/// ⚠️ 这些是**回归哨兵，不是对抗性证明**。
///
/// 连续三轮复审（8/10/11）都在指同一件事：源码级断言总是弱于它声称保护的行为。
/// 每补一个洞就冒出一个等价写法（改变量名 → 换行 → 级联 → 中间变量 → 字符串
/// 藏注释符 → extension 同名方法 → 早退式条件复用 …）。到第三轮已是打地鼠。
///
/// 所以这里的定位明确为：**挡住「有人把同一个错误重新改回去」**，
/// 而不是防住任意等价改写。已知无法覆盖的形态：
///   - 把调用抽成 helper 后跨函数追踪（需要调用图分析）
///   - `if (x) return;` 式早退造成的条件复用（_ConnectVisitor 只看 IfStatement 祖先）
///   - 死分支里放一个"正确"调用来掩盖活路径上的错误
///   - 把兜底写进不一定执行的条件分支（顺序断言只比源码位置）
/// 要覆盖这些需要数据流/调用图分析，成本远超收益 —— 真正的护栏应该是
/// 行为测试，但 CoreEngine 是重依赖单例，behavioral fixture 的代价另计。
void main() {
  final unit = parseFile(
    path: File('lib/engine/core_engine.dart').absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  /// 取指定方法体内所有 `xxx.timeout(arg, ...)` 的第一个实参源码
  List<String> notAwaitedIn(String methodName) {
    final v = _MethodBodyVisitor(methodName);
    unit.accept(v);
    final t = _TimeoutArgVisitor();
    v.body!.accept(t);
    return t.notAwaited;
  }

  List<String> timeoutArgsIn(String methodName) {
    final v = _MethodBodyVisitor(methodName);
    unit.accept(v);
    expect(v.body, isNotNull, reason: '没找到方法 $methodName');
    expect(v.found, 1,
        reason: 'CoreEngine 里 $methodName 应恰好一个，实际 ${v.found} 个 —— '
            '多个会让断言指向最后一个，悄悄失效');
    final t = _TimeoutArgVisitor();
    v.body!.accept(t);
    return t.args;
  }

  test('cancelRecording 必须用固定短超时，不得用 provider.stopTimeout', () {
    final args = timeoutArgsIn('cancelRecording');
    expect(notAwaitedIn('cancelRecording'), isEmpty,
        reason: 'stop().timeout(...) 未被 await —— 超时形同虚设，'
            '参数写什么都不起作用');
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
    expect(notAwaitedIn('stopRecording'), isEmpty,
        reason: 'stop().timeout(...) 未被 await —— 超时形同虚设，'
            '参数写什么都不起作用');
    expect(args.any((a) => a.contains('stopTimeout')), isTrue,
        reason: '正常路径必须尊重批量识别 provider 的长超时，否则丢结果。实际: $args');
  });

  test('闪念笔记：appendNote 必须被 await，且 ChatService 写入排在它之前', () {
    final v = _MethodBodyVisitor('stopRecording');
    unit.accept(v);
    expect(v.found, 1, reason: 'CoreEngine 里应恰好有一个 stopRecording');

    final a = _AppendNoteVisitor();
    v.body!.accept(a);
    expect(a.calls, isNotEmpty, reason: '没找到 DiaryService().appendNote 调用');
    final unawaited = a.calls.where((c) => !c.awaited).map((c) => c.node.toSource());
    expect(unawaited, isEmpty,
        reason: '这些 appendNote 调用没有被 await —— 识别完立刻从托盘退出'
            '（dispose 后紧跟 exit(0)）会丢掉这条闪念：${unawaited.join(", ")}');

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

  /// extension 里的同名方法也要排除。只覆写 visitClassDeclaration 挡不住 ——
  /// RecursiveAstVisitor 仍会递归进顶层 ExtensionDeclaration（codex 指出，
  /// 我原注释声称已排除，其实没有）。
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {}

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
  final List<String> notAwaited = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'timeout' &&
        node.argumentList.arguments.isNotEmpty) {
      final recv = node.target?.toSource() ?? '';
      if (recv.contains('_asrProvider') && recv.contains('stop()')) {
        // 必须被 await —— 不 await 的话 .timeout() 形同虚设，
        // 参数写什么都无所谓，只检查参数文本会放过这种退化。
        args.add(node.argumentList.arguments.first.toSource());
        if (!_isAwaited(node)) notAwaited.add(node.toSource());
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// 判断某个求值为 Future 的表达式是否真的被等待。
///
/// 这条规则我前两版都只写了近似，各错一次：
///   v1 遇 FunctionBody 就停 → `await Future(() => f())` 被误判成未 await
///      （实测 Future 构造器会展开回调返回的 Future，对照实验 307ms）。
///   v2 父链一路走到顶 → `await Future(() { f(); })` 被误判成已 await
///      （块体里 f() 的返回值被丢弃，外层 await 等的是空 Future）。
///
/// 正确规则：向上走，
///   - 碰到 AwaitExpression → 已等待
///   - 碰到 ExpressionFunctionBody（`=>`）→ 值会作为返回值继续向外传播，继续走
///   - 碰到 BlockFunctionBody（`{}`）→ 值被丢弃，除非它处在 ReturnStatement 里
bool _isAwaited(AstNode node) {
  // value = 当前正在向外传播的那个表达式。穿过函数体时它会变成整个函数表达式。
  AstNode? value = node;
  for (AstNode? p = node.parent; p != null; p = p.parent) {
    if (p is AwaitExpression) return true;
    if (p is ExpressionFunctionBody) {
      value = p.parent; // `=>` 体：值即函数返回值，继续向外传播
      continue;
    }
    if (p is BlockFunctionBody) {
      // 块体：只有被 return 出去才继续传播。
      // 内层必须从 value 往上找 —— 从 p 的直接子节点（Block）往上找是错的，
      // ReturnStatement 在 Block **下面**，那样永远找不到（第一版就栽在这）。
      var returned = false;
      for (AstNode? q = value; q != null && q != p; q = q.parent) {
        if (q is ReturnStatement) {
          returned = true;
          break;
        }
      }
      if (!returned) return false;
      value = p.parent;
    }
  }
  return false;
}

/// 找出所有 DiaryService().appendNote(...) 调用，逐个判断是否被 await。
///
/// 两处被 codex 指出的缺陷已修：
///  - 原来所有调用共享一个只增不减的 awaited 标志，
///    「一处 await + 一处漏 await」会被首个调用蒙混过关 → 改为逐个记录。
///  - 原来父链遇 FunctionBody 就停，导致
///    `await Future(() => DiaryService().appendNote(x))` 被误判成未 await。
///    实测 Future 构造器会展开回调返回的 Future（307ms 的对照实验），
///    外层 await 确实等到了内层完成，不该报 → 改为父链走到底。
///    裸调用 `DiaryService().appendNote(x);` 整条父链没有 AwaitExpression，
///    仍会被正确抓出。
class _AppendNoteVisitor extends RecursiveAstVisitor<void> {
  final List<({MethodInvocation node, bool awaited})> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation n) {
    if (n.methodName.name == 'appendNote' &&
        (n.target?.toSource() ?? '').contains('DiaryService')) {
      calls.add((node: n, awaited: _isAwaited(n)));
    }
    super.visitMethodInvocation(n);
  }
}
