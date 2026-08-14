import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「录音代次守卫」只在**每次 start() 都新建连接**的 provider 上成立。
///
/// 真实事故：我给 aliyun 也加了这个守卫，但它在 initialize() 就预连接
/// （_ensureConnectedAsync），listener 捕获 gen=0；start() 自增到 1 且
/// 因 _isConnected 为真而**复用**旧连接不重连 —— 守卫把每条消息都挡掉，
/// 阿里云识别直接全废。靠人工核对 initialize→start 时序才发现。
///
/// 复用连接的场景下，正确的判别依据是消息里的 task_id，不是录音代次。
void main() {
  final dir = Directory('lib/engine/providers');

  test('用了代次守卫的 provider，start() 必须无条件新建连接', () {
    final offenders = <String>[];
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('_provider.dart')) continue;
      final src = e.readAsStringSync();
      if (!src.contains('gen != _generation')) continue; // 没用守卫，跳过

      final start = RegExp(r'Future<void> start\(\) async \{([\s\S]*?)\n  \}')
          .firstMatch(src)
          ?.group(1);
      // 只约束「在 start() 里捕获代次」的 provider —— 那意味着代次绑定的是
      // **连接**，连接必须每次新建才对得上。
      // 批量识别（OpenAI/Groq）在 stop() 里捕获，绑定的是**单次请求**，
      // start() 本就不建连接，不适用本约束。
      if (start == null || !start.contains('final gen = _generation')) continue;
      final connects = RegExp(r'WebSocketChannel\.connect|_connectWebSocket\(\)')
          .hasMatch(start);
      final conditional =
          RegExp(r'if\s*\(\s*!_isConnected|_channel\s*!=\s*null').hasMatch(start);
      if (!connects || conditional) {
        offenders.add('${e.path}: start() 未无条件建连'
            '（connects=$connects, conditional=$conditional）');
      }
    }
    expect(offenders, isEmpty,
        reason: '这些 provider 复用连接却用了连接期捕获的代次守卫，'
            '会把本次录音的消息全部挡掉：\n  ${offenders.join("\n  ")}');
  });

  test('aliyun 复用预连接，不得使用代次守卫', () {
    final src = File('${dir.path}/aliyun_provider.dart').readAsStringSync();
    expect(src.contains('gen != _generation'), isFalse,
        reason: 'aliyun 在 initialize() 预连接且 start() 复用，'
            '代次守卫会让它收不到任何消息。见该文件顶部注释：'
            '这里要按 task_id 过滤，不是按代次');
  });
}
