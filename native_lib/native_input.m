#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <mach/mach_time.h>

// Debug Log Path
// Debug Log Path
void log_to_file(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  
  // Write to ~/Downloads/speakout_native.log
  // Hardcoded for reliable debugging on this machine
  const char* path = "/Users/leon/Downloads/speakout_native.log";
  FILE *f = fopen(path, "a");
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
    uint64_t t0 = mach_absolute_time();
    dartCallback((int)keyCode, type == kCGEventKeyDown);
    uint64_t t1 = mach_absolute_time();
    
    // Convert to milliseconds
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    double ms = (double)(t1 - t0) * info.numer / info.denom / 1000000.0;
    log_to_file("Key %d %s: dartCallback took %.2f ms", keyCode, type == kCGEventKeyDown ? "DOWN" : "UP", ms);
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

// 3. Check Key State (Watchdog)
// Returns 1 if key is physically down, 0 if up.
int check_key_pressed(int keyCode) {
  // kCGEventSourceStateHIDSystemState combines physical keyboard state
  bool isDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode)keyCode);
  return isDown ? 1 : 0;
}

// ============================================================================
// AUDIO RECORDING via AudioQueue (Input Only - No Output Device Involvement)
// ============================================================================

#define NUM_BUFFERS 3
#define BUFFER_DURATION_MS 100  // 100ms per buffer = 1600 samples @ 16kHz

// Callback for audio data from Dart
typedef void (*DartAudioCallback)(const int16_t* samples, int sampleCount);

// Audio Recording State
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[NUM_BUFFERS];
static DartAudioCallback audioCallback = NULL;
static bool isRecording = false;
static AudioStreamBasicDescription audioFormat;

// AudioQueue Input Callback
static void AudioInputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs) {
    if (!isRecording || audioCallback == NULL) {
        return;
    }
    
    // inBuffer->mAudioData contains raw PCM Int16 samples
    int16_t *samples = (int16_t *)inBuffer->mAudioData;
    int sampleCount = inBuffer->mAudioDataByteSize / sizeof(int16_t);
    
    // Send to Dart
    audioCallback(samples, sampleCount);
    
    // Re-enqueue buffer for next capture
    if (isRecording) {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
}

// Start Audio Recording
// Returns 1 on success, negative on error
int start_audio_recording(DartAudioCallback callback) {
    if (isRecording) {
        log_to_file("Audio: Already recording");
        return 1;
    }
    
    if (callback == NULL) {
        log_to_file("Audio: Callback is NULL");
        return -1;
    }
    
    audioCallback = callback;
    
    // Configure audio format: 16kHz, Mono, 16-bit signed integer
    memset(&audioFormat, 0, sizeof(audioFormat));
    audioFormat.mSampleRate = 16000.0;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mChannelsPerFrame = 1;
    audioFormat.mBytesPerFrame = 2;  // 16-bit mono = 2 bytes
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBytesPerPacket = 2;
    
    // Create AudioQueue for Input
    OSStatus status = AudioQueueNewInput(&audioFormat,
                                          AudioInputCallback,
                                          NULL,  // user data
                                          CFRunLoopGetMain(),
                                          kCFRunLoopCommonModes,
                                          0,
                                          &audioQueue);
    
    if (status != noErr) {
        log_to_file("Audio: Failed to create AudioQueue, status=%d", (int)status);
        return -2;
    }
    
    // Calculate buffer size for 100ms of audio
    // 16kHz * 0.1s = 1600 samples * 2 bytes = 3200 bytes
    UInt32 bufferByteSize = (UInt32)(audioFormat.mSampleRate * BUFFER_DURATION_MS / 1000.0 * audioFormat.mBytesPerFrame);
    
    // Allocate and enqueue buffers
    for (int i = 0; i < NUM_BUFFERS; i++) {
        status = AudioQueueAllocateBuffer(audioQueue, bufferByteSize, &audioBuffers[i]);
        if (status != noErr) {
            log_to_file("Audio: Failed to allocate buffer %d, status=%d", i, (int)status);
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
    
    isRecording = true;
    log_to_file("Audio: Recording started (16kHz, Mono, Int16)");
    return 1;
}

// Stop Audio Recording
void stop_audio_recording() {
    if (!isRecording || audioQueue == NULL) {
        return;
    }
    
    isRecording = false;
    
    // Stop and dispose queue
    AudioQueueStop(audioQueue, true);  // true = stop immediately
    AudioQueueDispose(audioQueue, true);
    audioQueue = NULL;
    audioCallback = NULL;
    
    log_to_file("Audio: Recording stopped");
}

// Check if currently recording
int is_audio_recording() {
    return isRecording ? 1 : 0;
}

// Check microphone permission (macOS 10.14+)
int check_microphone_permission() {
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
        if (status == AVAuthorizationStatusAuthorized) {
            return 1;  // Granted
        } else if (status == AVAuthorizationStatusNotDetermined) {
            // Request permission
            __block int result = 0;
            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
                result = granted ? 1 : 0;
                dispatch_semaphore_signal(sema);
            }];
            dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            return result;
        } else {
            return 0;  // Denied or Restricted
        }
    }
    return 1;  // Pre-10.14 doesn't require permission
}
