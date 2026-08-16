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
      final v = _MethodBodyVisitor(method);
      unit.accept(v);
      expect(v.body, isNotNull, reason: '没找到 $method');
      final body = v.body!.toSource();
      final guardAt = body.indexOf('_clipboardSessions == 0');
      final callAt = body.indexOf(nativeCall);
      expect(guardAt, greaterThanOrEqualTo(0), reason: '$method 没有最外层判断');
      expect(callAt, greaterThanOrEqualTo(0), reason: '$method 没调 $nativeCall');
      expect(guardAt, lessThan(callAt),
          reason: '$method 的 native 调用必须被「计数为 0」罩住 —— '
              'native 只有一份全局快照，内层也调的话，'
              '第二次 begin 会覆盖第一次的快照，第一次 end 会提前恢复');
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
