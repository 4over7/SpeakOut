import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// AppLog.e() 记的是回滚失败 / 凭证残留 / 悬空引用这类事件 ——
/// 报障时最需要的就是它们。它写在 app support 默认目录的
/// speakout_errors.log 里。
///
/// 诊断包若只收「用户自定义日志目录」，那没设过目录的用户导出来是空的，
/// 等于前面所有诊断日志都白记了。
void main() {
  final path = 'lib/ui/settings/sidebar/pages/developer_page.dart';

  test('诊断包必须同时收集 app support 默认目录', () {
    // 必须限定在打包日志的那个方法体内 —— 只查整个文件的话，
    // 别处出现同名调用就会让断言恒真（我第一版就是这样，退化漏报）。
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final v = _MethodSourceVisitor('_exportLogBundle');
    unit.accept(v);
    expect(v.body, isNotNull,
        reason: '没找到打包方法，断言失效了');
    expect(v.body!.contains('getApplicationSupportDirectory'), isTrue,
        reason: '诊断包没有收集默认日志目录 —— AppLog.e 写的 '
            'speakout_errors.log 拿不到，报障时等于没有线索');
  });

  test('收集逻辑不得只在「用户设了自定义目录」时才执行', () {
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final v = _CollectVisitor();
    unit.accept(v);
    expect(v.found, isTrue, reason: '没找到日志收集代码');
    expect(v.guardedByCustomDirOnly, isFalse,
        reason: '整段收集被 logDirectory.isNotEmpty 包住了 —— '
            '没设自定义目录的用户拿不到任何应用日志');
  });
}

class _CollectVisitor extends RecursiveAstVisitor<void> {
  bool found = false;
  bool guardedByCustomDirOnly = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'getApplicationSupportDirectory') {
      found = true;
      for (AstNode? p = node.parent; p != null; p = p.parent) {
        if (p is IfStatement &&
            p.expression.toSource().contains('logDirectory')) {
          guardedByCustomDirOnly = true;
          break;
        }
        if (p is MethodDeclaration) break;
      }
    }
    super.visitMethodInvocation(node);
  }
}

class _MethodSourceVisitor extends RecursiveAstVisitor<void> {
  final String name;
  String? body;
  _MethodSourceVisitor(this.name);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body = node.body.toSource();
    super.visitMethodDeclaration(node);
  }
}
