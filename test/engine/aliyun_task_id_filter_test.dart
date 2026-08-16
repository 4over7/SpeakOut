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

    // 不匹配必须真的 return —— 只读取不拦截等于没过滤
    expect(RegExp(r'msgTaskId != _taskId').hasMatch(body), isTrue,
        reason: '没有做不等比较');
    expect(body.contains('return;'), isTrue, reason: '比较后没有拦截');

    // 安全阀：万一服务端行为与协议不符导致消息全丢，日志要能一眼指出原因
    expect(body.contains('_droppedStaleFrame'), isTrue,
        reason: '缺少首次丢弃的诊断日志，全丢时会变成查不出的「阿里云没反应」');

    // 过滤必须发生在任何文本发布之前，否则旧句子已经串进去了。
    //
    // **锚点必须是「不匹配的拒绝判断」本身，不能是第一个 task_id** ——
    // task_id 在这个方法里出现多次（读 header、日志、比较）。拿第一个的话，
    // 把真正的拒绝分支挪到 _textController.add 之后，断言照样绿。
    final rejectAt = body.indexOf('msgTaskId != _taskId');
    final firstPublish = body.indexOf('_textController.add');
    expect(rejectAt, greaterThan(-1), reason: '没找到 task_id 不匹配的拒绝判断');
    expect(firstPublish, greaterThan(-1), reason: '没找到文本发布点');
    expect(rejectAt, lessThan(firstPublish),
        reason: 'task_id 过滤必须早于任何 _textController.add，'
            '否则过期帧已经污染了字幕');
    // **return 必须属于拒绝分支本身**，不能只是「两者之间存在 return」——
    //   if (msgTaskId != _taskId) { AppLog.d('stale'); }
    //   if (别的条件) return;
    // 这样也满足「之间有 return」，但过期帧照样会被发布。
    // 按大括号配平取出该 if 自己的块再查。
    final open = body.indexOf('{', rejectAt);
    expect(open, greaterThan(-1), reason: '拒绝判断后面没有块');
    var depth = 0;
    var close = -1;
    for (var i = open; i < body.length; i++) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') {
        depth--;
        if (depth == 0) {
          close = i;
          break;
        }
      }
    }
    expect(close, greaterThan(open), reason: '大括号不配平');
    expect(body.substring(open, close).contains('return'), isTrue,
        reason: 'task_id 不匹配的分支自己没有 return —— 只打日志等于没过滤');
  });

  test('aliyun 不得改用录音代次守卫', () {
    expect(src.contains('gen != _generation'), isFalse,
        reason: '该 provider 复用连接，代次守卫会把本次录音的消息也全挡掉');
  });

  test('start() 必须重生成 task_id 并复位诊断标志', () {
    final v = _MethodBodyVisitor('start');
    unit.accept(v);
    final body = v.body!.toSource();
    expect(body.contains('_taskId ='), isTrue,
        reason: 'task_id 若不每次重生成，过滤就失去意义');
    expect(body.contains('_droppedStaleFrame = false'), isTrue,
        reason: '安全阀标志要每次会话复位，否则只在首次会话打一次日志');
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
