#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Callback function type defined in Dart
typedef void (*DartKeyCallback)(int keyCode, bool isDown);

static CFMachPortRef eventTap = NULL;
static CFRunLoopSourceRef runLoopSource = NULL;
static DartKeyCallback dartCallback = NULL;

// Active hotkey info
static int targetKeyCode = -1; // e.g., 58 for Option, etc.
static bool isMonitoring = false;

// CGEventCallback
CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventTapDisabledByTimeout) {
        CGEventTapEnable(eventTap, true);
        return event;
    }
    
    if (type == kCGEventTapDisabledByUserInput) {
        return event;
    }

    if (!isMonitoring || dartCallback == NULL) {
        return event;
    }

    // Capture Key events
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        // int64_t flags = CGEventGetIntegerValueField(event, kCGEventFlagsChanged); // Check modifiers if needed
        
        // Notify Dart
        // We only care if it matches our target or if we want to stream *all* keys (Privacy risk? Let's filter on Dart side or generic?)
        // Linus Style: Stream it all to Dart, let Dart decide. Simple Kernel.
        dartCallback((int)keyCode, type == kCGEventKeyDown);
        
        // If we are "consuming" the PTT key to prevent system menu, we might return NULL.
        // But for now, let's just observe (pass-through).
    }

    return event;
}

// Exported Functions

// 1. Start Listening
int start_keyboard_listener(DartKeyCallback callback) {
    if (eventTap != NULL) return 0; // Already running

    dartCallback = callback;
    isMonitoring = true;

    // Listen for KeyDown and KeyUp
    CGEventMask eventMask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp); // | (1 << kCGEventFlagsChanged);

    eventTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, 
        eventMask,
        myCGEventCallback,
        NULL
    );

    if (!eventTap) {
        printf("Failed to create event tap. Check permissions!\n");
        return -1;
    }

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    return 1; // Success
}

// 2. Stop Listening
void stop_keyboard_listener() {
    if (runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = NULL;
    }
    if (eventTap) {
        CFRelease(eventTap);
        eventTap = NULL;
    }
    isMonitoring = false;
    dartCallback = NULL;
}

// 3. Inject Text (Simple String)
void inject_text(const char* text) {
    // Requires accessibility permissions
    // Convert C string to CFString
    CFStringRef cfStr = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
    
    // Create event source
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    
    // Create key strokes
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);
    
    // Set string
    UniChar buffer[2048];
    CFStringGetCharacters(cfStr, CFRangeMake(0, CFStringGetLength(cfStr)), buffer);
    CGEventKeyboardSetUnicodeString(keyDown, CFStringGetLength(cfStr), buffer);
    CGEventKeyboardSetUnicodeString(keyUp, CFStringGetLength(cfStr), buffer);
    
    // Post
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
    CFRelease(cfStr);
}

// 4. Check Permission
bool check_permission() {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
