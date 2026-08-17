import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/app_constants.dart';

/// ASR provider 收尾等待的两条纪律。
///
/// 引擎在 `core_engine.dart` 里按 `stopTimeout` 给 `stop()` 记时，
/// **超时回调返回的是空文本** —— provider 攒下的部分文本会一起被丢掉。
/// 所以 provider 内部的等待必须留出余量，不能跟外层预算齐平。
///
/// 踩过的三种形态：
/// - 写死 `const Duration(seconds: 5)`，而声明的 `stopTimeout` 是 6s（三个 provider）
/// - 阿里云 `stop()` **盲等 500ms** 就返回，服务端收尾帧一慢，最后一句直接没了
/// - 握手等待和收尾等待各自独立计时，最坏 2+4=6s，正好撞上外层预算
void main() {
  test('内层等待预算必须明显小于引擎给 stop() 的预算', () {
    expect(AppConstants.kAsrFinalFrameWait,
        lessThan(AppConstants.kAsrStopTimeout),
        reason: '内层不小于外层 = 引擎先放弃，返回空文本');
    expect(AppConstants.kAsrStopTimeout - AppConstants.kAsrFinalFrameWait,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
        reason: '余量不足 1 秒，调度抖动就能让外层先触发');
  });

  test('provider 的 stop() 里不得出现秒级的盲等', () {
    // `Future.delayed(const Duration(seconds: N))` 是「等固定时长再返回」，
    // 早到白等、晚到丢文本，两头不讨好。要等就等事件（Completer / 轮询标志位），
    // 时长上限统一走 AppConstants。
    // 毫秒级的 `Future.delayed` 是轮询节拍，不在此列。
    final offenders = <String>[];
    for (final f in Directory('lib/engine/providers')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final result = parseFile(
        path: f.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      for (final cls
          in result.unit.declarations.whereType<ClassDeclaration>()) {
        for (final m in cls.members.whereType<MethodDeclaration>()) {
          if (m.name.lexeme != 'stop') continue;
          final v = _BlindDelayVisitor();
          m.accept(v);
          for (final src in v.hits) {
            offenders.add('  ${f.path} :: $src');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'stop() 里的秒级盲等：\n${offenders.join('\n')}');
  });
}

class _BlindDelayVisitor extends RecursiveAstVisitor<void> {
  final List<String> hits = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'delayed') {
      final args = node.argumentList.arguments;
      if (args.isNotEmpty) {
        final a = args.first.toSource();
        // 只认「秒级」——毫秒级是轮询节拍，不是盲等
        if (RegExp(r'Duration\(\s*seconds:').hasMatch(a)) {
          hits.add(node.toSource());
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}
