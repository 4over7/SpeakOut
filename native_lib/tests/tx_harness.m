// 剪贴板事务的**可执行**交错测试。
//
// 为什么需要它：源码级断言只能证明「代码长这样」，证不了「这么执行」。
// 连续几轮 review 都能构造出骗过文本断言的写法（字符串诱饵、恒真条件、
// if(0) 包起来……）。这里直接跑真实的 tx_* 函数并检查最终剪贴板内容，
// 那类诱饵一个都骗不过去。
//
// 两条安全前提：
//   1. 用 pasteboardWithUniqueName，**不碰用户的通用剪贴板**；
//   2. 把 CGEventPost 宏掉，**不往当前焦点窗口发任何按键**。
// 二者都不需要改动生产代码 —— 直接 #include 实现文件即可拿到 static 函数。

// 先把系统头引进来，**再**宏掉 CGEventPost ——
// 反过来的话宏会先破坏 CGEvent.h 里的函数声明本身。
// native_input.m 的 import 有 include guard，重复引入无副作用。
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <AudioToolbox/AudioToolbox.h>
#include <Carbon/Carbon.h>
#include <Foundation/Foundation.h>

#define CGEventPost(tap, event) ((void)0)   // 绝不真的发键
#include "../native_input.m"

#import <objc/runtime.h>

static int g_fail = 0;

// ---- 失败注入：让 setString:forType: 按需返回 NO ----
//
// 有些分支（比如「clearContents 之后 setString 失败」）自然触发不了，
// 而那条恰恰是第 43 轮的 P1（返回 0 会让调用方销毁快照、剪贴板永久为空）。
// 用 runtime swizzle 在**测试文件里**注入失败，生产代码一行不改 ——
// 不把注入需求塞进实现，是这个项目踩过坑之后立的规矩。
static BOOL g_failSetString = NO;
static BOOL (*g_origSetString)(id, SEL, NSString *, NSString *);

static BOOL test_setString(id self, SEL _cmd, NSString *str, NSString *type) {
  if (g_failSetString) return NO;
  return g_origSetString(self, _cmd, str, type);
}

static void install_setstring_hook(void) {
  Method m = class_getInstanceMethod([NSPasteboard class],
                                     @selector(setString:forType:));
  g_origSetString = (BOOL (*)(id, SEL, NSString *, NSString *))
      method_getImplementation(m);
  method_setImplementation(m, (IMP)test_setString);
}

static void expect_str(const char *what, NSString *got, NSString *want) {
  BOOL ok = (got == nil && want == nil) || [got isEqualToString:want];
  if (!ok) {
    g_fail++;
    printf("  ✗ %s: got=%s want=%s\n", what,
           got ? [got UTF8String] : "(nil)", want ? [want UTF8String] : "(nil)");
  } else {
    printf("  ✓ %s\n", what);
  }
}

/// 直接收尾（不走 800ms 异步），拿到确定性结果
static void finish_now(NSPasteboard *pb, uint64_t gen) {
  NSArray *retry = nil;
  NSInteger retryExpected = -1;
  pthread_mutex_lock(&clipTxMutex);
  tx_finish_locked(pb, gen, &retry, &retryExpected);
  pthread_mutex_unlock(&clipTxMutex);
}

/// 把事务状态清干净，让每个用例互不影响
static void reset_tx(void) {
  pthread_mutex_lock(&clipTxMutex);
  _txActive = NO; _txOriginal = nil; _txOriginalValid = NO;
  _txToken = nil; _txExpectedChangeCount = -1;
  _txHoldDepth = 0; _txRestorePending = NO; _txPasteFailed = NO;
  pthread_mutex_unlock(&clipTxMutex);
}

static NSPasteboard *fresh_pb(NSString *initial) {
  NSPasteboard *pb = [NSPasteboard pasteboardWithUniqueName];
  [pb clearContents];
  if (initial) [pb setString:initial forType:NSPasteboardTypeString];
  reset_tx();
  return pb;
}

static uint64_t paste(NSPasteboard *pb, NSString *text) {
  pthread_mutex_lock(&clipTxMutex);
  uint64_t gen = 0;
  if (tx_begin_locked(pb)) gen = tx_paste_locked(pb, text);
  pthread_mutex_unlock(&clipTxMutex);
  return gen;
}

/// 模拟「别的进程/用户」占用剪贴板
static void external_write(NSPasteboard *pb, NSString *text) {
  [pb clearContents];
  [pb setString:text forType:NSPasteboardTypeString];
}

int main(void) {
  @autoreleasepool {
    printf("== 1. 基本还原：X → 注入 A → 收尾 → 应还原 X ==\n");
    {
      NSPasteboard *pb = fresh_pb(@"X");
      uint64_t gen = paste(pb, @"A");
      finish_now(pb, gen);
      expect_str("还原为 X", [pb stringForType:NSPasteboardTypeString], @"X");
    }

    printf("== 2. 用户中途接管：X → 注入 A → 用户复制 Z → 收尾 → 应保留 Z ==\n");
    {
      NSPasteboard *pb = fresh_pb(@"X");
      uint64_t gen = paste(pb, @"A");
      external_write(pb, @"Z");
      finish_now(pb, gen);
      expect_str("保留用户的 Z", [pb stringForType:NSPasteboardTypeString], @"Z");
    }

    printf("== 3. 接管后又注入：X → A → 用户复制 Z → 注入 B → 收尾 → 应还原 Z ==\n");
    {
      NSPasteboard *pb = fresh_pb(@"X");
      paste(pb, @"A");
      external_write(pb, @"Z");
      uint64_t gen2 = paste(pb, @"B");
      finish_now(pb, gen2);
      expect_str("还原为 Z（不是 X）",
                 [pb stringForType:NSPasteboardTypeString], @"Z");
    }

    printf("== 4. 原剪贴板为空：空 → 注入 A → 收尾 → 应回到空 ==\n");
    {
      NSPasteboard *pb = fresh_pb(nil);
      uint64_t gen = paste(pb, @"A");
      // 先确认**注入真的发生了** —— 否则「拒绝注入」和「还原成空」
      // 最终状态一样，这条用例就区分不出来（实测漏报过）。
      if (gen == 0) { g_fail++; printf("  ✗ 空剪贴板下注入被拒绝了\n"); }
      else printf("  ✓ 注入已发生\n");
      expect_str("注入期间剪贴板是 A",
                 [pb stringForType:NSPasteboardTypeString], @"A");
      finish_now(pb, gen);
      expect_str("回到空", [pb stringForType:NSPasteboardTypeString], nil);
    }

    printf("== 5. 流式会话：X → begin → chunk A → chunk B → end → 应还原 X ==\n");
    {
      NSPasteboard *pb = fresh_pb(@"X");
      pthread_mutex_lock(&clipTxMutex);
      tx_begin_locked(pb);
      _txHoldDepth++;
      tx_paste_locked(pb, @"A");
      uint64_t gen = tx_paste_locked(pb, @"B");
      _txHoldDepth--;
      pthread_mutex_unlock(&clipTxMutex);
      finish_now(pb, gen);
      expect_str("还原为 X", [pb stringForType:NSPasteboardTypeString], @"X");
    }

    printf("== 6. 同内容但无 token：别人写了和我们一样的文字 → 不得还原 ==\n");
    {
      NSPasteboard *pb = fresh_pb(@"X");
      uint64_t gen = paste(pb, @"A");
      external_write(pb, @"A"); // 内容相同、没有我们的 token
      finish_now(pb, gen);
      expect_str("保留对方的 A（内容相同也不能认作自己的）",
                 [pb stringForType:NSPasteboardTypeString], @"A");
    }

    printf("== 7. 连注两次：X → 注入 A → 注入 B → 收尾 → 应还原 X（不是 A）==\n");
    {
      // 这条专门盯「事务已开启仍重拍快照」：重拍的话第二次会把 A 当成
      // 用户的原始内容，收尾还原 A —— 就是第 33 轮那条 N3 丢数据缺陷。
      NSPasteboard *pb = fresh_pb(@"X");
      paste(pb, @"A");
      uint64_t gen2 = paste(pb, @"B");
      finish_now(pb, gen2);
      expect_str("还原为 X（重拍的话会变成 A）",
                 [pb stringForType:NSPasteboardTypeString], @"X");
    }

    printf("== 8. 会话未写入即接管：X → begin → 用户复制 Z → end → 应保留 Z ==\n");
    {
      // 这条专门盯「所有权判据丢掉 changeCount」：本事务一次都没写过剪贴板，
      // _txToken 为 nil，判据只剩 changeCount。去掉它就会直接返回 YES，
      // 把用户刚复制的 Z 换回 X。
      NSPasteboard *pb = fresh_pb(@"X");
      pthread_mutex_lock(&clipTxMutex);
      tx_begin_locked(pb);
      _txHoldDepth++;
      _txHoldDepth--;
      uint64_t gen = _txGeneration;
      pthread_mutex_unlock(&clipTxMutex);
      external_write(pb, @"Z");
      finish_now(pb, gen);
      expect_str("保留用户的 Z", [pb stringForType:NSPasteboardTypeString], @"Z");
    }

    printf("== 9. 快照不可信时不得还原：标记 invalid → 收尾 → 应保持现状 ==\n");
    {
      // 快照拍不稳时手里没有可信内容，还原等于拿垃圾覆盖现状。
      NSPasteboard *pb = fresh_pb(@"X");
      uint64_t gen = paste(pb, @"A");
      pthread_mutex_lock(&clipTxMutex);
      _txOriginalValid = NO;   // 模拟「快照当时就没拍稳」
      pthread_mutex_unlock(&clipTxMutex);
      finish_now(pb, gen);
      expect_str("保持 A，不拿不可信快照覆盖",
                 [pb stringForType:NSPasteboardTypeString], @"A");
    }

    printf("== 10. setString 失败：clear 之后写失败 → 仍须还原 X，不能留空 ==\n");
    {
      // 第 43 轮的 P1：这条路径返回 0 的话，调用方会以为「剪贴板没动过」，
      // 直接销毁快照且不安排还原 —— 用户剪贴板**永久为空**。
      install_setstring_hook();
      NSPasteboard *pb = fresh_pb(@"X");
      g_failSetString = YES;
      uint64_t gen = paste(pb, @"A");
      g_failSetString = NO;
      if (gen == 0) {
        g_fail++;
        printf("  ✗ 返回 0：调用方会当成「剪贴板没动过」而销毁快照\n");
      } else {
        printf("  ✓ 返回非零，收尾会照常进行\n");
      }
      finish_now(pb, gen);
      expect_str("仍还原为 X（不能留空）",
                 [pb stringForType:NSPasteboardTypeString], @"X");
    }

    printf("\n%s (%d 处不符)\n", g_fail ? "FAILED" : "ALL PASSED", g_fail);
    return g_fail ? 1 : 0;
  }
}
