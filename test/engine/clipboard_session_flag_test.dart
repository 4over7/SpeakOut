import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文本注入借道剪贴板：期间用户自己复制的内容会被下一个 chunk 覆盖，
/// 收尾还原时再抹一次（原生侧 changeCount 守卫只挡得住"最后一个 chunk 之后"的
/// 复制，挡不住 chunk 之间的）。所以 UI 需要知道"注入进行中"来拒绝复制。
///
/// 标志只能在 _clipBegin/_clipEnd 这一对包装里维护 —— 让 8 个调用点各自维护
/// 必然漂移。这里钉住这个约束。
/// （写这对包装时我一度把方法体替换成了自我递归，analyze 才拦下，故加此测试。）
void main() {
  final path = 'lib/engine/core_engine.dart';
  final src = File(path).readAsStringSync();
  final unit = parseFile(
    path: File(path).absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  test('原生剪贴板注入 API 只能由 _clipBegin/_clipEnd 调用', () {
    final v = _CallSiteVisitor();
    unit.accept(v);
    expect(v.calls, isNotEmpty, reason: '一处原生剪贴板调用都没找到，扫描失效了');
    for (final entry in v.calls.entries) {
      final api = entry.key;
      if (api == 'injectClipboardChunk') continue; // chunk 不改变会话状态
      for (final caller in entry.value) {
        final expected =
            api == 'injectClipboardBegin' ? '_clipBegin' : '_clipEnd';
        expect(caller, expected,
            reason: '$api 被 $caller 直接调用 —— 会话标志 _clipboardInjecting '
                '会漏置。必须走 $expected');
      }
    }
  });

  test('包装方法必须真的设置/清除标志，且不得自我递归', () {
    for (final (fn, flag, api) in [
      ('_clipBegin', '_clipboardSessions++', 'injectClipboardBegin'),
      ('_clipEnd', '_clipboardSessions--', 'injectClipboardEnd'),
    ]) {
      final v = _MethodBodyVisitor(fn);
      unit.accept(v);
      expect(v.body, isNotNull, reason: '没找到 $fn');
      final body = v.body!.toSource();
      expect(body.contains(flag), isTrue, reason: '$fn 没有维护标志');
      expect(body.contains(api), isTrue, reason: '$fn 没有调用原生 $api');
      expect(body.contains('$fn()'), isFalse, reason: '$fn 自我递归了');
    }
  });

  test('会话状态必须用计数而非布尔 —— AI 梳理与打字机注入可重叠', () {
    expect(src.contains('int _clipboardSessions'), isTrue,
        reason: '布尔标志下任一注入先结束就清零，另一个还在写 chunk，等于没防');
    // 重复 _clipEnd 必须是 no-op，不能再走一次 native。
    // native 的 inject_clipboard_end 里 clearContents 是无条件执行的，
    // 只有 saved != nil 才写回；第二次调用时 saved 已被取走置 nil，
    // 两个 dispatch_after 几乎同时到期，第二个先跑就会清空用户剪贴板，
    // 随后第一个因 changeCount 已变而跳过还原 —— 原内容永久丢失。
    final e = _MethodBodyVisitor('_clipEnd');
    unit.accept(e);
    final body = e.body!.toSource();
    expect(body.contains('_clipboardSessions == 0) return'), isTrue,
        reason: '_clipEnd 在计数已为 0 时必须直接返回，否则重复调用会清空用户剪贴板');
    expect(body.indexOf('return') < body.indexOf('_clipboardSessions--'), isTrue,
        reason: '早退必须在自减之前');
  });

  test('native 会话只在最外层开合 —— 它只有一份全局快照', () {
    // 断言的是**不变量**：native 调用必须被「计数为 0」的判断罩住。
    // 不写死成一整行字面量 —— 那样把 if 拆成多行（比如加了失败处理）
    // 就会让断言失效，而不变量根本没变。
    void assertGuarded(String method, String nativeCall) {
      // **用 AST 判断包含关系。** 字符串解析会被诱饵骗：
      //   if (_clipboardSessions == 0) { _log('injectClipboardBegin'); }
      //   _nativeInput?.injectClipboardBegin();
      // 这里 indexOf 会命中字符串里的假调用，把真正裸奔的 native 调用
      // 判成受保护（实测漏报过一次）。
      final decl = _MethodDeclVisitor(method);
      unit.accept(decl);
      expect(decl.node, isNotNull, reason: '没找到 $method');

      final calls = _FindInvocationVisitor(nativeCall);
      decl.node!.accept(calls);
      expect(calls.nodes, isNotEmpty,
          reason: '$method 没调 $nativeCall（AST 层面，字符串不算）');

      final guards = _FindIfVisitor();
      decl.node!.accept(guards);
      expect(guards.nodes, isNotEmpty,
          reason: '$method 没有「计数为 0」的判断');

      for (final call in calls.nodes) {
        final guarded = guards.nodes.any((g) {
          final t = g.thenStatement;
          return call.offset >= t.offset && call.end <= t.end;
        });
        expect(guarded, isTrue,
            reason: '$method 的 $nativeCall 不在任何「计数为 0」判断的 then 分支内 —— '
                'native 只有一份全局快照，内层也调的话，'
                '第二次 begin 会覆盖第一次的快照，第一次 end 会提前恢复');
      }
    }

    assertGuarded('_clipBegin', 'injectClipboardBegin');
    assertGuarded('_clipEnd', 'injectClipboardEnd');
  });

  test('UI 能通过 AppService facade 读到注入状态', () {
    expect(src.contains('bool get isClipboardInjecting'), isTrue);
    final facade = File('lib/services/app_service.dart').readAsStringSync();
    expect(facade.contains('isClipboardInjecting'), isTrue,
        reason: 'UI 不能直接摸 engine，必须有 facade 转发');
  });
}

class _CallSiteVisitor extends RecursiveAstVisitor<void> {
  final Map<String, List<String>> calls = {};
  String _current = '<top>';

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final prev = _current;
    _current = node.name.lexeme;
    super.visitMethodDeclaration(node);
    _current = prev;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final n = node.methodName.name;
    if (n.startsWith('injectClipboard')) {
      calls.putIfAbsent(n, () => []).add(_current);
    }
    super.visitMethodInvocation(node);
  }
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  FunctionBody? body;
  _MethodBodyVisitor(this.name);

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {}

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body = node.body;
    super.visitMethodDeclaration(node);
  }
}

class _MethodDeclVisitor extends RecursiveAstVisitor<void> {
  _MethodDeclVisitor(this.name);
  final String name;
  MethodDeclaration? node;

  @override
  void visitMethodDeclaration(MethodDeclaration n) {
    if (n.name.lexeme == name) node = n;
    super.visitMethodDeclaration(n);
  }
}

/// 按**结构**匹配 `_clipboardSessions == 0`，不认字符串 ——
/// `if (true || _clipboardSessions == 0)` 的 toSource 也含目标片段，
/// 但那个判断恒真，等于没有保护；
/// `if (reason == '_clipboardSessions == 0')` 更是纯诱饵。
class _FindIfVisitor extends RecursiveAstVisitor<void> {
  final List<IfStatement> nodes = [];

  bool _isTarget(Expression e) {
    if (e is BinaryExpression) {
      if (e.operator.lexeme == '==' &&
          e.leftOperand.toSource() == '_clipboardSessions' &&
          e.rightOperand is IntegerLiteral &&
          (e.rightOperand as IntegerLiteral).value == 0) {
        return true;
      }
      // 只允许 && 串联（仍是必要条件）；|| 会让它变成非必要项
      if (e.operator.lexeme == '&&') {
        return _isTarget(e.leftOperand) || _isTarget(e.rightOperand);
      }
    }
    return false;
  }

  @override
  void visitIfStatement(IfStatement n) {
    if (_isTarget(n.expression)) nodes.add(n);
    super.visitIfStatement(n);
  }
}

class _FindInvocationVisitor extends RecursiveAstVisitor<void> {
  _FindInvocationVisitor(this.name);
  final String name;
  final List<MethodInvocation> nodes = [];

  @override
  void visitMethodInvocation(MethodInvocation n) {
    // receiver 必须是 _nativeInput —— 只看方法名的话，别的对象上的同名方法
    // 会被误判成 native 调用。
    final recv = n.target?.toSource() ?? '';
    if (n.methodName.name == name && recv.contains('_nativeInput')) {
      nodes.add(n);
    }
    super.visitMethodInvocation(n);
  }
}
