import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';

/// native 层第 5 批 finding 的源码约束。
///
/// 这些不变量都无法在 Dart 里跑出来（要么在 CGEventTap 回调线程上，
/// 要么要真的操作系统剪贴板），所以沿用仓库既有做法：对 native_input.m
/// 做源码级断言，把「改回去就会复发」的那几行钉住。
/// 每一条都对应一个已经发生过或已被确认可触发的缺陷。
/// 导出签名的指纹。**改了任何导出函数的签名就要连同 ABI 版本一起更新。**
/// 值由「导出签名一变，ABI 版本必须跟着变」这条测试的失败信息给出。
const String kNativeAbiFingerprint = '7d094818ff94a198f613069271bed70857311af5';

void main() {
  final src = File('native_lib/native_input.m').readAsStringSync();

  /// 去掉注释。「不得再出现某某」这类**否定断言必须看代码** ——
  /// 否则解释性注释里提到的旧写法会把断言带偏。这个坑已经绊过三次，
  /// 所以做成可复用的，别再逐处打补丁。
  /// 只用于否定断言：行内 `//` 剥离会误伤字符串里的 URL，肯定断言仍看原文。
  String stripComments(String text) => text
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');

  final code = stripComments(src);

  /// 按**函数名**取函数体，不写死返回类型。
  /// 写死完整签名的代价已经付过三次了：把 void 改成 BOOL 这种与断言意图
  /// 完全无关的改动，会让一批断言集体失效。断言要盯的是函数体内容。
  /// 按**函数名**取函数体。前缀（返回类型、static、`__attribute__((...))`）
  /// 和跨行参数表都不参与匹配 —— 写死完整签名这个坑已经绊过六次，
  /// 每次都是「与断言意图完全无关的改动」让一批断言集体失效。
  String bodyOfFn(String name) {
    final m = RegExp(
            r'(?:^|\n)(?!\s*//)[^\n;{}]*\b' +
                RegExp.escape(name) +
                r'\s*\([^;{}]*?\)\s*\{([\s\S]*?)\n\}')
        .firstMatch(src);
    expect(m, isNotNull, reason: '没找到函数 $name —— 断言已失效，先修扫描');
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
      final body = bodyOfFn('myCGEventCallback');
      expect(body.contains('log_to_file('), isFalse,
          reason: '回调里出现同步文件 I/O，会导致 tap 被系统禁用');
      expect(body.contains('log_from_tap('), isTrue,
          reason: '回调应改用无阻塞的 log_from_tap');
    });

    test('log_from_tap 不得有堆分配或文件操作', () {
      final body = bodyOfFn('log_from_tap');
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
      final body = bodyOfFn('tx_begin_locked');
      expect(body.contains('if (_txActive) return'), isTrue,
          reason: '已有事务在跑就必须沿用它的快照，绝不重拍');
    });

    test('收尾必须在同一把锁里完成「校验+还原+清状态」', () {
      // 先清 pending 再去还原的话，中间插进来的注入会把已被污染的剪贴板
      // 当成新事务的原始快照，用户内容照样丢。
      final body = bodyOfFn('tx_finish_locked');
      final restoreAt = body.indexOf('writeObjects');
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
      final body = bodyOfFn('tx_paste_locked');
      expect(body.contains('pthread_mutex_unlock'), isFalse,
          reason: '这个函数内部不得放锁');
      expect(body.contains('post_command_key'), isTrue);
    });
  });

  group('R34 事务协调器的三条硬约束', () {
    test('每次内部写之前都要检查剪贴板有没有易主', () {
      // 只在收尾时查，只挡得住「最后一次内部写之后」的用户复制：
      //   X → chunk(A) → 用户复制 Z → chunk(B) 把 Z 清掉并更新 expected
      //   → 收尾看到匹配，还原 X。Z 永久丢失，用户毫无察觉。
      // 不写死判据长什么样 —— 它从 changeCount 换成过内容、又换成 token。
      // 不变量是「动剪贴板之前先判所有权，不是我们的就重拍快照」。
      final body = bodyOfFn('tx_paste_locked');
      final checkAt = body.indexOf('tx_snapshot_stable_locked');
      final clearAt = body.indexOf('clearContents');
      expect(checkAt, greaterThanOrEqualTo(0), reason: '写之前没有所有权检查');
      expect(clearAt, greaterThanOrEqualTo(0));
      expect(checkAt, lessThan(clearAt),
          reason: '检查必须在清空剪贴板之前，且发现易主要重拍快照');
    });

    test('推进代次的每条路径都必须有人收尾', () {
      // chunk / copy_selection 在没有 hold 罩着时会把代次推高，让先前安排的
      // 收尾任务因代次不符早退，自己却不安排新任务 —— 事务从此挂着不放，
      // _txActive 永为 YES，之后每次注入都沿用一份很旧的快照。
      for (final fn in ['inject_clipboard_chunk', 'copy_selection_impl']) {
        final body = bodyOfFn(fn);
        expect(body.contains('tx_schedule_finish'), isTrue,
            reason: '$fn 推进了代次却不安排收尾');
        expect(body.contains('_txHoldDepth == 0'), isTrue,
            reason: '$fn 需要判断有没有 hold 罩着');
      }
    });

    test('copy_selection 必须要求「恰好变了一次」', () {
      // changeCount 每次 clearContents 加一，增量 > 1 说明这段时间还有别人
      // 动过剪贴板 —— 此时把当前值记成我们的，收尾就会盖掉用户刚复制的内容。
      final body = bodyOfFn('copy_selection_impl');
      expect(body.contains('delta == 1'), isTrue,
          reason: '只看「变了」不够，必须恰好变一次');
    });
  });

  group('R34 其余回归', () {
    test('新录音开始必须复位平滑电平', () {
      final body = bodyOfFn('start_audio_recording');
      expect(body.contains('smoothed_level_reset()'), isTrue,
          reason: '不复位的话上一段的高电平会被这一段继承，波形虚高、静音判定延后');
    });

    test('生产者开关与落盘开关必须分开', () {
      // 合成一个的话，同步排空读完游标之后、置零之前 tap 线程还能再写一条，
      // 那条会被下一轮 timer 读到，但那时 log_to_file 已经短路了。
      final produce = bodyOfFn('log_from_tap');
      expect(produce.contains('tapLogProducerEnabled'), isTrue,
          reason: '生产者应看自己的开关，而不是落盘开关');
      final setter = bodyOfFn('set_debug_logging');
      final stopAt = setter.indexOf('atomic_store(&tapLogProducerEnabled, 0)');
      final flushAt = setter.indexOf('flush_tap_log_sync()');
      final offAt = setter.indexOf('atomic_store(&debugLoggingEnabled, 0)');
      expect(stopAt, greaterThanOrEqualTo(0));
      expect(stopAt, lessThan(flushAt), reason: '必须先停生产者再排空');
      expect(flushAt, lessThan(offAt), reason: '必须排空之后才关落盘');
    });

    test('drain timer 初始化必须线程安全', () {
      final body = bodyOfFn('start_tap_log_drain');
      expect(body.contains('dispatch_once'), isTrue,
          reason: '裸 if (timer != nil) 不是线程安全的');
    });
  });

  group('R37 未做项的收口', () {
    test('注入路径不得在临界区里长时间等待', () {
      // 持锁等待会把还原任务和别的注入一起陪绑。
      // tx_paste_locked 里的读回是同进程的，立刻就有结果，不该轮询；
      // chunk 的节奏等待与事务状态无关，应放锁外。
      final paste = stripComments(bodyOfFn('tx_paste_locked'));
      expect(RegExp(r'for\s*\(int i = 0; i < \d+; i\+\+\)').hasMatch(paste), isFalse,
          reason: '同进程读回不需要轮询，白等还拉长持锁时间');
      // 必须用 lastIndexOf：这个函数有多条早退路径、多个 unlock，
      // 拿第一个比会让断言恒成立（变异探针实测漏报过）。
      final chunk = stripComments(bodyOfFn('inject_clipboard_chunk'));
      final lastUnlock = chunk.lastIndexOf('pthread_mutex_unlock');
      final pacingAt = chunk.indexOf('usleep(30000)');
      expect(lastUnlock, greaterThanOrEqualTo(0));
      expect(pacingAt, greaterThanOrEqualTo(0));
      expect(lastUnlock, lessThan(pacingAt), reason: '节奏等待必须在锁外');
    });

    test('copy_selection 的等待必须放在锁外', () {
      final body = stripComments(bodyOfFn('copy_selection_impl'));
      final loopAt = body.indexOf('usleep(5000)');
      // 等待必须夹在「放锁」和「重新取锁」之间
      final unlockAt = body.lastIndexOf('pthread_mutex_unlock', loopAt);
      final relockAt = body.indexOf('pthread_mutex_lock', loopAt);
      expect(loopAt, greaterThanOrEqualTo(0));
      expect(unlockAt, greaterThanOrEqualTo(0));
      expect(relockAt, greaterThan(loopAt), reason: '等完必须重新取锁');
      expect(unlockAt, lessThan(loopAt),
          reason: '最长 250ms 的等待不该占着锁 —— 我们等的是目标 App 响应 Cmd+C，'
              '跟事务状态无关');
    });

    test('导出签名一变，ABI 版本必须跟着变（指纹锁）', () {
      // 「四处数字相等」拦不住「忘记升级」—— 我自己就在把
      // inject_clipboard_begin 从 void 改成 int 之后忘了升，
      // 而那正是这个握手要防的情形（Dart 按 Int32 去调旧的 void 函数，
      // 读到返回寄存器里的残值）。
      //
      // 这里把**三个平台**所有导出函数的规范化签名做成指纹钉住。
      // 只扫 macOS 是不够的：Linux/Windows 那两份实现单独改签名时，
      // 指纹不变、版本也不用升，同样会撞上 ABI 不匹配。
      //
      // 返回指针类型的函数（`const char *foo(void)`）星号与函数名之间没有空格，
      // 早期的正则漏掉了 6 个 —— 实测 `nm -gU` 有 47 个导出，正则只扫到 41。
      // 现在要求「扫到的数量」也钉死，正则退化会立刻暴露。
      List<String> sigsOf(String path) {
        final text = File(path).readAsStringSync();
        return RegExp(
                r'^(?!static\b)([A-Za-z_][A-Za-z0-9_ ]*?[ *]+)'
                r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^;{}]*?)\)\s*\{',
                multiLine: true)
            .allMatches(text)
            .map((m) =>
                '${m.group(1)!.trim()} ${m.group(2)} '
                '(${m.group(3)!.replaceAll(RegExp(r'\s+'), ' ').trim()})')
            .toList();
      }

      final all = <String>[];
      for (final f in [
        'native_lib/native_input.m',
        'native_lib/linux/native_input.c',
        'native_lib/windows/native_input.cpp',
      ]) {
        final sigs = sigsOf(f);
        expect(sigs.length, greaterThan(5), reason: '$f 没扫到足够导出，正则退化了');
        all.addAll(sigs.map((x) => '$f :: $x'));
      }

      // **ABI 的另一半在 Dart 这边。** 只扫 native 的话，把
      // `InjectTextC = Int32 Function(...)` 改成 `Int64` 时 native 源码没变、
      // 指纹不变、版本不变，握手照样通过 —— 而 Dart 会按错误宽度读返回值。
      final dartTypedefs = RegExp(r'^typedef\s+(\w+C)\s*=\s*([^;]+);',
              multiLine: true)
          .allMatches(File('lib/ffi/native_input_base.dart').readAsStringSync())
          .map((m) =>
              'dart :: ${m.group(1)} = ${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim()}')
          .toList();
      expect(dartTypedefs.length, greaterThan(20),
          reason: 'Dart typedef 没扫到足够条目，正则退化了');
      all.addAll(dartTypedefs);
      all.sort();
      // 正则扫到的导出面必须与 dylib 里**真实的**导出符号对得上。
      // 写死一个数字太脆（每加一个导出都要改），而且它证明不了「扫全了」；
      // 跟 `nm -gU` 对账才是真判据 —— 早期正则漏掉 6 个返回指针的函数
      // （`const char *foo(void)` 星号与名字之间没空格），就是这么发现的。
      if (Platform.isMacOS) {
        final nm = Process.runSync(
            'sh', ['-c', "nm -gU native_lib/libnative_input.dylib | awk '{print \$3}'"]);
        expect(nm.exitCode, 0, reason: 'nm 执行失败: ${nm.stderr}');
        final exported = (nm.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('_'))
            .map((l) => l.substring(1))
            .toSet();
        final scanned = RegExp(
                r'^(?!static\b)([A-Za-z_][A-Za-z0-9_ ]*?[ *]+)'
                r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^;{}]*?)\)\s*\{',
                multiLine: true)
            .allMatches(File('native_lib/native_input.m').readAsStringSync())
            .map((m) => m.group(2)!)
            .toSet();
        expect(exported.difference(scanned), isEmpty,
            reason: '这些函数真的导出了，但指纹正则没扫到 —— '
                '它们改签名不会被任何东西发现');
      }

      final digest = sha1.convert(utf8.encode(all.join('\n'))).toString();
      final expectedAbi = int.parse(digest.substring(0, 6), radix: 16);

      // **版本号 = 指纹前 6 位十六进制。**
      // 上一版是「手动递增的序号 + 一条比较四处相等的断言」，那拦不住
      // 「改了签名却忘了升」—— 四处都不改，断言当然全绿（我就这么漏过一次）。
      // 现在版本是签名的**函数**：改签名 → 指纹变 → 期望版本变 →
      // 四处写死的旧值全部对不上。只改一半在结构上不可能。
      // 锚到定义本身，不能只匹配名字 —— 注释里也会提到它（实测踩过）
      final defineRe = RegExp(r'#define SPEAKOUT_NATIVE_ABI_VERSION (\S+)');
      final sources = {
        'native_lib/native_input.m': defineRe,
        'native_lib/linux/native_input.c': defineRe,
        'native_lib/windows/native_input.cpp': defineRe,
        'lib/ffi/native_input_ffi.dart':
            RegExp(r'const int kExpectedNativeAbiVersion = (\S+);'),
      };
      final wrong = <String, String>{};
      sources.forEach((f, re) {
        final m = re.firstMatch(File(f).readAsStringSync());
        expect(m, isNotNull, reason: '$f 找不到 ABI 版本');
        // 必须写成 0x 开头的十六进制：`replaceFirst('0x','')` 后一律按 16 进制
        // 解析的话，某处写裸十进制 123456、别处写 0x123456 会被认为相同，
        // 运行时数值却不同。
        final raw = m!.group(1)!;
        expect(RegExp(r'^0x[0-9a-fA-F]{6,7}$').hasMatch(raw), isTrue,
            reason: '$f 的 ABI 版本必须是 0x 开头的十六进制，实际是 $raw');
        final got = int.parse(raw.substring(2), radix: 16);
        if (got != expectedAbi) wrong[f] = m.group(1)!;
      });
      expect(wrong, isEmpty,
          reason: '导出签名变了，ABI 版本必须跟着变。\n'
              '  期望：0x${expectedAbi.toRadixString(16).padLeft(6, '0')}\n'
              '  实际：$wrong\n'
              '  同时把 kNativeAbiFingerprint 更新为 $digest');
      expect(digest, kNativeAbiFingerprint,
          reason: '指纹变了，请更新 kNativeAbiFingerprint 为 $digest');
    });

    test('新的用户可见错误必须走错误码，不能硬编码文案', () {
      final engine = File('lib/engine/core_engine.dart').readAsStringSync();
      for (final code in ['inject_failed', 'inject_partial']) {
        expect(engine.contains("code: '$code'"), isTrue,
            reason: '引擎应发 $code 而不是直接给文案');
      }
      // 两种语言都得有，否则英文环境会漏中文出去
      for (final key in ['engineInjectFailed', 'engineInjectPartial']) {
        for (final arb in ['lib/l10n/app_zh.arb', 'lib/l10n/app_en.arb']) {
          expect(File(arb).readAsStringSync().contains('"$key"'), isTrue,
              reason: '$arb 缺 $key');
        }
      }
    });
  });

  group('R39/R40 复制读取原子化与还原重试', () {
    test('复制与读取必须是同一次调用', () {
      // 拆成两次 FFI 的话有两个窗口会读到别的内容：native 观察到的
      // changeCount 变化未必来自我们的 Cmd+C；返回后到 Dart 读之间还可能再变。
      // 任一命中，送进 LLM 的就是无关内容甚至敏感信息。
      expect(code.contains('copy_selection_text'), isTrue,
          reason: '缺少「复制并返回文本」的原子入口');
      final engine = File('lib/engine/core_engine.dart').readAsStringSync();
      expect(engine.contains('Clipboard.getData'), isFalse,
          reason: '梳理路径不得再自己读剪贴板');
      expect(engine.contains('copySelectionText()'), isTrue);
      // 读的过程本身也要稳定：读前读后 changeCount 一致才认
      final body = stripComments(bodyOfFn('copy_selection_text'));
      expect(body.contains('pb.changeCount != before'), isTrue,
          reason: '读文本要做稳定读，否则读到的可能是读一半被换掉的内容');
    });

    test('还原重试不得在锁内做', () {
      // 三次 50ms 的等待占着 clipTxMutex 会把注入路径一起卡住 150ms。
      final finish = stripComments(bodyOfFn('tx_finish_locked'));
      expect(finish.contains('usleep'), isFalse,
          reason: '重试的等待跑到锁里去了');
      expect(finish.contains('retryItems'), isTrue,
          reason: '首次失败要把待重试内容交给锁外的调用方');
      final sched = stripComments(bodyOfFn('tx_schedule_finish'));
      expect(sched.contains('usleep(50000)'), isTrue, reason: '锁外没有重试');
      expect(sched.contains('_txActive'), isTrue,
          reason: '重写之前必须确认没有新事务开起来，否则会盖掉它的内容');
    });

    test('还原重试前必须核对外部有没有接管剪贴板', () {
      // clipTxMutex 管不到**别的进程**。50ms 等待里用户完全可能自己复制了东西，
      // 无条件 clearContents 会把它永久盖掉；而 writeObjects 首次失败本身
      // 往往就意味着 ownership 已经易主，这时候盲目重试风险更大。
      final sched = stripComments(bodyOfFn('tx_schedule_finish'));
      expect(sched.contains('pb.changeCount != retryExpected'), isTrue,
          reason: '重试前只查了「有没有新的内部事务」，管不到别的进程');
      final guardAt = sched.indexOf('pb.changeCount != retryExpected');
      final clearAt = sched.indexOf('[pb clearContents]');
      expect(guardAt, greaterThanOrEqualTo(0));
      expect(clearAt, greaterThan(guardAt), reason: '核对必须在 clearContents 之前');
    });

    test('读取必须锁死在归因到的那一版，不许重试到新版本', () {
      // 「读前读后一致」只证明读的这一瞬没被换。复制完成之后、我们读之前
      // 外部写了 Z 的话，循环下一轮会对 Z 做一次稳定读并把 Z 返回，
      // 而事务的 expected 仍指向 Cmd+C 那一版 —— Z 就这么被发给了 LLM。
      final body = stripComments(bodyOfFn('copy_selection_text'));
      expect(body.contains('before != observed'), isTrue,
          reason: '读到的版本必须正是 copy_selection 归因到的那一版');
      expect(body.contains('copy_selection_impl(&observed)'), isTrue,
          reason: '归因到的 changeCount 必须从复制函数传出来');
    });

    test('还原失败必须能被 Dart 发现，且所有录音路径都对账', () {
      expect(code.contains('clipboard_restore_failures'), isTrue,
          reason: '异步还原失败没有任何上报通道');
      final engine = File('lib/engine/core_engine.dart').readAsStringSync();
      // 必须在**录音开始**时对账：还原是注入之后 800ms 才发生的，
      // 放在注入末尾永远晚一拍；放这里 ptt/闪念/梳理都会经过。
      final reportAt = engine.indexOf('_reportClipboardRestoreFailures();');
      final permAt = engine.indexOf('// 1. PERMISSION CHECK');
      expect(reportAt, greaterThanOrEqualTo(0));
      expect(permAt, greaterThan(reportAt),
          reason: '对账要放在录音开始处，不能只挂在某一条注入分支上');
    });
  });

  group('线上事故：注入文字滞留剪贴板', () {
    test('所有权判据必须是我们自己写的 token', () {
      // 所有权判定必须集中在一处，且三条判据齐全。
      // token 不是访问控制：general pasteboard 对所有进程可读，
      // 别的进程能原样重放它 —— 所以 token 只是辅助，
      // 真正的 ownership 判据仍是 changeCount。
      //
      // 注：2026-08-16 那次线上故障的根因**至今未定案**，曾归因为
      // 「旁观者推高 changeCount」但探针证伪、已作废。这条断言守的是
      // 判据本身的正确性，不是那次故障的修复证明。
      // 三处必须走**同一个**判定函数，而不是各自拼判据 ——
      // 分散写正是上一轮「只改收尾那一处」的复发温床。
      for (final fn in ['tx_finish_locked', 'tx_paste_locked', 'copy_selection_impl']) {
        final body = stripComments(bodyOfFn(fn));
        expect(body.contains('tx_still_ours_locked'), isTrue,
            reason: '$fn 没有走统一的所有权判定');
      }
      // 判定本身三条缺一不可：
      //   changeCount —— Apple 文档里判断 ownership 是否还在自己手上的正规机制
      //   单 item     —— stringForType 会合并所有提供该 type 的 item
      //   token 匹配  —— 挡住「用户从别处复制到一模一样的文字」
      final judge = stripComments(bodyOfFn('tx_still_ours_locked'));
      expect(judge.contains('_txExpectedChangeCount'), isTrue,
          reason: 'changeCount 才是 ownership 的正规判据，不能丢');
      expect(judge.contains('pasteboardItems.count != 1'), isTrue,
          reason: 'stringForType 会合并所有 item，必须限定单 item');
      expect(judge.contains('_txToken'), isTrue);

      // token 写入必须检查并读回：写失败却把 _txToken 记下来的话，
      // 收尾时永远判成「不是我们的」，还原被**永久**跳过。
      final paste = stripComments(bodyOfFn('tx_paste_locked'));
      expect(paste.contains('![pb setString:tok forType:kSpeakOutOwnerType]'),
          isTrue,
          reason: 'token 写入的返回值必须检查');
      expect(paste.contains('token write failed'), isTrue,
          reason: 'token 写失败要能在日志里查到，且必须判为注入失败');
    });

    test('setString / writeObjects / Cmd+V 投递的失败都不得被吞', () {
      final paste = stripComments(bodyOfFn('tx_paste_locked'));
      expect(paste.contains('![pb setString:text'), isTrue,
          reason: 'setString 在 ownership 变化时会返回 false，必须看');
      expect(paste.contains('!post_command_key'), isTrue,
          reason: 'CGEvent 创建失败时不能照样报成功');
      final finish = stripComments(bodyOfFn('tx_finish_locked'));
      expect(finish.contains('[pb writeObjects:_txOriginal]'), isTrue);
      // 首次失败在锁内只交出待重试内容，最终失败的判定挪到了锁外的重试段
      expect(finish.contains('retryItems'), isTrue,
          reason: '还原写入失败必须被识别并交给锁外重试');
      final sched = stripComments(bodyOfFn('tx_schedule_finish'));
      expect(sched.contains('RESTORE WRITE FAILED'), isTrue,
          reason: '重试全败时剪贴板已被清空，不能记成 restored');
    });

    test('发 Cmd+V 之前必须确认剪贴板已生效', () {
      // 出货版是 usleep(10000) 然后直接发键 —— 纯猜的等待。
      // 跨进程 pasteboard 可见性没有时限保证，等不够就会把旧内容贴进用户文档。
      final body = bodyOfFn('tx_paste_locked');
      expect(stripComments(body).contains('usleep(10000)'), isFalse,
          reason: '不能靠固定等待，要校验');
      expect(body.contains('isEqualToString:text'), isTrue,
          reason: '必须读回来确认就是我们写的那份');
      final checkAt = body.indexOf('isEqualToString:text');
      final postAt = body.indexOf('post_command_key');
      expect(checkAt, lessThan(postAt), reason: '校验必须在发键之前');
    });

    test('注入失败必须能传回 Dart，不能静默', () {
      // 注入失败 = 用户刚口述的整段话没进输入框。静默吞掉的话，
      // 他只会对着没变化的界面发愣，还以为是识别没成功。
      expect(RegExp(r'int inject_text\(const char \*text\)').hasMatch(src), isTrue,
          reason: 'inject_text 必须返回成败，不能是 void');
      final dart = File('lib/engine/core_engine.dart').readAsStringSync();
      expect(dart.contains('注入失败'), isTrue,
          reason: 'CoreEngine 必须把注入失败暴露给用户');
    });
  });

  group('R36 快照拿不到就必须中止注入', () {
    test('snapshot_pasteboard 要区分「读取失败」和「本来就是空的」', () {
      // pasteboardItems 为 nil 按 Apple 说明也可能是读取出错。当成空的话，
      // 我们会拿一份「什么都没有」的快照去覆盖用户真实内容。
      final body = bodyOfFn('snapshot_pasteboard');
      expect(body.contains('oldContents == nil'), isTrue,
          reason: '必须把 nil 单独判成读取失败');
      expect(body.contains('return NO'), isTrue);
    });

    test('begin 拿不到快照必须返回 0，Dart 侧必须据此放弃流式注入', () {
      // 返回 void（或恒返回 1）的话：native 没开 hold，Dart 照样把会话计数 +1，
      // 打字机以为有 hold 罩着继续发 chunk，而每个 chunk 在 native 那边都是
      // 孤儿、各自安排收尾 —— 文字在 chunk 之间就被还原掉了。
      final body = bodyOfFn('inject_clipboard_begin');
      final abortAt = body.indexOf('begin aborted');
      expect(abortAt, greaterThanOrEqualTo(0), reason: '没找到中止分支');
      final after = body.substring(abortAt);
      expect(after.startsWith(RegExp(r'[^;]*;\s*\n\s*return 0;')), isTrue,
          reason: '中止分支必须 return 0，实测「仍返回 1」曾无断言覆盖');
      final dart = File('lib/engine/core_engine.dart').readAsStringSync();
      expect(dart.contains('if (!_clipBegin())'), isTrue,
          reason: 'Dart 侧必须检查 _clipBegin 的返回值');
    });

    test('三个注入入口在拿不到快照时都必须提前返回', () {
      // 「先照写、收尾时不还原」不是可用的失败策略 —— 那等于把用户剪贴板
      // 换成我们注入的文字并永久留在那里（口述内容还会泄漏在剪贴板里）。
      for (final fn in [
        'inject_via_clipboard',
        'inject_clipboard_begin',
        'inject_clipboard_chunk',
      ]) {
        final body = bodyOfFn(fn);
        expect(body.contains('if (!tx_begin_locked('), isTrue,
            reason: '$fn 没有检查快照是否拿到');
        final guardAt = body.indexOf('if (!tx_begin_locked(');
        final pasteAt = body.indexOf('tx_paste_locked');
        if (pasteAt >= 0) {
          expect(guardAt, lessThan(pasteAt),
              reason: '$fn 的检查必须在写剪贴板之前');
        }
      }
    });

    test('中途重拍失败返回 0，调用方不得安排收尾', () {
      final chunk = bodyOfFn('inject_clipboard_chunk');
      expect(chunk.contains('gen == 0'), isTrue,
          reason: 'chunk 没处理「没写成」的返回值');
      final oneShot = bodyOfFn('inject_via_clipboard');
      expect(oneShot.contains('gen != 0'), isTrue,
          reason: '一次性注入没处理「没写成」的返回值');
    });

    test('copy_selection 的基线必须取自稳定快照，不能重读', () {
      // 重读的话，重拍返回之后到读 before 之间用户又复制一次，
      // before 就把那次外部变更吸收了，我们的 Cmd+C 让 delta 恰好为 1 ——
      // 误判成纯内部变更，收尾把用户刚复制的内容覆盖掉。
      final body = bodyOfFn('copy_selection_impl');
      expect(body.contains('? _txExpectedChangeCount'), isTrue,
          reason: '事务活跃时 before 必须取自基线，不能重读 changeCount');
      // 放锁等待期间事务可能被别的线程换掉，重新取锁后必须逐项核对
      // 放锁 → 等待 → 重新取锁：中间事务可能被别的线程换掉。
      // 必须逐项核对并在不符时**放弃归因**，否则 expected 会倒退、
      // 凭空造出一个不存在的新代次。
      final code = stripComments(body);
      expect(code.contains('stateIntact'), isTrue, reason: '缺少 TOCTOU 核对');
      final checkAt = code.indexOf('!stateIntact');
      final noteAt = code.indexOf('tx_note_mutation_locked');
      expect(checkAt, greaterThanOrEqualTo(0), reason: '核对结果没有被使用');
      expect(noteAt, greaterThan(checkAt),
          reason: '必须先核对、不符就返回，之后才允许 note_mutation');
      // 五项缺一不可。漏掉 expected 曾经无人发现：另一次 copy_selection
      // 因 ownership 变化而重拍快照时，**只更新 expected，不推进 generation、
      // 不换 token** —— 只比其余四项的话这种交错会全部「成立」。
      for (final v in [
        '_txGeneration == genBefore',
        '_txActive == activeBefore',
        '_txOriginalValid == validBefore',
        '_txToken == tokenBefore',
        '_txExpectedChangeCount == expectedBefore',
        'pb.changeCount == observed',
      ]) {
        expect(code.contains(v), isTrue, reason: 'TOCTOU 核对漏了 $v');
      }
    });

    test('tap 日志必须先登记在途再复查开关', () {
      final body = bodyOfFn('log_from_tap');
      final addAt = body.indexOf('atomic_fetch_add_explicit(&tapLogInFlight');
      final gateAt = body.indexOf('atomic_load(&tapLogProducerEnabled)');
      expect(addAt, greaterThanOrEqualTo(0));
      expect(gateAt, greaterThanOrEqualTo(0));
      expect(addAt, lessThan(gateAt),
          reason: '顺序反了就还有窗口：读到 enabled 后被抢占，'
              '关闭方看到 inFlight=0 直接关掉，恢复后写的那条就丢了');
    });
  });

  group('R35 快照必须与 changeCount 同版本', () {
    test('拍快照与读 changeCount 之间不得留窗口', () {
      // 先拍快照再读 count，两步之间用户完全可能复制东西：
      //   X → 拍到 X → 用户复制 Z（count 变）→ expected 记成 Z 的 count
      //   → 之后写前检查看到「没易主」不重拍 → 收尾还原 X，Z 被覆盖。
      final body = bodyOfFn('tx_snapshot_stable_locked');
      expect(body.contains('const NSInteger before = pb.changeCount'), isTrue);
      expect(body.contains('const NSInteger after = pb.changeCount'), isTrue);
      expect(body.contains('if (before == after)'), isTrue,
          reason: '必须两次读一致才认这份快照');
    });

    test('所有拍快照的入口都走稳定版本', () {
      // tx_begin_locked 和写前重拍都不能直接调 snapshot_pasteboard
      for (final fn in ['tx_begin_locked', 'tx_paste_locked']) {
        final body = bodyOfFn(fn);
        expect(body.contains('_txOriginal = snapshot_pasteboard'), isFalse,
            reason: '$fn 直接拍了不稳定的快照');
      }
    });

    test('快照拍不稳时禁止还原', () {
      // 此时手里没有可信内容：clearContents 之后无内容可写等于清空用户剪贴板
      final finish = bodyOfFn('tx_finish_locked');
      expect(finish.contains('!_txOriginalValid'), isTrue,
          reason: '收尾必须先看快照可不可信');
    });

    test('copy_selection 发 Cmd+C 之前也要查易主', () {
      // delta == 1 只说明「观察到一次变化」，证明不了事务开始后没有先发生外部变化
      final body = bodyOfFn('copy_selection_impl');
      final checkAt = body.indexOf('tx_snapshot_stable_locked');
      final postAt = body.indexOf('post_command_key');
      expect(checkAt, greaterThanOrEqualTo(0), reason: '发 Cmd+C 前没查所有权');
      expect(postAt, greaterThanOrEqualTo(0));
      expect(checkAt, lessThan(postAt), reason: '检查必须在发 Cmd+C 之前');
    });

    test('关闭 verbose 必须等在途写者归零', () {
      // 停开关只挡新进入者：回调可能刚读到 enabled、正在 vsnprintf，
      // 排空看不到它，随后落盘也关了 —— 那条日志照样丢。
      final body = bodyOfFn('set_debug_logging');
      expect(body.contains('tapLogInFlight'), isTrue,
          reason: '缺少静默屏障，停开关不等于没有在途写者');
      final waitAt = body.indexOf('tapLogInFlight');
      final flushAt = body.indexOf('flush_tap_log_sync()');
      expect(waitAt, lessThan(flushAt), reason: '必须等在途归零之后再排空');
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
      final body = bodyOfFn('tx_begin_locked');
      expect(body.contains('tx_snapshot_stable_locked'), isTrue,
          reason: '事务开启时要拍稳定快照并记基线');
      // 基线本身在 helper 里落，确认它确实落了 —— 否则上一行只是在验「调了个函数」
      final helper = bodyOfFn('tx_snapshot_stable_locked');
      expect(helper.contains('_txExpectedChangeCount = after'), isTrue,
          reason: '基线必须取自与快照同版本的那次读，'
              '否则「我们没动过而用户动了」这种情形分不出来');
    });

    test('copy_selection 不得固定 sleep 后把「当前值」认作自己造成的', () {
      // 固定睡 100ms 的话，用户恰好在这窗口内自己复制了东西，那个值会被
      // 记成我们的变更，之后收尾就拿旧快照把他刚复制的内容覆盖掉。
      final body = bodyOfFn('copy_selection_impl');
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
      final body = bodyOfFn('microphone_permission_status');
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
      final body = bodyOfFn('smoothed_level_update');
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
      final body = bodyOfFn('log_from_tap');
      expect(body.contains('tapLogRead'), isTrue, reason: '写者没读游标，会覆盖未消费的槽');
      expect(body.contains('w - r >= TAP_LOG_SLOTS'), isTrue,
          reason: '环满时必须丢新的这条');
      expect(src.contains('static atomic_uint tapLogRead'), isTrue,
          reason: '读游标要跨线程可见，必须是原子量');
    });

    test('关闭 verbose 前必须先同步排空', () {
      // log_to_file 自己也受这个开关控制，先置零就会丢掉最后 200ms 那批 ——
      // 往往正是用户关开关前想看的那几行。
      final body = bodyOfFn('set_debug_logging');
      final flushAt = body.indexOf('flush_tap_log_sync()');
      final zeroAt = body.indexOf('atomic_store(&debugLoggingEnabled, 0)');
      expect(flushAt, greaterThanOrEqualTo(0), reason: '关闭路径没有排空');
      expect(zeroAt, greaterThanOrEqualTo(0));
      expect(flushAt, lessThan(zeroAt), reason: '必须先排空再置零');
    });
  });
}
