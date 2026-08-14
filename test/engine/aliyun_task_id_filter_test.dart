import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aliyun 复用 WebSocket 连接（initialize 预连接，start 在 _isConnected 时不重连），
/// 所以上一次录音的迟到帧会在下一次录音期间到达，把旧句子 append 进新会话的
/// _committedText —— 字幕串台。stop() 只固定等 500ms，窗口很容易命中。
///
/// 复用连接下唯一可靠的会话标识是 task_id（每次 start() 重新生成、随
/// StartTranscription 下发、服务端原样回带）。**不能**用其它 provider 那套
/// 「录音代次」—— 那是给「每次 start 都新建连接」设计的，套到这里会把本次录音的
/// 消息也全挡掉。
void main() {
  final path = 'lib/engine/providers/aliyun_provider.dart';
  final src = File(path).readAsStringSync();
  final unit = parseFile(
    path: File(path).absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
  ).unit;

  test('_handleMessage 必须按 task_id 过滤过期帧', () {
    final v = _MethodBodyVisitor('_handleMessage');
    unit.accept(v);
    expect(v.body, isNotNull, reason: '没找到 _handleMessage');
    final body = v.body!.toSource();

    expect(body.contains("header['task_id']"), isTrue,
        reason: '_handleMessage 没有读取 header.task_id，无法识别过期帧');
    expect(body.contains('_taskId'), isTrue,
        reason: '没有与当前会话的 _taskId 比对');

    // 过滤必须发生在任何文本发布之前，否则旧句子已经串进去了
    final filterAt = body.indexOf('task_id');
    final firstPublish = body.indexOf('_textController.add');
    expect(firstPublish, greaterThan(-1), reason: '没找到文本发布点');
    expect(filterAt, lessThan(firstPublish),
        reason: 'task_id 过滤必须早于任何 _textController.add，'
            '否则过期帧已经污染了字幕');
  });

  test('aliyun 不得改用录音代次守卫', () {
    expect(src.contains('gen != _generation'), isFalse,
        reason: '该 provider 复用连接，代次守卫会把本次录音的消息也全挡掉');
  });

  test('task_id 每次 start() 重新生成', () {
    final v = _MethodBodyVisitor('start');
    unit.accept(v);
    expect(v.body!.toSource().contains('_taskId ='), isTrue,
        reason: 'task_id 若不每次重生成，过滤就失去意义');
  });
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  final String name;
  FunctionBody? body;
  _MethodBodyVisitor(this.name);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.name.lexeme != 'AliyunProvider') return;
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == name) body = node.body;
    super.visitMethodDeclaration(node);
  }
}
