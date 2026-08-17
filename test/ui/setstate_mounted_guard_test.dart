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

  /// 上一条的反面 —— 补守卫时最容易犯的错。
  ///
  /// `if (!mounted) return;` 后面**紧跟一个既有 await 又有 setState 的复合语句**，
  /// 意味着守卫连同里面的**落盘一起挡掉了**。页面在 await 期间关掉时，
  /// 用户刚做的选择被静默丢弃，而这比一个 setState 异常严重得多。
  ///
  /// 真实事件（同一次批量补守卫里犯了 5 次）：
  /// - 选完日志目录 → `setLogDirectory` 被跳过
  /// - 选完闪念目录 → Swift 侧已提交 security-scoped bookmark、Dart 侧没落盘，
  ///   两边对不上，DiaryService 的对账 fail-closed，闪念直接不能写
  /// - 录完快捷键 → 整个 `switch` 被跳过，那次录制白做
  /// - 选完 LLM 模型 → preset 已存、model 没存，配置自相矛盾
  ///
  /// **规矩：mounted 只挡 setState，不挡落盘，也不挡全局通知。**
  test('mounted 守卫不得挡在落盘前面', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final result = parseFile(
        path: f.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      result.unit
          .accept(_GuardBlocksWriteVisitor(f.path, result.lineInfo, offenders));
    }
    expect(offenders, isEmpty,
        reason: '守卫后面紧跟的语句里 await 先于 setState —— '
            '页面已销毁时那次 await 的副作用会被一起跳过：\n'
            '${offenders.join('\n')}');
  });
}

class _GuardBlocksWriteVisitor extends RecursiveAstVisitor<void> {
  _GuardBlocksWriteVisitor(this.path, this.lineInfo, this.offenders);

  final String path;
  final LineInfo lineInfo;
  final List<String> offenders;

  @override
  void visitBlock(Block node) {
    for (var i = 0; i < node.statements.length - 1; i++) {
      if (node.statements[i].toSource() != 'if (!mounted) return;') continue;
      final next = node.statements[i + 1];
      final src = next.toSource();
      // 裸 setState 是正常写法，不算
      if (src.startsWith('setState(')) continue;
      // 只看**本层**：闭包里的 setState 是回调，不在这条语句里同步执行
      // （引导页把 `() => setState(...)` 当参数传出去就属于这种）。
      final scan = _SameLevelScanner()..visit(next);
      if (scan.firstSetState == null || scan.firstAwait == null) continue;
      // 真正要抓的是「副作用先于 setState」：await 在前，说明守卫把它一起挡了
      if (scan.firstAwait! > scan.firstSetState!) continue;
      final loc = lineInfo.getLocation(next.offset);
      offenders.add('  $path:${loc.lineNumber}  '
          '${src.length > 80 ? '${src.substring(0, 80)}…' : src}');
    }
    super.visitBlock(node);
  }
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

  /// 同理，`await` 也走 AST：`AppLog.d('await ')` 不该被当成真的有 await。
  /// 嵌套闭包里的 await 也会算进来 —— 那是 fail-closed 方向，
  /// 顶多多要一句 `if (!mounted)`，不会漏掉真问题。
  static bool _has<T extends AstNode>(AstNode node) {
    final v = _NodeFinder<T>();
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
      if (_has<AwaitExpression>(st)) {
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

class _NodeFinder<T extends AstNode> extends GeneralizingAstVisitor<void> {
  bool found = false;

  @override
  void visitNode(AstNode node) {
    if (node is T) found = true;
    super.visitNode(node);
  }
}

/// 只扫**同一个异步层**：遇到函数字面量就不往里走。
/// 闭包里的 await / setState 属于另一次执行，跟当前这条语句的顺序无关。
class _SameLevelScanner extends RecursiveAstVisitor<void> {
  int? firstAwait;
  int? firstSetState;

  void visit(AstNode node) => node.accept(this);

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // 故意不 super：不进闭包
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    firstAwait ??= node.offset;
    super.visitAwaitExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState') firstSetState ??= node.offset;
    super.visitMethodInvocation(node);
  }
}
