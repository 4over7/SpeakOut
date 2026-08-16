#import <AppKit/AppKit.h>
int main(void) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSInteger c0 = pb.changeCount;
    NSInteger cc = [pb clearContents];          // 出货代码的 ourChangeCount
    NSInteger c1 = pb.changeCount;
    [pb setString:@"speakout-probe-XYZ" forType:NSPasteboardTypeString];
    NSInteger c2 = pb.changeCount;
    printf("before=%ld  clearContents返回=%ld  clear后=%ld  setString后=%ld\n",
           (long)c0, (long)cc, (long)c1, (long)c2);
    printf("判据 (setString后 == clearContents返回) ? %s\n",
           (c2 == cc) ? "成立 → 还原不会被自己的写入打断"
                      : "不成立 → 每次注入的还原都必然被跳过（100% 必现）");
    // 停 900ms 再看有没有旁观者动过（模拟 800ms 还原窗口）
    usleep(900000);
    NSInteger c3 = pb.changeCount;
    printf("900ms 后=%ld  期间是否有旁观者改动: %s\n", (long)c3,
           (c3 == c2) ? "没有" : "有！");
  }
  return 0;
}
