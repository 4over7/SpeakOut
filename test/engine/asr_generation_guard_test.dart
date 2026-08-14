import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「录音代次守卫」只在**每次 start() 都无条件新建连接**的 provider 上成立。
///
/// 真实事故：我给 aliyun 也加了这个守卫，但它在 initialize() 就预连接
/// （_ensureConnectedAsync），listener 捕获 gen=0；start() 自增到 1 且
/// 因 _isConnected 为真而复用旧连接不重连 —— 守卫把每条消息都挡掉，
/// 阿里云识别直接全废。复用连接的正确判别依据是 task_id，见
/// aliyun_task_id_filter_test.dart。
///
/// 第一版判据用正则找 `!_isConnected` / `_channel != null` 字样，被 codex 指出
/// 挡不住 `if (_channel == null) { connect(); listen(); }` 这种常见写法。
/// 改用 AST：只要 connect 调用**处在任何 if 之内**，就说明是条件复用，
/// 与连接期捕获的代次不兼容。
void main() {
  final dir = Directory('lib/engine/providers');

  test('在 start() 里捕获代次的 provider，connect 不得处在任何条件分支内', () {
    final offenders = <String>[];
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('_provider.dart')) continue;
      final src = e.readAsStringSync();
      if (!src.contains('gen != _generation')) continue; // 没用守卫

      final unit = parseFile(
        path: e.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;
      final mv = _MethodBodyVisitor('start', className: null);
      unit.accept(mv);
      if (mv.body == null) {
        offenders.add('${e.path}: 找不到 start()');
        continue;
      }
      // 只约束「代次在 start() 里捕获」的 provider —— 那意味着代次绑定的是连接。
      // 批量识别（OpenAI/Groq）在 stop() 里捕获，绑定的是单次请求，不适用。
      if (!mv.body!.toSource().contains('finalgen=_generation') &&
          !mv.body!.toSource().contains('final gen = _generation')) {
        continue;
      }
      final cv = _ConnectVisitor();
      mv.body!.accept(cv);
      if (!cv.found) {
        offenders.add('${e.path}: start() 里没有 connect 调用，'
            '代次却绑定在连接上 —— 说明连接是复用的');
      } else if (cv.insideCondition) {
        offenders.add('${e.path}: connect 处在条件分支内（复用连接），'
            '连接期捕获的代次会挡掉本次录音的全部消息');
      }
    }
    expect(offenders, isEmpty,
        reason: '代次守卫的前提被破坏：\n  ${offenders.join("\n  ")}');
  });

  test('aliyun 复用预连接，不得使用代次守卫', () {
    final src = File('${dir.path}/aliyun_provider.dart').readAsStringSync();
    expect(src.contains('gen != _generation'), isFalse,
        reason: 'aliyun 在 initialize() 预连接且 start() 复用，'
            '代次守卫会让它收不到任何消息。它按 task_id 过滤');
  });
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  final String? className;
  FunctionBody? body;
  int found = 0;
  _MethodBodyVisitor(this.name, {this.className});

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (className != null && node.name.lexeme != className) return;
    super.visitClassDeclaration(node);
  }

  /// extension 里的同名方法不算 —— RecursiveAstVisitor 默认会递归进去，
  /// 只覆写 visitClassDeclaration 挡不住（codex 指出）。
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {}

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) {
      body = node.body;
      found++;
    }
    super.visitMethodDeclaration(node);
  }
}

/// 找 WebSocket connect 调用，并判断它是否处在任何 if 之内
class _ConnectVisitor extends RecursiveAstVisitor<void> {
  bool found = false;
  bool insideCondition = false;

  void _check(AstNode node) {
    found = true;
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is IfStatement) {
        insideCondition = true;
        break;
      }
      if (p is MethodDeclaration) break;
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final s = node.toSource();
    if (s.contains('WebSocketChannel.connect') ||
        s.startsWith('_connectWebSocket(')) {
      _check(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.toSource().contains('WebSocketChannel.connect')) _check(node);
    super.visitInstanceCreationExpression(node);
  }
}
