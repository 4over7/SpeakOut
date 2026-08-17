import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回滚配置的地方必须把引擎也拉回来。
///
/// `initASR` 在 await `provider.initialize()` **之前**就 dispose 了旧 provider，
/// 所以初始化失败时 `_asrProvider` 是 null。只把 `activeModelId` / `workMode` /
/// `selectedAsrAccount` 改回去的话，用户看到的是「还停在原来那档」，
/// 按快捷键却毫无反应 —— 界面上没有任何异常可看。
///
/// 这条规则是 rethrow 上线之后才暴露的：在那之前 `initASR` 从不抛，
/// 整段回滚代码根本没执行过。
///
/// **形状断言**，不是行为断言。它只能保证「回滚分支里调了恢复函数」，
/// 保证不了恢复真的成功 —— 那由 `_app.isASRReady` 在运行时判，
/// 并据此给用户不同的提示文案。
void main() {
  const path = 'lib/ui/settings/tabs/mode_tab.dart';

  /// 出现这些就说明这个 catch 在回滚配置
  const rollbackWrites = {
    'setActiveModel',
    'setActiveModelId',
    'setWorkMode',
    'setSelectedAsrAccount',
  };

  test('回滚配置的 catch 必须调 _restoreEngineAfterRollback', () {
    final unit = parseFile(
      path: File(path).absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;

    final v = _RollbackCatchVisitor(rollbackWrites);
    unit.accept(v);

    expect(v.total, greaterThanOrEqualTo(3),
        reason: '预期至少 3 处回滚分支（模型激活 / 工作模式 / 云账户下拉），'
            '只找到 ${v.total} 处 —— 结构变了，先确认扫描还有效');
    expect(v.missing, isEmpty,
        reason: '这些 catch 回滚了配置却没恢复引擎：\n${v.missing.join('\n\n')}');
  });
}

class _RollbackCatchVisitor extends RecursiveAstVisitor<void> {
  _RollbackCatchVisitor(this.rollbackWrites);

  final Set<String> rollbackWrites;
  int total = 0;
  final List<String> missing = [];

  @override
  void visitCatchClause(CatchClause node) {
    final calls = _CallNameCollector();
    node.body.accept(calls);
    if (calls.names.intersection(rollbackWrites).isNotEmpty) {
      total++;
      if (!calls.names.contains('_restoreEngineAfterRollback')) {
        final src = node.body.toSource();
        missing.add(src.length > 300 ? '${src.substring(0, 300)}…' : src);
      }
    }
    super.visitCatchClause(node);
  }
}

/// 走 AST 收方法名 —— 字符串/注释里出现的同名文本不算数。
class _CallNameCollector extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}
