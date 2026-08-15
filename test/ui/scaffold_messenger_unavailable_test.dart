import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

/// macOS 的根是 MacosApp（macos_ui 内部构造 CupertinoApp），**没有**
/// ScaffoldMessenger 祖先 —— `ScaffoldMessenger.of(context)` 会抛
/// "No ScaffoldMessenger widget found."
///
/// 这不是理论推断：下面第一个用例真的 pump 一遍并捕获异常。
///
/// 曾经全 macOS UI 有 10 处 SnackBar 提示，全部无效；其中 developer_page
/// 把 `final messenger = ScaffoldMessenger.of(context);` 放在 onPressed 第一句，
/// 直接抛 → 对话框弹不出来 → **配置导出/导入功能整个坏死**，不只是少个提示。
/// 本 App 真正接了消费者的提示通道是 NotificationService（main.dart 订阅）。
void main() {
  testWidgets('MacosApp 下 ScaffoldMessenger 不可用（前提验证）', (t) async {
    Object? err;
    await t.pumpWidget(MacosApp(
      home: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () {
            try {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(const SnackBar(content: Text('x')));
            } catch (e) {
              err = e;
            }
          },
          child: const Text('tap'),
        ),
      ),
    ));
    await t.tap(find.text('tap'));
    await t.pump();
    expect(err, isNotNull,
        reason: '如果哪天 macos_ui 提供了 ScaffoldMessenger，本断言会失败 —— '
            '那时可以放宽下面那条规则');
  });

  test('macOS UI 代码里不得使用 ScaffoldMessenger', () {
    final offenders = <String>[];
    for (final e in Directory('lib/ui').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('/linux/')) continue; // Linux 壳有真正的 Material Scaffold
      var ln = 0;
      for (final line in e.readAsLinesSync()) {
        ln++;
        final t = line.trim();
        if (t.startsWith('//') || t.startsWith('///')) continue; // 解释性注释不算
        final code = t.contains('//') ? t.substring(0, t.indexOf('//')) : t;
        if (code.contains('ScaffoldMessenger')) offenders.add('${e.path}:$ln');
      }
    }
    expect(offenders, isEmpty,
        reason: 'macOS 没有 ScaffoldMessenger 祖先，这些调用会抛异常。'
            '用 NotificationService().notify(...) 代替：\n  ${offenders.join("\n  ")}');
  });
}
