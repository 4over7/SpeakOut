import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CoreEngine.initASR` 的两条纪律。
///
/// **这是形状断言，不是行为断言。** CoreEngine 要 FFI + 真模型才跑得起来，
/// 这里只能守住「代码还长这样」。语义正确性靠 review 与手工冒烟。
/// 混用两者的教训见 `docs/anti-patterns/dont-let-source-text-assertions-prove-behavior.md`。
///
/// ## 纪律一：串行化
///
/// `_initASRUnsafe` 在 await `provider.initialize()` **之前**就把 `_asrProvider`
/// 置 null 了。两次调用重叠时，第二次看不到旧 provider → 跳过 dispose →
/// 两个 provider 并发初始化 → 后完成的覆盖字段，先完成的**永远不被 dispose**
/// （云端漏 WebSocket / 离线漏 native recognizer），而它的 textStream 还在
/// 往 `_partialTextController` 推，两路结果交替出现在同一个浮窗上。
///
/// 所以 `_initASRUnsafe` 只允许从 `initASR` 的链里调用。
///
/// ## 纪律二：初始化失败必须上抛
///
/// 曾经两个 catch 都只发一条 `EngineStatus.error` 就正常返回 ——
/// 调用方看到的是「成功」，设置页那段 `Init failed -> rollback` 于是成了死代码，
/// 配置停在一个加载不起来的模型上，用户按快捷键毫无反应。
void main() {
  const path = 'lib/engine/core_engine.dart';

  CompilationUnit parseUnit() => parseFile(
        path: File(path).absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;

  MethodDeclaration methodNamed(String name) {
    final cls = parseUnit()
        .declarations
        .whereType<ClassDeclaration>()
        .firstWhere((c) => c.name.lexeme == 'CoreEngine',
            orElse: () => throw StateError('没找到 CoreEngine，扫描失效'));
    return cls.members.whereType<MethodDeclaration>().firstWhere(
        (m) => m.name.lexeme == name,
        orElse: () => throw StateError('没找到 $name，扫描失效'));
  }

  test('_initASRUnsafe 只能从 initASR 调用 —— 绕过它就绕过了串行化', () {
    // 标识符扫描而不是调用图分析：`parseFile` 是 syntax-only 的拿不到 element，
    // 靠语法形态判断接收者永远补不完（见 write_chain_discipline_test 的说明）。
    // 名字总要写出来，所以扫名字 fail-closed。
    final cls = parseUnit()
        .declarations
        .whereType<ClassDeclaration>()
        .firstWhere((c) => c.name.lexeme == 'CoreEngine');

    final hits = <String>[];
    for (final member in cls.members) {
      if (member is MethodDeclaration &&
          member.name.lexeme == '_initASRUnsafe') {
        continue; // 声明本身
      }
      final v = _IdentifierCollector('_initASRUnsafe');
      member.accept(v);
      if (v.count > 0) {
        hits.addAll(List.filled(
            v.count, member is MethodDeclaration ? member.name.lexeme : '$member'));
      }
    }
    expect(hits, ['initASR'],
        reason: '_initASRUnsafe 只允许出现在 initASR 里各一次；'
            '现在是 $hits —— 多出来的那处绕过了串行链');
  });

  test('initASR 必须先 await 上一次再排队，并把自己挂回链上', () {
    final body = methodNamed('initASR').toSource();
    expect(body, contains('_asrInitChain'),
        reason: '不接上一次的链就不是串行化');
    // 「读旧链 → await 它 → 把新任务写回链」三步缺一不可：
    // 只 await 不写回 = 第三次调用又和第二次并发。
    final readIdx = body.indexOf('final prev = _asrInitChain');
    final awaitIdx = body.indexOf('await prev');
    final writeIdx = body.lastIndexOf('_asrInitChain = task');
    expect(readIdx, greaterThanOrEqualTo(0), reason: '没读旧链');
    expect(awaitIdx, greaterThan(readIdx), reason: '没等上一次做完');
    expect(writeIdx, greaterThan(awaitIdx), reason: '新任务没挂回链上');
  });

  test('initASR 在进入 unsafe 前锁住录音入口，完成后 finally 解锁', () {
    final body = methodNamed('initASR').toSource();
    final guardIdx = body.indexOf('_recordingState != RecordingState.idle');
    final lockIdx = body.indexOf('_asrSwitchInProgress = true');
    final unsafeIdx = body.indexOf('await _initASRUnsafe');
    final unlockIdx = body.indexOf('_asrSwitchInProgress = false');

    expect(lockIdx, greaterThan(guardIdx));
    expect(unsafeIdx, greaterThan(lockIdx));
    expect(unlockIdx, greaterThan(unsafeIdx),
        reason: '切换期间必须持续拒绝新录音，失败也要解锁');
  });

  test('_initASRUnsafe 在释放当前 provider 前必须拒绝非 idle 状态', () {
    final body = methodNamed('_initASRUnsafe').toSource();
    final guardIdx = body.indexOf('_recordingState != RecordingState.idle');
    final rejectIdx = body.indexOf('throw StateError', guardIdx);
    final disposeIdx = body.indexOf('await _asrProvider!.dispose()');

    expect(guardIdx, greaterThanOrEqualTo(0), reason: '录音中不能替换 provider');
    expect(rejectIdx, greaterThan(guardIdx), reason: '非 idle 状态必须明确失败');
    expect(disposeIdx, greaterThan(rejectIdx),
        reason: '守卫必须在释放旧 provider 前执行');
  });

  test('把 _asrProvider 置 null 的 catch 必须 rethrow', () {
    // 判据挑「catch 里有 _asrProvider = null」而不是「第 N 个 try」：
    // 前者跟着语义走，后者跟着行号走，加一个 try 就失效。
    final v = _NullingCatchCollector();
    methodNamed('_initASRUnsafe').accept(v);
    expect(v.total, 2,
        reason: '预期正好两处初始化失败分支（云端 / 本地），实际 ${v.total} 处 —— '
            '结构变了，请确认新分支是否也需要 rethrow');
    expect(v.withoutRethrow, isEmpty,
        reason: '这些 catch 把 provider 置 null 却没上抛，调用方会当成初始化成功：'
            '${v.withoutRethrow}');
  });

  test('两条 provider 初始化失败路径都要 dispose 局部 provider', () {
    final body = methodNamed('_initASRUnsafe').toSource();
    expect(
      RegExp(r'await _disposeProviderAfterInitFailure\(provider\)')
          .allMatches(body)
          .length,
      2,
      reason: '只把字段置 null 会泄漏初始化到一半的 native/WebSocket 资源',
    );
  });
}

class _IdentifierCollector extends RecursiveAstVisitor<void> {
  _IdentifierCollector(this.target);
  final String target;
  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == target) count++;
    super.visitSimpleIdentifier(node);
  }
}

class _NullingCatchCollector extends RecursiveAstVisitor<void> {
  int total = 0;
  final List<String> withoutRethrow = [];

  @override
  void visitCatchClause(CatchClause node) {
    final src = node.body.toSource();
    if (src.contains('_asrProvider = null')) {
      total++;
      final r = _RethrowFinder();
      node.body.accept(r);
      if (!r.found) withoutRethrow.add(src.replaceAll(RegExp(r'\s+'), ' '));
    }
    super.visitCatchClause(node);
  }
}

class _RethrowFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitRethrowExpression(RethrowExpression node) {
    found = true;
    super.visitRethrowExpression(node);
  }
}
