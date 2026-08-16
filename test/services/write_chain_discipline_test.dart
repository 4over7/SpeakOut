import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// CloudAccountService 的写操作全部经 _serializedWrite 排队。
///
/// 约束：**已在链内的代码不得再调用公开写方法** ——
/// 那会把自己排到自己后面，永远等不到，表现是**卡死而不是报错**。
///
/// 这条规则替代了我一度加过的「布尔重入标志」。那个做法是错的：
/// 标志在链内 op 的整个执行期（含每个 await 间隙）都为 true，
/// 外部调用会被误判成重入而直接执行，与链内操作并发 ——
/// 等于把刚加的串行化又打穿了。对照实验的执行顺序是
/// A:start → B:BYPASS → B:start → A:end → B:end。
///
/// ## 为什么不做调用图分析
///
/// 上一版沿调用图走，靠**接收者的语法形态**判断「这是不是对自己的调用」。
/// 那条路走不通：`parseFile` 是 syntax-only 的，拿不到 element，于是
///
///     final s = CloudAccountService(); s.updateAccount(a);   // 局部变量
///     staticHolder.service.updateAccount(a);                  // 静态字段
///     (this as CloudAccountService).updateAccount(a);         // cast
///     final f = updateAccount; await f(a);                    // tear-off
///
/// 每一种都要单独补一个分支，而且永远不知道补没补完 —— 补漏的代价是放行死锁。
///
/// 现在换成**标识符扫描**：类里除了那几个薄包装的声明本身，任何位置都不许再
/// 出现公开写方法的名字。接收者是什么、以什么语法形态调用，全都不重要 ——
/// 名字总要写出来。这条规则 fail-closed，且不随语言特性增加而失效。
///
/// **覆盖边界（说清楚，别当它是全能的）**：只扫这一个文件里的这一个类。
/// 链内代码如果绕道**别处的顶层函数**再回头调公开写方法，本测试看不见。
/// 下面用 part / mixin / extension 三条断言把类自身的成员面锁死，
/// 剩下的跨文件间接路径只能靠 review。
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
  const path = 'lib/services/cloud_account_service.dart';
  const serviceName = 'CloudAccountService';

  CompilationUnit parseUnit() => parseFile(
        path: File(path).absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      ).unit;

  test('类的成员面必须完整落在这一个文件里', () {
    // 标识符扫描只看这个文件。类的成员一旦能长在 part / mixin / extension 里，
    // 扫描就出现盲区，而盲区里的一次公开写调用就是永久死锁。
    final unit = parseUnit();
    expect(unit.directives.whereType<PartDirective>(), isEmpty,
        reason: 'part 文件里的成员逃出标识符扫描');
    expect(unit.directives.whereType<PartOfDirective>(), isEmpty);

    final cls = unit.declarations.whereType<ClassDeclaration>().firstWhere(
        (c) => c.name.lexeme == serviceName,
        orElse: () => throw StateError('没找到 $serviceName，扫描失效'));
    expect(cls.withClause, isNull, reason: 'mixin 里的成员逃出标识符扫描');
    expect(cls.extendsClause, isNull, reason: '父类里的成员逃出标识符扫描');

    final extensions = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            RegExp(r'extension\s+\w*\s*on\s+' + serviceName)
                .hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(extensions, isEmpty, reason: 'extension 里的成员逃出标识符扫描');
  });

  test('公开写方法必须是 _serializedWrite 的薄包装', () {
    final unit = parseUnit();
    final decls = <String, MethodDeclaration>{};
    for (final cls in unit.declarations.whereType<ClassDeclaration>()) {
      if (cls.name.lexeme != serviceName) continue;
      for (final m in cls.members.whereType<MethodDeclaration>()) {
        decls[m.name.lexeme] = m;
      }
    }
    // 反向哨兵：名字写错 / 方法被改名时，下面的扫描会变成空转，
    // 这里先确认每个受管名字真的存在。
    final missing = publicWrites.where((n) => !decls.containsKey(n)).toList();
    expect(missing, isEmpty, reason: '这些公开写方法找不到声明，受管清单已过期：$missing');

    final notWrapped = publicWrites
        .where((n) => !decls[n]!.body.toSource().contains('_serializedWrite'))
        .toList();
    expect(notWrapped, isEmpty,
        reason: '这些公开写方法没有入链，会与链内操作并发：$notWrapped');
  });

  test('除薄包装的声明本身外，类内不得出现公开写方法名', () {
    final unit = parseUnit();
    final v = _IdentifierScan(publicWrites);
    unit.accept(v);
    expect(v.hits, isEmpty,
        reason: '这些位置会重新入链、把自己排到自己后面（卡死而非报错），'
            '应改调对应的 *Unsafe：\n  ${v.hits.join("\n  ")}');
  });

  test('每个 _serializedWrite 调用都必须解析出以 Unsafe 结尾的入链目标', () {
    // fail-closed：认不出目标就判失败。旧版只在 `() => X()` 这一种形态下
    // 收集得到目标，`_serializedWrite(_reloadUnsafe)` 这种 tear-off 直接
    // 静默漏过 —— 而且因为别处还有目标，"targets 非空" 也报不出来。
    final unit = parseUnit();
    final v = _ChainTargetVisitor();
    unit.accept(v);
    expect(v.calls, isNotEmpty, reason: '一个 _serializedWrite 调用都没找到，扫描失效');

    final bad = <String>[];
    for (final c in v.calls) {
      if (c.targets.isEmpty) {
        bad.add('认不出入链目标: ${c.source}');
        continue;
      }
      for (final t in c.targets) {
        if (!t.endsWith('Unsafe')) bad.add('入链目标没有 Unsafe 后缀: $t');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n  '));
  });

  test('不得用布尔标志做重入判断', () {
    final src = File(path).readAsStringSync();
    expect(src.contains('_inSerializedWrite'), isFalse,
        reason: '布尔重入标志会在 await 间隙让外部调用绕过串行 —— '
            '见本文件顶部注释里的对照实验');
  });
}

/// 扫描类内对受管名字的**任何**标识符引用。
///
/// 方法声明名在 analyzer 里是 `Token` 而不是 `SimpleIdentifier`，
/// 不会被 visitSimpleIdentifier 访问到 —— 所以薄包装自己的声明天然不算命中，
/// 不需要为它开例外。注释和字符串字面量同理，都不是标识符。
class _IdentifierScan extends RecursiveAstVisitor<void> {
  _IdentifierScan(this._managed);
  final Set<String> _managed;
  final List<String> hits = [];
  String? _enclosing;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final prev = _enclosing;
    _enclosing = node.name.lexeme;
    super.visitMethodDeclaration(node);
    _enclosing = prev;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_managed.contains(node.name)) {
      hits.add('${_enclosing ?? "<类体>"} 里引用了 ${node.name}');
    }
    super.visitSimpleIdentifier(node);
  }
}

class _ChainCall {
  _ChainCall(this.source, this.targets);
  final String source;
  final List<String> targets;
}

/// 收集每个 `_serializedWrite(...)` 调用及其入链目标
class _ChainTargetVisitor extends RecursiveAstVisitor<void> {
  final List<_ChainCall> calls = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == '_serializedWrite') {
      final args = node.argumentList.arguments;
      calls.add(_ChainCall(
        node.toSource(),
        args.isEmpty ? const [] : _resolveTargets(args.first),
      ));
    }
    super.visitMethodInvocation(node);
  }

  static List<String> _resolveTargets(Expression arg) {
    if (arg is SimpleIdentifier) return [arg.name]; // tear-off
    if (arg is FunctionExpression) {
      final body = arg.body;
      if (body is ExpressionFunctionBody) {
        final e = body.expression;
        if (e is MethodInvocation) return [e.methodName.name];
        if (e is SimpleIdentifier) return [e.name];
        if (e is AwaitExpression) {
          final inner = e.expression;
          if (inner is MethodInvocation) return [inner.methodName.name];
        }
        return const [];
      }
      final v = _InnerCallVisitor();
      body.accept(v);
      return v.names;
    }
    return const [];
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
