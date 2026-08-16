import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aliyun 复用 WebSocket 连接（initialize 预连接，start 在 _isConnected 时不重连），
/// 所以上一次录音的迟到帧会在下一次录音期间到达，把旧句子 append 进新会话的
/// _committedText —— 字幕串台。stop() 只固定等 500ms，窗口很容易命中。
///
/// 复用连接下唯一可靠的会话标识是 task_id（每次 start() 重新生成、随
/// StartTranscription 下发、服务端原样回带）。**不能**用其它 provider 那套
/// 「录音代次」—— 那是给「每次 start 都新建连接」设计的，套到这里会把本次录音的
/// 消息也全挡掉。
void main() {
  final path = 'lib/engine/providers/aliyun_provider.dart';
  final src = File(path).readAsStringSync();
  final unit = parseFile(
    path: File(path).absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  test('_handleMessage 必须按 task_id 过滤过期帧', () {
    final v = _MethodBodyVisitor('_handleMessage');
    unit.accept(v);
    expect(v.body, isNotNull, reason: '没找到 _handleMessage');
    final body = v.body!.toSource();

    expect(body.contains("header['task_id']"), isTrue,
        reason: '_handleMessage 没有读取 header.task_id，无法识别过期帧');
    expect(body.contains('_taskId'), isTrue,
        reason: '没有与当前会话的 _taskId 比对');

    // 不匹配必须真的 return —— 只读取不拦截等于没过滤
    expect(RegExp(r'msgTaskId != _taskId').hasMatch(body), isTrue,
        reason: '没有做不等比较');
    expect(body.contains('return;'), isTrue, reason: '比较后没有拦截');

    // 安全阀：万一服务端行为与协议不符导致消息全丢，日志要能一眼指出原因
    expect(body.contains('_droppedStaleFrame'), isTrue,
        reason: '缺少首次丢弃的诊断日志，全丢时会变成查不出的「阿里云没反应」');

    // 过滤必须发生在任何文本发布之前，否则旧句子已经串进去了。
    //
    // **锚点必须是「不匹配的拒绝判断」本身，不能是第一个 task_id** ——
    // task_id 在这个方法里出现多次（读 header、日志、比较）。拿第一个的话，
    // 把真正的拒绝分支挪到 _textController.add 之后，断言照样绿。
    // 位置比较也要用 AST offset —— 字符串 indexOf 会命中日志里的
    // `AppLog.d('msgTaskId != _taskId')`，把「过滤在发布之后」判成之前。
    // **用 AST 判断包含关系，不要再做字符串解析。**
    // 字符串解析会被诱饵骗：`AppLog.d('{ return }')` 里那个 return 会被
    // contains 命中，而过期帧其实照样往下走。
    final rejectIf = _FindIfVisitor('msgTaskId', '_taskId');
    unit.accept(rejectIf);
    expect(rejectIf.node, isNotNull,
        reason: '没找到形如 `msgTaskId != _taskId` 的拒绝判断'
            '（按 AST 结构匹配，不认字符串）');

    // then 分支的**最后一条直接语句**必须是 return —— 递归找 return 会被
    // `if (false) return;` 和 closure 里的 return 骗过。
    final then = rejectIf.node!.thenStatement;
    Statement? last;
    if (then is Block) {
      expect(then.statements, isNotEmpty, reason: '拒绝分支是空块');
      last = then.statements.last;
    } else {
      last = then;
    }
    expect(last is ReturnStatement, isTrue,
        reason: '拒绝分支的最后一条语句不是 return —— 过期帧照样会往下走');

    // 拒绝判断必须早于所有真实的发布调用（按 AST offset，不按字符串位置）
    final publishes = _FindInvocationVisitor('add');
    unit.accept(publishes);
    final textAdds = publishes.nodes
        .where((n) => n.target?.toSource().contains('_textController') ?? false)
        .toList();
    expect(textAdds, isNotEmpty, reason: '没找到 _textController.add 调用');
    for (final pub in textAdds) {
      expect(rejectIf.node!.offset, lessThan(pub.offset),
          reason: 'task_id 过滤必须早于每一处 _textController.add，'
              '否则过期帧已经污染了字幕');
    }
  });

  test('aliyun 不得改用录音代次守卫', () {
    expect(src.contains('gen != _generation'), isFalse,
        reason: '该 provider 复用连接，代次守卫会把本次录音的消息也全挡掉');
  });

  test('start() 必须重生成 task_id 并复位诊断标志', () {
    final v = _MethodBodyVisitor('start');
    unit.accept(v);
    final body = v.body!.toSource();
    expect(body.contains('_taskId ='), isTrue,
        reason: 'task_id 若不每次重生成，过滤就失去意义');
    expect(body.contains('_droppedStaleFrame = false'), isTrue,
        reason: '安全阀标志要每次会话复位，否则只在首次会话打一次日志');
  });
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  FunctionBody? body;
  _MethodBodyVisitor(this.name);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.name.lexeme != 'AliyunProvider') return;
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body = node.body;
    super.visitMethodDeclaration(node);
  }
}

/// 按**结构**找 `左 != 右` 的判断，不认字符串 ——
/// `if (false && msgTaskId != _taskId)` 的 toSource 也含目标片段，
/// 但那个条件永远不成立。这里要求 `!=` 是条件的顶层运算符
/// （允许被 `&&` 串联的合取项，因为那仍然是必要条件）。
class _FindIfVisitor extends RecursiveAstVisitor<void> {
  _FindIfVisitor(this.left, this.right);
  final String left;
  final String right;
  IfStatement? node;

  bool _isTarget(Expression e) {
    if (e is BinaryExpression) {
      if (e.operator.lexeme == '!=' &&
          e.leftOperand.toSource() == left &&
          e.rightOperand.toSource() == right) {
        return true;
      }
      // 只允许 && 串联：|| 会让这个条件变成非必要项
      if (e.operator.lexeme == '&&') {
        return _isTarget(e.leftOperand) || _isTarget(e.rightOperand);
      }
    }
    return false;
  }

  @override
  void visitIfStatement(IfStatement n) {
    if (node == null && _isTarget(n.expression)) node = n;
    super.visitIfStatement(n);
  }
}

class _FindInvocationVisitor extends RecursiveAstVisitor<void> {
  _FindInvocationVisitor(this.name);
  final String name;
  final List<MethodInvocation> nodes = [];

  @override
  void visitMethodInvocation(MethodInvocation n) {
    if (n.methodName.name == name) nodes.add(n);
    super.visitMethodInvocation(n);
  }
}

