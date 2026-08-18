// 日志目录切换的可执行测试。直接包含实现文件，验证真实的 C 状态转换。

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>

#define CGEventPost(tap, event) ((void)0)
#include "../native_input.m"

int main(void) {
  char path[1024];
  set_log_directory("/tmp/speakout-custom-log");
  get_log_path(path, sizeof(path));
  if (strstr(path, "/tmp/speakout-custom-log/") == NULL) {
    printf("自定义日志目录未生效\n");
    return 1;
  }

  set_log_directory("");
  get_log_path(path, sizeof(path));
  if (strstr(path, "/tmp/speakout-custom-log/") != NULL) {
    printf("空字符串仍沿用旧日志目录\n");
    return 1;
  }

  printf("ALL PASSED\n");
  return 0;
}
