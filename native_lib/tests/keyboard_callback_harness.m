// 键盘回调 trampoline 生命周期的可执行并发测试。
// 不创建真实 EventTap，只验证 stop 必须等待已进入的回调退出。

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>

#define CGEventPost(tap, event) ((void)0)
#include "../native_input.m"

static pthread_mutex_t harnessMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t harnessCondition = PTHREAD_COND_INITIALIZER;
static bool callbackEntered = false;
static bool releaseCallback = false;
static atomic_bool stopReturned = false;

static void blocking_callback(int keyCode, bool isDown, unsigned int flags) {
  (void)keyCode;
  (void)isDown;
  (void)flags;
  pthread_mutex_lock(&harnessMutex);
  callbackEntered = true;
  pthread_cond_broadcast(&harnessCondition);
  while (!releaseCallback) {
    pthread_cond_wait(&harnessCondition, &harnessMutex);
  }
  pthread_mutex_unlock(&harnessMutex);
}

static void *emit_thread(void *unused) {
  (void)unused;
  emit_key_callback(58, true, 0);
  return NULL;
}

static void *stop_thread(void *unused) {
  (void)unused;
  stop_keyboard_listener();
  atomic_store(&stopReturned, true);
  return NULL;
}

int main(void) {
  pthread_mutex_lock(&keyCallbackMutex);
  dartCallback = blocking_callback;
  pthread_mutex_unlock(&keyCallbackMutex);
  atomic_store(&isMonitoring, true);

  pthread_t emitter;
  pthread_create(&emitter, NULL, emit_thread, NULL);

  pthread_mutex_lock(&harnessMutex);
  while (!callbackEntered) {
    pthread_cond_wait(&harnessCondition, &harnessMutex);
  }
  pthread_mutex_unlock(&harnessMutex);

  pthread_t stopper;
  pthread_create(&stopper, NULL, stop_thread, NULL);
  usleep(50000);
  if (atomic_load(&stopReturned)) {
    fprintf(stderr, "stop 未等待在途回调\n");
    return 1;
  }

  pthread_mutex_lock(&harnessMutex);
  releaseCallback = true;
  pthread_cond_broadcast(&harnessCondition);
  pthread_mutex_unlock(&harnessMutex);

  pthread_join(emitter, NULL);
  pthread_join(stopper, NULL);
  if (!atomic_load(&stopReturned) || dartCallback != NULL) {
    fprintf(stderr, "stop 返回后 trampoline 仍可达\n");
    return 1;
  }

  printf("ALL PASSED\n");
  return 0;
}
