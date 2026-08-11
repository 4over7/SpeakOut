import Foundation
import AppKit

// 剪贴板还原的竞态验证 —— Dart 测试够不着原生层，只能这样直接打 dylib。
//   swift tools/clipboard_race/clip_race.swift normal   # 无人打扰 → 应还原原剪贴板
//   swift tools/clipboard_race/clip_race.swift race     # 还原窗口内用户复制 → 不该被覆盖
// 注意：会真的发一次 Cmd+V，请把前台切到无害的地方（终端即可）。
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let dylibPath = repoRoot.appendingPathComponent("native_lib/libnative_input.dylib").path

// 直接调 dylib 的 inject_text，绕开 app 录音流程
typealias InjectFn = @convention(c) (UnsafePointer<CChar>) -> Void
let handle = dlopen(dylibPath, RTLD_NOW)!
let inject = unsafeBitCast(dlsym(handle, "inject_text")!, to: InjectFn.self)

let pb = NSPasteboard.general

func setClip(_ s: String) { pb.clearContents(); pb.setString(s, forType: .string) }
func clip() -> String { pb.string(forType: .string) ?? "<nil>" }

let scenario = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "race"

setClip("ORIGINAL_USER_CLIPBOARD")
print("初始剪贴板: \(clip())")

inject("INJECTED_TEXT")          // 内部：存剪贴板 → 写入 → Cmd+V → 800ms 后还原

if scenario == "race" {
    // 模拟用户在还原窗口内自己复制了别的东西
    usleep(200_000)              // 200ms，远早于 800ms 还原
    setClip("USER_COPIED_LATER")
    print("200ms 时用户复制: \(clip())")
}

// 等还原定时器过去
usleep(1_200_000)
print("1.2s 后剪贴板: \(clip())")

switch scenario {
case "race":
    if clip() == "USER_COPIED_LATER" {
        print("✅ changeCount 保护生效：没有覆盖用户新复制的内容")
    } else {
        print("❌ 保护失效：用户复制的内容被还原逻辑吃掉了 → \(clip())")
    }
default:
    if clip() == "ORIGINAL_USER_CLIPBOARD" {
        print("✅ 正常路径：原剪贴板已还原")
    } else {
        print("❌ 原剪贴板未还原 → \(clip())")
    }
}
