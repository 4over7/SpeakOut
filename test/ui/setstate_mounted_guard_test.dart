import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// `await` 之后的 `setState` 必须先判 `mounted`。
///
/// 页面在 await 期间可能已经被销毁 —— 设置页跟着 sidebar 换页就没了，
/// 引导页的模型下载更是要跑好几分钟。这时 `setState` 抛
/// `setState() called after dispose()`，异常进全局 zone，
/// 用户看到的是「点了没反应」而日志里只有一行看不懂的堆栈。
///
/// 一次清了 76 处。**加新代码时这条会挡住你** —— 挡住是对的，
/// 在 setState 前补一句 `if (!mounted) return;` 就行。
///
/// ## 判据边界（说清楚，别当它是全能的）
///
/// 只看**同一个 Block 内的相邻语句序列**：前面出现过 `await`、
/// 中间没有任何语句提到 `mounted`、然后是 `setState(`。
/// 外层 block 的 await + 内层 block 的 setState 看不见（fail-open），
/// 闭包里的 await 也看不见。它防的是**批量回潮**，不是每一种写法。
///
/// 这是形状断言而不是行为断言，理由见
/// `docs/anti-patterns/dont-let-source-text-assertions-prove-behavior.md`。
void main() {
  test('await 之后的 setState 一律要有 mounted 守卫', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final result = parseFile(
        path: f.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      result.unit.accept(
          _UnguardedSetStateVisitor(f.path, result.lineInfo, offenders));
    }
    expect(offenders, isEmpty,
        reason: '这些 setState 跑在 await 之后却没判 mounted，'
            '页面已销毁时会抛 setState() called after dispose():\n'
            '${offenders.join('\n')}');
  });
}

class _UnguardedSetStateVisitor extends RecursiveAstVisitor<void> {
  _UnguardedSetStateVisitor(this.path, this.lineInfo, this.offenders);

  final String path;
  final LineInfo lineInfo;
  final List<String> offenders;

  /// `_setState`（UpdateService 的私有方法）不能算进来 —— 它不是 State.setState。
  static final _setStateCall = RegExp(r'(?<![\w$])setState\(');

  /// 走 AST 而不是 `src.contains('mounted')` —— 后者会被
  /// `AppLog.d('mounted')` 这种字符串诱饵骗过去，白放一处。
  static bool _mentionsMounted(AstNode node) {
    final v = _MountedFinder();
    node.accept(v);
    return v.found;
  }

  @override
  void visitBlock(Block node) {
    var sawAwait = false;
    var guarded = false;
    for (final st in node.statements) {
      final src = st.toSource();
      final mentionsMounted = _mentionsMounted(st);
      // 语句自身带 mounted 判断的算已守卫（`if (mounted) setState(...)`）
      if (sawAwait && !guarded && _setStateCall.hasMatch(src) && !mentionsMounted) {
        final loc = lineInfo.getLocation(st.offset);
        offenders.add('  $path:${loc.lineNumber}');
        sawAwait = false; // 同一段只报一次，避免刷屏
      }
      if (mentionsMounted) guarded = true;
      if (src.contains('await ')) {
        sawAwait = true;
        guarded = false;
      }
    }
    super.visitBlock(node);
  }
}

class _MountedFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'mounted') found = true;
    super.visitSimpleIdentifier(node);
  }
}
