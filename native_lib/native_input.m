#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// Debug Log Path
#define DEBUG_LOG_PATH "/tmp/speakout_debug.log"

void log_to_file(const char *fmt, ...) {
  FILE *fp = fopen(DEBUG_LOG_PATH, "a");
  if (!fp)
    return;

  time_t now;
  time(&now);
  char buf[20];
  strftime(buf, sizeof(buf), "%H:%M:%S", localtime(&now));

  fprintf(fp, "[%s] ", buf);

  va_list args;
  va_start(args, fmt);
  vfprintf(fp, fmt, args);
  va_end(args);

  fprintf(fp, "\n");
  fclose(fp);
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
static bool isMonitoring = false;

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
    dartCallback((int)keyCode, type == kCGEventKeyDown);
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
    // On newer Macs, FN key generates kCGEventFlagsChanged with keyCode=63
    // but the flag bit may vary. Use toggle approach: first event = down,
    // second = up
    else if (keyCode == 63) {
      static bool lastFnState = false;
      // Check kCGEventFlagMaskSecondaryFn (0x800000) first
      bool fnFlagSet = (flags & kCGEventFlagMaskSecondaryFn) != 0;
      // Fallback: if flag not set, toggle state on each event
      if (fnFlagSet) {
        isDown = true;
        lastFnState = true;
      } else {
        // If flag is cleared and we were previously down, it's a release
        if (lastFnState) {
          isDown = false;
          lastFnState = false;
        } else {
          // First event with no flag = assume down
          isDown = true;
          lastFnState = true;
        }
      }
      log_to_file("FN Key 63: flags=0x%llx, fnFlagSet=%d, isDown=%d",
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

// 3. Inject Text (Simple String)
// 3. Inject Text (Robust Chunking)
void inject_text(const char *text) {
  if (text == NULL)
    return;

  // 1. Convert C-String to CFString
  CFStringRef cfStr =
      CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
  if (!cfStr)
    return;

  CFIndex totalLen = CFStringGetLength(cfStr);
  if (totalLen == 0) {
    CFRelease(cfStr);
    return;
  }

  // 2. Setup Event Source
  CGEventSourceRef source =
      CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
  CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);

  // 3. Chunking Loop
  // Many apps drop events if payload is too large.
  // 50 chars per event is a safe balance between speed and reliability.
  const int CHUNK_SIZE = 50;
  UniChar buffer[CHUNK_SIZE];

  for (CFIndex i = 0; i < totalLen; i += CHUNK_SIZE) {
    // Calculate current chunk length
    CFIndex remaining = totalLen - i;
    CFIndex chunkLen = (remaining > CHUNK_SIZE) ? CHUNK_SIZE : remaining;

    // Extract characters
    CFStringGetCharacters(cfStr, CFRangeMake(i, chunkLen), buffer);

    // Set string to event
    CGEventKeyboardSetUnicodeString(keyDown, chunkLen, buffer);
    CGEventKeyboardSetUnicodeString(keyUp, chunkLen, buffer);

    // Post Event
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);

    // Extremely brief pause to let Main Loop breathe if text is huge (optional,
    // but safer) usleep(1000); // 1ms
  }

  // 4. Cleanup
  CFRelease(keyDown);
  CFRelease(keyUp);
  CFRelease(source);
  CFRelease(cfStr);
}

// 4. Check Permission
bool check_permission() {
  // Obj-C syntax for permission check dictionary
  NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
  bool trusted =
      AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  return trusted;
}
