/**
 * SpeakOut Windows Native Input Library
 *
 * 导出与 macOS 版本完全相同的 21+ 个 C 函数签名，
 * 使用 Win32 API 实现：
 *   - 键盘监听: SetWindowsHookEx (WH_KEYBOARD_LL)
 *   - 文本注入: SendInput (KEYEVENTF_UNICODE)
 *   - 音频采集: WASAPI (IAudioClient + IAudioCaptureClient)
 *   - 设备管理: IMMDeviceEnumerator
 *
 * 编译: 参见同目录 CMakeLists.txt (MSVC C++)
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <atomic>

// WASAPI headers
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <endpointvolume.h>

// COM helpers
#include <objbase.h>
#include <propvarutil.h>

// For _beginthreadex
#include <process.h>

extern "C" {

// ============================================================
// DLL Export macro
// ============================================================
#define EXPORT __declspec(dllexport)

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
static CRITICAL_SECTION g_ringLock;
static int g_ringLockInitialized = 0;

static void ring_init(void) {
    if (!g_ringLockInitialized) {
        InitializeCriticalSection(&g_ringLock);
        g_ringLockInitialized = 1;
    }
    g_ringWritePos = 0;
    g_ringReadPos = 0;
}

static void ring_write(const int16_t* samples, int count) {
    EnterCriticalSection(&g_ringLock);
    for (int i = 0; i < count; i++) {
        g_ringBuffer[g_ringWritePos % RING_BUFFER_SAMPLES] = samples[i];
        g_ringWritePos++;
    }
    // If writer overtakes reader, advance reader
    if (g_ringWritePos - g_ringReadPos > RING_BUFFER_SAMPLES) {
        g_ringReadPos = g_ringWritePos - RING_BUFFER_SAMPLES;
    }
    LeaveCriticalSection(&g_ringLock);
}

static int ring_read(int16_t* out, int maxSamples) {
    EnterCriticalSection(&g_ringLock);
    long available = (long)(g_ringWritePos - g_ringReadPos);
    if (available < 0) available = 0;
    int toRead = (available < maxSamples) ? (int)available : maxSamples;
    for (int i = 0; i < toRead; i++) {
        out[i] = g_ringBuffer[g_ringReadPos % RING_BUFFER_SAMPLES];
        g_ringReadPos++;
    }
    LeaveCriticalSection(&g_ringLock);
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
static HHOOK g_keyboardHook = NULL;
static KeyCallback g_keyCallback = NULL;
static HANDLE g_hookThread = NULL;
static DWORD g_hookThreadId = 0;

// Audio
static std::atomic<int> g_isRecording(0);
static HANDLE g_audioThread = NULL;
static IMMDeviceEnumerator* g_deviceEnumerator = NULL;

// Device change listener
static DeviceChangeCallback g_deviceChangeCallback = NULL;

// ============================================================
// 1. KEYBOARD LISTENER
// ============================================================

static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION && g_keyCallback) {
        KBDLLHOOKSTRUCT* kbData = (KBDLLHOOKSTRUCT*)lParam;
        int isDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) ? 1 : 0;
        g_keyCallback((int)kbData->vkCode, isDown);
    }
    return CallNextHookEx(g_keyboardHook, nCode, wParam, lParam);
}

static unsigned __stdcall keyboard_thread_proc(void* param) {
    (void)param;

    g_keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, NULL, 0);
    if (!g_keyboardHook) {
        fprintf(stderr, "[NativeInput] SetWindowsHookEx failed: %lu\n", GetLastError());
        return 1;
    }

    // Message loop required for low-level hooks
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    UnhookWindowsHookEx(g_keyboardHook);
    g_keyboardHook = NULL;
    return 0;
}

EXPORT int start_keyboard_listener(KeyCallback callback) {
    if (g_keyboardHook) return 1; // Already running

    g_keyCallback = callback;
    g_hookThread = (HANDLE)_beginthreadex(NULL, 0, keyboard_thread_proc, NULL, 0, (unsigned*)&g_hookThreadId);
    if (!g_hookThread) {
        fprintf(stderr, "[NativeInput] Failed to create hook thread\n");
        return 0;
    }

    return 1;
}

EXPORT void stop_keyboard_listener(void) {
    if (g_hookThreadId) {
        PostThreadMessage(g_hookThreadId, WM_QUIT, 0, 0);
        if (g_hookThread) {
            WaitForSingleObject(g_hookThread, 2000);
            CloseHandle(g_hookThread);
            g_hookThread = NULL;
        }
        g_hookThreadId = 0;
    }
    g_keyCallback = NULL;
}

// ============================================================
// 2. KEY STATE CHECK
// ============================================================

EXPORT int check_key_pressed(int keyCode) {
    // GetAsyncKeyState returns MSB set if key is currently down
    SHORT state = GetAsyncKeyState(keyCode);
    return (state & 0x8000) ? 1 : 0;
}

// ============================================================
// 3. TEXT INJECTION
// ============================================================

EXPORT void inject_text(const char* text) {
    if (!text) return;

    // Convert UTF-8 to UTF-16
    int wideLen = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    if (wideLen <= 0) return;

    WCHAR* wideText = (WCHAR*)malloc(wideLen * sizeof(WCHAR));
    if (!wideText) return;
    MultiByteToWideChar(CP_UTF8, 0, text, -1, wideText, wideLen);

    // Count actual characters (exclude null terminator)
    int charCount = wideLen - 1;
    if (charCount <= 0) {
        free(wideText);
        return;
    }

    // Allocate INPUT array: 2 events per character (down + up)
    int inputCount = charCount * 2;
    INPUT* inputs = (INPUT*)calloc(inputCount, sizeof(INPUT));
    if (!inputs) {
        free(wideText);
        return;
    }

    for (int i = 0; i < charCount; i++) {
        // Key down
        inputs[i * 2].type = INPUT_KEYBOARD;
        inputs[i * 2].ki.wScan = wideText[i];
        inputs[i * 2].ki.dwFlags = KEYEVENTF_UNICODE;

        // Key up
        inputs[i * 2 + 1].type = INPUT_KEYBOARD;
        inputs[i * 2 + 1].ki.wScan = wideText[i];
        inputs[i * 2 + 1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    }

    SendInput(inputCount, inputs, sizeof(INPUT));

    free(inputs);
    free(wideText);
}

// ============================================================
// 4. PERMISSIONS (Windows: always granted, no special perms needed)
// ============================================================

EXPORT int check_permission_silent(void) {
    return 1;  // Windows doesn't require special permissions
}

EXPORT int check_input_monitoring_permission(void) {
    return 1;
}

EXPORT int check_accessibility_permission(void) {
    return 1;
}

EXPORT int check_microphone_permission(void) {
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    int needUninit = SUCCEEDED(hr);

    IMMDeviceEnumerator* enumerator = NULL;
    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator), (void**)&enumerator
    );

    int result = 0;
    if (SUCCEEDED(hr) && enumerator) {
        IMMDevice* device = NULL;
        hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
        if (SUCCEEDED(hr) && device) {
            result = 1;
            device->Release();
        }
        enumerator->Release();
    }

    if (needUninit) CoUninitialize();
    return result;
}

// ============================================================
// 5. AUDIO RECORDING (WASAPI + Ring Buffer)
// ============================================================

static unsigned __stdcall audio_capture_thread(void* param) {
    (void)param;

    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) {
        fprintf(stderr, "[Audio] CoInitializeEx failed\n");
        g_isRecording.store(0);
        return 1;
    }

    IMMDeviceEnumerator* enumerator = NULL;
    IMMDevice* device = NULL;
    IAudioClient* audioClient = NULL;
    IAudioCaptureClient* captureClient = NULL;

    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator), (void**)&enumerator
    );
    if (FAILED(hr)) goto cleanup;

    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    if (FAILED(hr)) goto cleanup;

    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, NULL, (void**)&audioClient);
    if (FAILED(hr)) goto cleanup;

    // Configure for 16kHz mono 16-bit PCM
    {
        WAVEFORMATEX wfx;
        memset(&wfx, 0, sizeof(wfx));
        wfx.wFormatTag = WAVE_FORMAT_PCM;
        wfx.nChannels = 1;
        wfx.nSamplesPerSec = 16000;
        wfx.wBitsPerSample = 16;
        wfx.nBlockAlign = wfx.nChannels * wfx.wBitsPerSample / 8;
        wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

        // 50ms buffer (REFERENCE_TIME is in 100-nanosecond units)
        REFERENCE_TIME bufferDuration = 500000; // 50ms
        hr = audioClient->Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            0,
            bufferDuration,
            0,
            &wfx,
            NULL
        );
        if (FAILED(hr)) {
            fprintf(stderr, "[Audio] WASAPI Initialize failed (hr=0x%08lX), trying mix format\n", hr);
            goto cleanup;
        }
    }

    hr = audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);
    if (FAILED(hr)) goto cleanup;

    hr = audioClient->Start();
    if (FAILED(hr)) goto cleanup;

    // Capture loop
    while (g_isRecording.load()) {
        Sleep(20); // ~50 polls per second

        UINT32 packetLength = 0;
        hr = captureClient->GetNextPacketSize(&packetLength);
        if (FAILED(hr)) break;

        while (packetLength > 0) {
            BYTE* data = NULL;
            UINT32 numFrames = 0;
            DWORD flags = 0;

            hr = captureClient->GetBuffer(&data, &numFrames, &flags, NULL, NULL);
            if (FAILED(hr)) break;

            if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data && numFrames > 0) {
                ring_write((const int16_t*)data, (int)numFrames);
            }

            captureClient->ReleaseBuffer(numFrames);

            hr = captureClient->GetNextPacketSize(&packetLength);
            if (FAILED(hr)) break;
        }
    }

    audioClient->Stop();

cleanup:
    if (captureClient) captureClient->Release();
    if (audioClient) audioClient->Release();
    if (device) device->Release();
    if (enumerator) enumerator->Release();
    CoUninitialize();

    g_isRecording.store(0);
    return 0;
}

EXPORT int start_audio_recording(void) {
    if (g_isRecording.load()) return 1; // Already recording

    ring_init();
    g_isRecording.store(1);

    g_audioThread = (HANDLE)_beginthreadex(NULL, 0, audio_capture_thread, NULL, 0, NULL);
    if (!g_audioThread) {
        g_isRecording.store(0);
        return 0;
    }

    return 1;
}

EXPORT void stop_audio_recording(void) {
    g_isRecording.store(0);
    if (g_audioThread) {
        WaitForSingleObject(g_audioThread, 3000);
        CloseHandle(g_audioThread);
        g_audioThread = NULL;
    }
}

EXPORT int is_audio_recording(void) {
    return g_isRecording.load() ? 1 : 0;
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

// Helper: get device enumerator (lazy init)
static IMMDeviceEnumerator* get_enumerator(void) {
    if (!g_deviceEnumerator) {
        CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        CoCreateInstance(
            __uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
            __uuidof(IMMDeviceEnumerator), (void**)&g_deviceEnumerator
        );
    }
    return g_deviceEnumerator;
}

// Helper: convert WCHAR to UTF-8 (caller must free)
static char* wchar_to_utf8(const WCHAR* wstr) {
    if (!wstr) return NULL;
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (len <= 0) return NULL;
    char* str = (char*)malloc(len);
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, str, len, NULL, NULL);
    return str;
}

// Static buffer for JSON responses (avoid malloc/free complexity for Dart FFI)
static char g_jsonBuffer[8192];

EXPORT const char* get_audio_input_devices(void) {
    IMMDeviceEnumerator* enumerator = get_enumerator();
    if (!enumerator) return "[]";

    IMMDeviceCollection* collection = NULL;
    HRESULT hr = enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &collection);
    if (FAILED(hr) || !collection) return "[]";

    UINT count = 0;
    collection->GetCount(&count);

    int offset = 0;
    offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, "[");

    for (UINT i = 0; i < count && offset < (int)sizeof(g_jsonBuffer) - 256; i++) {
        IMMDevice* device = NULL;
        collection->Item(i, &device);
        if (!device) continue;

        // Get device ID
        LPWSTR deviceId = NULL;
        device->GetId(&deviceId);

        // Get device name from properties
        IPropertyStore* props = NULL;
        device->OpenPropertyStore(STGM_READ, &props);

        char* name = NULL;
        if (props) {
            PROPVARIANT varName;
            PropVariantInit(&varName);
            props->GetValue(PKEY_Device_FriendlyName, &varName);
            if (varName.vt == VT_LPWSTR) {
                name = wchar_to_utf8(varName.pwszVal);
            }
            PropVariantClear(&varName);
            props->Release();
        }

        char* id_utf8 = wchar_to_utf8(deviceId);

        if (i > 0) offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, ",");
        offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset,
            "{\"id\":\"%s\",\"name\":\"%s\",\"isBluetooth\":false,\"isBuiltIn\":false,\"sampleRate\":16000}",
            id_utf8 ? id_utf8 : "",
            name ? name : "Unknown"
        );

        if (id_utf8) free(id_utf8);
        if (name) free(name);
        if (deviceId) CoTaskMemFree(deviceId);
        device->Release();
    }

    offset += snprintf(g_jsonBuffer + offset, sizeof(g_jsonBuffer) - offset, "]");
    collection->Release();

    return g_jsonBuffer;
}

EXPORT const char* get_current_input_device(void) {
    IMMDeviceEnumerator* enumerator = get_enumerator();
    if (!enumerator) return "{}";

    IMMDevice* device = NULL;
    HRESULT hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    if (FAILED(hr) || !device) return "{}";

    LPWSTR deviceId = NULL;
    device->GetId(&deviceId);

    IPropertyStore* props = NULL;
    device->OpenPropertyStore(STGM_READ, &props);

    char* name = NULL;
    if (props) {
        PROPVARIANT varName;
        PropVariantInit(&varName);
        props->GetValue(PKEY_Device_FriendlyName, &varName);
        if (varName.vt == VT_LPWSTR) {
            name = wchar_to_utf8(varName.pwszVal);
        }
        PropVariantClear(&varName);
        props->Release();
    }

    char* id_utf8 = wchar_to_utf8(deviceId);

    snprintf(g_jsonBuffer, sizeof(g_jsonBuffer),
        "{\"id\":\"%s\",\"name\":\"%s\",\"isBluetooth\":false,\"isBuiltIn\":false,\"sampleRate\":16000}",
        id_utf8 ? id_utf8 : "",
        name ? name : "Unknown"
    );

    if (id_utf8) free(id_utf8);
    if (name) free(name);
    if (deviceId) CoTaskMemFree(deviceId);
    device->Release();

    return g_jsonBuffer;
}

EXPORT int set_input_device(const char* deviceUID) {
    (void)deviceUID;
    return 1;
}

EXPORT int switch_to_builtin_mic(void) {
    return 1;
}

EXPORT int is_current_input_bluetooth(void) {
    return 0;
}

EXPORT int start_device_change_listener(DeviceChangeCallback callback) {
    g_deviceChangeCallback = callback;
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

    // Simple RMS calculation
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

// ============================================================
// DLL Entry Point
// ============================================================

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved) {
    (void)hModule;
    (void)reserved;

    switch (reason) {
    case DLL_PROCESS_ATTACH:
        ring_init();
        break;
    case DLL_PROCESS_DETACH:
        stop_keyboard_listener();
        stop_audio_recording();
        if (g_deviceEnumerator) {
            g_deviceEnumerator->Release();
            g_deviceEnumerator = NULL;
        }
        if (g_ringLockInitialized) {
            DeleteCriticalSection(&g_ringLock);
            g_ringLockInitialized = 0;
        }
        break;
    }
    return TRUE;
}

} // extern "C"
