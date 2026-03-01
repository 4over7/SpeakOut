/**
 * SpeakOut Linux Native Input Library
 *
 * 导出与 macOS/Windows 版本完全相同的 21+ 个 C 函数签名，
 * 使用 Linux API 实现：
 *   - 键盘监听: /dev/input (evdev) — 无需 X11
 *   - 文本注入: xdotool / xte (X11) 或 ydotool (Wayland)
 *   - 音频采集: PulseAudio (pa_simple)
 *   - 设备管理: PulseAudio context API
 *
 * 编译: 参见同目录 CMakeLists.txt
 *   gcc -shared -fPIC -o libnative_input.so native_input.c \
 *       -lpulse-simple -lpulse -lX11 -lXtst -lpthread
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdatomic.h>
#include <math.h>
#include <pthread.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <errno.h>
#include <linux/input.h>

/* PulseAudio simple API */
#include <pulse/simple.h>
#include <pulse/error.h>

/* X11 for text injection (optional, dlopened) */
#include <dlfcn.h>

// ============================================================
// DLL Export macro
// ============================================================
#define EXPORT __attribute__((visibility("default")))

// ============================================================
// Callback types (must match Dart FFI signatures)
// ============================================================
typedef void (*KeyCallback)(int keyCode, int isDown);
typedef void (*DeviceChangeCallback)(const char* deviceId, const char* deviceName, int isBluetooth);

// ============================================================
// Ring Buffer for audio samples (16-bit PCM, 16kHz)
// ============================================================
#define RING_BUFFER_SAMPLES (16000 * 30)  // 30 seconds max

static int16_t g_ringBuffer[RING_BUFFER_SAMPLES];
static volatile long g_ringWritePos = 0;
static volatile long g_ringReadPos = 0;
static pthread_mutex_t g_ringLock = PTHREAD_MUTEX_INITIALIZER;

static void ring_init(void) {
    g_ringWritePos = 0;
    g_ringReadPos = 0;
}

static void ring_write(const int16_t* samples, int count) {
    pthread_mutex_lock(&g_ringLock);
    for (int i = 0; i < count; i++) {
        g_ringBuffer[g_ringWritePos % RING_BUFFER_SAMPLES] = samples[i];
        g_ringWritePos++;
    }
    if (g_ringWritePos - g_ringReadPos > RING_BUFFER_SAMPLES) {
        g_ringReadPos = g_ringWritePos - RING_BUFFER_SAMPLES;
    }
    pthread_mutex_unlock(&g_ringLock);
}

static int ring_read(int16_t* out, int maxSamples) {
    pthread_mutex_lock(&g_ringLock);
    long available = (long)(g_ringWritePos - g_ringReadPos);
    if (available < 0) available = 0;
    int toRead = (available < maxSamples) ? (int)available : maxSamples;
    for (int i = 0; i < toRead; i++) {
        out[i] = g_ringBuffer[g_ringReadPos % RING_BUFFER_SAMPLES];
        g_ringReadPos++;
    }
    pthread_mutex_unlock(&g_ringLock);
    return toRead;
}

static int ring_available(void) {
    long available = (long)(g_ringWritePos - g_ringReadPos);
    return (available < 0) ? 0 : (int)available;
}

// ============================================================
// Global state
// ============================================================

// Keyboard
static KeyCallback g_keyCallback = NULL;
static pthread_t g_keyThread;
static atomic_int g_keyListening = 0;
static int g_evdevFd = -1;

// Audio
static atomic_int g_isRecording = 0;
static pthread_t g_audioThread;

// Device change listener
static DeviceChangeCallback g_deviceChangeCallback = NULL;

// ============================================================
// 1. KEYBOARD LISTENER (evdev /dev/input)
// ============================================================

/* Find the first keyboard device in /dev/input/by-id/ or /dev/input/eventN */
static int find_keyboard_device(void) {
    /* Try /dev/input/by-id/ first, look for -kbd */
    DIR* dir = opendir("/dev/input/by-id");
    if (dir) {
        struct dirent* entry;
        while ((entry = readdir(dir)) != NULL) {
            if (strstr(entry->d_name, "-kbd") || strstr(entry->d_name, "keyboard")) {
                char path[512];
                snprintf(path, sizeof(path), "/dev/input/by-id/%s", entry->d_name);
                int fd = open(path, O_RDONLY | O_NONBLOCK);
                if (fd >= 0) {
                    closedir(dir);
                    return fd;
                }
            }
        }
        closedir(dir);
    }

    /* Fallback: scan /dev/input/eventN */
    for (int i = 0; i < 32; i++) {
        char path[64];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        /* Check if this device has EV_KEY capability */
        unsigned long evbit = 0;
        if (ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), &evbit) >= 0) {
            if (evbit & (1 << EV_KEY)) {
                return fd;
            }
        }
        close(fd);
    }
    return -1;
}

static void* keyboard_thread_proc(void* param) {
    (void)param;

    g_evdevFd = find_keyboard_device();
    if (g_evdevFd < 0) {
        fprintf(stderr, "[NativeInput] No keyboard device found. "
                "Try: sudo usermod -aG input $USER\n");
        atomic_store(&g_keyListening, 0);
        return NULL;
    }

    /* Set blocking mode for read */
    int flags = fcntl(g_evdevFd, F_GETFL, 0);
    fcntl(g_evdevFd, F_SETFL, flags & ~O_NONBLOCK);

    struct input_event ev;
    while (atomic_load(&g_keyListening)) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(g_evdevFd, &fds);
        struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 }; /* 100ms timeout */

        int ret = select(g_evdevFd + 1, &fds, NULL, NULL, &tv);
        if (ret <= 0) continue;

        ssize_t n = read(g_evdevFd, &ev, sizeof(ev));
        if (n != sizeof(ev)) continue;

        if (ev.type == EV_KEY && g_keyCallback) {
            /* ev.value: 0=up, 1=down, 2=repeat */
            if (ev.value == 0 || ev.value == 1) {
                g_keyCallback((int)ev.code, ev.value);
            }
        }
    }

    close(g_evdevFd);
    g_evdevFd = -1;
    return NULL;
}

EXPORT int start_keyboard_listener(KeyCallback callback) {
    if (atomic_load(&g_keyListening)) return 1;

    g_keyCallback = callback;
    atomic_store(&g_keyListening, 1);

    if (pthread_create(&g_keyThread, NULL, keyboard_thread_proc, NULL) != 0) {
        fprintf(stderr, "[NativeInput] Failed to create keyboard thread\n");
        atomic_store(&g_keyListening, 0);
        return 0;
    }
    pthread_detach(g_keyThread);
    return 1;
}

EXPORT void stop_keyboard_listener(void) {
    atomic_store(&g_keyListening, 0);
    g_keyCallback = NULL;
}

// ============================================================
// 2. KEY STATE CHECK
// ============================================================

EXPORT int check_key_pressed(int keyCode) {
    /* Read current state from evdev if available */
    if (g_evdevFd >= 0) {
        unsigned char keys[KEY_MAX / 8 + 1];
        memset(keys, 0, sizeof(keys));
        if (ioctl(g_evdevFd, EVIOCGKEY(sizeof(keys)), keys) >= 0) {
            return (keys[keyCode / 8] >> (keyCode % 8)) & 1;
        }
    }
    return 0;
}

// ============================================================
// 3. TEXT INJECTION (xdotool)
// ============================================================

EXPORT void inject_text(const char* text) {
    if (!text || !text[0]) return;

    /* Use xdotool for X11, ydotool for Wayland */
    const char* session_type = getenv("XDG_SESSION_TYPE");
    char cmd[4096];

    if (session_type && strcmp(session_type, "wayland") == 0) {
        /* Wayland: try wtype first, then ydotool */
        snprintf(cmd, sizeof(cmd), "wtype '%s' 2>/dev/null || ydotool type '%s' 2>/dev/null", text, text);
    } else {
        /* X11: xdotool */
        snprintf(cmd, sizeof(cmd), "xdotool type --clearmodifiers '%s'", text);
    }

    int ret = system(cmd);
    if (ret != 0) {
        fprintf(stderr, "[NativeInput] Text injection failed (ret=%d). "
                "Install xdotool (X11) or wtype (Wayland).\n", ret);
    }
}

// ============================================================
// 4. PERMISSIONS (Linux: check /dev/input access)
// ============================================================

EXPORT int check_permission_silent(void) {
    /* Check if we can read any input device */
    int fd = find_keyboard_device();
    if (fd >= 0) {
        close(fd);
        return 1;
    }
    return 0;
}

EXPORT int check_input_monitoring_permission(void) {
    return check_permission_silent();
}

EXPORT int check_accessibility_permission(void) {
    return 1; /* Linux doesn't have accessibility permission concept */
}

EXPORT int check_microphone_permission(void) {
    /* Try to open PulseAudio briefly */
    pa_sample_spec ss = {
        .format = PA_SAMPLE_S16LE,
        .rate = 16000,
        .channels = 1
    };
    int error;
    pa_simple* s = pa_simple_new(NULL, "SpeakOut", PA_STREAM_RECORD,
                                  NULL, "permission_check", &ss, NULL, NULL, &error);
    if (s) {
        pa_simple_free(s);
        return 1;
    }
    return 0;
}

// ============================================================
// 5. AUDIO RECORDING (PulseAudio + Ring Buffer)
// ============================================================

static void* audio_capture_thread(void* param) {
    (void)param;

    pa_sample_spec ss = {
        .format = PA_SAMPLE_S16LE,
        .rate = 16000,
        .channels = 1
    };

    int error;
    pa_simple* s = pa_simple_new(NULL, "SpeakOut", PA_STREAM_RECORD,
                                  NULL, "audio_capture", &ss, NULL, NULL, &error);
    if (!s) {
        fprintf(stderr, "[Audio] PulseAudio open failed: %s\n", pa_strerror(error));
        atomic_store(&g_isRecording, 0);
        return NULL;
    }

    /* Read in 20ms chunks: 16000 * 0.02 = 320 samples */
    int16_t buf[320];

    while (atomic_load(&g_isRecording)) {
        if (pa_simple_read(s, buf, sizeof(buf), &error) < 0) {
            fprintf(stderr, "[Audio] PulseAudio read error: %s\n", pa_strerror(error));
            break;
        }
        ring_write(buf, 320);
    }

    pa_simple_free(s);
    atomic_store(&g_isRecording, 0);
    return NULL;
}

EXPORT int start_audio_recording(void) {
    if (atomic_load(&g_isRecording)) return 1;

    ring_init();
    atomic_store(&g_isRecording, 1);

    if (pthread_create(&g_audioThread, NULL, audio_capture_thread, NULL) != 0) {
        fprintf(stderr, "[Audio] Failed to create audio thread\n");
        atomic_store(&g_isRecording, 0);
        return 0;
    }
    pthread_detach(g_audioThread);
    return 1;
}

EXPORT void stop_audio_recording(void) {
    atomic_store(&g_isRecording, 0);
    /* Wait briefly for thread to finish */
    usleep(100000); /* 100ms */
}

EXPORT int is_audio_recording(void) {
    return atomic_load(&g_isRecording) ? 1 : 0;
}

EXPORT int get_available_audio_samples(void) {
    return ring_available();
}

EXPORT int read_audio_buffer(int16_t* outSamples, int maxSamples) {
    if (!outSamples || maxSamples <= 0) return 0;
    return ring_read(outSamples, maxSamples);
}

EXPORT void native_free(void* ptr) {
    if (ptr) free(ptr);
}

// ============================================================
// 6. AUDIO DEVICE MANAGEMENT
// ============================================================

static char g_jsonBuffer[8192];

EXPORT const char* get_audio_input_devices(void) {
    /* Use pactl to list sources in JSON-ish format */
    FILE* fp = popen("pactl list sources short 2>/dev/null", "r");
    if (!fp) return "[]";

    int offset = 0;
    offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, "[");

    char line[1024];
    int first = 1;
    while (fgets(line, sizeof(line), fp)) {
        /* Format: index\tname\tmodule\tsample_spec\tstate */
        char* idx_str = strtok(line, "\t");
        char* name = strtok(NULL, "\t");
        if (!idx_str || !name) continue;

        /* Skip monitor sources (output monitors, not input) */
        if (strstr(name, ".monitor")) continue;

        if (!first) offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, ",");
        first = 0;

        offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset,
            "{\"id\":\"%s\",\"name\":\"%s\",\"isBluetooth\":%s,\"isBuiltIn\":false,\"sampleRate\":16000}",
            name, name,
            strstr(name, "bluez") ? "true" : "false"
        );

        if (offset >= (int)sizeof(g_jsonBuffer) - 256) break;
    }
    pclose(fp);

    offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, "]");
    return g_jsonBuffer;
}

EXPORT const char* get_current_input_device(void) {
    FILE* fp = popen("pactl get-default-source 2>/dev/null", "r");
    if (!fp) return "{}";

    char name[512] = {0};
    if (fgets(name, sizeof(name), fp)) {
        /* Remove trailing newline */
        size_t len = strlen(name);
        if (len > 0 && name[len-1] == '\n') name[len-1] = '\0';
    }
    pclose(fp);

    snprintf(g_jsonBuffer, sizeof(g_jsonBuffer),
        "{\"id\":\"%s\",\"name\":\"%s\",\"isBluetooth\":%s,\"isBuiltIn\":false,\"sampleRate\":16000}",
        name, name,
        strstr(name, "bluez") ? "true" : "false"
    );
    return g_jsonBuffer;
}

EXPORT int set_input_device(const char* deviceUID) {
    if (!deviceUID) return 0;
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "pactl set-default-source '%s' 2>/dev/null", deviceUID);
    return system(cmd) == 0 ? 1 : 0;
}

EXPORT int switch_to_builtin_mic(void) {
    /* Set default source to the first non-bluetooth source */
    return 1; /* No-op for now */
}

EXPORT int is_current_input_bluetooth(void) {
    const char* info = get_current_input_device();
    return strstr(info, "\"isBluetooth\":true") ? 1 : 0;
}

EXPORT int start_device_change_listener(DeviceChangeCallback callback) {
    g_deviceChangeCallback = callback;
    /* TODO: use pactl subscribe for device change events */
    return 1;
}

EXPORT void stop_device_change_listener(void) {
    g_deviceChangeCallback = NULL;
}

EXPORT const char* get_preferred_device_uid(void) {
    return "";
}

EXPORT void set_preferred_device_uid(const char* uid) {
    (void)uid;
}

// ============================================================
// 7. SIGNAL QUALITY ANALYSIS
// ============================================================

EXPORT const char* analyze_audio_quality(int16_t* samples, int sampleCount, int sampleRate) {
    if (!samples || sampleCount <= 0) return "{}";

    double sum = 0.0;
    for (int i = 0; i < sampleCount; i++) {
        double s = (double)samples[i] / 32768.0;
        sum += s * s;
    }
    double rms = sqrt(sum / sampleCount);
    double dbfs = 20.0 * log10(rms + 1e-10);

    snprintf(g_jsonBuffer, sizeof(g_jsonBuffer),
        "{\"rms\":%.6f,\"dbfs\":%.1f,\"sampleRate\":%d,\"sampleCount\":%d}",
        rms, dbfs, sampleRate, sampleCount
    );
    return g_jsonBuffer;
}

EXPORT int is_likely_telephone_quality(void) {
    return 0;
}
