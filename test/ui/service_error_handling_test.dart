import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// CloudAccountService 的写操作现在会**抛**（早期它们静默失败）。
/// UI 不接住的话，异常只进全局 zone 打印一行日志 ——
/// 用户既看不到成功也看不到失败，等于把「消息指错方向」换成「完全没消息」。
///
/// 这条规则来自一串真实演进：
///   静默 no-op → 抛 StateError → 惰性获取 → 写前加载 → 读前加载 →
///   「抛了但没人接」。每修一层，下一层才浮出来。
void main() {
  const throwing = {
    'importFromFile',
    'addAccount',
    'updateAccount',
    'removeAccount',
  };

  test('UI 里调用 CloudAccountService 的写方法必须在 try 内', () {
    final offenders = <String>[];
    for (final e in Directory('lib/ui').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final unit = parseFile(
        path: e.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;
      final v = _CallVisitor(throwing);
      unit.accept(v);
      for (final c in v.unguarded) {
        offenders.add('${e.path}: $c');
      }
    }
    expect(offenders, isEmpty,
        reason: '这些调用没有 try 包住 —— 失败时用户看不到任何提示：\n'
            '  ${offenders.join("\n  ")}');
  });
}

class _CallVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names;
  final List<String> unguarded = [];
  _CallVisitor(this.names);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final recv = node.target?.toSource() ?? '';
    if (names.contains(node.methodName.name) &&
        recv.contains('CloudAccountService')) {
      var guarded = false;
      for (AstNode? p = node.parent; p != null; p = p.parent) {
        if (p is TryStatement) {
          guarded = true;
          break;
        }
        if (p is FunctionBody && p.parent is! FunctionExpression) break;
      }
      if (!guarded) unguarded.add(node.toSource());
    }
    super.visitMethodInvocation(node);
  }
}
