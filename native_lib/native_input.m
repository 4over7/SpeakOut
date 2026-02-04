#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <mach/mach_time.h>
#include <pwd.h>
#include <unistd.h>

// Debug Log Path
// Debug Log Path
// Get dynamic log path: ~/Downloads/speakout_native.log
static char* get_log_path() {
  static char path[512] = {0};
  if (path[0] == 0) {
    const char* home = getenv("HOME");
    if (!home) {
      struct passwd* pw = getpwuid(getuid());
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

// Memory safety for async audio callbacks
void native_free(void *ptr) {
    if (ptr) free(ptr);
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
  #define INJECT_CHUNK_SIZE 50
  UniChar buffer[INJECT_CHUNK_SIZE];

  for (CFIndex i = 0; i < totalLen; i += INJECT_CHUNK_SIZE) {
    // Calculate current chunk length
    CFIndex remaining = totalLen - i;
    CFIndex chunkLen = (remaining > INJECT_CHUNK_SIZE) ? INJECT_CHUNK_SIZE : remaining;

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
  bool isDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode)keyCode);
  return isDown ? 1 : 0;
}

// ============================================================================
// AUDIO RECORDING via AudioQueue (Input Only - No Output Device Involvement)
// ============================================================================

#define NUM_BUFFERS 10
#define BUFFER_DURATION_MS 100  // 100ms per buffer = 1600 samples @ 16kHz

// Callback for audio data from Dart
typedef void (*DartAudioCallback)(const int16_t* samples, int sampleCount);

// Audio Recording State
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[NUM_BUFFERS];
static DartAudioCallback audioCallback = NULL;
static atomic_bool isRecording = false;  // Thread-safe: accessed from AudioQueue callback thread
static AudioStreamBasicDescription audioFormat;

// AudioQueue Input Callback (runs on background system thread)
// Flag to track if callback is valid (set to false before clearing audioCallback)
static volatile bool callbackValid = false;

static void AudioInputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs) {
    // DEFENSIVE: Check all conditions before calling Dart callback
    // The callbackValid flag is set to false BEFORE audioCallback is cleared,
    // preventing race conditions where we call a stale callback pointer.
    if (!atomic_load(&isRecording)) {
        return;
    }
    
    // Double-check callback validity
    if (!callbackValid || audioCallback == NULL) {
        // Callback became invalid, just re-enqueue buffer without calling Dart
        if (atomic_load(&isRecording)) {
            AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
        }
        return;
    }
    
    // Capture callback pointer locally to prevent race condition
    DartAudioCallback localCallback = audioCallback;
    if (localCallback == NULL) {
        return;
    }
    
    // CRITICAL: We MUST copy the data before re-enqueuing the buffer.
    // Since Dart's NativeCallable.listener is asynchronous, the buffer
    // will be overwritten by the time Dart processes it if we don't copy.
    UInt32 size = inBuffer->mAudioDataByteSize;
    void *copy = malloc(size);
    if (copy) {
        memcpy(copy, inBuffer->mAudioData, size);
        int sampleCount = size / sizeof(int16_t);
        // Dart is responsible for calling native_free(copy)
        // Use local copy of callback pointer for safety
        localCallback((int16_t *)copy, sampleCount);
    }
    
    // Re-enqueue buffer immediately for next capture
    if (atomic_load(&isRecording)) {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
}

// Start Audio Recording
// Returns 1 on success, negative on error
int start_audio_recording(DartAudioCallback callback) {
    if (atomic_load(&isRecording)) {
        log_to_file("Audio: Already recording");
        return 1;
    }
    
    if (callback == NULL) {
        log_to_file("Audio: Callback is NULL");
        return -1;
    }
    
    audioCallback = callback;
    callbackValid = true;  // Mark callback as valid
    
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
    // Use NULL for runloop to run on a background system thread
    OSStatus status = AudioQueueNewInput(&audioFormat,
                                          AudioInputCallback,
                                          NULL,  // user data
                                          NULL,  // background thread
                                          NULL,  // runloop mode
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
    
    atomic_store(&isRecording, true);
    log_to_file("Audio: Recording started (16kHz, Mono, Int16)");
    return 1;
}

// Stop Audio Recording
void stop_audio_recording() {
    if (!atomic_load(&isRecording) || audioQueue == NULL) {
        return;
    }
    
    atomic_store(&isRecording, false);
    
    // CRITICAL: Mark callback invalid BEFORE stopping queue
    // This prevents the callback from being called with stale pointer
    callbackValid = false;
    
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

// ============================================================================
// AUDIO DEVICE MANAGEMENT
// ============================================================================

// Device change callback type
typedef void (*DartDeviceChangeCallback)(const char* deviceId, const char* deviceName, int isBluetooth);
static DartDeviceChangeCallback deviceChangeCallback = NULL;

// Stored preferred device UID
static char preferredDeviceUID[256] = {0};
static char builtInDeviceUID[256] = {0};

// Get string property from audio device
static NSString* getDeviceStringProperty(AudioObjectID deviceID, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress propAddr = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CFStringRef value = NULL;
    UInt32 size = sizeof(CFStringRef);
    
    OSStatus status = AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, &value);
    if (status != noErr || value == NULL) {
        return nil;
    }
    
    NSString* result = (__bridge_transfer NSString*)value;
    return result;
}

// Get transport type of device
static UInt32 getDeviceTransportType(AudioObjectID deviceID) {
    AudioObjectPropertyAddress propAddr = {
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 transportType = 0;
    UInt32 size = sizeof(UInt32);
    
    AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, &transportType);
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
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &propAddr, 0, NULL, &size);
    if (status != noErr || size == 0) {
        return false;
    }
    
    AudioBufferList* bufferList = (AudioBufferList*)malloc(size);
    status = AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, bufferList);
    
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
    AudioObjectPropertyAddress propAddr = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    
    Float64 sampleRate = 0;
    UInt32 size = sizeof(Float64);
    AudioObjectGetPropertyData(deviceID, &propAddr, 0, NULL, &size, &sampleRate);
    return sampleRate;
}

// Get all input devices
// Returns JSON string: [{"id":"...", "name":"...", "isBluetooth":true, "isBuiltIn":false, "sampleRate":48000}, ...]
const char* get_audio_input_devices() {
    static char jsonBuffer[8192];
    memset(jsonBuffer, 0, sizeof(jsonBuffer));
    
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propAddr, 0, NULL, &size);
    if (status != noErr) {
        strcpy(jsonBuffer, "[]");
        return jsonBuffer;
    }
    
    int deviceCount = size / sizeof(AudioObjectID);
    AudioObjectID* devices = (AudioObjectID*)malloc(size);
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, NULL, &size, devices);
    
    if (status != noErr) {
        free(devices);
        strcpy(jsonBuffer, "[]");
        return jsonBuffer;
    }
    
    NSMutableArray* deviceArray = [NSMutableArray array];
    
    for (int i = 0; i < deviceCount; i++) {
        AudioObjectID deviceID = devices[i];
        
        // Only include input devices
        if (!hasInputCapability(deviceID)) {
            continue;
        }
        
        NSString* uid = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
        NSString* name = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);
        
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
        
        NSDictionary* deviceDict = @{
            @"id": uid,
            @"name": name,
            @"isBluetooth": @(bluetooth),
            @"isBuiltIn": @(builtIn),
            @"sampleRate": @(sampleRate)
        };
        [deviceArray addObject:deviceDict];
    }
    
    free(devices);
    
    NSError* error = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:deviceArray options:0 error:&error];
    if (jsonData) {
        NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        strncpy(jsonBuffer, [jsonStr UTF8String], sizeof(jsonBuffer) - 1);
    } else {
        strcpy(jsonBuffer, "[]");
    }
    
    return jsonBuffer;
}

// Get current default input device info
// Returns JSON: {"id":"...", "name":"...", "isBluetooth":true, ...}
const char* get_current_input_device() {
    static char jsonBuffer[1024];
    memset(jsonBuffer, 0, sizeof(jsonBuffer));
    
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectID deviceID = 0;
    UInt32 size = sizeof(AudioObjectID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);
    
    if (status != noErr || deviceID == kAudioObjectUnknown) {
        strcpy(jsonBuffer, "{}");
        return jsonBuffer;
    }
    
    NSString* uid = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
    NSString* name = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);
    
    if (uid == nil || name == nil) {
        strcpy(jsonBuffer, "{}");
        return jsonBuffer;
    }
    
    bool bluetooth = isBluetoothDevice(deviceID);
    bool builtIn = isBuiltInDevice(deviceID);
    Float64 sampleRate = getDeviceSampleRate(deviceID);
    
    NSDictionary* deviceDict = @{
        @"id": uid,
        @"name": name,
        @"isBluetooth": @(bluetooth),
        @"isBuiltIn": @(builtIn),
        @"sampleRate": @(sampleRate)
    };
    
    NSError* error = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:deviceDict options:0 error:&error];
    if (jsonData) {
        NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        strncpy(jsonBuffer, [jsonStr UTF8String], sizeof(jsonBuffer) - 1);
    } else {
        strcpy(jsonBuffer, "{}");
    }
    
    return jsonBuffer;
}

// Set input device by UID
// Returns 1 on success, 0 on failure
int set_input_device(const char* deviceUID) {
    if (deviceUID == NULL || deviceUID[0] == 0) {
        log_to_file("AudioDevice: set_input_device called with NULL UID");
        return 0;
    }
    
    NSString* targetUID = [NSString stringWithUTF8String:deviceUID];
    
    // Find device ID by UID
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propAddr, 0, NULL, &size);
    if (status != noErr) {
        return 0;
    }
    
    int deviceCount = size / sizeof(AudioObjectID);
    AudioObjectID* devices = (AudioObjectID*)malloc(size);
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, NULL, &size, devices);
    
    if (status != noErr) {
        free(devices);
        return 0;
    }
    
    AudioObjectID targetDevice = kAudioObjectUnknown;
    for (int i = 0; i < deviceCount; i++) {
        NSString* uid = getDeviceStringProperty(devices[i], kAudioDevicePropertyDeviceUID);
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
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &setAddr, 0, NULL, sizeof(AudioObjectID), &targetDevice);
    
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
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectID deviceID = 0;
    UInt32 size = sizeof(AudioObjectID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);
    
    if (status != noErr || deviceID == kAudioObjectUnknown) {
        return 0;
    }
    
    return isBluetoothDevice(deviceID) ? 1 : 0;
}

// Device change listener callback
static OSStatus deviceChangeListenerProc(AudioObjectID inObjectID,
                                          UInt32 inNumberAddresses,
                                          const AudioObjectPropertyAddress* inAddresses,
                                          void* inClientData) {
    for (UInt32 i = 0; i < inNumberAddresses; i++) {
        if (inAddresses[i].mSelector == kAudioHardwarePropertyDefaultInputDevice) {
            log_to_file("AudioDevice: Default input device changed");
            
            if (deviceChangeCallback != NULL) {
                // Get new device info
                AudioObjectPropertyAddress propAddr = {
                    kAudioHardwarePropertyDefaultInputDevice,
                    kAudioObjectPropertyScopeGlobal,
                    kAudioObjectPropertyElementMain
                };
                
                AudioObjectID deviceID = 0;
                UInt32 size = sizeof(AudioObjectID);
                OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propAddr, 0, NULL, &size, &deviceID);
                
                if (status == noErr && deviceID != kAudioObjectUnknown) {
                    NSString* uid = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
                    NSString* name = getDeviceStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);
                    bool isBluetooth = isBluetoothDevice(deviceID);
                    
                    if (uid && name) {
                        deviceChangeCallback([uid UTF8String], [name UTF8String], isBluetooth ? 1 : 0);
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
        log_to_file("AudioDevice: start_device_change_listener called with NULL callback");
        return 0;
    }
    
    deviceChangeCallback = callback;
    
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    OSStatus status = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &propAddr, deviceChangeListenerProc, NULL);
    
    if (status == noErr) {
        log_to_file("AudioDevice: Device change listener started");
        return 1;
    } else {
        log_to_file("AudioDevice: Failed to add device listener, status=%d", (int)status);
        return 0;
    }
}

// Stop listening for device changes
void stop_device_change_listener() {
    AudioObjectPropertyAddress propAddr = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &propAddr, deviceChangeListenerProc, NULL);
    deviceChangeCallback = NULL;
    log_to_file("AudioDevice: Device change listener stopped");
}

// Get preferred high-quality device UID (user's choice or built-in)
const char* get_preferred_device_uid() {
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
void set_preferred_device_uid(const char* uid) {
    if (uid != NULL) {
        strncpy(preferredDeviceUID, uid, sizeof(preferredDeviceUID) - 1);
        log_to_file("AudioDevice: Preferred device set to: %s", uid);
    }
}
