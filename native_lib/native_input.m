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

static void start_tap_log_drain(void);

void set_debug_logging(int enabled) {
  atomic_store(&debugLoggingEnabled, enabled ? 1 : 0);
  if (enabled) start_tap_log_drain();
  // 关掉时不撤 drain timer：撤销要跨线程同步 source 的生命周期，代价远大于
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
// 这里改成单写者/单读者环形缓冲：回调侧只做一次栈上 vsnprintf + 一个 release
// store，无堆分配、无系统调用；后台队列每 200ms 排空一次，真正的 I/O 在那边做。
//
// 溢出（200ms 内超过 TAP_LOG_SLOTS 条）丢最旧的若干条并留一行标记。写者覆盖
// 正在被读的槽位时最坏结果是那一行内容撕裂 —— 读侧整块 memcpy 后强制补 NUL，
// 不会越界。调试日志可以容忍撕裂，不能容忍拖慢回调。
#define TAP_LOG_SLOTS 256
#define TAP_LOG_LINE 192
static char tapLogRing[TAP_LOG_SLOTS][TAP_LOG_LINE];
static atomic_uint tapLogWrite = 0;
static unsigned tapLogRead = 0;
static dispatch_source_t tapLogDrainTimer = nil;

__attribute__((format(printf, 1, 2))) static void log_from_tap(const char *fmt,
                                                               ...) {
  if (!atomic_load(&debugLoggingEnabled)) return;
  unsigned w = atomic_load_explicit(&tapLogWrite, memory_order_relaxed);
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(tapLogRing[w % TAP_LOG_SLOTS], TAP_LOG_LINE, fmt, ap);
  va_end(ap);
  atomic_store_explicit(&tapLogWrite, w + 1, memory_order_release);
}

static void drain_tap_log(void) {
  unsigned w = atomic_load_explicit(&tapLogWrite, memory_order_acquire);
  if (w - tapLogRead > TAP_LOG_SLOTS) {
    unsigned dropped = (w - tapLogRead) - TAP_LOG_SLOTS;
    tapLogRead = w - TAP_LOG_SLOTS;
    log_to_file("[tap-log] dropped %u lines (ring overflow)", dropped);
  }
  while (tapLogRead != w) {
    char line[TAP_LOG_LINE];
    memcpy(line, tapLogRing[tapLogRead % TAP_LOG_SLOTS], TAP_LOG_LINE);
    line[TAP_LOG_LINE - 1] = '\0';
    log_to_file("%s", line);
    tapLogRead++;
  }
}

static void start_tap_log_drain(void) {
  if (tapLogDrainTimer != nil) return;
  dispatch_queue_t q =
      dispatch_queue_create("com.speakout.taplog", DISPATCH_QUEUE_SERIAL);
  tapLogDrainTimer =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
  dispatch_source_set_timer(tapLogDrainTimer, DISPATCH_TIME_NOW,
                            200 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
  dispatch_source_set_event_handler(tapLogDrainTimer, ^{
    drain_tap_log();
  });
  dispatch_resume(tapLogDrainTimer);
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
static void post_command_key(CGKeyCode key, CGEventTapLocation tap) {
  CGEventSourceRef source =
      CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  if (!source) return;
  const CGEventFlags kCmdFlags =
      kCGEventFlagMaskCommand | NX_DEVICELCMDKEYMASK | NX_NONCOALSESCEDMASK;
  CGEventRef cmdDown = CGEventCreateKeyboardEvent(source, 55, true);
  CGEventRef keyDown = CGEventCreateKeyboardEvent(source, key, true);
  CGEventRef keyUp = CGEventCreateKeyboardEvent(source, key, false);
  CGEventRef cmdUp = CGEventCreateKeyboardEvent(source, 55, false);
  if (cmdDown && keyDown && keyUp && cmdUp) {
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
}

// 深拷贝当前剪贴板内容，供之后还原。空剪贴板返回 nil。
static NSArray *snapshot_pasteboard(NSPasteboard *pasteboard) {
  NSArray *oldContents = [pasteboard pasteboardItems];
  if (oldContents.count == 0) return nil;
  NSMutableArray *items = [NSMutableArray array];
  for (NSPasteboardItem *item in oldContents) {
    NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
    for (NSString *type in [item types]) {
      NSData *data = [item dataForType:type];
      if (data) {
        [copy setData:data forType:type];
      }
    }
    [items addObject:copy];
  }
  return items;
}

// --- 一次性剪贴板注入的还原事务 ---
//
// 快照**必须按事务拍一次**，不能每次注入都重拍。原先每次都读当前剪贴板当
// 「原始内容」，于是 CLIPBOARD_RESTORE_DELAY_MS 内连注两次时：
//   原剪贴板 X → 注入 A（存 X）→ 注入 B（存到的却是 A）
//   → A 的还原任务看到 changeCount 变了，跳过 → B 的还原任务写回 A
// 结果 X 永久丢失，剪贴板里留着 SpeakOut 自己注入的文本。连续听写、
// 或普通注入紧接打字机注入都能触发。
//
// 现在：只有当前没有待还原任务时才拍快照；之后的注入只推进代次，
// 唯有最后一代的任务负责把最初那份快照写回去。
static pthread_mutex_t clipboardTxMutex = PTHREAD_MUTEX_INITIALIZER;
static NSArray *_txSavedItems = nil;   // 事务开始前的原始剪贴板
static BOOL _txRestorePending = NO;
static uint64_t _txGeneration = 0;

static void inject_via_clipboard(const char *text) {
  @autoreleasepool {
    NSString *newText = [NSString stringWithUTF8String:text];
    if (newText == nil || newText.length == 0)
      return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    // 1. 事务级快照：已有待还原任务说明我们仍持有更早的原始内容，别覆盖它
    pthread_mutex_lock(&clipboardTxMutex);
    if (!_txRestorePending) {
      _txSavedItems = snapshot_pasteboard(pasteboard);
      _txRestorePending = YES;
    }
    const uint64_t myGen = ++_txGeneration;
    pthread_mutex_unlock(&clipboardTxMutex);

    // 2. Put text on clipboard
    NSInteger ourChangeCount = [pasteboard clearContents];
    [pasteboard setString:newText forType:NSPasteboardTypeString];
    usleep(10000); // 10ms for pasteboard propagation

    // 3. Simulate Cmd+V
    post_command_key(9, kCGHIDEventTap);

    // 4. 还原剪贴板。等待期变长后，用户很可能在这期间自己复制了别的东西 ——
    //    changeCount 变了就说明剪贴板已易主，此时还原等于把用户刚复制的内容吃掉。
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, CLIPBOARD_RESTORE_DELAY_MS * NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          pthread_mutex_lock(&clipboardTxMutex);
          if (myGen != _txGeneration) { // 后面还有更新的注入，交给它收尾
            pthread_mutex_unlock(&clipboardTxMutex);
            return;
          }
          NSArray *saved = _txSavedItems;
          _txSavedItems = nil;
          _txRestorePending = NO;
          pthread_mutex_unlock(&clipboardTxMutex);

          if (pasteboard.changeCount != ourChangeCount) return;
          [pasteboard clearContents];
          if (saved != nil && saved.count > 0) {
            [pasteboard writeObjects:saved];
          }
        });
  }
}

// --- Streaming clipboard injection (for typewriter effect) ---
// Saves clipboard once at begin, pastes each chunk, restores at end.
static BOOL _clipboardSessionActive = NO;
static NSArray *_savedClipboardItems = nil;
// 本会话最后一次由我们自己造成的 changeCount，供 end 判断剪贴板有没有易主。
// -1 表示本会话还没动过剪贴板 —— 此时应无条件还原。
static NSInteger _lastChunkChangeCount = -1;

void inject_clipboard_begin(void) {
  @autoreleasepool {
    // 会话状态必须用独立标志，**不能**拿 _savedClipboardItems 是否为 nil 代表：
    // 用户剪贴板本来就为空时，下面第 19 行会把快照设成 nil ——
    // 那样 end 会误判成「无会话」直接返回，注入的语音文本永久留在剪贴板里
    // （既违反恢复契约，也是口述内容泄漏）。
    _clipboardSessionActive = true;
    // **必须复位**：这是跨会话共享的静态量，不清零的话上一次会话留下的
    // changeCount 会被这一次的 end 当判据 —— AI 梳理里 begin 后 Cmd+C 改了
    // 剪贴板、LLM 又在首个 chunk 之前失败时，end 拿旧值一比就判成「已易主」
    // 而跳过还原，用户开梳理前的剪贴板内容就这么没了。
    _lastChunkChangeCount = -1;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    _savedClipboardItems = snapshot_pasteboard(pasteboard);
    log_to_file("Clipboard streaming: begin (saved %lu items)",
                (unsigned long)(_savedClipboardItems ? _savedClipboardItems.count : 0));
  }
}

void inject_clipboard_chunk(const char *text) {
  if (text == NULL || text[0] == '\0')
    return;

  @autoreleasepool {
    NSString *newText = [NSString stringWithUTF8String:text];
    if (newText == nil || newText.length == 0)
      return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    _lastChunkChangeCount = [pasteboard clearContents];
    [pasteboard setString:newText forType:NSPasteboardTypeString];
    usleep(10000); // 10ms for pasteboard propagation

    post_command_key(9, kCGHIDEventTap);
    usleep(30000); // 30ms for paste to complete before next chunk
  }
}

void inject_clipboard_end(void) {
  @autoreleasepool {
    // 没有进行中的会话就直接返回：下面 clearContents 是无条件的，
    // 只有 saved != nil 才写回 —— 在无会话状态下再走一遍等于把用户剪贴板清空。
    // Dart 侧已用会话计数堵住重复调用，这里再兜一层，防别的调用方绕过。
    //
    // 判据是独立标志而不是 _savedClipboardItems == nil：原剪贴板为空时
    // 快照本来就是 nil，用它判断会让 end 误早退、注入文本留在剪贴板。
    if (!_clipboardSessionActive) {
      log_to_file("Clipboard streaming: end ignored (no active session)");
      return;
    }
    _clipboardSessionActive = false;
    // Restore clipboard after a short delay
    NSArray *saved = _savedClipboardItems;
    _savedClipboardItems = nil;
    const NSInteger expected = _lastChunkChangeCount;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, CLIPBOARD_RESTORE_DELAY_MS * NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
          // 剪贴板已易主（用户自己复制了东西）就别还原，否则会吃掉他刚复制的内容
          if (expected >= 0 && pasteboard.changeCount != expected) {
            log_to_file("Clipboard streaming: end (skipped restore, clipboard changed)");
            return;
          }
          [pasteboard clearContents];
          if (saved != nil && saved.count > 0) {
            [pasteboard writeObjects:saved];
          }
          log_to_file("Clipboard streaming: end (restored)");
        });
  }
}

// --- AI 梳理辅助函数 ---

// 模拟 Cmd+C 复制选中文字到剪贴板
void copy_selection(void) {
  @autoreleasepool {
    post_command_key(8, kCGAnnotatedSessionEventTap); // 8 = 'c'
    usleep(100000); // 100ms 等待剪贴板更新
    // 会话进行中的 Cmd+C 也是「我们自己造成的变更」，要记进判据。
    // 否则 end 会把它当成用户易主而跳过还原；反过来，用户在这之后真的自己
    // 复制了东西，changeCount 就会对不上，还原被正确跳过 —— 两种情形分得开。
    if (_clipboardSessionActive) {
      _lastChunkChangeCount = [[NSPasteboard generalPasteboard] changeCount];
    }
  }
}

// 模拟任意按键（用于 → 取消选区、Return 换行等）
void press_key(int keyCode, int modifierFlags) {
  @autoreleasepool {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return;
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
    if (keyDown) CFRelease(keyDown);
    if (keyUp) CFRelease(keyUp);
    CFRelease(source);
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
void inject_text(const char *text) {
  if (text == NULL || text[0] == '\0')
    return;

  inject_via_clipboard(text);
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
static _Atomic uint32_t smoothedLevelBits = 0;
static _Atomic uint64_t smoothedLevelStamp = 0;

static float smoothed_level_update(float level) {
  const uint64_t now = mach_absolute_time();
  mach_timebase_info_data_t tb;
  mach_timebase_info(&tb);
  for (;;) {
    uint32_t oldBits = atomic_load(&smoothedLevelBits);
    const uint64_t oldStamp = atomic_load(&smoothedLevelStamp);
    float prev;
    memcpy(&prev, &oldBits, sizeof(prev));

    float next;
    if (level >= prev) {
      next = level; // instant rise
    } else {
      // stamp 与 bits 不是一次原子读到的，可能取到稍旧的时间戳；
      // 那只会让这一次衰减多算一点，不产生 UB，也不会累积偏差。
      const double ms =
          (double)(now - oldStamp) * tb.numer / tb.denom / 1000000.0;
      // 原系数 0.88 的语义是「每 80ms 保留 88%」，这里把它还原成时间函数
      const double keep = pow(0.88, ms / 80.0);
      next = (float)(prev * keep + level * (1.0 - keep));
    }

    uint32_t newBits;
    memcpy(&newBits, &next, sizeof(newBits));
    if (atomic_compare_exchange_weak(&smoothedLevelBits, &oldBits, newBits)) {
      atomic_store(&smoothedLevelStamp, now);
      return next;
    }
  }
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
