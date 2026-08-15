import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/config/app_log.dart';

/// AppLog.d() 在 enabled=false（生产默认，见 AppConstants.kVerboseLogging）
/// 时首行就 return。
///
/// 这一轮我在多处加了「失败就记日志」的兜底 —— 回滚失败、凭证残留、悬空引用。
/// 用 d() 记等于什么都没记：用户真遇到时磁盘处于混合状态，却没有任何线索。
/// 所以单开 AppLog.e()，不看开关。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('speakout_log_test');
  });
  tearDown(() {
    AppLog.enabled = false;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('verbose 关闭时 d() 不落盘、e() 必须落盘', () async {
    await AppLog.initForTest(File('${tmp.path}/t.log'));
    AppLog.enabled = false;

    AppLog.d('这条不该出现');
    AppLog.e('这条必须出现');
    await AppLog.flushForTest();

    final content = File('${tmp.path}/t.log').readAsStringSync();
    expect(content.contains('这条不该出现'), isFalse,
        reason: 'verbose 关闭时 d() 不应落盘');
    expect(content.contains('这条必须出现'), isTrue,
        reason: 'e() 受 verbose 开关影响了 —— '
            '那些「失败只记日志」的兜底在默认配置下等于没记');
    expect(content.contains('[ERROR]'), isTrue, reason: 'e() 应带错误标记');
  });

  test('verbose 打开时两者都落盘', () async {
    await AppLog.initForTest(File('${tmp.path}/t2.log'));
    AppLog.enabled = true;

    AppLog.d('debug 内容');
    AppLog.e('error 内容');
    await AppLog.flushForTest();

    final content = File('${tmp.path}/t2.log').readAsStringSync();
    expect(content.contains('debug 内容'), isTrue);
    expect(content.contains('error 内容'), isTrue);
  });
}
