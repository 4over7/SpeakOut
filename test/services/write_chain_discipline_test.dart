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
