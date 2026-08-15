import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知横幅必须真的被挂载。
///
/// 真实事故：我把 Home 里的订阅与横幅删掉、准备改挂到 MacosApp.builder，
/// 但那次脚本在后一个断言处中止、**整个文件没写盘**，我又只补做了删除的部分。
/// 结果订阅没了、横幅没了、Overlay 从未挂上 —— 通知系统整个死掉，
/// 比改之前更糟，而 671 个测试全绿，一条都没拦住。
///
/// 所以这里同时钉两头：类要存在，且必须在 MacosApp 上被真正使用。
void main() {
  final mainSrc = File('lib/main.dart').readAsStringSync();

  test('NotificationService 必须有消费者', () {
    final subscribers = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.readAsStringSync().contains('NotificationService().stream.listen')) {
        subscribers.add(e.path);
      }
    }
    expect(subscribers, isNotEmpty,
        reason: '没有任何地方订阅 NotificationService.stream —— '
            '所有 notify() 都会石沉大海');
  });

  test('macOS 入口必须把 NotificationOverlay 挂在 MacosApp.builder 上', () {
    final unit = parseFile(
      path: File('lib/main.dart').absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final v = _MacosAppVisitor();
    unit.accept(v);
    expect(v.found, isTrue, reason: '没找到 MacosApp(...) 构造');
    expect(v.hasBuilder, isTrue,
        reason: 'MacosApp 没有 builder —— 横幅无法盖在聊天页/设置页等上层 route 之上');
    expect(v.builderSource.contains('NotificationOverlay'), isTrue,
        reason: 'builder 里没有 NotificationOverlay，通知不会被展示：'
            '${v.builderSource}');
  });

  test('Home 里不得再自建横幅（否则会有两份，且被上层 route 遮住那份是死的）', () {
    expect(mainSrc.contains('_currentNotification'), isFalse,
        reason: 'Home 仍保留着旧横幅状态');
  });
}

class _MacosAppVisitor extends RecursiveAstVisitor<void> {
  bool found = false;
  bool hasBuilder = false;
  String builderSource = '';

  void _scan(ArgumentList args) {
    found = true;
    for (final a in args.arguments) {
      if (a is NamedExpression && a.name.label.name == 'builder') {
        hasBuilder = true;
        builderSource = a.expression.toSource();
      }
    }
  }

  // parseFile 是**纯语法解析、不做类型解析**，所以不带 new/const 的
  // `MacosApp(...)` 会被解析成 MethodInvocation 而非 InstanceCreationExpression。
  // 两种都要认 —— 只认后者的话断言恒为「没找到」，等于没测。
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'MacosApp') {
      _scan(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.toSource() == 'MacosApp') {
      _scan(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }
}
