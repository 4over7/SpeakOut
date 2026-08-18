// AudioQueue stop/dispose 状态的可执行测试宿主。
// 系统函数全部在测试文件里替换，不会打开或关闭真实麦克风。

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>

static OSStatus g_stopStatus = noErr;
static OSStatus g_disposeStatus = noErr;
static int g_stopCalls = 0;
static int g_disposeCalls = 0;

static OSStatus test_audio_queue_stop(AudioQueueRef queue, Boolean immediate) {
  (void)queue;
  (void)immediate;
  g_stopCalls++;
  return g_stopStatus;
}

static OSStatus test_audio_queue_dispose(AudioQueueRef queue, Boolean immediate) {
  (void)queue;
  (void)immediate;
  g_disposeCalls++;
  return g_disposeStatus;
}

#define AudioQueueStop test_audio_queue_stop
#define AudioQueueDispose test_audio_queue_dispose
#include "../native_input.m"

static int failures = 0;

static void expect_true(const char *label, int condition) {
  if (condition) {
    printf("  ✓ %s\n", label);
  } else {
    failures++;
    printf("  ✗ %s\n", label);
  }
}

static void reset_queue(void) {
  audioQueue = (AudioQueueRef)(uintptr_t)0x1;
  atomic_store(&isRecording, true);
  g_stopStatus = noErr;
  g_disposeStatus = noErr;
  g_stopCalls = 0;
  g_disposeCalls = 0;
}

int main(void) {
  @autoreleasepool {
    printf("== 1. 已停止状态必须幂等成功 ==\n");
    audioQueue = NULL;
    atomic_store(&isRecording, true);
    expect_true("返回成功", stop_audio_recording() == 1);
    expect_true("录音标志清零", !atomic_load(&isRecording));
    expect_true("不调用系统函数", g_stopCalls == 0 && g_disposeCalls == 0);

    printf("== 2. Stop 失败但 Dispose 成功，最终关闭仍算成功 ==\n");
    reset_queue();
    g_stopStatus = -1;
    expect_true("返回成功", stop_audio_recording() == 1);
    expect_true("两步都执行", g_stopCalls == 1 && g_disposeCalls == 1);
    expect_true("句柄清空", audioQueue == NULL);

    printf("== 3. Dispose 失败必须回传，且返回后不得再持有句柄 ==\n");
    reset_queue();
    g_disposeStatus = -2;
    expect_true("返回失败", stop_audio_recording() == 0);
    expect_true("录音标志清零", !atomic_load(&isRecording));
    expect_true("句柄清空", audioQueue == NULL);

    if (failures == 0) {
      printf("ALL PASSED\n");
      return 0;
    }
    printf("%d FAILED\n", failures);
    return 1;
  }
}
