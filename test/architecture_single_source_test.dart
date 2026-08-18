import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 架构约束测试：某些「唯一真源」必须真的唯一。
///
/// 起因是一次真实事故 —— UI 直读 selectedAsrAccountId 自己做回退（取池中第一个），
/// Engine 走推荐顺序，于是界面显示火山、实际连阿里云；而且那个「已选中」从不落盘。
/// 后来收敛到 CloudAccountService.effectiveAsrAccount()，
/// 但 codex 审查指出：**光有收敛挡不住下一个人再写一遍直读** ——
/// 事实上当时语言过滤那两处就漏掉了，测试全绿也发现不了。
///
/// 所以这里用源码级断言把入口钉死：只有真源本身可以碰原始 key。
///
/// ⚠️ 局限（codex 审查指出，明写在此以免被当成完备保证）：
/// 这是**字符串/正则扫描，不是依赖分析**。它能挡住「照抄一份直读逻辑」这种最常见的退化，
/// 但挡不住刻意绕过 —— 例如在豁免文件里加个转发 getter 供 UI 间接读取，
/// 或先把 CloudCapability.asrStreaming 存进变量再传入。
/// 而且豁免粒度是整个文件，不是具体的 getter/helper。
/// 真要完备需要 AST 级依赖检查；当前取「低成本挡住高频退化」这个折中。
void main() {
  /// 允许直接读取该 key 的文件（真源与其存取层）
  const asrAllowed = {
    'lib/services/config_service.dart',      // getter/setter 定义处
    'lib/services/cloud_account_service.dart', // effectiveAsrAccount 内部
  };

  /// 只看真实代码行 —— 注释里提到这个名字（比如解释「不要直读」的注释本身）不算违规
  bool hasRealUsage(String src, Pattern needle) {
    for (var line in src.split('\n')) {
      final t = line.trim();
      if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;
      // 去掉行尾注释再判断
      final code = t.contains('//') ? t.substring(0, t.indexOf('//')) : t;
      if (code.contains(needle)) return true;
    }
    return false;
  }

  List<String> filesWithRealUsage(Pattern needle, Set<String> allowed) {
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('l10n/generated')) continue;
      if (allowed.any((a) => e.path.endsWith(a))) continue;
      if (hasRealUsage(e.readAsStringSync(), needle)) hits.add(e.path);
    }
    return hits;
  }

  test('除真源外，任何地方不得直读 selectedAsrAccountId', () {
    final hits = filesWithRealUsage('selectedAsrAccountId', asrAllowed);
    expect(
      hits,
      isEmpty,
      reason: '这些文件绕过了 CloudAccountService.effectiveAsrAccount()，'
          '会再次出现「界面显示 A、实际用 B」：\n  ${hits.join("\n  ")}',
    );
  });

  // ── 三层架构：UI 不得穿透 Service 直接操作 Engine ──
  //
  // 这条断言改到第 4 版。前三版都栽在「判据比它声称防的东西更窄」上：
  //   v1 只查 import —— facade 重构（73bf717）去掉 import 却留着
  //      AppService.engine 这个 public 字段，12 处穿透测试全绿。
  //   v2 查访问路径但把接收者硬编码成 AppService()/_app/_appService/appService
  //      且逐行匹配 —— 换变量名、点号换行、级联、中间变量别名，四种普通写法全漏。
  //   v3 改成整文件空白归一化后正则扫 `.engine` —— codex 指出并实测：
  //      注释剥离不是字符串感知的，`log('https://x'); AppService().engine...`
  //      会在字符串里的 `//` 处被截断，真实违规被抹掉 → **漏报**；
  //      反过来 `const k = 'settings.engine.mode';` 又会 **误报**。
  //      我当时把它记成「已知局限」，但漏报违背了这条断言存在的意义。
  //
  // v4 直接走 AST：analyzer 精确区分标识符、字符串字面量、注释与插值表达式，
  // 上面所有形态一次根除，不再有「判据窄于目标」的空间。
  test('UI 不得穿透 AppService 直接操作 engine', () {
    final hits = <String>[];
    for (final e in Directory('lib/ui').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final parsed = parseFile(
          path: e.absolute.path, featureSet: FeatureSet.latestLanguageVersion());
      final visitor = _EngineAccessVisitor();
      parsed.unit.accept(visitor);
      for (final expr in visitor.hits) {
        hits.add('${e.path}: $expr');
      }
    }
    expect(hits, isEmpty,
        reason: 'UI 应走 AppService 的 facade getter，不要直接摸 engine 对象'
            '（缺什么就往 AppService 补一个转发 getter）：\n  ${hits.join("\n  ")}');
  });

  // 拆卸顺序：必须 native 先停回调，Dart 才能释放 NativeCallable 蹦床。
  // 反序会让 native 侧的 dartCallback 指向已释放内存。
  // stopListener() 曾经全仓零调用点 —— 拆卸路径压根没写完。
  test('CoreEngine.dispose 必须先 stopListener 再 close NativeCallable', () {
    final src = File('lib/engine/core_engine.dart').readAsStringSync();
    final body = RegExp(r'Future<void> dispose\(\) async\s*\{([\s\S]*?)\n  \}')
        .firstMatch(src)
        ?.group(1);
    expect(body, isNotNull, reason: '没找到 CoreEngine.dispose() 方法体');
    final stopAt = body!.indexOf('stopListener()');
    final closeAt = body.indexOf('_nativeCallable?.close()');
    expect(stopAt, greaterThanOrEqualTo(0),
        reason: 'dispose() 未调用 stopListener()，原生 eventTap 不会摘除');
    expect(closeAt, greaterThanOrEqualTo(0), reason: 'dispose() 未关闭 _nativeCallable');
    expect(stopAt, lessThan(closeAt),
        reason: 'stopListener() 必须早于 _nativeCallable.close()，'
            '否则 native 仍持有已释放的回调指针');
  });

  test('UI 不得自己拼 ASR 账户池（应调 asrAccountPool）', () {
    // 判据要精确到「取账户」这个动作；按能力筛 CredentialField 是另一回事，不算
    // 用正则而非精确字符串：换行、空格都不该成为绕过手段
    final hits = filesWithRealUsage(
        RegExp(r'getAccountsWithCapability\s*\(\s*CloudCapability\.asrStreaming'),
        const {});
    expect(hits.where((p) => p.contains('/ui/')), isEmpty,
        reason: 'UI 自行拼装账户池会与 Engine 的口径漂移：\n  ${hits.join("\n  ")}');
  });
}

/// 收集所有名为 `engine` 的属性访问 —— 无论接收者叫什么、怎么换行、是否级联。
/// AST 天然排除字符串字面量与注释，也天然包含字符串插值里的真实表达式。
class _EngineAccessVisitor extends RecursiveAstVisitor<void> {
  final List<String> hits = [];

  void _check(String name, AstNode node) {
    if (name == 'engine') hits.add(node.toSource());
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _check(node.propertyName.name, node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _check(node.identifier.name, node);
    super.visitPrefixedIdentifier(node);
  }

  /// `foo.engine()` —— 被调用的成员叫 engine。
  /// 必须看 methodName 而不是 target：看 target 的话
  ///   `foo.engine()` 会漏（target 是 foo），
  ///   `engine.search()` 会误报（target 恰好叫 engine，可能是无关的搜索引擎变量）。
  /// `foo.engine.bar()` 不归这里管 —— 它的 target 是 PrefixedIdentifier /
  /// PropertyAccess，递归下去由上面两个 visit 命中，不会重复计数。
  @override
  void visitMethodInvocation(MethodInvocation node) {
    // 不判 target 是否为 null：裸 `engine()`（局部/顶层函数返回 CoreEngine）
    // 同样是穿透。lib/ui 目前没有这种写法，宁可误报也不留缺口。
    _check(node.methodName.name, node);
    super.visitMethodInvocation(node);
  }
}
