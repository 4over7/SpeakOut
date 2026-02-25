#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <pwd.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// Debug Log Path
// Debug Log Path
// Get dynamic log path: ~/Downloads/speakout_native.log
static char *get_log_path() {
  static char path[512] = {0};
  if (path[0] == 0) {
    const char *home = getenv("HOME");
    if (!home) {
      struct passwd *pw = getpwuid(getuid());
      home = pw ? pw->pw_dir : "/tmp";
    }
    snprintf(path, sizeof(path), "%s/Downloads/speakout_native.log", home);
  }
  return path;
}

void log_to_file(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);

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
  NSString *msg = [[NSString alloc] initWithFormat:formatStr arguments:args];
  NSLog(@"[NativeInput] %@", msg);
  va_end(args);
}

// Callback function type defined in Dart
typedef void (*DartKeyCallback)(int keyCode, bool isDown);

// Forward declaration
bool check_permission();

// Global Variables
static CFMachPortRef eventTap = NULL;
static CFRunLoopSourceRef runLoopSource = NULL;
static DartKeyCallback dartCallback = NULL;

// Active hotkey info
static int targetKeyCode = -1; // e.g., 58 for Option, etc.
static atomic_bool isMonitoring = false;

// macOS 26+: Globe/Fn key sends KeyDown/Up with keyCode=179 in addition to
// FlagsChanged with keyCode=63. The FlagsChanged events fire DOWN+UP almost
// simultaneously (useless for push-to-talk hold detection), while KeyDown/Up
// 179 has proper hold timing. Once we see 179 events, suppress FlagsChanged 63.
static bool hasGlobeKeyEvents = false;

// CGEventCallback
CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type,
                             CGEventRef event, void *refcon) {
  if (type == kCGEventTapDisabledByTimeout) {
    log_to_file("EventTap Disabled by Timeout. Re-enabling...");
    CGEventTapEnable(eventTap, true);
    return event;
  }

  if (type == kCGEventTapDisabledByUserInput) {
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
    log_to_file("Event: Key 58 (Option) Type: %d", type);
  }

  // Capture Key events
  if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
    // macOS 26+: Globe/Fn key sends KeyDown/Up with keyCode=179.
    // Map to legacy Fn keyCode 63 so Dart PTT matching works.
    int mappedKeyCode = (int)keyCode;
    if (keyCode == 179) {
      hasGlobeKeyEvents = true;
      mappedKeyCode = 63;
      log_to_file("Globe key 179 -> mapped to Fn 63 (%s)",
                  type == kCGEventKeyDown ? "DOWN" : "UP");
    }

    uint64_t t0 = mach_absolute_time();
    dartCallback(mappedKeyCode, type == kCGEventKeyDown);
    uint64_t t1 = mach_absolute_time();

    // Convert to milliseconds
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    double ms = (double)(t1 - t0) * info.numer / info.denom / 1000000.0;
    log_to_file("Key %d %s: dartCallback took %.2f ms", mappedKeyCode,
                type == kCGEventKeyDown ? "DOWN" : "UP", ms);
  } else if (type == kCGEventFlagsChanged) {
    CGEventFlags flags = CGEventGetFlags(event);
    bool isDown = false;

    // Check specific keys based on standard macOS keycodes
    // Option (Alt): 58 (Left), 61 (Right)
    if (keyCode == 58 || keyCode == 61) {
      isDown = (flags & kCGEventFlagMaskAlternate) != 0;
    }
    // Shift: 56 (Left), 60 (Right)
    else if (keyCode == 56 || keyCode == 60) {
      isDown = (flags & kCGEventFlagMaskShift) != 0;
    }
    // Control: 59 (Left), 62 (Right)
    else if (keyCode == 59 || keyCode == 62) {
      isDown = (flags & kCGEventFlagMaskControl) != 0;
    }
    // Command: 55 (Left), 54 (Right)
    else if (keyCode == 55 || keyCode == 54) {
      isDown = (flags & kCGEventFlagMaskCommand) != 0;
    }
    // CapsLock: 57
    else if (keyCode == 57) {
      isDown = (flags & kCGEventFlagMaskAlphaShift) != 0;
    }
    // FN Key: keyCode=63 - use state tracking
    // On macOS 26+, Fn/Globe key also sends KeyDown/Up 179 with proper hold
    // timing. FlagsChanged 63 fires DOWN+UP almost simultaneously, making it
    // useless for push-to-talk. Once we detect Globe key 179, suppress this.
    else if (keyCode == 63) {
      if (hasGlobeKeyEvents) {
        // Suppress: KeyDown/Up 179 (mapped to 63) handles this correctly
        log_to_file("FN FlagsChanged 63: suppressed (Globe key 179 active)");
        return event;
      }
      // Legacy path for older macOS without Globe key 179 events
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
      log_to_file("FN Key 63 (legacy): flags=0x%llx, fnFlagSet=%d, isDown=%d",
                  (unsigned long long)flags, fnFlagSet, isDown);
    }

    if (keyCode == 58) {
      log_to_file("FlagsChanged: Key 58. IsDown: %d", isDown);
    }

    dartCallback((int)keyCode, isDown);
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

  // Use kCGHIDEventTap for highest priority - intercepts events before system
  // shortcuts kCGHeadInsertEventTap puts us early in the chain
  // kCGEventTapOptionDefault means we can inspect and optionally modify events
  eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                              kCGEventTapOptionDefault, eventMask,
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

// Inject via CGEvent keyboard events (works for most GUI apps)
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
      CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
  CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);

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
    CGEventKeyboardSetUnicodeString(keyDown, chunkLen, buffer);
    CGEventKeyboardSetUnicodeString(keyUp, chunkLen, buffer);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);

    i += chunkLen;
  }

  CFRelease(keyDown);
  CFRelease(keyUp);
  CFRelease(source);
  CFRelease(cfStr);
}

// Inject via clipboard paste (Cmd+V) — for terminal emulators
static void inject_via_clipboard(const char *text) {
  @autoreleasepool {
    NSString *newText = [NSString stringWithUTF8String:text];
    if (newText == nil || newText.length == 0)
      return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    // 1. Save current clipboard contents
    NSArray *savedItems = nil;
    NSArray *oldContents = [pasteboard pasteboardItems];
    if (oldContents.count > 0) {
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
      savedItems = items;
    }

    // 2. Put text on clipboard
    [pasteboard clearContents];
    [pasteboard setString:newText forType:NSPasteboardTypeString];
    usleep(10000); // 10ms for pasteboard propagation

    // 3. Simulate Cmd+V (keycode 9 = 'v')
    CGEventSourceRef source =
        CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 9, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 9, false);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);

    // 4. Restore clipboard after 200ms
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          [pasteboard clearContents];
          if (savedItems != nil && savedItems.count > 0) {
            [pasteboard writeObjects:savedItems];
          }
        });
  }
}

// Main entry: auto-detect and use the right method
void inject_text(const char *text) {
  if (text == NULL || text[0] == '\0')
    return;

  if (is_terminal_app()) {
    log_to_file("Inject: Using clipboard paste (terminal detected)");
    inject_via_clipboard(text);
  } else {
    inject_via_keyboard(text);
  }
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

// 3. Check Key State (Watchdog)
// Returns 1 if key is physically down, 0 if up.
int check_key_pressed(int keyCode) {
  // kCGEventSourceStateHIDSystemState combines physical keyboard state
  bool isDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState,
                                      (CGKeyCode)keyCode);
  return isDown ? 1 : 0;
}

// ============================================================================
// AUDIO RECORDING via AudioQueue + Ring Buffer
// CoreAudio writes to C ring buffer; Dart polls via read_audio_buffer().
// This eliminates SIGABRT from stale Dart FFI trampoline metadata.
// ============================================================================

#define NUM_BUFFERS 10
#define BUFFER_DURATION_MS 100 // 100ms per buffer = 1600 samples @ 16kHz

// Ring buffer: ~30 seconds of 16kHz mono Int16 = 480000 samples (~940KB)
#define RING_BUFFER_SAMPLES 480000

// Audio Recording State
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[NUM_BUFFERS];
static atomic_bool isRecording = false;
static AudioStreamBasicDescription audioFormat;

// Lock-free ring buffer (single producer / single consumer)
static int16_t ringBuffer[RING_BUFFER_SAMPLES];
static volatile uint64_t ringWritePos =
    0; // monotonically increasing write cursor
static volatile uint64_t ringReadPos =
    0; // monotonically increasing read cursor

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
  uint64_t wp = ringWritePos;
  for (int i = 0; i < sampleCount; i++) {
    ringBuffer[wp % RING_BUFFER_SAMPLES] = samples[i];
    wp++;
  }
  // Memory barrier: ensure all writes are visible before advancing cursor
  __sync_synchronize();
  ringWritePos = wp;

  // Re-enqueue buffer immediately for next capture
  if (atomic_load(&isRecording)) {
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
  }
}

/// Returns the number of unread samples available in the ring buffer.
int get_available_audio_samples() {
  uint64_t wp = ringWritePos;
  uint64_t rp = ringReadPos;
  int64_t avail = (int64_t)(wp - rp);
  if (avail < 0)
    avail = 0;
  // Cap to ring buffer size to prevent reading stale wrapped data
  if (avail > RING_BUFFER_SAMPLES) {
    // Reader fell behind; skip to latest data minus a small margin
    ringReadPos = wp - RING_BUFFER_SAMPLES + 1600; // skip to ~100ms before head
    avail = (int64_t)(wp - ringReadPos);
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

  uint64_t rp = ringReadPos;
  for (int i = 0; i < toRead; i++) {
    outSamples[i] = ringBuffer[rp % RING_BUFFER_SAMPLES];
    rp++;
  }
  // Memory barrier before advancing read cursor
  __sync_synchronize();
  ringReadPos = rp;

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
  ringWritePos = 0;
  ringReadPos = 0;

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

// Check if currently recording
int is_audio_recording() { return isRecording ? 1 : 0; }

// Check microphone permission (macOS 10.14+)
int check_microphone_permission() {
  if (@available(macOS 10.14, *)) {
    AVAuthorizationStatus status =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
      return 1; // Granted
    } else if (status == AVAuthorizationStatusNotDetermined) {
      // Request permission
      __block int result = 0;
      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                               completionHandler:^(BOOL granted) {
                                 result = granted ? 1 : 0;
                                 dispatch_semaphore_signal(sema);
                               }];
      dispatch_semaphore_wait(
          sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
      return result;
    } else {
      return 0; // Denied or Restricted
    }
  }
  return 1; // Pre-10.14 doesn't require permission
}

// ============================================================================
// AUDIO DEVICE MANAGEMENT
// ============================================================================

// Device change callback type
typedef void (*DartDeviceChangeCallback)(const char *deviceId,
                                         const char *deviceName,
                                         int isBluetooth);
static DartDeviceChangeCallback deviceChangeCallback = NULL;

// Stored preferred device UID
static char preferredDeviceUID[256] = {0};
static char builtInDeviceUID[256] = {0};

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

  NSString *result = (NSString *)value;
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

  // Set as default input device
  AudioObjectPropertyAddress setAddr = {
      kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain};

  status =
      AudioObjectSetPropertyData(kAudioObjectSystemObject, &setAddr, 0, NULL,
                                 sizeof(AudioObjectID), &targetDevice);

  if (status == noErr) {
    log_to_file("AudioDevice: Set input device to: %s", deviceUID);
    strncpy(preferredDeviceUID, deviceUID, sizeof(preferredDeviceUID) - 1);
    return 1;
  } else {
    log_to_file("AudioDevice: Failed to set device, status=%d", (int)status);
    return 0;
  }
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

      if (deviceChangeCallback != NULL) {
        // Get new device info
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
            deviceChangeCallback([uid UTF8String], [name UTF8String],
                                 isBluetooth ? 1 : 0);
          }
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

  deviceChangeCallback = callback;

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
  deviceChangeCallback = NULL;
  log_to_file("AudioDevice: Device change listener stopped");
}

// Get preferred high-quality device UID (user's choice or built-in)
const char *get_preferred_device_uid() {
  if (preferredDeviceUID[0] != 0) {
    return preferredDeviceUID;
  }
  if (builtInDeviceUID[0] != 0) {
    return builtInDeviceUID;
  }
  // Trigger enumeration
  get_audio_input_devices();
  return builtInDeviceUID;
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

#import <Accelerate/Accelerate.h>

// FFT setup for 512-sample analysis window
static FFTSetup fftSetup = NULL;
static int log2n = 9; // 2^9 = 512

static void ensureFFTSetup() {
  if (fftSetup == NULL) {
    fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
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
  vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFT_FORWARD);

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
