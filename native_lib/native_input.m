#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <pwd.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <Accelerate/Accelerate.h>

// Debug logging flag — disabled by default, enabled via set_debug_logging(1)
static atomic_int debugLoggingEnabled = 0;

// 生产者开关与「落盘是否启用」必须分开。合成一个的话，同步排空读完 write
// 游标之后、置零之前，tap 线程还能再发布一条 —— 那条会被下一轮 timer 读到，
// 但那时 log_to_file 已经因为 flag=0 直接返回，日志照样丢。
// 关闭顺序：先停生产者 → 同步排空（此时落盘仍开着）→ 再关落盘。
static atomic_int tapLogProducerEnabled = 0;
// 已经越过开关、还没发布记录的在途写者。只「停开关 + 同步排空」是不够的：
// 回调可能刚读到 enabled、正在 vsnprintf，此时排空看不到它，随后落盘也关了 ——
// 那条日志照样丢。关闭时要等这个计数归零，形成真正的静默屏障。
static atomic_uint tapLogInFlight = 0;
static void start_tap_log_drain(void);
static void flush_tap_log_sync(void);

// ABI 版本握手。
//
// C symbol 名里不带返回类型：Dart 按 Int32 去调一个还是 void 的旧
// `inject_text`，符号照样查得到，调用也不会崩 —— 返回寄存器里是**未定义残值**，
// 于是「注入成功了吗」变成掷骰子。正常 DMG/install 是整包替换不会混搭，
// 但手工替换、部分更新、加载路径残留都可能撞上。
//
// **版本号不是手动递增的整数，而是「导出签名指纹的前 6 位十六进制」。**
// 手动递增靠自觉，而我自己就漏过一次（把 inject_clipboard_begin 从 void 改成
// int 却没升版本，正好是这个握手要防的情形）。现在版本是签名的**函数**：
// 改了任何导出签名，指纹变、版本就必须跟着变，结构上不可能只改一半。
// 数值由 test/engine/native_batch5_invariants_test.dart 的指纹锁给出。
// 旧 dylib 没有这个 symbol，查找失败 → Dart 明确知道版本不匹配，
// 而不是悄悄读垃圾。
#define SPEAKOUT_NATIVE_ABI_VERSION 0xd80931
// 剪贴板还原最终失败的累计次数。还原发生在注入之后 800ms 的异步任务里，
// 没法用返回值告诉 Dart —— 只记日志的话，用户的剪贴板被清空了却毫不知情。
// Dart 侧在下一次注入时读一下这个计数，涨了就提示。
static atomic_uint clipboardRestoreFailures = 0;

// 剪贴板还原最终失败的累计次数（见 clipboardRestoreFailures 的说明）
unsigned clipboard_restore_failures(void) {
  return atomic_load_explicit(&clipboardRestoreFailures, memory_order_relaxed);
}

int native_input_abi_version(void) { return SPEAKOUT_NATIVE_ABI_VERSION; }

void set_debug_logging(int enabled) {
  if (enabled) {
    atomic_store(&debugLoggingEnabled, 1);
    atomic_store(&tapLogProducerEnabled, 1);
    start_tap_log_drain();
    return;
  }
  // 三步顺序不能乱：停生产者 → 排空 → 关落盘。
  // 少了第一步，排空读完游标后 tap 线程还能再写一条，那条必丢。
  atomic_store(&tapLogProducerEnabled, 0);
  // 等已登记的写者清空。配合上面「先登记再复查」，这里归零就意味着
  // 不会再有新记录发布 —— 是真正的静默屏障，不只是把窗口变小。
  //
  // 上限 ~10ms 是给调用线程（Dart UI isolate 同步 FFI）的保护：tap 回调里
  // 那段只是 vsnprintf，正常几微秒就出来。真的等不到，宁可丢一条调试日志，
  // 也不能把界面卡住。这条取舍写在这里，别当成「已经严格保证」。
  for (int i = 0; i < 1000; i++) {
    if (atomic_load_explicit(&tapLogInFlight, memory_order_acquire) == 0) break;
    usleep(10);
  }
  flush_tap_log_sync();
  atomic_store(&debugLoggingEnabled, 0);
  // 不撤 drain timer：撤销要跨线程同步 source 的生命周期，代价远大于
  // 200ms 空转一次的开销 —— 此时 ring 已无写入，handler 立刻返回。
}

// Log file path — defaults to ~/Downloads/speakout_native.log
// Override via set_log_directory()
static char logFilePath[1024] = {0};

void set_log_directory(const char *dir) {
  if (dir == NULL || dir[0] == 0) return;
  snprintf(logFilePath, sizeof(logFilePath), "%s/speakout_native.log", dir);
}

static char *get_log_path() {
  if (logFilePath[0] != 0) return logFilePath;
  // Default: ~/Library/Application Support/com.speakout.speakout/speakout_native.log
  // (与 Dart 层 AppLog 的 speakout.log 在同一目录)
  static char defaultPath[512] = {0};
  if (defaultPath[0] == 0) {
    const char *home = getenv("HOME");
    if (!home) {
      struct passwd *pw = getpwuid(getuid());
      home = pw ? pw->pw_dir : "/tmp";
    }
    snprintf(defaultPath, sizeof(defaultPath),
             "%s/Library/Application Support/com.speakout.speakout/speakout_native.log", home);
  }
  return defaultPath;
}

void log_to_file(const char *fmt, ...) {
  if (!atomic_load(&debugLoggingEnabled)) return;

  va_list args;
  va_start(args, fmt);
  va_list args_copy;
  va_copy(args_copy, args);

  FILE *f = fopen(get_log_path(), "a");
  if (f) {
    time_t now;
    time(&now);
    char buf[20];
    strftime(buf, sizeof(buf), "%H:%M:%S", localtime(&now));
    fprintf(f, "[%s] ", buf);
    vfprintf(f, fmt, args);
    fprintf(f, "\n");
    fclose(f);
  }

  NSString *formatStr = [[NSString alloc] initWithUTF8String:fmt];
  NSString *msg = [[NSString alloc] initWithFormat:formatStr arguments:args_copy];
  NSLog(@"[NativeInput] %@", msg);
  va_end(args_copy);
  va_end(args);
}

// --- CGEventTap 回调专用日志 ---
//
// **回调里绝不能调 log_to_file。** 它做 fopen / vfprintf / fclose / NSString
// 分配 / NSLog，全是同步阻塞操作，而这个回调跑在主 RunLoop 上、有系统时限：
// 磁盘忙或日志系统卡一下，系统就判定 tap 无响应并禁用它，快捷键随之失效。
// 打开 verbose 日志本来是为了排查别的问题，却把键盘监听搞挂 —— 因果完全错位。
//
// 单写者（tap 线程）/ 单读者（drain 队列）环形缓冲：回调侧只做一次栈上
// vsnprintf + 一个 release store，无堆分配、无系统调用；后台队列每 200ms
// 排空一次，真正的 I/O 在那边做。
//
// **写满时丢新的，绝不覆盖读者尚未取走的槽位。** 上一版是覆盖最旧的，
// 那不是「日志撕裂」这么轻 —— 读者正在 memcpy 某个槽、写者同时 vsnprintf
// 同一个 char[]，在 C 内存模型下就是数据竞争，是 UB。为此写者必须看得见
// 读游标，所以 tapLogRead 也是原子量。
#define TAP_LOG_SLOTS 256
#define TAP_LOG_LINE 192
static char tapLogRing[TAP_LOG_SLOTS][TAP_LOG_LINE];
static atomic_uint tapLogWrite = 0;
static atomic_uint tapLogRead = 0;
static atomic_uint tapLogDropped = 0;
static dispatch_source_t tapLogDrainTimer = nil;
static dispatch_queue_t tapLogQueue = nil;

__attribute__((format(printf, 1, 2))) static void log_from_tap(const char *fmt,
                                                               ...) {
  // **先登记再复查开关**，顺序反了就还有窗口：读到 enabled=1 之后被抢占，
  // 关闭方看到 inFlight=0 直接 flush 并关落盘，我们恢复后写的那条就永远丢了。
  atomic_fetch_add_explicit(&tapLogInFlight, 1, memory_order_acquire);
  if (!atomic_load(&tapLogProducerEnabled)) {
    atomic_fetch_sub_explicit(&tapLogInFlight, 1, memory_order_release);
    return;
  }
  const unsigned w = atomic_load_explicit(&tapLogWrite, memory_order_relaxed);
  const unsigned r = atomic_load_explicit(&tapLogRead, memory_order_acquire);
  if (w - r >= TAP_LOG_SLOTS) { // 环已满：丢这一条，别去踩读者手里的槽
    atomic_fetch_add_explicit(&tapLogDropped, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&tapLogInFlight, 1, memory_order_release);
    return;
  }
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(tapLogRing[w % TAP_LOG_SLOTS], TAP_LOG_LINE, fmt, ap);
  va_end(ap);
  atomic_store_explicit(&tapLogWrite, w + 1, memory_order_release);
  atomic_fetch_sub_explicit(&tapLogInFlight, 1, memory_order_release);
}

static void drain_tap_log(void) {
  const unsigned w = atomic_load_explicit(&tapLogWrite, memory_order_acquire);
  unsigned r = atomic_load_explicit(&tapLogRead, memory_order_relaxed);
  while (r != w) {
    log_to_file("%s", tapLogRing[r % TAP_LOG_SLOTS]);
    r++;
    // 逐条推进读游标：写者据此判断有没有空槽，攒到最后再发布会让它白等一轮
    atomic_store_explicit(&tapLogRead, r, memory_order_release);
  }
  const unsigned dropped =
      atomic_exchange_explicit(&tapLogDropped, 0, memory_order_relaxed);
  if (dropped > 0) {
    log_to_file("[tap-log] dropped %u lines (ring full)", dropped);
  }
}

static void start_tap_log_drain(void) {
  // dispatch_once：set_debug_logging 可能从不止一个线程进来，
  // 裸 `if (timer != nil)` 本身不是线程安全的
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    tapLogQueue = dispatch_queue_create("com.speakout.taplog", DISPATCH_QUEUE_SERIAL);
    tapLogDrainTimer =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, tapLogQueue);
    dispatch_source_set_timer(tapLogDrainTimer, DISPATCH_TIME_NOW,
                              200 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(tapLogDrainTimer, ^{
      drain_tap_log();
    });
    dispatch_resume(tapLogDrainTimer);
  });
}

// 关 verbose 前必须先把环里剩下的排空：log_to_file 自己也受这个开关控制，
// 先置零的话，最后 200ms 那批（往往正是用户关开关前想看的那几行）永远落不了盘。
static void flush_tap_log_sync(void) {
  if (tapLogQueue == nil) return;
  dispatch_sync(tapLogQueue, ^{
    drain_tap_log();
  });
}

// Callback function type defined in Dart (v2: added modifierFlags for combo key support)
typedef void (*DartKeyCallback)(int keyCode, bool isDown, unsigned int modifierFlags);

// Device-specific modifier masks (from IOKit/hidsystem/IOLLEvent.h)
#define NX_DEVICELCTLKEYMASK    0x00000001
#define NX_DEVICELSHIFTKEYMASK  0x00000002
#define NX_DEVICERSHIFTKEYMASK  0x00000004
#define NX_DEVICELCMDKEYMASK    0x00000008
#define NX_DEVICERCMDKEYMASK    0x00000010
#define NX_DEVICELALTKEYMASK    0x00000020
#define NX_DEVICERALTKEYMASK    0x00000040
#define NX_DEVICERCTLKEYMASK    0x00002000
// 真实键盘事件都带此位；合成事件漏了它，部分 App 会认不出组合键
#define NX_NONCOALSESCEDMASK    0x00000100

// 合成 Cmd+V 时各事件之间的间隔：连发会被系统合并（实测四个事件只有前两个到达）
#define INJECT_KEY_GAP_US 8000

// 自身合成事件的标记。注入时我们真的会按下 Command/字母键，这些事件同样会流经
// 本进程的 CGEventTap；若用户恰好把热键设成 Left Command 之类，就会被自己触发一次录音。
// 打上标记后回调里直接放行不处理。
#define SPEAKOUT_SYNTHETIC_MARK 0x53504B54  // 'SPKT'

// 粘贴后多久还原剪贴板。必须长于目标 App 真正读到剪贴板的耗时 ——
// Electron 应用走跨进程 IPC，比原生控件慢得多，还原太早会粘出旧内容。
#define CLIPBOARD_RESTORE_DELAY_MS 800

// Forward declaration
bool check_permission();

// Global Variables
static CFMachPortRef eventTap = NULL;
static CFRunLoopSourceRef runLoopSource = NULL;
static DartKeyCallback dartCallback = NULL;

// Active hotkey info
static int targetKeyCode = -1; // e.g., 58 for Option, etc.
static atomic_bool isMonitoring = false;

// macOS 26+: Globe/Fn key sends KeyDown/Up with keyCode=179 AND
// FlagsChanged with keyCode=63. Order is NOT guaranteed — either may arrive
// first. Use bidirectional timestamp dedup: whichever fires first wins,
// the second one within 100ms is suppressed.
static uint64_t lastGlobe179Time = 0;
static uint64_t lastFn63Time = 0;

// CGEventCallback
CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type,
                             CGEventRef event, void *refcon) {
  // 自己注入时合成的按键不参与热键判定，否则把热键设成 Command 的用户
  // 每次粘贴都会被自己触发一次录音
  if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) ==
      SPEAKOUT_SYNTHETIC_MARK) {
    return event;
  }

  // 两类禁用都必须重启，**不能只处理 Timeout**：
  // ByUserInput 之后不重启的话，此后所有快捷键事件都收不到 —— PTT / 闪念 /
  // 翻译全部静默失效，进程还活着、也不报错，用户只会觉得「快捷键坏了」。
  // 无条件重启是安全的：全仓 CGEventTapEnable 只有这里和 start 处，都传 true，
  // 没有「有意禁用」的路径会跟它打架。
  if (type == kCGEventTapDisabledByTimeout ||
      type == kCGEventTapDisabledByUserInput) {
    log_from_tap("EventTap disabled (%s). Re-enabling...",
                 type == kCGEventTapDisabledByTimeout ? "timeout" : "user input");
    if (eventTap) CGEventTapEnable(eventTap, true);
    return event;
  }

  if (!isMonitoring || dartCallback == NULL) {
    return event;
  }

  // Log specific keys to verify listener is ALIVE
  CGKeyCode keyCode =
      (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
  // Log every 10th event or specific keys (58=Option)
  if (keyCode == 58) {
    log_from_tap("Event: Key 58 (Option) Type: %d", type);
  }

  // Capture Key events
  if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
    // macOS 26+: Globe/Fn key sends KeyDown/Up with keyCode=179.
    // Map to legacy Fn keyCode 63 so Dart PTT matching works.
    int mappedKeyCode = (int)keyCode;
    if (keyCode == 179) {
      // Reverse dedup: if FlagsChanged 63 already fired within 100ms, suppress 179
      if (lastFn63Time > 0) {
        mach_timebase_info_data_t tbInfo;
        mach_timebase_info(&tbInfo);
        uint64_t elapsed = mach_absolute_time() - lastFn63Time;
        double elapsedMs = (double)elapsed * tbInfo.numer / tbInfo.denom / 1000000.0;
        if (elapsedMs < 100.0) {
          log_from_tap("Globe key 179: suppressed (FlagsChanged 63 was %.0fms ago)", elapsedMs);
          return event;
        }
      }
      lastGlobe179Time = mach_absolute_time();
      mappedKeyCode = 63;
      log_from_tap("Globe key 179 -> mapped to Fn 63 (%s)",
                  type == kCGEventKeyDown ? "DOWN" : "UP");
    }

    CGEventFlags flags = CGEventGetFlags(event);
    unsigned int devFlags = (unsigned int)(flags & 0xFFFF); // device-dependent bits
    uint64_t t0 = mach_absolute_time();
    dartCallback(mappedKeyCode, type == kCGEventKeyDown, devFlags);
    uint64_t t1 = mach_absolute_time();

    // Convert to milliseconds
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    double ms = (double)(t1 - t0) * info.numer / info.denom / 1000000.0;
    log_from_tap("Key %d %s: dartCallback took %.2f ms", mappedKeyCode,
                type == kCGEventKeyDown ? "DOWN" : "UP", ms);
  } else if (type == kCGEventFlagsChanged) {
    CGEventFlags flags = CGEventGetFlags(event);
    bool isDown = false;

    // Use device-specific masks to correctly distinguish left/right modifiers
    unsigned int devFlags = (unsigned int)(flags & 0xFFFF);

    // Option (Alt): 58 (Left), 61 (Right)
    if (keyCode == 58) {
      isDown = (devFlags & NX_DEVICELALTKEYMASK) != 0;
    } else if (keyCode == 61) {
      isDown = (devFlags & NX_DEVICERALTKEYMASK) != 0;
    }
    // Shift: 56 (Left), 60 (Right)
    else if (keyCode == 56) {
      isDown = (devFlags & NX_DEVICELSHIFTKEYMASK) != 0;
    } else if (keyCode == 60) {
      isDown = (devFlags & NX_DEVICERSHIFTKEYMASK) != 0;
    }
    // Control: 59 (Left), 62 (Right)
    else if (keyCode == 59) {
      isDown = (devFlags & NX_DEVICELCTLKEYMASK) != 0;
    } else if (keyCode == 62) {
      isDown = (devFlags & NX_DEVICERCTLKEYMASK) != 0;
    }
    // Command: 55 (Left), 54 (Right)
    else if (keyCode == 55) {
      isDown = (devFlags & NX_DEVICELCMDKEYMASK) != 0;
    } else if (keyCode == 54) {
      isDown = (devFlags & NX_DEVICERCMDKEYMASK) != 0;
    }
    // CapsLock: 57
    else if (keyCode == 57) {
      isDown = (flags & kCGEventFlagMaskAlphaShift) != 0;
    }
    // FN Key: keyCode=63 - use state tracking
    // On macOS 26+, Fn/Globe key also sends KeyDown/Up 179 with proper hold
    // timing. FlagsChanged 63 fires DOWN+UP nearly simultaneously. Use
    // timestamp dedup: if 179 fired within last 100ms, skip this event.
    else if (keyCode == 63) {
      if (lastGlobe179Time > 0) {
        mach_timebase_info_data_t tbInfo;
        mach_timebase_info(&tbInfo);
        uint64_t elapsed = mach_absolute_time() - lastGlobe179Time;
        double elapsedMs = (double)elapsed * tbInfo.numer / tbInfo.denom / 1000000.0;
        if (elapsedMs < 100.0) {
          log_from_tap("FN FlagsChanged 63: suppressed (Globe 179 was %.0fms ago)", elapsedMs);
          return event;
        }
      }
      // Fallback: no recent 179, handle FlagsChanged 63 directly
      static bool lastFnState = false;
      bool fnFlagSet = (flags & kCGEventFlagMaskSecondaryFn) != 0;
      if (fnFlagSet) {
        isDown = true;
        lastFnState = true;
      } else {
        if (lastFnState) {
          isDown = false;
          lastFnState = false;
        } else {
          isDown = true;
          lastFnState = true;
        }
      }
      lastFn63Time = mach_absolute_time();
      log_from_tap("FN Key 63 (legacy): flags=0x%llx, fnFlagSet=%d, isDown=%d",
                  (unsigned long long)flags, fnFlagSet, isDown);
    }

    if (keyCode == 58 || keyCode == 61) {
      log_from_tap("FlagsChanged: Key %d. IsDown: %d. devFlags: 0x%04x", keyCode, isDown, devFlags);
    }

    dartCallback((int)keyCode, isDown, devFlags);
  }

  return event;
}

// Exported Functions

// 1. Start Listening
// Returns 1 on success, -1 on failure.
int start_keyboard_listener(DartKeyCallback callback) {
  if (eventTap != NULL) {
    log_to_file("Start: EventTap already exists.");
    return 1; // Already running
  }

  dartCallback = callback;
  isMonitoring = true;

  log_to_file("Start: Requesting EventTap...");

  // Listen for KeyDown, KeyUp, AND FlagsChanged (Modifiers)
  CGEventMask eventMask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp) |
                          (1 << kCGEventFlagsChanged);

  // Use kCGHIDEventTap for highest priority
  // kCGEventTapOptionListenOnly: we only observe events, never modify/block them
  eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                              kCGEventTapOptionListenOnly, eventMask,
                              myCGEventCallback, NULL);

  if (!eventTap) {
    log_to_file("FATAL: Failed to create event tap! Security Check: %d",
                check_permission());
    return -1;
  }

  // Create the run loop source
  runLoopSource =
      CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);

  // Add to the Main RunLoop.
  // FLUTTER runs on the main thread, so CFRunLoopGetMain() is correct.
  CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
  CGEventTapEnable(eventTap, true);

  log_to_file("Start: Keyboard listener attached to RunLoop.");

  return 1; // Success
}

// 2. Stop Listening
void stop_keyboard_listener() {
  if (runLoopSource) {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource,
                          kCFRunLoopCommonModes);
    CFRelease(runLoopSource);
    runLoopSource = NULL;
  }
  if (eventTap) {
    CFRelease(eventTap);
    eventTap = NULL;
  }
  isMonitoring = false;
  dartCallback = NULL;
  printf("[Native] Keyboard listener stopped.\n");
}

// Memory safety for async audio callbacks
void native_free(void *ptr) {
  if (ptr)
    free(ptr);
}

// 3. Inject Text — Smart Detection
// Detects if the active app is a terminal emulator.
// Terminals: clipboard paste (Cmd+V), since CGEventKeyboardSetUnicodeString
//   is unreliable in terminal emulators (e.g. Ghostty garbles Unicode).
// Other apps: CGEvent keyboard injection (avoids touching clipboard).

// Check if the frontmost app is a known terminal emulator
static bool is_terminal_app(void) {
  @autoreleasepool {
    NSRunningApplication *frontApp =
        [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (frontApp == nil)
      return false;

    NSString *bundleId = frontApp.bundleIdentifier;
    if (bundleId == nil)
      return false;

    // Known terminal emulator bundle IDs
    NSArray *terminalBundleIds = @[
      @"com.mitchellh.ghostty",  // Ghostty
      @"com.googlecode.iterm2",  // iTerm2
      @"com.apple.Terminal",     // macOS Terminal
      @"io.alacritty",           // Alacritty
      @"dev.warp.Warp-Stable",   // Warp
      @"net.kovidgoyal.kitty",   // Kitty
      @"co.zeit.hyper",          // Hyper
      @"com.github.wez.wezterm", // WezTerm
    ];

    for (NSString *termId in terminalBundleIds) {
      if ([bundleId isEqualToString:termId]) {
        return true;
      }
    }
    return false;
  }
}

// Exported: let Dart check if frontmost app is a terminal
int check_is_terminal_app(void) {
  return is_terminal_app() ? 1 : 0;
}

// Inject via CGEvent keyboard events (works for most GUI apps)
// Uses kCGEventSourceStatePrivate to avoid conflicts with real HID events,
// and creates fresh CGEvent objects per chunk to prevent async post races.
static void inject_via_keyboard(const char *text) {
  CFStringRef cfStr =
      CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
  if (!cfStr)
    return;

  CFIndex totalLen = CFStringGetLength(cfStr);
  if (totalLen == 0) {
    CFRelease(cfStr);
    return;
  }

  CGEventSourceRef source =
      CGEventSourceCreate(kCGEventSourceStatePrivate);
  if (!source) {
    CFRelease(cfStr);
    return;
  }

// Chunk to avoid apps dropping events for large payloads.
// Ensure chunk boundaries don't split UTF-16 surrogate pairs.
#define INJECT_CHUNK_SIZE 50
  UniChar buffer[INJECT_CHUNK_SIZE];

  for (CFIndex i = 0; i < totalLen;) {
    CFIndex remaining = totalLen - i;
    CFIndex chunkLen =
        (remaining > INJECT_CHUNK_SIZE) ? INJECT_CHUNK_SIZE : remaining;

    // Prevent splitting a surrogate pair
    if (chunkLen < remaining) {
      CFStringGetCharacters(cfStr, CFRangeMake(i + chunkLen - 1, 1), buffer);
      if (CFStringIsSurrogateHighCharacter(buffer[0])) {
        chunkLen--; // Don't split the pair
      }
    }

    CFStringGetCharacters(cfStr, CFRangeMake(i, chunkLen), buffer);

    // Create fresh events per chunk — reusing events causes races with async CGEventPost
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);
    if (!keyDown || !keyUp) {
      if (keyDown) CFRelease(keyDown);
      if (keyUp) CFRelease(keyUp);
      break;
    }

    CGEventKeyboardSetUnicodeString(keyDown, chunkLen, buffer);
    CGEventKeyboardSetUnicodeString(keyUp, chunkLen, buffer);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);

    CFRelease(keyDown);
    CFRelease(keyUp);

    // Small delay between chunks to let the event queue drain
    if (i + chunkLen < totalLen) {
      usleep(3000); // 3ms
    }

    i += chunkLen;
  }

  CFRelease(source);
  CFRelease(cfStr);
}

// Inject via clipboard paste (Cmd+V) — for terminal emulators
// 合成「Command + 某键」。必须逐位复刻真实键盘事件，否则部分 App 认不出这是组合键。
//
// 曾经的写法是「只造目标键 + CGEventSetFlags(Command)」，在原生控件和 Chromium 里能用
// （它们只读高位 modifierFlags），但 Flutter 应用完全收不到 —— 它在框架层靠
// HardwareKeyboard 的按键状态判断组合键，而那个状态只由 Command 键自身的 down/up 维护。
// 三处缺失缺一不可：
//   a) 发送 Command 键本身的 down/up，不能只打 flags 标记
//   b) flags 补上低位设备相关位：左Command | 非合并 —— 真实按键都带着
//   c) 事件间留间隔，否则四个事件会被系统合并掉（实测只有前两个能到达）
// 返回是否**四个事件都成功构造并投递**。原先是 void：source 或任一事件
// 创建失败时静默返回，外层照样报告注入成功 —— 用户口述的话没进去，界面却显示就绪。
static BOOL post_command_key(CGKeyCode key, CGEventTapLocation tap) {
  CGEventSourceRef source =
      CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  if (!source) return NO;
  const CGEventFlags kCmdFlags =
      kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK | NX_NONCOALSESCEDMASK;
  CGEventRef cmdDown = CGEventCreateKeyboardEvent(source, 55, true);
  CGEventRef keyDown = CGEventCreateKeyboardEvent(source, key, true);
  CGEventRef keyUp = CGEventCreateKeyboardEvent(source, key, false);
  CGEventRef cmdUp = CGEventCreateKeyboardEvent(source, 55, false);
  const BOOL allCreated = (cmdDown && keyDown && keyUp && cmdUp);
  if (allCreated) {
    CGEventSetFlags(cmdDown, kCmdFlags);
    CGEventSetFlags(keyDown, kCmdFlags);
    CGEventSetFlags(keyUp, kCmdFlags);
    CGEventSetFlags(cmdUp, NX_NONCOALSESCEDMASK); // Command 已抬起
    CGEventRef marked[4] = {cmdDown, keyDown, keyUp, cmdUp};
    for (int i = 0; i < 4; i++) {
      CGEventSetIntegerValueField(marked[i], kCGEventSourceUserData,
                                  SPEAKOUT_SYNTHETIC_MARK);
    }
    CGEventPost(tap, cmdDown);
    usleep(INJECT_KEY_GAP_US);
    CGEventPost(tap, keyDown);
    usleep(INJECT_KEY_GAP_US);
    CGEventPost(tap, keyUp);
    usleep(INJECT_KEY_GAP_US);
    CGEventPost(tap, cmdUp);
  }
  if (cmdDown) CFRelease(cmdDown);
  if (keyDown) CFRelease(keyDown);
  if (keyUp) CFRelease(keyUp);
  if (cmdUp) CFRelease(cmdUp);
  CFRelease(source);
  if (!allCreated) log_to_file("post_command_key: CGEvent creation failed");
  return allCreated;
}

// 深拷贝当前剪贴板内容，供之后还原。
//
// 返回值区分**读取失败**和**剪贴板本来就是空的** —— 这两种不能混：
// `pasteboardItems` 为 nil 按 Apple 头文件说明既可能是空、也可能是读取出错，
// 当成空的话我们会拿一份「什么都没有」的快照去覆盖用户真实内容。
// 失败时 *out 不被赋值，调用方必须中止事务。
//
// **逐 type 取不到 data 不算失败。** 剪贴板里有 file promise 之类的延迟类型时，
// 某些 type 的 dataForType: 本来就会返回 nil。为此中止注入的话，
// 用户口述的文字直接丢失 —— 那比「还原时少一个冷门格式」严重得多。
// 这类缺失记为 lossy 并写日志，不影响主流程。
static BOOL snapshot_pasteboard(NSPasteboard *pasteboard, NSArray **out) {
  NSArray *oldContents = [pasteboard pasteboardItems];
  if (oldContents == nil) {
    log_to_file("Clipboard tx: pasteboardItems returned nil (read error)");
    return NO;
  }
  if (oldContents.count == 0) {
    *out = nil;
    return YES;
  }
  NSMutableArray *items = [NSMutableArray array];
  int lossy = 0;
  for (NSPasteboardItem *item in oldContents) {
    NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
    for (NSString *type in [item types]) {
      NSData *data = [item dataForType:type];
      if (data == nil) {
        lossy++;
        continue;
      }
      if (![copy setData:data forType:type]) lossy++;
    }
    [items addObject:copy];
  }
  if (lossy > 0) {
    log_to_file("Clipboard tx: snapshot lossy (%d types unavailable)", lossy);
  }
  *out = items;
  return YES;
}

// ============================================================================
// 剪贴板事务协调器 —— 一次性注入 / 流式注入 / Cmd+C 共用同一套状态
// ============================================================================
//
// **不能给两条注入路径各留一套快照。** 上一版就是这么写的（一次性用
// _txSavedItems，流式用 _savedClipboardItems），靠 Dart 侧的会话计数推断
// 两者不会交错 —— 但那个计数只合并流式会话，管不到普通 inject()，
// 更管不到 native 这边 800ms 的延迟还原窗口。可达路径：
//
//   剪贴板 X → 普通听写注入 A（事务存下 X，等 800ms）
//   → 800ms 内触发 AI 梳理：流式 begin 把 **A** 当成原始快照，Cmd+C 又改了
//     changeCount → 普通注入的还原任务认为剪贴板已易主，跳过还原 X
//   → 梳理结束时流式会话把 **A** 写回去
//   最终剪贴板是 A，X 永久丢失。反向顺序（流式 end 后 800ms 内普通注入）同理。
//
// 现在只有一套事务：
//   - 原始快照只在事务开启时拍一次，两条路径共用
//   - 每次我们改动剪贴板都推进代次，只有最后一代负责收尾
//   - _txExpectedChangeCount 记「如果只有我们动过，现在该是多少」，
//     对不上就说明用户自己复制了东西，不还原（否则会吃掉他刚复制的内容）
//   - 流式会话用 _txHoldDepth 挂起还原：会话期间不收尾，end 时才安排
//
// 互斥锁覆盖「快照 + clearContents/setString + 记代次」和
// 「校验 + 还原 + 清状态」两整段。只保护 bookkeeping 是不够的 ——
// 还原任务如果先清掉 pending 再去还原，中间插进来的注入会把已被污染的
// 剪贴板当成新事务的原始快照，用户内容照样丢。
static pthread_mutex_t clipTxMutex = PTHREAD_MUTEX_INITIALIZER;
static BOOL _txActive = NO;                  // 事务已开启（持有原始快照）
static NSArray *_txOriginal = nil;           // 事务开启前的剪贴板内容
static uint64_t _txGeneration = 0;           // 我们每改一次剪贴板就 +1
static NSInteger _txExpectedChangeCount = -1; // 只有我们动过的话，现在该是多少
static BOOL _txOriginalValid = NO;            // 快照是否可信（拍不稳时为 NO）
// 还原重试进行中。期间禁止开新事务 —— 剪贴板此刻是被 clearContents 清空的
// 状态，让新事务在这时拍快照，它会把「空」当成用户的原始内容。
static BOOL _txRestorePending = NO;
// 本次一次性注入是否失败。**整段 inject_text 都在 injectTextMutex 里跑**，
// 所以同一时刻只有一个 inject_text 在用它 —— 否则这个全局标志表达不了
// 「哪一次调用」的结果：A 失败后、A 读取前 B 把它重置，A 就会错报成功。
// 流式 chunk 也会置位，但流式调用方不读它，且被同一把锁挡在外面。
static pthread_mutex_t injectTextMutex = PTHREAD_MUTEX_INITIALIZER;
static BOOL _txPasteFailed = NO;
// 私有 pasteboard type：只用来放我们本次事务的 token。
// 目标 App 只读它认识的类型（纯文本等），多这一个自定义 UTI 对粘贴内容无影响。
static NSString *const kSpeakOutOwnerType = @"com.speakout.injection-token";
// 本次事务的 token。收尾时靠它判断「剪贴板还是不是我们放的」，
// 理由见 tx_finish_locked —— changeCount 和文本内容都是不可靠的代理量。
static NSString *_txToken = nil;

static int _txHoldDepth = 0;                 // 流式会话深度，>0 时挂起还原

// 以下 tx_* 全部要求调用方已持有 clipTxMutex。

// 拍一份**与 changeCount 同版本**的快照。
//
// 不能「先拍快照，再读 changeCount」—— 两步之间用户完全可能复制东西：
//   剪贴板 X → snapshot_pasteboard 拍到 X → 用户复制 Z（count 变）
//   → expected 记成 Z 的 count → 之后写前检查看到「没易主」，不重拍
//   → 收尾还原 X，Z 被永久覆盖。
// 读 count → 拍 → 再读 count，两次一致才算这份快照和这个 count 是同一版本。
// 返回 NO = 没拿到可信快照。调用方**必须在 clearContents 之前中止**：
// 「先照写、收尾时不还原」不是可用的失败策略 —— 那等于把用户剪贴板换成
// 我们注入的文字并永久留在那里（口述内容还会泄漏在剪贴板里）。
static BOOL tx_snapshot_stable_locked(NSPasteboard *pb) {
  for (int i = 0; i < 8; i++) {
    const NSInteger before = pb.changeCount;
    NSArray *snap = nil;
    if (!snapshot_pasteboard(pb, &snap)) break; // 读取出错，重试也无意义
    const NSInteger after = pb.changeCount;
    if (before == after) {
      _txOriginal = snap;
      _txOriginalValid = YES;
      _txExpectedChangeCount = after;
      return YES;
    }
  }
  log_to_file("Clipboard tx: snapshot failed, aborting injection");
  _txOriginal = nil;
  _txOriginalValid = NO;
  return NO;
}

// 返回 NO = 快照没拿到，事务未开启，调用方必须放弃这次注入
static BOOL tx_begin_locked(NSPasteboard *pb) {
  // 上一个事务的还原正在重试：此刻剪贴板是被 clearContents 清空的状态，
  // 现在拍快照会把「空」当成用户的原始内容，等于替旧事务把数据丢掉。
  if (_txRestorePending) {
    log_to_file("Clipboard tx: begin refused (restore retry pending)");
    return NO;
  }
  if (_txActive) return YES; // 已有事务在跑就沿用它的原始快照，绝不重拍
  if (!tx_snapshot_stable_locked(pb)) return NO;
  _txActive = YES;
  return YES;
}

static uint64_t tx_note_mutation_locked(NSInteger newChangeCount) {
  _txExpectedChangeCount = newChangeCount;
  return ++_txGeneration;
}

// 剪贴板是否仍归本事务所有。**三个条件缺一不可：**
//
// 1. `changeCount == _txExpectedChangeCount` —— 这是 Apple 文档里
//    判断 ownership 是否还在自己手上的**正规机制**。我一度想用 token 取代它，
//    那是过度反应：当时怀疑「旁观者会推高 changeCount」，探针已证伪。
// 2. 恰好一个 item —— `stringForType:` 会把**所有**提供该 type 的 item 合并，
//    别人往剪贴板里加一个 item 也可能读出同样的 token。
// 3. token 精确匹配 —— 挡住「用户从别处复制到一模一样的文字」，
//    那时 changeCount 也变了，但多一层不吃亏。
//
// ⚠️ token 不是访问控制：general pasteboard 对所有进程可读，
// 别的进程完全可以原样重放它。所以 token 只是**辅助**证据，
// 真正的 ownership 判据仍是 changeCount。
static BOOL tx_still_ours_locked(NSPasteboard *pb) {
  if (pb.changeCount != _txExpectedChangeCount) return NO;
  // _txToken 为 nil 有三种来源：刚 begin 还没写过、copy_selection 只复制没写
  // token、以及 token 写入失败。三种情况下文本要么不是我们写的、要么已由我们
  // 写入且 changeCount 仍等于 clearContents 的返回值 —— 按 Apple 的 ownership
  // 语义，此时仍算我们持有，可以还原。
  if (_txToken == nil) return YES;
  if (pb.pasteboardItems.count != 1) return NO;
  NSString *token = [pb stringForType:kSpeakOutOwnerType];
  return token != nil && [token isEqualToString:_txToken];
}

// `retryItems` 是出参：首次还原写入失败时，把待写回的内容交出去，
// 由调用方**在锁外**重试 —— 重试要 sleep，占着锁会把注入一起卡住。
// 事务开起来了但一个字都没写进剪贴板（写前重拍快照失败）时的收摊。
// 不清的话 _txActive 会一直挂着：它不像 pending 那样拒绝新注入，
// 但下一次注入会沿用这份已经不可信的事务状态，而且如果之后没有注入了，
// 这个标志就永远悬在那里。
static void tx_abandon_locked(void) {
  _txActive = NO;
  _txOriginal = nil;
  _txOriginalValid = NO;
  _txToken = nil;
  _txExpectedChangeCount = -1;
}

static void tx_finish_locked(NSPasteboard *pb, uint64_t gen,
                             NSArray **retryItems, NSInteger *retryExpected) {
  if (!_txActive) return;
  if (gen != _txGeneration) return; // 后面还有更新的改动，交给它收尾
  if (_txHoldDepth > 0) return;     // 流式会话还开着，等它 end
  // 所有权判定见 tx_still_ours_locked()：changeCount + 单 item + token，三条齐全。
  //
  // ⚠️ 别再想着「用 token 取代 changeCount」—— 我干过一次，是错的：
  // changeCount 才是 Apple 文档里判断 ownership 的正规机制，
  // 而 token 连访问控制都不是（general pasteboard 对所有进程可读，能被原样重放）。
  //
  // ⚠️ 2026-08-16 那次线上故障（注入 5 分钟后 Cmd+V 贴出识别结果）
  // **根因至今未定案**。本实现是健壮性改进，不是那次故障的已验证修复。
  // 详见 docs/debug-log/2026-08-16-paste-yields-previous-recognition.md。
  const BOOL stillOurs = tx_still_ours_locked(pb);
  if (!_txOriginalValid) {
    // 快照当时就没拍稳，还原等于拿不可信内容覆盖现状 —— 什么都不做
    log_to_file("Clipboard tx: skipped restore (snapshot was never stable)");
  } else if (stillOurs) {
    // **基线必须取 clearContents 的返回值**，不能在写失败之后重读
    // pb.changeCount：写失败的那一瞬间别的进程可能已经复制了东西，
    // 重读等于把「外部接管」当成我们自己的基线记下来 ——
    // 下一轮重试就会认为「还是我们的」，把用户刚复制的内容清掉。
    const NSInteger owned = [pb clearContents];
    if (_txOriginal.count == 0) {
      log_to_file("Clipboard tx: restored (original was empty)");
    } else if ([pb writeObjects:_txOriginal]) {
      log_to_file("Clipboard tx: restored");
    } else {
      // 首次写入失败。重试不能在锁里做（三次 50ms 会把注入卡住），
      // 但**事务状态不能就此清空** —— 此刻剪贴板已被 clearContents 清空，
      // 若让新事务在这时开起来，它会把「空剪贴板」拍成自己的原始快照，
      // 而我们的重试又会因为「有新事务」而放弃，用户内容就这么没了，
      // 连失败计数都不会涨。所以立一个 pending 标志把新事务挡在外面。
      *retryItems = _txOriginal;
      *retryExpected = owned;
      _txRestorePending = YES;
      log_to_file("Clipboard tx: restore write failed, retry pending");
    }
  } else {
    log_to_file("Clipboard tx: skipped restore (clipboard content is no longer ours)");
  }
  _txActive = NO;
  _txOriginal = nil;
  _txOriginalValid = NO;
  _txToken = nil;
  _txExpectedChangeCount = -1;
}

static void tx_schedule_finish(uint64_t gen) {
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, CLIPBOARD_RESTORE_DELAY_MS * NSEC_PER_MSEC),
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
          NSPasteboard *pb = [NSPasteboard generalPasteboard];
          NSArray *retryItems = nil;
          NSInteger retryExpected = -1;
          pthread_mutex_lock(&clipTxMutex);
          tx_finish_locked(pb, gen, &retryItems, &retryExpected);
          pthread_mutex_unlock(&clipTxMutex);

          if (retryItems == nil) return;
          // 只有 usleep 在锁外。**「核对 + clearContents + writeObjects +
          // 更新状态」必须在同一个临界区里**：分开做的话，核对通过之后、
          // 我们写之前，新注入可能已经把自己的文本写进去并准备粘贴，
          // 我们一 clear 一 write 就把它换成了旧快照，用户粘出来的是错的。
          BOOL recovered = NO;
          BOOL abandoned = NO;
          for (int i = 0; i < 3 && !recovered && !abandoned; i++) {
            usleep(50000);
            pthread_mutex_lock(&clipTxMutex);
            // clipTxMutex 管不到别的进程：这 50ms 里用户完全可能自己复制了
            // 东西，无条件 clearContents 会把它永久盖掉。而 writeObjects
            // 首次失败本身往往就意味着 ownership 已经易主。
            if (pb.changeCount != retryExpected) {
              log_to_file("Clipboard tx: restore retry aborted (clipboard taken over)");
              abandoned = YES;
            } else {
              retryExpected = [pb clearContents]; // 本轮的 ownership 基线
              recovered = [pb writeObjects:retryItems];
            }
            if (recovered || abandoned) {
              _txRestorePending = NO; // 出口统一在锁内解除
            }
            pthread_mutex_unlock(&clipTxMutex);
          }
          if (recovered) {
            log_to_file("Clipboard tx: restored after retry");
            return;
          }
          if (abandoned) return;

          // 三轮都没写进去。此刻剪贴板已被 clearContents 清空，
          // 用户的内容真的没了。计数让 Dart 侧能发现 —— 还原是异步的，
          // 没法用返回值告诉调用方，只记日志的话用户永远不知道。
          pthread_mutex_lock(&clipTxMutex);
          _txRestorePending = NO;
          pthread_mutex_unlock(&clipTxMutex);
          atomic_fetch_add_explicit(&clipboardRestoreFailures, 1,
                                    memory_order_relaxed);
          log_to_file("Clipboard tx: RESTORE WRITE FAILED, clipboard left empty");
        }
      });
}

// 把文本放上剪贴板并粘贴。锁一直持到 Cmd+V 发出为止 ——
// 中途放锁的话，另一次注入可以在我们粘贴之前改掉剪贴板，粘出来就是别的内容。
static uint64_t tx_paste_locked(NSPasteboard *pb, NSString *text) {
  // **每次内部写之前都要看剪贴板有没有易主。** 只在收尾时查是不够的 ——
  // 那只挡得住「最后一次内部写之后」的用户复制：
  //   X → chunk(A)（expected=A）→ 用户复制 Z → chunk(B) 把 Z 清掉、expected=B
  //   → 收尾看到 B==expected，还原 X。Z 永久丢失，而且用户毫无察觉。
  // 一旦发现易主，用户手里那份才是该还原的目标，旧快照已经过期，重新拍。
  // 写之前先确认剪贴板还是我们的，判据与收尾**共用同一个函数** ——
  // 只改收尾那一处是不够的：写前如果不查，就会把「我们自己刚注入的文字」
  // 重新拍成「用户的原始内容」，收尾再把它还原回去，注入文本照样滞留。
  if (!tx_still_ours_locked(pb)) {
    log_to_file("Clipboard tx: clipboard no longer ours mid-transaction, re-snapshot");
    if (!tx_snapshot_stable_locked(pb)) return 0; // 0 = 没写，调用方别安排收尾
  }
  NSInteger cc = [pb clearContents];
  // 无论后面粘不粘得成，剪贴板已经被我们改了，基线必须跟上 ——
  // 否则下一次写前检查会把「我们自己刚写进去的文字」当成用户的新内容重新拍快照。
  if (![pb setString:text forType:NSPasteboardTypeString]) {
    // setString 在 ownership 已经变化时会返回 false。忽略它就会白等 200ms
    // 才发现问题，而且分不清「没写进去」和「写进去了但没生效」。
    log_to_file("Clipboard tx: setString failed (ownership changed?)");
    return 0;
  }
  // token 先用局部变量：写成功**且读得回**才认，否则 _txToken 与剪贴板实际
  // 内容不符 —— 收尾时永远判成「不是我们的」，还原被永久跳过。
  NSString *tok = [[NSUUID UUID] UUIDString];
  if (![pb setString:tok forType:kSpeakOutOwnerType] ||
      ![tok isEqualToString:[pb stringForType:kSpeakOutOwnerType] ?: @""]) {
    log_to_file("Clipboard tx: token write failed, aborting paste");
    _txToken = nil;
    _txPasteFailed = YES;
    return tx_note_mutation_locked(cc); // 剪贴板已被我们改脏，仍要安排收尾
  }
  _txToken = tok;
  const uint64_t gen = tx_note_mutation_locked(cc);

  // 确认剪贴板里确实是我们写的那份，再发 Cmd+V。校验不过就不发 ——
  // 宁可这次注入失败（调用方会告知用户），也不能把别的内容贴进用户文档。
  //
  // **这个校验能证明什么、不能证明什么，必须说清楚：**
  // 它是在**我们自己的进程里**读回来比对。`setString:` 已经返回成功的前提下，
  // 这一读几乎必然立刻命中 —— 所以它**证明不了目标 App 那边看到了新内容**，
  // 跨进程 pasteboard 可见性依然没有保证。
  // 它真正挡住的是：`setString` 声称成功但内容并非我们写的那份
  // （例如紧接着有别的进程重新声明了剪贴板）。
  //
  // 换句话说：出货版那句 `usleep(10000)` 想解决的「跨进程传播竞态」，
  // 这里**并没有解决**，只是把「盲等 10ms」换成了「确认自己这边写对了」。
  // 要真正解决，需要目标进程的粘贴回执，而 macOS 没有提供这种机制。
  // 因为上面这条理由，这里**只读一次**，不轮询：同进程读回来要么立刻就对，
  // 要么就是真的被别人接管了 —— 再等 200ms 也等不出不一样的结果，
  // 徒然把持锁时间和 UI 阻塞拉长。
  // （上一版在这里轮询 40×5ms，那是按「等跨进程传播」设计的，
  //   而这个读根本不跨进程，等于白等。）
  NSString *now = [pb stringForType:NSPasteboardTypeString];
  const BOOL visible = (now != nil && [now isEqualToString:text]);
  if (!visible) {
    // 返回 gen 而不是 0：剪贴板已经被我们污染了，收尾任务必须照常安排，
    // 把用户原来的内容放回去。
    log_to_file("Clipboard tx: readback mismatch (taken over?), paste skipped");
    _txPasteFailed = YES;
    return gen;
  }

  if (!post_command_key(9, kCGHIDEventTap)) {
    log_to_file("Clipboard tx: Cmd+V post failed");
    _txPasteFailed = YES;
  }
  return gen;
}

static void inject_via_clipboard(const char *text) {
  @autoreleasepool {
    NSString *newText = [NSString stringWithUTF8String:text];
    if (newText == nil || newText.length == 0) {
      // 非法 UTF-8 也是一次失败。原先直接 return，_txPasteFailed 没置位，
      // inject_text 于是返回 1 —— 明明什么都没注入却报成功。
      pthread_mutex_lock(&clipTxMutex);
      _txPasteFailed = YES;
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: invalid UTF-8 text, nothing injected");
      return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    pthread_mutex_lock(&clipTxMutex);
    // 拿不到可信快照就**放弃这次注入**：照写下去等于把用户剪贴板换成
    // 我们的文字且再也换不回来（口述内容还会留在剪贴板里）。
    if (!tx_begin_locked(pasteboard)) {
      _txPasteFailed = YES;
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: inject aborted (no trustworthy snapshot)");
      return;
    }
    const uint64_t gen = tx_paste_locked(pasteboard, newText);
    if (gen == 0) {
      _txPasteFailed = YES; // 中途重拍失败，压根没写成
      if (_txHoldDepth == 0) tx_abandon_locked(); // 没 hold 罩着就别把事务挂那儿
    }
    log_to_file("Clipboard tx: inject len=%lu gen=%llu%s",
                (unsigned long)newText.length, (unsigned long long)gen,
                _txPasteFailed ? " FAILED" : "");
    pthread_mutex_unlock(&clipTxMutex);

    if (gen != 0) tx_schedule_finish(gen);
  }
}

// --- Streaming clipboard injection (for typewriter effect) ---
// begin 挂起还原，chunk 逐段粘贴，end 解除挂起并安排还原。

// 返回 1 = 会话已开启；0 = 快照拿不到，会话**没有**开启。
// **不能返回 void**：Dart 侧照样会把会话计数 +1，于是打字机以为有 hold 罩着，
// 每个 chunk 都变成孤儿、各自安排收尾，文字在 chunk 之间就被还原掉了。
int inject_clipboard_begin(void) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    pthread_mutex_lock(&clipTxMutex);
    // 会话状态必须是独立的深度计数，**不能**拿 _txOriginal 是否为 nil 代表：
    // 用户剪贴板本来就为空时快照就是 nil，那样 end 会误判成「无会话」直接返回，
    // 注入的语音文本永久留在剪贴板里（既违反恢复契约，也是口述内容泄漏）。
    if (!tx_begin_locked(pb)) {
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: begin aborted (no trustworthy snapshot)");
      return 0;
    }
    _txHoldDepth++;
    log_to_file("Clipboard tx: hold++ (depth=%d, saved %lu items)", _txHoldDepth,
                (unsigned long)(_txOriginal ? _txOriginal.count : 0));
    pthread_mutex_unlock(&clipTxMutex);
    return 1;
  }
}

// 返回 1 = 这段 chunk 已发出粘贴；0 = 没有。
// **不能继续返回 void**：chunk 静默失败时 Dart 仍会把整段流式注入算成功，
// 既不回退也不提示，用户口述的话就这么没了。
int inject_clipboard_chunk(const char *text) {
  if (text == NULL || text[0] == '\0')
    return 0;

  @autoreleasepool {
    NSString *newText = [NSString stringWithUTF8String:text];
    if (newText == nil || newText.length == 0)
      return 0;

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    pthread_mutex_lock(&clipTxMutex);
    _txPasteFailed = NO; // 只反映这一段 chunk 的结果
    if (!tx_begin_locked(pb)) { // 没走 begin 也能兜住
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: chunk aborted (no trustworthy snapshot)");
      return 0;
    }
    const uint64_t gen = tx_paste_locked(pb, newText);
    if (gen == 0) { // 中途重拍失败，没写成，别安排收尾
      if (_txHoldDepth == 0) tx_abandon_locked(); // 孤儿 chunk：别留悬挂事务
      pthread_mutex_unlock(&clipTxMutex);
      return 0;
    }
    const BOOL pasted = !_txPasteFailed;
    const BOOL orphan = (_txHoldDepth == 0);
    pthread_mutex_unlock(&clipTxMutex);
    // 节奏等待放在**锁外**：它只是给目标 App 留出粘贴时间，
    // 跟事务状态无关，没必要让还原任务陪着一起等 30ms。
    usleep(30000); // 30ms for paste to complete before next chunk

    // **推进了代次就必须有人收尾。** 没有 hold 罩着的 chunk（比如 end 之后
    // 迟到的那一条）会把代次推到 gen+1，让先前安排的收尾任务因代次不符而
    // 早退，自己却不安排新任务 —— 事务从此挂着不放，_txActive 永为 YES，
    // 之后每次注入都沿用一份很旧的快照。
    if (orphan) tx_schedule_finish(gen);
    return pasted ? 1 : 0;
  }
}

void inject_clipboard_end(void) {
  @autoreleasepool {
    pthread_mutex_lock(&clipTxMutex);
    // 没有进行中的会话就直接返回：下面的还原是无条件 clearContents，
    // 无会话状态下再走一遍等于把用户剪贴板清空。
    // Dart 侧已用会话计数堵住重复调用，这里再兜一层，防别的调用方绕过。
    if (_txHoldDepth == 0) {
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: end ignored (no active session)");
      return;
    }
    _txHoldDepth--;
    if (_txHoldDepth > 0 || !_txActive) {
      pthread_mutex_unlock(&clipTxMutex);
      return;
    }
    const uint64_t gen = _txGeneration;
    pthread_mutex_unlock(&clipTxMutex);

    tx_schedule_finish(gen);
  }
}

// --- AI 梳理辅助函数 ---

// 模拟 Cmd+C 复制选中文字到剪贴板
// 返回 1 = 剪贴板确实因为我们的 Cmd+C 变了；0 = 没有（事件没造出来、
// 目标 App 没响应、或期间还有别人动过）。
// **不能返回 void**：Cmd+C 没生效时 Dart 会把**旧剪贴板内容**当成用户选中的
// 文字发给 LLM —— 那可能是完全无关、甚至敏感的内容。
// `outObserved` 出参：归因成功时写回「我们认定属于本次 Cmd+C 的那个
// changeCount」。copy_selection_text 用它锁死读取版本 —— 只有读到的正是
// 那一版才算数，读到更新的版本一律失败，不许「重试到新版本」。
static int copy_selection_impl(NSInteger *outObserved) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    pthread_mutex_lock(&clipTxMutex);
    // **发 Cmd+C 之前也要查易主。** delta == 1 只能说明「观察到一次变化」，
    // 证明不了事务开始之后没有先发生过外部变化：
    //   begin 在 X 上开事务 → 用户复制 Z → copy_selection 读到 Z 的 count
    //   → Cmd+C 复制出 Y，delta 恰好是 1 → 记成内部变更
    //   → 收尾还原 X，Z 被覆盖。
    if (_txActive && !tx_still_ours_locked(pb)) {
      log_to_file("Clipboard tx: clipboard no longer ours before copy_selection, re-snapshot");
      tx_snapshot_stable_locked(pb); // 失败也继续：这里只是复制，不覆盖剪贴板
    }
    // **基线必须取自稳定快照那一刻，不能在这里重读。** 重读的话，重拍返回之后
    // 到这一行之间用户又复制一次（count 变 c+1），before 就把那次外部变更吸收了，
    // 随后我们的 Cmd+C 让 delta 恰好等于 1 —— 误判成纯内部变更，
    // 收尾把用户刚复制的内容覆盖掉。
    const NSInteger before =
        (_txActive && _txOriginalValid) ? _txExpectedChangeCount : pb.changeCount;
    if (!post_command_key(8, kCGAnnotatedSessionEventTap)) { // 8 = 'c'
      pthread_mutex_unlock(&clipTxMutex);
      log_to_file("Clipboard tx: Cmd+C post failed");
      return 0;
    }

    // **不能固定睡 100ms 再把「当前值」认作自己造成的变更。** 用户恰好在这
    // 100ms 内自己复制了东西的话，那个值会被记成我们的，之后收尾就会拿旧快照
    // 把他刚复制的内容覆盖掉。改成轮询等自己的 Cmd+C 落地，拿到就走 ——
    // 之后用户再复制，changeCount 就对不上，还原会被正确跳过。
    // **等待放在锁外。** 这一等最长 250ms，占着 clipTxMutex 等的话，
    // 还原任务和别的注入都被陪绑 —— 而我们等的只是目标 App 响应 Cmd+C，
    // 跟事务状态无关。锁在这里放掉，拿到结果后再重新取。
    //
    // 放锁 = 事务状态可能被别的线程改掉，所以把这一刻的状态全部拍下来，
    // 重新取锁后逐项核对。不核对的话就是 TOCTOU：别人推进了代次、
    // 换了 token / expected，我们却拿放锁前的 before 去 note_mutation，
    // 让 expected 倒退、凭空造出一个不存在的「新代次」。
    const uint64_t genBefore = _txGeneration;
    const BOOL activeBefore = _txActive;
    const BOOL validBefore = _txOriginalValid;
    NSString *tokenBefore = _txToken;
    // expected 也要拍：另一次 copy_selection 因 ownership 变化而重拍快照时，
    // **只更新 expected，不推进 generation、不换 token** —— 只比那三项的话，
    // 这种交错会全部「成立」，我们却拿着过期的 before 去归因。
    const NSInteger expectedBefore = _txExpectedChangeCount;
    pthread_mutex_unlock(&clipTxMutex);
    NSInteger observed = before;
    for (int i = 0; i < 50; i++) { // 最多 250ms：目标 App 卡顿时 100ms 常常不够
      usleep(5000);
      observed = pb.changeCount;
      if (observed != before) break;
    }
    pthread_mutex_lock(&clipTxMutex);

    // 逐项核对放锁期间事务有没有被换过；换过就放弃本轮归因 ——
    // 硬记进去只会污染别人的事务。
    const BOOL stateIntact = (_txGeneration == genBefore) &&
                             (_txActive == activeBefore) &&
                             (_txOriginalValid == validBefore) &&
                             (_txToken == tokenBefore) &&
                             (_txExpectedChangeCount == expectedBefore) &&
                             (pb.changeCount == observed);
    if (!stateIntact) {
      log_to_file("Clipboard tx: tx changed during copy_selection wait, skip attribution");
      pthread_mutex_unlock(&clipTxMutex);
      return 0;
    }

    // **必须恰好变了一次才算我们的。** changeCount 每次 clearContents/declareTypes
    // 加一，所以增量 > 1 说明这段时间里还有别人动过剪贴板 —— 此时把当前值
    // 记成「我们造成的」，收尾就会拿旧快照把用户刚复制的内容盖掉。
    const NSInteger delta = observed - before;
    BOOL orphan = NO;
    uint64_t gen = 0;
    if (_txActive && delta == 1) {
      gen = tx_note_mutation_locked(observed);
      orphan = (_txHoldDepth == 0);
    } else if (delta > 1) {
      log_to_file("Clipboard tx: copy_selection saw %ld changes, treating as external",
                  (long)delta);
    } else if (delta == 0) {
      // 我们的 Cmd+C 250ms 内没落地。它可能稍后才生效，届时 changeCount 与
      // expected 对不上，收尾会跳过还原 —— 结果是剪贴板留着这份复制内容，
      // 而不是用户原来的。分不出来，就宁可不动（还原反而可能盖掉用户的东西）。
      log_to_file("Clipboard tx: copy_selection timed out waiting for clipboard");
    }
    const BOOL copied = (delta == 1);
    if (copied && outObserved != NULL) *outObserved = observed;
    pthread_mutex_unlock(&clipTxMutex);
    if (orphan) tx_schedule_finish(gen);
    return copied ? 1 : 0;
  }
}

// 复制选中文字**并把它直接返回**，调用方用 native_free 释放。
// 失败返回 NULL。
//
// **为什么不能沿用「copy_selection() 然后 Dart 自己读剪贴板」：**
// 那是两次独立的 FFI，中间有两个窗口都会读到别的东西：
//   1. native 只证明「观察到一次 changeCount 变化」，证明不了那次变化
//      就是我们的 Cmd+C 造成的；
//   2. native 返回后 Dart 还固定等 150ms 才读，这段时间里剪贴板可能又被改了。
// 两个窗口任一命中，送进 LLM 的就是无关内容 —— 甚至是用户剪贴板里的敏感信息。
//
// 这里把「发 Cmd+C → 等变化 → 读文本」收进同一次调用，并把读取**锁死在
// copy_selection 归因到的那一版**上。
//
// ⚠️ **仍然证明不了「那次变化就是我们的 Cmd+C 造成的」。**
// changeCount 只说明 ownership 变过，说不出是谁变的：Cmd+C 还没被目标 App
// 处理、而别的进程恰好写了一次时，delta 同样是 1，我们会把它误当成选中文字。
// 要拿到确定性来源只能走 Accessibility 的选中文本属性（AXSelectedText），
// 那是另一条路，尚未实现。这里只关闭了「复制之后又被改」的窗口，
// 没有、也无法用 changeCount 关闭「第一次变化来源不明」的窗口。
const char *copy_selection_text(void) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSInteger observed = -1;
    if (copy_selection_impl(&observed) != 1) return NULL;

    // **锁死版本：只接受 copy_selection 归因到的那一版。**
    // 上一版这里是「读前读后一致就行」，那只证明「读的这一瞬没被换」——
    // 复制完成之后、我们读之前外部写了 Z 的话，循环下一轮会对 Z 做一次
    // 稳定读并把 Z 返回，而事务的 expected 仍指向 Cmd+C 那一版。
    // 现在读到的版本对不上就直接失败，**不许重试到新版本**。
    for (int i = 0; i < 8; i++) {
      const NSInteger before = pb.changeCount;
      if (before != observed) {
        log_to_file("Clipboard tx: clipboard moved past the copied version, abort");
        return NULL;
      }
      NSString *text = [pb stringForType:NSPasteboardTypeString];
      if (pb.changeCount != before) continue; // 读的过程中被换了，重来
      if (text == nil) return NULL;
      const char *utf8 = [text UTF8String];
      if (utf8 == NULL) return NULL;
      char *copy = strdup(utf8);
      return copy; // Dart 侧负责 native_free
    }
    log_to_file("Clipboard tx: copy_selection_text unstable read");
    return NULL;
  }
}

// 模拟任意按键（用于 → 取消选区、Return 换行等）
// 返回 1 = 按键已投递。AI 梳理靠它移动光标/换行，构造失败却不上报的话，
// 结果会插到错误位置、甚至覆盖用户原来的选区。
int press_key(int keyCode, int modifierFlags) {
  @autoreleasepool {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return 0;
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, (CGKeyCode)keyCode, true);
    CGEventRef keyUp   = CGEventCreateKeyboardEvent(source, (CGKeyCode)keyCode, false);
    if (keyDown && keyUp) {
      CGEventSetIntegerValueField(keyDown, kCGEventSourceUserData,
                                  SPEAKOUT_SYNTHETIC_MARK);
      CGEventSetIntegerValueField(keyUp, kCGEventSourceUserData,
                                  SPEAKOUT_SYNTHETIC_MARK);
      if (modifierFlags) {
        CGEventSetFlags(keyDown, (CGEventFlags)modifierFlags);
        CGEventSetFlags(keyUp,   (CGEventFlags)modifierFlags);
      }
      CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
      CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
    }
    const BOOL ok = (keyDown != NULL && keyUp != NULL);
    if (keyDown) CFRelease(keyDown);
    if (keyUp) CFRelease(keyUp);
    CFRelease(source);
    return ok ? 1 : 0;
  }
}

// --- AI 报告辅助函数 ---

// 激活指定 bundleId 的 App（切换到前台）
int activate_app(const char *bundleId) {
  if (bundleId == NULL || bundleId[0] == '\0') return 0;
  @autoreleasepool {
    NSString *bid = [NSString stringWithUTF8String:bundleId];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bid];
    if (apps.count == 0) return 0;
    NSRunningApplication *app = apps[0];
    // 先取消隐藏
    if (app.isHidden) [app unhide];
    BOOL ok = NO;
    // macOS 14+: 使用 activateFromApplication:options: (调用方作为发起者)
    if (@available(macOS 14.0, *)) {
      NSRunningApplication *selfApp = [NSRunningApplication currentApplication];
      ok = [app activateFromApplication:selfApp options:0];
    }
    // 回退: 旧 API
    if (!ok) {
      #pragma clang diagnostic push
      #pragma clang diagnostic ignored "-Wdeprecated-declarations"
      ok = [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      #pragma clang diagnostic pop
    }
    // 兜底: 通过 NSWorkspace 打开 (总是能激活)
    if (!ok) {
      NSURL *url = [app bundleURL];
      if (url) {
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
                                             configuration:[NSWorkspaceOpenConfiguration configuration]
                                         completionHandler:nil];
        ok = YES;
      }
    }
    return ok ? 1 : 0;
  }
}

// 获取当前前台 App 信息，返回 JSON: {"bundleId":"...","name":"...","windowTitle":"..."}
// 调用者需要 free() 返回的指针
const char *get_frontmost_app_info(void) {
  @autoreleasepool {
    NSRunningApplication *frontApp =
        [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (frontApp == nil) return strdup("{}");

    NSString *bid = frontApp.bundleIdentifier ?: @"";
    NSString *name = frontApp.localizedName ?: @"";

    // 获取前台窗口标题 (CGWindowList)
    NSString *windowTitle = @"";
    pid_t pid = frontApp.processIdentifier;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (windowList) {
      for (CFIndex i = 0; i < CFArrayGetCount(windowList); i++) {
        NSDictionary *info = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);
        NSNumber *ownerPID = info[(__bridge NSString *)kCGWindowOwnerPID];
        if (ownerPID && [ownerPID intValue] == pid) {
          NSString *title = info[(__bridge NSString *)kCGWindowName];
          if (title && title.length > 0) {
            windowTitle = title;
            break; // 取第一个有标题的窗口
          }
        }
      }
      CFRelease(windowList);
    }

    // 转义 JSON 中的引号和反斜杠
    windowTitle = [windowTitle stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    windowTitle = [windowTitle stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    name = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    NSString *json = [NSString stringWithFormat:@"{\"bundleId\":\"%@\",\"name\":\"%@\",\"windowTitle\":\"%@\"}", bid, name, windowTitle];
    return strdup([json UTF8String]);
  }
}

// Main entry: always use clipboard paste for reliability.
// CGEvent keyboard injection drops characters in apps with heavy UI (WeChat, Slack, etc.)
// due to async HID event queue. Clipboard paste is 100% reliable.
// 返回 1 = 已发出粘贴；0 = 没注入（快照拿不到，或剪贴板没生效所以放弃了 Cmd+V）。
// **不能继续返回 void 静默吞掉**：注入失败时用户口述的整段话就没了，
// 他需要知道这一次没成，而不是对着没有变化的输入框发愣。
int inject_text(const char *text) {
  if (text == NULL || text[0] == '\0')
    return 0;

  // 把「重置 → 注入 → 读结果」整段串起来，否则并发调用会互相吃掉对方的结果
  pthread_mutex_lock(&injectTextMutex);

  pthread_mutex_lock(&clipTxMutex);
  _txPasteFailed = NO;
  pthread_mutex_unlock(&clipTxMutex);

  inject_via_clipboard(text);

  pthread_mutex_lock(&clipTxMutex);
  const BOOL failed = _txPasteFailed;
  pthread_mutex_unlock(&clipTxMutex);

  pthread_mutex_unlock(&injectTextMutex);
  return failed ? 0 : 1;
}

// 4. Check Permission (with prompt dialog)
bool check_permission() {
  // Obj-C syntax for permission check dictionary
  NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
  bool trusted =
      AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  return trusted;
}

// 4b. Check Permission silently (no prompt - for refresh button)
bool check_permission_silent() {
  NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @NO};
  bool trusted =
      AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  return trusted;
}

// 4c. Check Input Monitoring permission (macOS 10.15+)
// Uses CGPreflightListenEventAccess() for precise detection
int check_input_monitoring_permission() {
  if (@available(macOS 10.15, *)) {
    return CGPreflightListenEventAccess() ? 1 : 0;
  }
  return 1; // Pre-10.15: no separate input monitoring permission
}

// 4d. Check Accessibility permission
// AXIsProcessTrusted() is the canonical check for Accessibility.
// CGPreflightPostEventAccess() can lag behind on macOS 26+.
int check_accessibility_permission() {
  return AXIsProcessTrusted() ? 1 : 0;
}

// 3. Check Key State (Watchdog)
// Returns 1 if key is physically down, 0 if up.
//
// Modifier keys (Option/Shift/Control/Command/Fn/CapsLock) are NOT reliable
// via CGEventSourceKeyState — it often returns false while the key is held.
// Use CGEventSourceFlagsState + device-specific masks instead, matching the
// logic in the FlagsChanged handler above so Left/Right are distinguished.
int check_key_pressed(int keyCode) {
  switch (keyCode) {
    case 58: case 61:   // Option (L / R)
    case 56: case 60:   // Shift  (L / R)
    case 59: case 62:   // Control (L / R)
    case 55: case 54:   // Command (L / R)
    case 57:            // CapsLock
    case 63: {          // Fn
      CGEventFlags flags = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
      unsigned int devFlags = (unsigned int)(flags & 0xFFFF);
      switch (keyCode) {
        case 58: return (devFlags & NX_DEVICELALTKEYMASK)   ? 1 : 0;
        case 61: return (devFlags & NX_DEVICERALTKEYMASK)   ? 1 : 0;
        case 56: return (devFlags & NX_DEVICELSHIFTKEYMASK) ? 1 : 0;
        case 60: return (devFlags & NX_DEVICERSHIFTKEYMASK) ? 1 : 0;
        case 59: return (devFlags & NX_DEVICELCTLKEYMASK)   ? 1 : 0;
        case 62: return (devFlags & NX_DEVICERCTLKEYMASK)   ? 1 : 0;
        case 55: return (devFlags & NX_DEVICELCMDKEYMASK)   ? 1 : 0;
        case 54: return (devFlags & NX_DEVICERCMDKEYMASK)   ? 1 : 0;
        case 57: return (flags & kCGEventFlagMaskAlphaShift)  ? 1 : 0;
        case 63: return (flags & kCGEventFlagMaskSecondaryFn) ? 1 : 0;
      }
      return 0;
    }
    default:
      // Normal keys: CGEventSourceKeyState is reliable
      return CGEventSourceKeyState(kCGEventSourceStateHIDSystemState,
                                   (CGKeyCode)keyCode) ? 1 : 0;
  }
}

// ============================================================================
// AUDIO RECORDING via AudioQueue + Ring Buffer
// CoreAudio writes to C ring buffer; Dart polls via read_audio_buffer().
// This eliminates SIGABRT from stale Dart FFI trampoline metadata.
// ============================================================================

#define NUM_BUFFERS 10
#define BUFFER_DURATION_MS 100 // 100ms per buffer = 1600 samples @ 16kHz

// Ring buffer: 60 seconds of 16kHz mono Int16 = 960000 samples (~1.8MB)
// Transfer buffer between AudioQueue callback and Dart polling.
// Polling every 100ms keeps it well under capacity; 60s provides ample margin.
#define RING_BUFFER_SAMPLES 960000

// Audio Recording State
static char preferredDeviceUID[256] = {0};
static char builtInDeviceUID[256] = {0};
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[NUM_BUFFERS];
static atomic_bool isRecording = false;
static AudioStreamBasicDescription audioFormat;

// Lock-free ring buffer (single producer / single consumer)
static int16_t ringBuffer[RING_BUFFER_SAMPLES];
static _Atomic uint64_t ringWritePos = 0; // monotonically increasing write cursor
static _Atomic uint64_t ringReadPos = 0;  // monotonically increasing read cursor
// 录音起点游标：start_audio_recording 时记录当前 wp。
// save_recording_wav 用它而不是 ringReadPos 算起点，
// 否则 ASR 流式消费 ring buffer 后 ringReadPos 已经追上 wp，保存的 WAV 只剩残尾。
static _Atomic uint64_t recordingStartPos = 0;

// ---- Real-time Audio Level for Waveform Visualization ----
// RMS of latest samples → single 0.0~1.0 value for UI to scale random animation.

// Smoothed level with fast attack / slow decay (VU meter style)
//
// 状态用原子位模式保存、衰减按**经过的时间**算，两个原因都成立：
//
// 1. 三个调用方分布在两个线程上 —— Dart UI isolate（main.dart 的波形、
//    core_engine 的静音检测）和 AppKit 主线程（AppDelegate 的 80ms Timer，
//    通过 dlopen 拿到同一个 dylib 里的同一个静态量）。Flutter 的 UI task
//    runner 与 platform task runner 本来就是两个线程，普通 float 的
//    读改写在 C 内存模型下是数据竞争。
// 2. 比竞争更早暴露的是：**原实现的衰减速度跟着调用次数走**。
//    「每调一次乘 0.88」是按「80ms 一个轮询器」设计的，实际有三个轮询器，
//    衰减就快约三倍 —— 波形掉得比设计快，静音检测也跟着提前触发。
//    改成按 elapsed 算 keep 系数后，结果与谁在轮询、轮询多密都无关。
// **用一把锁，不要拆成两个原子量。** 上一版把 level 和时间戳分别放进两个
// atomic，看着无锁，实际提交不了一个一致状态：
//   T1 CAS 成功写了 bits，在写 stamp 前被抢占
//   → T2 读到「新 bits + 旧 stamp」，把已经算过的那段衰减又算一遍
//   → T1 恢复后把 stamp 写回更早的值，时间倒退，下一次再重复衰减一遍
// 更糟的一种交错会让 now < oldStamp，无符号相减下溢成天文数字，
// keep≈0，电平瞬间塌到当前输入 —— 正好是这次要修掉的那类异常下降。
// 这个函数每秒只调几十次，一把 mutex 的代价可以忽略。
static pthread_mutex_t levelMutex = PTHREAD_MUTEX_INITIALIZER;
static float smoothedLevel = 0.0f;
static uint64_t smoothedLevelStamp = 0;

// 新录音开始时复位：停止录音时 get_audio_level 直接返回 0 且不更新状态，
// 上一段以高电平收尾、几百毫秒后又开一段的话，新会话的第一批低音量样本
// 会接着旧的高电平往下衰减 —— 波形虚高，静音判定也跟着延后。
static void smoothed_level_reset(void) {
  pthread_mutex_lock(&levelMutex);
  smoothedLevel = 0.0f;
  smoothedLevelStamp = mach_absolute_time();
  pthread_mutex_unlock(&levelMutex);
}

static float smoothed_level_update(float level) {
  const uint64_t now = mach_absolute_time();
  mach_timebase_info_data_t tb;
  mach_timebase_info(&tb);

  pthread_mutex_lock(&levelMutex);
  if (level >= smoothedLevel) {
    smoothedLevel = level; // instant rise
  } else {
    // now < stamp 只可能来自异常时钟，钳成 0 —— 无符号相减一旦下溢，
    // keep 会算成 0，电平直接塌到当前输入。
    const uint64_t delta = now > smoothedLevelStamp ? now - smoothedLevelStamp : 0;
    const double ms = (double)delta * tb.numer / tb.denom / 1000000.0;
    // 原系数 0.88 的语义是「每 80ms 保留 88%」，这里把它还原成时间函数
    const double keep = pow(0.88, ms / 80.0);
    smoothedLevel = (float)(smoothedLevel * keep + level * (1.0 - keep));
  }
  smoothedLevelStamp = now;
  const float result = smoothedLevel;
  pthread_mutex_unlock(&levelMutex);
  return result;
}

// Exported: returns current RMS audio level (0.0 = silence, 1.0 = loud).
// Dart/Swift polls this every ~80ms.
float get_audio_level(void) {
    if (!atomic_load(&isRecording)) return 0.0f;

    uint64_t wp = atomic_load_explicit(&ringWritePos, memory_order_acquire);
    // Use ~10ms of samples (160 @ 16kHz) for responsive level
    const int windowSize = 160;
    if (wp < (uint64_t)windowSize) return 0.0f;

    // Compute RMS
    double sumSq = 0;
    uint64_t startPos = wp - windowSize;
    for (int i = 0; i < windowSize; i++) {
        float s = (float)ringBuffer[(startPos + i) % RING_BUFFER_SAMPLES] / 32768.0f;
        sumSq += s * s;
    }
    float rms = sqrtf((float)(sumSq / windowSize));

    // Aggressive mapping: any speech → quickly ramp to full.
    // 15dB window: whisper already near half, normal speech maxed.
    // RMS 0.002 (-54dB) → 0.0 (noise floor)
    // RMS 0.005 (-46dB) → ~0.5
    // RMS 0.01+ (-40dB) → 1.0 (quiet speech already maxed)
    if (rms < 0.002f) return 0.0f;  // noise floor cutoff
    float db = 20.0f * log10f(rms);
    float level = (db + 54.0f) / 14.0f;  // [-54dB, -40dB] → [0, 1]
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;

    // Asymmetric smoothing: instant attack, ~500ms decay (half-life ~460ms)
    return smoothed_level_update(level);
}

// Legacy stub — kept for ABI compatibility if old code still links it.
void get_audio_spectrum(float *outBands, int count) {
    if (!outBands || count <= 0) return;
    float level = get_audio_level();
    int n = count < 7 ? count : 7;
    for (int i = 0; i < n; i++) outBands[i] = level;
}

// AudioQueue Input Callback — runs on CoreAudio's AQClient thread.
// IMPORTANT: This function NEVER calls Dart. It only writes to the ring buffer.
static void AudioInputCallback(
    void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer,
    const AudioTimeStamp *inStartTime, UInt32 inNumberPacketDescriptions,
    const AudioStreamPacketDescription *inPacketDescs) {
  if (!atomic_load(&isRecording)) {
    return;
  }

  UInt32 byteSize = inBuffer->mAudioDataByteSize;
  int sampleCount = byteSize / sizeof(int16_t);
  const int16_t *samples = (const int16_t *)inBuffer->mAudioData;

  // Write samples into ring buffer (wrap around using modulo)
  uint64_t wp = atomic_load_explicit(&ringWritePos, memory_order_relaxed);
  for (int i = 0; i < sampleCount; i++) {
    ringBuffer[wp % RING_BUFFER_SAMPLES] = samples[i];
    wp++;
  }
  // Release barrier: ensure all buffer writes are visible before advancing cursor
  atomic_store_explicit(&ringWritePos, wp, memory_order_release);

  // Re-enqueue buffer immediately for next capture
  if (atomic_load(&isRecording)) {
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
  }
}

/// Returns the number of unread samples available in the ring buffer.
int get_available_audio_samples() {
  uint64_t wp = atomic_load_explicit(&ringWritePos, memory_order_acquire);
  uint64_t rp = atomic_load_explicit(&ringReadPos, memory_order_relaxed);
  int64_t avail = (int64_t)(wp - rp);
  if (avail < 0)
    avail = 0;
  // Cap to ring buffer size to prevent reading stale wrapped data
  if (avail > RING_BUFFER_SAMPLES) {
    // Reader fell behind; skip to latest data minus a small margin
    uint64_t newRp = wp - RING_BUFFER_SAMPLES + 1600;
    atomic_store_explicit(&ringReadPos, newRp, memory_order_relaxed);
    avail = (int64_t)(wp - newRp);
  }
  return (int)avail;
}

/// Read samples from the ring buffer into the provided output buffer.
/// Returns the number of samples actually read.
/// Caller must allocate `outSamples` with at least `maxSamples` capacity.
int read_audio_buffer(int16_t *outSamples, int maxSamples) {
  if (outSamples == NULL || maxSamples <= 0)
    return 0;

  int avail = get_available_audio_samples();
  if (avail <= 0)
    return 0;

  int toRead = avail < maxSamples ? avail : maxSamples;

  uint64_t rp = atomic_load_explicit(&ringReadPos, memory_order_relaxed);
  for (int i = 0; i < toRead; i++) {
    outSamples[i] = ringBuffer[rp % RING_BUFFER_SAMPLES];
    rp++;
  }
  atomic_store_explicit(&ringReadPos, rp, memory_order_relaxed);

  return toRead;
}

// Start Audio Recording (no Dart callback needed)
// Returns 1 on success, negative on error
int start_audio_recording() {
  if (atomic_load(&isRecording)) {
    log_to_file("Audio: Already recording");
    return 1;
  }

  // 波形/静音检测的平滑状态也要复位，否则上一段的高电平会被这一段继承
  smoothed_level_reset();

  // Reset ring buffer cursors
  atomic_store_explicit(&ringWritePos, 0, memory_order_relaxed);
  atomic_store_explicit(&ringReadPos, 0, memory_order_relaxed);
  atomic_store_explicit(&recordingStartPos, 0, memory_order_relaxed);

  // Configure audio format: 16kHz, Mono, 16-bit signed integer
  memset(&audioFormat, 0, sizeof(audioFormat));
  audioFormat.mSampleRate = 16000.0;
  audioFormat.mFormatID = kAudioFormatLinearPCM;
  audioFormat.mFormatFlags =
      kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  audioFormat.mBitsPerChannel = 16;
  audioFormat.mChannelsPerFrame = 1;
  audioFormat.mBytesPerFrame = 2; // 16-bit mono = 2 bytes
  audioFormat.mFramesPerPacket = 1;
  audioFormat.mBytesPerPacket = 2;

  // Create AudioQueue for Input
  OSStatus status = AudioQueueNewInput(&audioFormat, AudioInputCallback,
                                       NULL, // user data
                                       NULL, // background thread
                                       NULL, // runloop mode
                                       0, &audioQueue);

  if (status != noErr) {
    log_to_file("Audio: Failed to create AudioQueue, status=%d", (int)status);
    return -2;
  }

  // Set preferred input device if specified (non-empty and not "system")
  if (preferredDeviceUID[0] != 0 &&
      strcmp(preferredDeviceUID, "system") != 0) {
    CFStringRef uid = CFStringCreateWithCString(NULL, preferredDeviceUID,
                                                 kCFStringEncodingUTF8);
    if (uid) {
      OSStatus devStatus = AudioQueueSetProperty(
          audioQueue, kAudioQueueProperty_CurrentDevice, &uid, sizeof(uid));
      if (devStatus != noErr) {
        log_to_file("Audio: Failed to set preferred device '%s', status=%d — falling back to system default",
                     preferredDeviceUID, (int)devStatus);
        // Clear preferred device so we don't keep failing
        preferredDeviceUID[0] = 0;
      } else {
        log_to_file("Audio: Using preferred device '%s'", preferredDeviceUID);
      }
      CFRelease(uid);
    }
  }

  // Calculate buffer size for 100ms of audio
  UInt32 bufferByteSize =
      (UInt32)(audioFormat.mSampleRate * BUFFER_DURATION_MS / 1000.0 *
               audioFormat.mBytesPerFrame);

  // Allocate and enqueue buffers
  for (int i = 0; i < NUM_BUFFERS; i++) {
    status =
        AudioQueueAllocateBuffer(audioQueue, bufferByteSize, &audioBuffers[i]);
    if (status != noErr) {
      log_to_file("Audio: Failed to allocate buffer %d, status=%d", i,
                  (int)status);
      AudioQueueDispose(audioQueue, true);
      audioQueue = NULL;
      return -3;
    }
    AudioQueueEnqueueBuffer(audioQueue, audioBuffers[i], 0, NULL);
  }

  // Start recording
  status = AudioQueueStart(audioQueue, NULL);
  if (status != noErr) {
    log_to_file("Audio: Failed to start AudioQueue, status=%d", (int)status);
    AudioQueueDispose(audioQueue, true);
    audioQueue = NULL;
    return -4;
  }

  atomic_store(&isRecording, true);
  log_to_file("Audio: Recording started (16kHz, Mono, Int16, RingBuffer)");
  return 1;
}

// Stop Audio Recording
void stop_audio_recording() {
  if (!atomic_load(&isRecording) || audioQueue == NULL) {
    return;
  }

  atomic_store(&isRecording, false);

  // Stop and dispose queue (synchronous)
  AudioQueueStop(audioQueue, true);
  AudioQueueDispose(audioQueue, true);
  audioQueue = NULL;

  log_to_file("Audio: Recording stopped");
}

/// Save the current ring buffer contents to a WAV file (16kHz mono 16-bit PCM).
/// Called from Dart when developer mode is on, before ring buffer is reset.
/// Returns 1 on success, 0 on failure.
int save_recording_wav(const char *path) {
  if (path == NULL || path[0] == '\0') return 0;

  uint64_t wp = atomic_load_explicit(&ringWritePos, memory_order_relaxed);
  uint64_t startPos = atomic_load_explicit(&recordingStartPos, memory_order_relaxed);
  if (wp <= startPos) return 0; // no data

  uint64_t sampleCount = wp - startPos;
  // Ring buffer 容量限制：录音超过 60s 时只能保存最新 60s（旧数据已被覆盖）
  if (sampleCount > RING_BUFFER_SAMPLES) {
    sampleCount = RING_BUFFER_SAMPLES;
    startPos = wp - RING_BUFFER_SAMPLES;
  }

  uint32_t dataSize = (uint32_t)(sampleCount * 2); // 16-bit = 2 bytes per sample
  uint32_t fileSize = 44 + dataSize;

  FILE *f = fopen(path, "wb");
  if (!f) return 0;

  // WAV header
  uint16_t numChannels = 1;
  uint32_t sampleRate = 16000;
  uint16_t bitsPerSample = 16;
  uint32_t byteRate = sampleRate * numChannels * bitsPerSample / 8;
  uint16_t blockAlign = numChannels * bitsPerSample / 8;
  uint32_t chunkSize = fileSize - 8;
  uint32_t subchunk1Size = 16;
  uint16_t audioFormat = 1; // PCM

  fwrite("RIFF", 1, 4, f);
  fwrite(&chunkSize, 4, 1, f);
  fwrite("WAVE", 1, 4, f);
  fwrite("fmt ", 1, 4, f);
  fwrite(&subchunk1Size, 4, 1, f);
  fwrite(&audioFormat, 2, 1, f);
  fwrite(&numChannels, 2, 1, f);
  fwrite(&sampleRate, 4, 1, f);
  fwrite(&byteRate, 4, 1, f);
  fwrite(&blockAlign, 2, 1, f);
  fwrite(&bitsPerSample, 2, 1, f);
  fwrite("data", 1, 4, f);
  fwrite(&dataSize, 4, 1, f);

  // PCM data from ring buffer (startPos 已在上面计算好)
  for (uint64_t i = 0; i < sampleCount; i++) {
    int16_t sample = ringBuffer[(startPos + i) % RING_BUFFER_SAMPLES];
    fwrite(&sample, 2, 1, f);
  }

  fclose(f);
  log_to_file("Audio: Saved recording to %s (%llu samples, %.1fs)", path, sampleCount, (double)sampleCount / 16000.0);
  return 1;
}

// Check if currently recording
int is_audio_recording() { return isRecording ? 1 : 0; }

// Check Screen Recording permission (macOS 10.15+, public API in CGWindow.h)
// AI Debug 需要此权限以读取其他 app 窗口标题 (kCGWindowName)
// 只读检查，不触发系统弹窗
int check_screen_recording_permission(void) {
  return CGPreflightScreenCaptureAccess() ? 1 : 0;
}

// Check microphone permission (macOS 10.14+)
// 返回当前授权状态，与 AVAuthorizationStatus 取值一致：
// 0=notDetermined 1=restricted 2=denied 3=authorized。
// **只查询，绝不弹窗、绝不阻塞。**
int microphone_permission_status(void) {
  if (@available(macOS 10.14, *)) {
    return (int)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
  }
  return 3; // Pre-10.14 doesn't require permission
}

// 仅在 notDetermined 时弹系统授权框，**立即返回**，结果靠随后轮询 status 拿。
void request_microphone_permission(void) {
  if (@available(macOS 10.14, *)) {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] !=
        AVAuthorizationStatusNotDetermined) {
      return;
    }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                             completionHandler:^(BOOL granted){
                                 // 结果由调用方轮询 microphone_permission_status 获取
                             }];
  }
}

// 之前这里是「同步 FFI 等一个要人点的 UI」，两个缺陷叠在一起：
//   1. 等 5 秒就返回。用户读一眼提示、切个窗口再点「允许」就超时，
//      而此时函数返回初值 0 = 拒绝，这次录音被判无权限直接中止 ——
//      用户明明点了允许，却被告知没权限。
//   2. `__block int result` 由 completion block 在任意线程写、超时后由调用
//      线程读，无任何同步，是实打实的数据竞争。
// 更根本的是：调用它的是 UI isolate（onboarding 的 _checkPermissions），
// 阻塞 5 秒等于界面冻 5 秒。所以改成非阻塞查询 + 独立的异步请求，
// 两个缺陷一起消失。
int check_microphone_permission() {
  return microphone_permission_status() == 3 ? 1 : 0;
}

// ============================================================================
// AUDIO DEVICE MANAGEMENT
// ============================================================================

// Device change callback type
typedef void (*DartDeviceChangeCallback)(const char *deviceId,
                                         const char *deviceName,
                                         int isBluetooth);
static DartDeviceChangeCallback deviceChangeCallback = NULL;

// 保护 deviceChangeCallback 的读取-调用与清空。
// 没有它的话：listener proc 把指针存进局部变量后，还要做 4 次 CoreAudio 查询
// （毫秒级）才真正调用，而 AudioObjectRemovePropertyListener 不等待在途回调 ——
// stop 返回后 Dart 侧 close() 释放 trampoline，那次在途调用就是 use-after-free。
// 加锁后 stop_device_change_listener() 返回即保证：没有回调在途，也不会再有新的。
static pthread_mutex_t deviceChangeCallbackMutex = PTHREAD_MUTEX_INITIALIZER;

// (moved to top of audio section for forward reference)

// Get string property from audio device
static NSString *getDeviceStringProperty(AudioObjectID deviceID,
                                         AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress propAddr = {selector,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain};

  CFStringRef value = NULL;
  UInt32 size = sizeof(CFStringRef);

  OSStatus status =
      AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, &value);
  if (status != noErr || value == NULL) {
    return nil;
  }

  NSString *result = (__bridge_transfer NSString *)value;
  return result;
}

// Get transport type of device
static UInt32 getDeviceTransportType(AudioObjectID deviceID) {
  AudioObjectPropertyAddress propAddr = {kAudioDevicePropertyTransportType,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain};

  UInt32 transportType = 0;
  UInt32 size = sizeof(UInt32);

  AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size,
                             &transportType);
  return transportType;
}

// Check if device is Bluetooth
static bool isBluetoothDevice(AudioObjectID deviceID) {
  UInt32 transport = getDeviceTransportType(deviceID);
  // 'blue' = 0x626C7565 = Bluetooth
  // 'blth' = 0x626C7468 = Bluetooth Low Energy (some devices)
  return (transport == kAudioDeviceTransportTypeBluetooth ||
          transport == 'blth');
}

// Check if device is built-in
static bool isBuiltInDevice(AudioObjectID deviceID) {
  UInt32 transport = getDeviceTransportType(deviceID);
  return (transport == kAudioDeviceTransportTypeBuiltIn);
}

// Check if device has input capability
static bool hasInputCapability(AudioObjectID deviceID) {
  AudioObjectPropertyAddress propAddr = {
      kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput,
      kAudioObjectPropertyElementMain};

  UInt32 size = 0;
  OSStatus status =
      AudioObjectGetPropertyDataSize(deviceID, &propAddr, 0, NULL, &size);
  if (status != noErr || size == 0) {
    return false;
  }

  AudioBufferList *bufferList = (AudioBufferList *)malloc(size);
  status = AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size,
                                      bufferList);

  bool hasInput = false;
  if (status == noErr && bufferList->mNumberBuffers > 0) {
    for (UInt32 i = 0; i < bufferList->mNumberBuffers; i++) {
      if (bufferList->mBuffers[i].mNumberChannels > 0) {
        hasInput = true;
        break;
      }
    }
  }

  free(bufferList);
  return hasInput;
}

// Get device sample rate
static Float64 getDeviceSampleRate(AudioObjectID deviceID) {
  AudioObjectPropertyAddress propAddr = {kAudioDevicePropertyNominalSampleRate,
                                         kAudioDevicePropertyScopeInput,
                                         kAudioObjectPropertyElementMain};

  Float64 sampleRate = 0;
  UInt32 size = sizeof(Float64);
  AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, &sampleRate);
  return sampleRate;
}

// Get all input devices
// Returns JSON string: [{"id":"...", "name":"...", "isBluetooth":true,
// "isBuiltIn":false, "sampleRate":48000}, ...]
const char *get_audio_input_devices() {
  static char jsonBuffer[8192];
  memset(jsonBuffer, 0, sizeof(jsonBuffer));

  AudioObjectPropertyAddress propAddr = {kAudioHardwarePropertyDevices,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain};

  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                   &propAddr, 0, NULL, &size);
  if (status != noErr) {
    strcpy(jsonBuffer, "[]");
    return jsonBuffer;
  }

  int deviceCount = size / sizeof(AudioObjectID);
  AudioObjectID *devices = (AudioObjectID *)malloc(size);
  status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0,
                                      NULL, &size, devices);

  if (status != noErr) {
    free(devices);
    strcpy(jsonBuffer, "[]");
    return jsonBuffer;
  }

  NSMutableArray *deviceArray = [NSMutableArray array];

  for (int i = 0; i < deviceCount; i++) {
    AudioObjectID deviceID = devices[i];

    // Only include input devices
    if (!hasInputCapability(deviceID)) {
      continue;
    }

    NSString *uid =
        getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
    NSString *name = getDeviceStringProperty(
        deviceID, kAudioDevicePropertyDeviceNameCFString);

    if (uid == nil || name == nil) {
      continue;
    }

    bool bluetooth = isBluetoothDevice(deviceID);
    bool builtIn = isBuiltInDevice(deviceID);
    Float64 sampleRate = getDeviceSampleRate(deviceID);

    // Store built-in device UID for quick access
    if (builtIn && builtInDeviceUID[0] == 0) {
      strncpy(builtInDeviceUID, [uid UTF8String], sizeof(builtInDeviceUID) - 1);
      log_to_file("AudioDevice: Found built-in mic: %s", [name UTF8String]);
    }

    NSDictionary *deviceDict = @{
      @"id" : uid,
      @"name" : name,
      @"isBluetooth" : @(bluetooth),
      @"isBuiltIn" : @(builtIn),
      @"sampleRate" : @(sampleRate)
    };
    [deviceArray addObject:deviceDict];
  }

  free(devices);

  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:deviceArray
                                                     options:0
                                                       error:&error];
  if (jsonData) {
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData
                                              encoding:NSUTF8StringEncoding];
    strncpy(jsonBuffer, [jsonStr UTF8String], sizeof(jsonBuffer) - 1);
  } else {
    strcpy(jsonBuffer, "[]");
  }

  return jsonBuffer;
}

// Get current default input device info
// Returns JSON: {"id":"...", "name":"...", "isBluetooth":true, ...}
const char *get_current_input_device() {
  static char jsonBuffer[1024];
  memset(jsonBuffer, 0, sizeof(jsonBuffer));

  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  AudioObjectID deviceID = 0;
  UInt32 size = sizeof(AudioObjectID);
  OSStatus status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);

  if (status != noErr || deviceID == kAudioObjectUnknown) {
    strcpy(jsonBuffer, "{}");
    return jsonBuffer;
  }

  NSString *uid =
      getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
  NSString *name =
      getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);

  if (uid == nil || name == nil) {
    strcpy(jsonBuffer, "{}");
    return jsonBuffer;
  }

  bool bluetooth = isBluetoothDevice(deviceID);
  bool builtIn = isBuiltInDevice(deviceID);
  Float64 sampleRate = getDeviceSampleRate(deviceID);

  NSDictionary *deviceDict = @{
    @"id" : uid,
    @"name" : name,
    @"isBluetooth" : @(bluetooth),
    @"isBuiltIn" : @(builtIn),
    @"sampleRate" : @(sampleRate)
  };

  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:deviceDict
                                                     options:0
                                                       error:&error];
  if (jsonData) {
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData
                                              encoding:NSUTF8StringEncoding];
    strncpy(jsonBuffer, [jsonStr UTF8String], sizeof(jsonBuffer) - 1);
  } else {
    strcpy(jsonBuffer, "{}");
  }

  return jsonBuffer;
}

// Set input device by UID
// Returns 1 on success, 0 on failure
int set_input_device(const char *deviceUID) {
  if (deviceUID == NULL || deviceUID[0] == 0) {
    log_to_file("AudioDevice: set_input_device called with NULL UID");
    return 0;
  }

  NSString *targetUID = [NSString stringWithUTF8String:deviceUID];

  // Find device ID by UID
  AudioObjectPropertyAddress propAddr = {kAudioHardwarePropertyDevices,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain};

  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                   &propAddr, 0, NULL, &size);
  if (status != noErr) {
    return 0;
  }

  int deviceCount = size / sizeof(AudioObjectID);
  AudioObjectID *devices = (AudioObjectID *)malloc(size);
  status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0,
                                      NULL, &size, devices);

  if (status != noErr) {
    free(devices);
    return 0;
  }

  AudioObjectID targetDevice = kAudioObjectUnknown;
  for (int i = 0; i < deviceCount; i++) {
    NSString *uid =
        getDeviceStringProperty(devices[i], kAudioDevicePropertyDeviceUID);
    if ([uid isEqualToString:targetUID]) {
      targetDevice = devices[i];
      break;
    }
  }
  free(devices);

  if (targetDevice == kAudioObjectUnknown) {
    log_to_file("AudioDevice: Device not found: %s", deviceUID);
    return 0;
  }

  // Only set preferredDeviceUID — don't change macOS system default.
  // The actual device switch happens in start_audio_recording() via
  // kAudioQueueProperty_CurrentDevice, which only affects SpeakOut.
  log_to_file("AudioDevice: Set preferred device to: %s", deviceUID);
  strncpy(preferredDeviceUID, deviceUID, sizeof(preferredDeviceUID) - 1);
  return 1;
}

// Check if a device with the given UID is currently available.
// Uses kAudioHardwarePropertyTranslateUIDToDevice for O(1) lookup —
// does NOT enumerate all devices, safe to call during BT negotiation.
// Returns 1 if available, 0 if not found or UID is empty.
int is_device_available(const char *deviceUID) {
  if (deviceUID == NULL || deviceUID[0] == 0) return 0;

  CFStringRef uidRef =
      CFStringCreateWithCString(NULL, deviceUID, kCFStringEncodingUTF8);
  if (!uidRef) return 0;

  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyTranslateUIDToDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

  AudioObjectID deviceID = kAudioObjectUnknown;
  UInt32 size = sizeof(AudioObjectID);
  OSStatus status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr,
                                 sizeof(CFStringRef), &uidRef, &size, &deviceID);
  CFRelease(uidRef);

  return (status == noErr && deviceID != kAudioObjectUnknown) ? 1 : 0;
}

// Switch to built-in microphone
// Returns 1 on success, 0 if already built-in or failed
int switch_to_builtin_mic() {
  // Ensure we have the built-in device UID
  if (builtInDeviceUID[0] == 0) {
    // Trigger device enumeration to find it
    get_audio_input_devices();
  }

  if (builtInDeviceUID[0] == 0) {
    log_to_file("AudioDevice: No built-in microphone found");
    return 0;
  }

  return set_input_device(builtInDeviceUID);
}

// Check if current input is Bluetooth
// Returns 1 if Bluetooth, 0 otherwise
int is_current_input_bluetooth() {
  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  AudioObjectID deviceID = 0;
  UInt32 size = sizeof(AudioObjectID);
  OSStatus status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);

  if (status != noErr || deviceID == kAudioObjectUnknown) {
    return 0;
  }

  return isBluetoothDevice(deviceID) ? 1 : 0;
}

// Device change listener callback
static OSStatus
deviceChangeListenerProc(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                         const AudioObjectPropertyAddress *inAddresses,
                         void *inClientData) {
  for (UInt32 i = 0; i < inNumberAddresses; i++) {
    if (inAddresses[i].mSelector == kAudioHardwarePropertyDefaultInputDevice) {
      log_to_file("AudioDevice: Default input device changed");

      // 先在**锁外**把设备信息查完 —— 绝不能持锁调 CoreAudio：
      // stop_device_change_listener() 里 AudioObjectRemovePropertyListener 若
      // 持 HAL 内部锁等待在途回调返回，而回调正持本锁反过来要 HAL 锁，就是
      // 锁序反转死锁。锁外查询后，临界区只剩一次立即返回的 trampoline 调用。
      AudioObjectPropertyAddress propAddr = {
          kAudioHardwarePropertyDefaultInputDevice,
          kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

      AudioObjectID deviceID = 0;
      UInt32 size = sizeof(AudioObjectID);
      OSStatus status = AudioObjectGetPropertyData(
          kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);

      if (status == noErr && deviceID != kAudioObjectUnknown) {
        NSString *uid =
            getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
        NSString *name = getDeviceStringProperty(
            deviceID, kAudioDevicePropertyDeviceNameCFString);
        bool isBluetooth = isBluetoothDevice(deviceID);

        if (uid && name) {
          // 临界区只包住「读指针 + 调用」。不能只把指针拷进局部变量再在锁外调：
          // 那样只避开了空指针判断的 TOCTOU，避不开「调用时 trampoline 已被释放」。
          // cb 是 NativeCallable.listener 的 trampoline，投递消息后立即返回，
          // 所以 stop 最多阻塞这一瞬间。
          pthread_mutex_lock(&deviceChangeCallbackMutex);
          DartDeviceChangeCallback cb = deviceChangeCallback;
          if (cb != NULL) {
            cb([uid UTF8String], [name UTF8String], isBluetooth ? 1 : 0);
          }
          pthread_mutex_unlock(&deviceChangeCallbackMutex);
        }
      }
    }
  }
  return noErr;
}

// Start listening for device changes
// Returns 1 on success, 0 on failure
int start_device_change_listener(DartDeviceChangeCallback callback) {
  if (callback == NULL) {
    log_to_file(
        "AudioDevice: start_device_change_listener called with NULL callback");
    return 0;
  }

  pthread_mutex_lock(&deviceChangeCallbackMutex);
  deviceChangeCallback = callback;
  pthread_mutex_unlock(&deviceChangeCallbackMutex);

  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  OSStatus status = AudioObjectAddPropertyListener(
      kAudioObjectSystemObject, &propAddr, deviceChangeListenerProc, NULL);

  if (status == noErr) {
    log_to_file("AudioDevice: Device change listener started");
    return 1;
  } else {
    log_to_file("AudioDevice: Failed to add device listener, status=%d",
                (int)status);
    return 0;
  }
}

// Stop listening for device changes
void stop_device_change_listener() {
  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &propAddr,
                                    deviceChangeListenerProc, NULL);
  // 持锁清空：若此刻有回调在途，这里会阻塞到它跑完。
  // 本函数返回后即保证「没有回调在途，也不会再有新的」——
  // Dart 侧这才可以安全 close() 那个 NativeCallable。
  pthread_mutex_lock(&deviceChangeCallbackMutex);
  deviceChangeCallback = NULL;
  pthread_mutex_unlock(&deviceChangeCallbackMutex);
  log_to_file("AudioDevice: Device change listener stopped");
}

// Get preferred device UID. Returns empty string if using system default.
const char *get_preferred_device_uid() {
  return preferredDeviceUID; // empty string = system default
}

// Set preferred high-quality device UID
void set_preferred_device_uid(const char *uid) {
  if (uid != NULL) {
    strncpy(preferredDeviceUID, uid, sizeof(preferredDeviceUID) - 1);
    log_to_file("AudioDevice: Preferred device set to: %s", uid);
  }
}

// ============================================================================
// SIGNAL QUALITY ANALYSIS (Phase 3)
// ============================================================================

// FFT setup for 512-sample quality analysis window
static FFTSetup qualityFFTSetup = NULL;
static int log2n = 9; // 2^9 = 512

static void ensureFFTSetup() {
  if (qualityFFTSetup == NULL) {
    qualityFFTSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
    log_to_file("AudioQuality: FFT setup created (N=512)");
  }
}

/// Analyze audio samples and estimate quality
/// Returns JSON: {"bandwidth": 8000, "snr": 15.5, "isTelephoneQuality": true}
/// Parameters:
///   - samples: 16-bit audio samples
///   - sampleCount: number of samples (should be >= 512)
///   - sampleRate: audio sample rate (e.g., 16000)
const char *analyze_audio_quality(const int16_t *samples, int sampleCount,
                                  int sampleRate) {
  static char resultBuffer[256];

  if (samples == NULL || sampleCount < 512) {
    snprintf(resultBuffer, sizeof(resultBuffer),
             "{\"bandwidth\":0,\"snr\":0,\"isTelephoneQuality\":false,"
             "\"error\":\"insufficient samples\"}");
    return resultBuffer;
  }

  ensureFFTSetup();

  // Use 512 samples for FFT
  int N = 512;

  // Convert int16 to float and apply Hann window
  float *floatSamples = (float *)malloc(N * sizeof(float));
  float *windowedSamples = (float *)malloc(N * sizeof(float));

  for (int i = 0; i < N; i++) {
    floatSamples[i] = (float)samples[i] / 32768.0f;
    // Hann window
    float window = 0.5f * (1.0f - cosf(2.0f * M_PI * i / (N - 1)));
    windowedSamples[i] = floatSamples[i] * window;
  }

  // Prepare for FFT (split complex format)
  DSPSplitComplex splitComplex;
  splitComplex.realp = (float *)malloc((N / 2) * sizeof(float));
  splitComplex.imagp = (float *)malloc((N / 2) * sizeof(float));

  // Pack real samples into split complex format
  vDSP_ctoz((DSPComplex *)windowedSamples, 2, &splitComplex, 1, N / 2);

  // Perform FFT
  vDSP_fft_zrip(qualityFFTSetup, &splitComplex, 1, log2n, FFT_FORWARD);

  // Calculate magnitude squared for each bin
  float *magnitudes = (float *)malloc((N / 2) * sizeof(float));
  vDSP_zvmags(&splitComplex, 1, magnitudes, 1, N / 2);

  // Calculate total energy and high-frequency energy
  float totalEnergy = 0;
  float highFreqEnergy = 0;
  float lowFreqEnergy = 0;

  float binWidth = (float)sampleRate / N; // Hz per bin
  int cutoffBin =
      (int)(4000.0f / binWidth); // 4kHz cutoff for "telephone" detection
  int highestSignificantBin = 0;
  float noiseFloor = 0;

  // Find noise floor (average of highest frequency bins)
  for (int i = N / 2 - 20; i < N / 2; i++) {
    noiseFloor += magnitudes[i];
  }
  noiseFloor /= 20.0f;

  float threshold = noiseFloor * 10.0f; // 10dB above noise floor

  for (int i = 1; i < N / 2; i++) {
    totalEnergy += magnitudes[i];
    if (i > cutoffBin) {
      highFreqEnergy += magnitudes[i];
    } else {
      lowFreqEnergy += magnitudes[i];
    }

    // Find highest bin with significant energy
    if (magnitudes[i] > threshold) {
      highestSignificantBin = i;
    }
  }

  // Estimate effective bandwidth
  float effectiveBandwidth = highestSignificantBin * binWidth;

  // Calculate SNR (rough estimate: peak to noise floor ratio in dB)
  float peakMag = 0;
  vDSP_maxv(magnitudes, 1, &peakMag, N / 2);
  float snr = (noiseFloor > 0) ? 10.0f * log10f(peakMag / noiseFloor) : 0;

  // Determine if telephone quality:
  // - Effective bandwidth < 4kHz
  // - OR high frequency energy is < 10% of low frequency energy
  bool isTelephoneQuality = false;
  if (effectiveBandwidth < 4000) {
    isTelephoneQuality = true;
  } else if (lowFreqEnergy > 0 && (highFreqEnergy / lowFreqEnergy) < 0.1f) {
    isTelephoneQuality = true;
  }

  log_to_file("AudioQuality: bandwidth=%.0f Hz, SNR=%.1f dB, telephone=%s",
              effectiveBandwidth, snr, isTelephoneQuality ? "YES" : "NO");

  // Build result JSON
  snprintf(resultBuffer, sizeof(resultBuffer),
           "{\"bandwidth\":%.0f,\"snr\":%.1f,\"isTelephoneQuality\":%s}",
           effectiveBandwidth, snr, isTelephoneQuality ? "true" : "false");

  // Cleanup
  free(floatSamples);
  free(windowedSamples);
  free(splitComplex.realp);
  free(splitComplex.imagp);
  free(magnitudes);

  return resultBuffer;
}

/// Quick check if current audio appears to be telephone quality
/// Uses device transport type + sample rate as heuristic
/// Returns 1 if likely telephone quality, 0 otherwise
// Launch an external shell script (for auto-update: replaces app after exit)
void launch_updater(const char *scriptPath) {
  @autoreleasepool {
    NSString *path = [NSString stringWithUTF8String:scriptPath];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[path];

    // 把启动期 stdout/stderr 也写到日志，方便排查"helper 没跑起来"的情况
    // （脚本内部本身用 exec >> $LOG 2>&1 接管了输出，这里只兜底启动阶段）
    NSString *home = NSHomeDirectory();
    NSString *logDir = [home stringByAppendingPathComponent:@"Library/Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *logPath = [logDir stringByAppendingPathComponent:@"speakout-updater.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
      [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    }
    NSFileHandle *logFh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (logFh) {
      [logFh seekToEndOfFile];
      task.standardOutput = logFh;
      task.standardError = logFh;
    } else {
      task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
      task.standardError = [NSFileHandle fileHandleWithNullDevice];
    }

    @try {
      [task launch];
      log_to_file("launch_updater: launched %s (pid=%d, log=%s)",
                  scriptPath, task.processIdentifier, logPath.UTF8String);
    } @catch (NSException *e) {
      log_to_file("launch_updater: failed to launch %s: %s", scriptPath, e.reason.UTF8String);
    }
  }
}

int is_likely_telephone_quality() {
  AudioObjectPropertyAddress propAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  AudioObjectID deviceID = 0;
  UInt32 size = sizeof(AudioObjectID);
  OSStatus status = AudioObjectGetPropertyData(
      kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);

  if (status != noErr || deviceID == kAudioObjectUnknown) {
    return 0;
  }

  // Check if Bluetooth
  if (!isBluetoothDevice(deviceID)) {
    return 0; // Not Bluetooth, unlikely to be telephone quality
  }

  // Check sample rate - low sample rate indicates HFP/HSP mode
  Float64 sampleRate = getDeviceSampleRate(deviceID);
  if (sampleRate > 0 && sampleRate <= 16000) {
    log_to_file("AudioQuality: Bluetooth device with low sample rate (%.0f Hz) "
                "- likely telephone quality",
                sampleRate);
    return 1;
  }

  return 0;
}
