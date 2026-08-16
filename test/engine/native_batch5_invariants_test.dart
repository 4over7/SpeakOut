import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// native 层第 5 批 finding 的源码约束。
///
/// 这些不变量都无法在 Dart 里跑出来（要么在 CGEventTap 回调线程上，
/// 要么要真的操作系统剪贴板），所以沿用仓库既有做法：对 native_input.m
/// 做源码级断言，把「改回去就会复发」的那几行钉住。
/// 每一条都对应一个已经发生过或已被确认可触发的缺陷。
void main() {
  final src = File('native_lib/native_input.m').readAsStringSync();

  String bodyOf(String signature) {
    final m = RegExp('${RegExp.escape(signature)} \\{([\\s\\S]*?)\\n\\}')
        .firstMatch(src);
    expect(m, isNotNull, reason: '没找到 $signature —— 断言已失效，先修扫描');
    return m!.group(1)!;
  }

  group('N1 EventTap 两类禁用都要重启', () {
    test('ByUserInput 不能只是 return', () {
      // 只重启 Timeout、对 ByUserInput 直接 return 的话，此后所有快捷键
      // 事件都收不到：PTT / 闪念 / 翻译全部静默失效，进程还活着也不报错。
      final m = RegExp(
              r'if\s*\(\s*type\s*==\s*kCGEventTapDisabledByUserInput\s*\)\s*\{\s*return event;')
          .hasMatch(src);
      expect(m, isFalse, reason: 'ByUserInput 被直接放过，tap 不会恢复');
    });

    test('两类禁用共用同一个重启分支', () {
      final m = RegExp(
              r'kCGEventTapDisabledByTimeout\s*\|\|[\s\S]{0,80}?kCGEventTapDisabledByUserInput')
          .hasMatch(src);
      expect(m, isTrue, reason: '两类禁用应合并处理并重新 CGEventTapEnable');
      expect(src.contains('CGEventTapEnable(eventTap, true)'), isTrue);
    });
  });

  group('N2 CGEventTap 回调里不得做同步 I/O', () {
    test('回调函数体内不得出现 log_to_file', () {
      // log_to_file 做 fopen / vfprintf / fclose / NSString 分配 / NSLog。
      // 这个回调跑在主 RunLoop 上且有系统时限 —— 磁盘忙一下，系统就判定
      // tap 无响应并禁用它。打开 verbose 日志本来是为了排查别的问题，
      // 却把键盘监听搞挂，因果完全错位。
      final body = bodyOf('CGEventRef myCGEventCallback(CGEventTapProxy proxy, '
          'CGEventType type,\n                             CGEventRef event, void *refcon)');
      expect(body.contains('log_to_file('), isFalse,
          reason: '回调里出现同步文件 I/O，会导致 tap 被系统禁用');
      expect(body.contains('log_from_tap('), isTrue,
          reason: '回调应改用无阻塞的 log_from_tap');
    });

    test('log_from_tap 不得有堆分配或文件操作', () {
      final body = bodyOf(
          '__attribute__((format(printf, 1, 2))) static void log_from_tap(const char *fmt,\n                                                               ...)');
      for (final forbidden in ['fopen', 'NSLog', 'alloc', 'malloc', 'strdup', 'dispatch_']) {
        expect(body.contains(forbidden), isFalse,
            reason: 'log_from_tap 里出现 $forbidden —— 回调侧必须零分配零系统调用');
      }
      expect(body.contains('vsnprintf'), isTrue, reason: '应在预分配槽位上格式化');
    });
  });

  group('N3 一次性剪贴板注入必须是事务级快照', () {
    test('只有无待还原任务时才拍快照', () {
      // 每次注入都重拍快照的话：原剪贴板 X → 注入 A（存 X）→ 800ms 内
      // 注入 B（存到的却是 A）→ A 的还原任务见 changeCount 变了而跳过
      // → B 的还原任务写回 A。X 永久丢失，剪贴板留着我们自己注入的文本。
      final body = bodyOf('static void inject_via_clipboard(const char *text)');
      expect(body.contains('if (!_txRestorePending)'), isTrue,
          reason: '快照必须按事务拍一次，不能每次注入都重拍');
      expect(body.contains('++_txGeneration'), isTrue,
          reason: '需要代次，让只有最后一代的任务负责还原');
      expect(body.contains('myGen != _txGeneration'), isTrue,
          reason: '还原任务必须先确认自己是最后一代');
    });

    test('事务状态的读写都在互斥锁内', () {
      final body = bodyOf('static void inject_via_clipboard(const char *text)');
      expect('pthread_mutex_lock(&clipboardTxMutex)'.allMatches(body).length,
          greaterThanOrEqualTo(2),
          reason: '注入侧与还原任务侧分别在两个线程上，都要持锁');
    });
  });

  group('N6 流式会话不得共用上一次会话的 changeCount', () {
    test('begin 必须复位 _lastChunkChangeCount', () {
      // 不复位的话：AI 梳理里 begin 后 Cmd+C 改了剪贴板、LLM 又在首个
      // chunk 之前失败时，end 拿上一次会话的旧值一比就判成「已易主」
      // 而跳过还原 —— 用户开梳理前的剪贴板内容就这么没了。
      final body = bodyOf('void inject_clipboard_begin(void)');
      expect(body.contains('_lastChunkChangeCount = -1'), isTrue,
          reason: 'begin 没复位，判据会跨会话残留');
    });

    test('copy_selection 在会话中要把自己造成的变更记进判据', () {
      final body = bodyOf('void copy_selection(void)');
      expect(body.contains('_clipboardSessionActive'), isTrue);
      expect(body.contains('_lastChunkChangeCount'), isTrue,
          reason: '会话内的 Cmd+C 也是我们造成的变更，不记就会被当成用户易主');
    });
  });

  group('N7 麦克风权限查询不得阻塞', () {
    test('不得再用信号量同步等授权 UI', () {
      // 旧实现等 5 秒就返回初值 0（=拒绝）：用户读一眼提示再点「允许」
      // 就超时，这次录音被判无权限直接中止。而且它跑在 UI isolate 上，
      // 等于界面冻 5 秒。`__block int result` 还是无同步的数据竞争。
      expect(src.contains('dispatch_semaphore_wait'), isFalse,
          reason: '同步 FFI 不能等一个要人点的 UI');
    });

    test('查询与请求必须是两个函数', () {
      expect(src.contains('int microphone_permission_status(void)'), isTrue);
      expect(src.contains('void request_microphone_permission(void)'), isTrue);
      final body = bodyOf('int microphone_permission_status(void)');
      expect(body.contains('requestAccess'), isFalse,
          reason: '查询函数不得弹框');
    });
  });

  group('N8 音频电平平滑必须与调用频率无关', () {
    test('不得再用非原子的裸 float 累积', () {
      // 三个调用方分布在两个线程：Dart UI isolate（波形 + 静音检测）
      // 和 AppKit 主线程（80ms Timer）。除了数据竞争，更实际的问题是
      // 「每调一次乘 0.88」让衰减速度跟着调用次数走 —— 离线探针实测
      // 三个轮询器时 480ms 后衰减到 0.1002，而设计值是 0.4644。
      expect(RegExp(r'static float smoothedLevel\s*=').hasMatch(src), isFalse,
          reason: '裸 float 既是数据竞争，衰减也会随轮询器个数变快');
      expect(src.contains('_Atomic uint32_t smoothedLevelBits'), isTrue);
    });

    test('衰减按经过时间算，而不是按调用次数', () {
      final body = bodyOf('static float smoothed_level_update(float level)');
      expect(body.contains('pow(0.88'), isTrue,
          reason: 'keep 系数应由 elapsed 推出，与调用频率无关');
      expect(body.contains('atomic_compare_exchange_weak'), isTrue,
          reason: '读改写要用 CAS 循环');
    });
  });
}
