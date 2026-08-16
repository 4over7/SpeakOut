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

  /// 去掉注释后的源码。「不得再出现某标识符」这类断言必须看**代码** ——
  /// 否则解释性注释里提到的旧名字会把断言带偏（这条就绊过一次）。
  /// 只用于否定断言：行内 `//` 剥离会误伤字符串里的 URL，肯定断言仍看 src。
  final code = src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');

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

  group('N3+P1 剪贴板事务：两条注入路径必须共用同一套状态', () {
    test('只有一套事务状态，不得再有第二份快照', () {
      // 上一版一次性用 _txSavedItems、流式用 _savedClipboardItems，
      // 靠 Dart 的会话计数推断两者不会交错 —— 但那个计数管不到普通 inject()，
      // 更管不到 native 这边 800ms 的延迟还原窗口。可达路径：
      //   X → 普通注入 A（存 X，等 800ms）→ 800ms 内触发 AI 梳理，
      //   流式 begin 把 A 当原始快照 → 普通注入的还原任务判定已易主而跳过
      //   → 梳理结束写回 A。X 永久丢失。
      expect(code.contains('_savedClipboardItems'), isFalse,
          reason: '流式不得再持有自己的快照');
      expect(code.contains('_txSavedItems'), isFalse);
      expect(src.contains('_txOriginal'), isTrue, reason: '应只剩一份原始快照');
    });

    test('原始快照只在事务开启时拍一次', () {
      final body =
          RegExp(r'static void tx_begin_locked\(NSPasteboard \*pb\) \{([\s\S]*?)\n\}')
              .firstMatch(src)
              ?.group(1);
      expect(body, isNotNull);
      expect(body!.contains('if (_txActive) return'), isTrue,
          reason: '已有事务在跑就必须沿用它的快照，绝不重拍');
    });

    test('收尾必须在同一把锁里完成「校验+还原+清状态」', () {
      // 先清 pending 再去还原的话，中间插进来的注入会把已被污染的剪贴板
      // 当成新事务的原始快照，用户内容照样丢。
      final body =
          RegExp(r'static void tx_finish_locked\(NSPasteboard \*pb, uint64_t gen\) \{([\s\S]*?)\n\}')
              .firstMatch(src)
              ?.group(1);
      expect(body, isNotNull);
      final restoreAt = body!.indexOf('writeObjects');
      final clearAt = body.indexOf('_txActive = NO');
      expect(restoreAt, greaterThanOrEqualTo(0));
      expect(clearAt, greaterThanOrEqualTo(0));
      expect(restoreAt, lessThan(clearAt),
          reason: '必须先还原再清事务状态');
      expect(body.contains('gen != _txGeneration'), isTrue,
          reason: '只有最后一代负责收尾');
    });

    test('粘贴序列全程持锁 —— 不能在写剪贴板和 Cmd+V 之间放锁', () {
      // 放锁的话另一次注入可以在我们粘贴之前改掉剪贴板，粘出来是别的内容。
      final body =
          RegExp(r'static uint64_t tx_paste_locked\(NSPasteboard \*pb, NSString \*text\) \{([\s\S]*?)\n\}')
              .firstMatch(src)
              ?.group(1);
      expect(body, isNotNull, reason: '没找到 tx_paste_locked');
      expect(body!.contains('pthread_mutex_unlock'), isFalse,
          reason: '这个函数内部不得放锁');
      expect(body.contains('post_command_key'), isTrue);
    });
  });

  group('R34 事务协调器的三条硬约束', () {
    test('每次内部写之前都要检查剪贴板有没有易主', () {
      // 只在收尾时查，只挡得住「最后一次内部写之后」的用户复制：
      //   X → chunk(A) → 用户复制 Z → chunk(B) 把 Z 清掉并更新 expected
      //   → 收尾看到匹配，还原 X。Z 永久丢失，用户毫无察觉。
      final body =
          RegExp(r'static uint64_t tx_paste_locked\(NSPasteboard \*pb, NSString \*text\) \{([\s\S]*?)\n\}')
              .firstMatch(src)
              ?.group(1);
      expect(body, isNotNull);
      final checkAt = body!.indexOf('pb.changeCount != _txExpectedChangeCount');
      final clearAt = body.indexOf('clearContents');
      expect(checkAt, greaterThanOrEqualTo(0), reason: '写之前没有易主检查');
      expect(checkAt, lessThan(clearAt), reason: '检查必须在清空剪贴板之前');
      expect(body.contains('snapshot_pasteboard'), isTrue,
          reason: '发现易主后要把用户当前内容作为新的还原目标');
    });

    test('推进代次的每条路径都必须有人收尾', () {
      // chunk / copy_selection 在没有 hold 罩着时会把代次推高，让先前安排的
      // 收尾任务因代次不符早退，自己却不安排新任务 —— 事务从此挂着不放，
      // _txActive 永为 YES，之后每次注入都沿用一份很旧的快照。
      for (final fn in ['void inject_clipboard_chunk(const char *text)',
                        'void copy_selection(void)']) {
        final body = bodyOf(fn);
        expect(body.contains('tx_schedule_finish'), isTrue,
            reason: '$fn 推进了代次却不安排收尾');
        expect(body.contains('_txHoldDepth == 0'), isTrue,
            reason: '$fn 需要判断有没有 hold 罩着');
      }
    });

    test('copy_selection 必须要求「恰好变了一次」', () {
      // changeCount 每次 clearContents 加一，增量 > 1 说明这段时间还有别人
      // 动过剪贴板 —— 此时把当前值记成我们的，收尾就会盖掉用户刚复制的内容。
      final body = bodyOf('void copy_selection(void)');
      expect(body.contains('delta == 1'), isTrue,
          reason: '只看「变了」不够，必须恰好变一次');
    });
  });

  group('R34 其余回归', () {
    test('新录音开始必须复位平滑电平', () {
      final body = bodyOf('int start_audio_recording()');
      expect(body.contains('smoothed_level_reset()'), isTrue,
          reason: '不复位的话上一段的高电平会被这一段继承，波形虚高、静音判定延后');
    });

    test('生产者开关与落盘开关必须分开', () {
      // 合成一个的话，同步排空读完游标之后、置零之前 tap 线程还能再写一条，
      // 那条会被下一轮 timer 读到，但那时 log_to_file 已经短路了。
      final produce = bodyOf(
          '__attribute__((format(printf, 1, 2))) static void log_from_tap(const char *fmt,\n                                                               ...)');
      expect(produce.contains('tapLogProducerEnabled'), isTrue,
          reason: '生产者应看自己的开关，而不是落盘开关');
      final setter = bodyOf('void set_debug_logging(int enabled)');
      final stopAt = setter.indexOf('atomic_store(&tapLogProducerEnabled, 0)');
      final flushAt = setter.indexOf('flush_tap_log_sync()');
      final offAt = setter.indexOf('atomic_store(&debugLoggingEnabled, 0)');
      expect(stopAt, greaterThanOrEqualTo(0));
      expect(stopAt, lessThan(flushAt), reason: '必须先停生产者再排空');
      expect(flushAt, lessThan(offAt), reason: '必须排空之后才关落盘');
    });

    test('drain timer 初始化必须线程安全', () {
      final body = bodyOf('static void start_tap_log_drain(void)');
      expect(body.contains('dispatch_once'), isTrue,
          reason: '裸 if (timer != nil) 不是线程安全的');
    });
  });

  group('N6 流式会话不得共用上一次会话的 changeCount', () {
    test('判据必须随事务开启而重置', () {
      // 不复位的话：AI 梳理里 begin 后 Cmd+C 改了剪贴板、LLM 又在首个
      // chunk 之前失败时，end 拿上一次会话的旧值一比就判成「已易主」
      // 而跳过还原 —— 用户开梳理前的剪贴板内容就这么没了。
      // 跨会话共享的判据必须随事务生命周期走，不能是永不复位的静态量
      expect(code.contains('_lastChunkChangeCount'), isFalse,
          reason: '旧的跨会话静态判据应已随事务协调器一起去掉');
      final body =
          RegExp(r'static void tx_begin_locked\(NSPasteboard \*pb\) \{([\s\S]*?)\n\}')
              .firstMatch(src)!
              .group(1)!;
      expect(body.contains('_txExpectedChangeCount = pb.changeCount'), isTrue,
          reason: '事务开启时要记基线，否则「我们没动过而用户动了」这种情形分不出来');
    });

    test('copy_selection 不得固定 sleep 后把「当前值」认作自己造成的', () {
      // 固定睡 100ms 的话，用户恰好在这窗口内自己复制了东西，那个值会被
      // 记成我们的变更，之后收尾就拿旧快照把他刚复制的内容覆盖掉。
      final body = bodyOf('void copy_selection(void)');
      expect(body.contains('usleep(100000)'), isFalse,
          reason: '不能固定睡满再归因，要轮询等自己的 Cmd+C 落地');
      expect(body.contains('observed != before'), isTrue,
          reason: '必须与调用前的基线比较，确认变更确实发生了才归因');
      expect(body.contains('tx_note_mutation_locked'), isTrue,
          reason: '会话内的 Cmd+C 也是我们造成的变更，要记进判据');
    });
  });

  group('N7 麦克风权限查询不得阻塞', () {
    test('不得再用信号量同步等授权 UI', () {
      // 旧实现等 5 秒就返回初值 0（=拒绝）：用户读一眼提示再点「允许」
      // 就超时，这次录音被判无权限直接中止。而且它跑在 UI isolate 上，
      // 等于界面冻 5 秒。`__block int result` 还是无同步的数据竞争。
      expect(code.contains('dispatch_semaphore_wait'), isFalse,
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

  group('N8 音频电平平滑必须与调用频率无关且状态一致', () {
    test('不得用两个独立原子量拼一个状态', () {
      // level 和 stamp 分别放进两个 atomic 提交不了一致状态：
      // 线程 A CAS 写完 bits 尚未写 stamp 时，线程 B 读到「新 bits + 旧 stamp」
      // 会把已算过的衰减再算一遍；A 恢复后写回更早的 stamp 让时间倒退。
      // 另一种交错让 now < oldStamp，无符号相减下溢，keep≈0，电平瞬间塌掉。
      expect(code.contains('smoothedLevelBits'), isFalse,
          reason: '双原子拼状态不成立，应改用一把锁');
      expect(src.contains('pthread_mutex_t levelMutex'), isTrue);
    });

    test('衰减按经过时间算，而不是按调用次数', () {
      final body = bodyOf('static float smoothed_level_update(float level)');
      expect(body.contains('pow(0.88'), isTrue,
          reason: 'keep 系数应由 elapsed 推出，与调用频率无关');
      expect(body.contains('pthread_mutex_lock(&levelMutex)'), isTrue);
      expect(body.contains('now > smoothedLevelStamp ? now - smoothedLevelStamp : 0'),
          isTrue,
          reason: '必须钳住时钟倒退，否则无符号下溢会让电平直接塌到当前输入');
    });
  });

  group('P2 tap 日志环形缓冲：满则丢新，绝不覆盖读者手里的槽', () {
    test('写者必须看得见读游标', () {
      // 覆盖未消费的槽位不是「日志撕裂」这么轻 —— 读者 memcpy 与写者
      // vsnprintf 同一个 char[]，在 C 内存模型下是数据竞争，是 UB。
      final body = bodyOf(
          '__attribute__((format(printf, 1, 2))) static void log_from_tap(const char *fmt,\n                                                               ...)');
      expect(body.contains('tapLogRead'), isTrue, reason: '写者没读游标，会覆盖未消费的槽');
      expect(body.contains('w - r >= TAP_LOG_SLOTS'), isTrue,
          reason: '环满时必须丢新的这条');
      expect(src.contains('static atomic_uint tapLogRead'), isTrue,
          reason: '读游标要跨线程可见，必须是原子量');
    });

    test('关闭 verbose 前必须先同步排空', () {
      // log_to_file 自己也受这个开关控制，先置零就会丢掉最后 200ms 那批 ——
      // 往往正是用户关开关前想看的那几行。
      final body = bodyOf('void set_debug_logging(int enabled)');
      final flushAt = body.indexOf('flush_tap_log_sync()');
      final zeroAt = body.indexOf('atomic_store(&debugLoggingEnabled, 0)');
      expect(flushAt, greaterThanOrEqualTo(0), reason: '关闭路径没有排空');
      expect(zeroAt, greaterThanOrEqualTo(0));
      expect(flushAt, lessThan(zeroAt), reason: '必须先排空再置零');
    });
  });
}
