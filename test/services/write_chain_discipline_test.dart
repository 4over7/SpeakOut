import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// CloudAccountService 的写操作全部经 _serializedWrite 排队。
///
/// 约束：**已在链内的方法（*Unsafe）不得调用公开写方法** ——
/// 那会把自己排到自己后面，永远等不到，表现是**卡死而不是报错**。
///
/// 这条规则替代了我一度加过的「布尔重入标志」。那个做法是错的：
/// 标志在链内 op 的整个执行期（含每个 await 间隙）都为 true，
/// 外部调用会被误判成重入而直接执行，与链内操作并发 ——
/// 等于把刚加的串行化又打穿了。对照实验的执行顺序是
/// A:start → B:BYPASS → B:start → A:end → B:end。
void main() {
  const publicWrites = {
    'addAccount',
    'updateAccount',
    'removeAccount',
    'importFromFile',
    'migrateFromLegacy',
    'migrateDeepSeekModels',
    'reload',
  };

  test('链内方法（*Unsafe）不得调用公开写方法', () {
    final path = 'lib/services/cloud_account_service.dart';
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final v = _UnsafeBodyVisitor(publicWrites);
    unit.accept(v);
    expect(v.methodsFound, greaterThan(0), reason: '一个 *Unsafe 方法都没找到，扫描失效');
    expect(v.violations, isEmpty,
        reason: '链内调用公开写方法会自死锁（卡死而非报错）。'
            '应改调对应的 *Unsafe：\n  ${v.violations.join("\n  ")}');
  });

  test('入链目标必须以 Unsafe 结尾 —— 否则纪律断言扫不到它', () {
    // 上一条断言只扫 *Unsafe 后缀的方法体。若有人写了个链内 helper
    // 却不带这个后缀，它内部调公开写方法就没人拦，仍会自死锁。
    // 这里反向约束命名，把约定闭环：入链的必须叫 *Unsafe。
    final path = 'lib/services/cloud_account_service.dart';
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final v = _ChainTargetVisitor();
    unit.accept(v);
    expect(v.targets, isNotEmpty, reason: '一个入链目标都没找到，扫描失效');
    final bad = v.targets.where((t) => !t.endsWith('Unsafe')).toList();
    expect(bad, isEmpty,
        reason: '这些入链目标没有 Unsafe 后缀，纪律断言扫不到它们：$bad');
  });

  test('不得用布尔标志做重入判断', () {
    final src =
        File('lib/services/cloud_account_service.dart').readAsStringSync();
    expect(src.contains('_inSerializedWrite'), isFalse,
        reason: '布尔重入标志会在 await 间隙让外部调用绕过串行 —— '
            '见本文件顶部注释里的对照实验');
  });
}

class _UnsafeBodyVisitor extends RecursiveAstVisitor<void> {
  final Set<String> publicWrites;
  final List<String> violations = [];
  int methodsFound = 0;
  String? _current;

  _UnsafeBodyVisitor(this.publicWrites);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (name.endsWith('Unsafe')) {
      methodsFound++;
      _current = name;
      super.visitMethodDeclaration(node);
      _current = null;
      return;
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_current != null &&
        node.target == null &&
        publicWrites.contains(node.methodName.name)) {
      violations.add('$_current → ${node.methodName.name}()');
    }
    super.visitMethodInvocation(node);
  }
}

/// 收集 _serializedWrite(() => X()) 里的目标方法名
class _ChainTargetVisitor extends RecursiveAstVisitor<void> {
  final List<String> targets = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == '_serializedWrite' &&
        node.argumentList.arguments.isNotEmpty) {
      final arg = node.argumentList.arguments.first;
      final inner = _InnerCallVisitor();
      arg.accept(inner);
      targets.addAll(inner.names);
    }
    super.visitMethodInvocation(node);
  }
}

class _InnerCallVisitor extends RecursiveAstVisitor<void> {
  final List<String> names = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}
