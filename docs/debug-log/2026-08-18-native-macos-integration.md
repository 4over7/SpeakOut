# Native/macOS 集成闭环（2026-08-18）

## 第 1 轮：普通 Flutter 构建的浮窗波形静默

### 现象

普通 `flutter build macos` 的 App 包内只有 Flutter assets 中的 `libnative_input.dylib`，AppDelegate 却只查 `Contents/MacOS/native_lib`。后者仅由安装脚本补拷，因此开发构建的 Dart 录音可用、原生浮窗电平函数始终加载失败。

### 假设·判断原因

Dart `NativeInput._resolveDylibPath()` 已覆盖两种布局；Swift 与它漂移，且构建产物的 `find` 结果只命中 assets 路径，足以确定不是系统或 `dlopen` 限制。

### 措施

AppDelegate 按与 Dart 相同的顺序查安装目录与 Flutter assets，保留成功的 handle；符号缺失时关闭失败 handle。波形启动前先废止旧 Timer。原生日志不再输出识别文本、用户目录或错误 details；NSOpenPanel 使用系统本地化默认文案。

### 验证结果

macOS Debug 构建成功；对 App 包内精确 assets 路径执行 `dlopen + dlsym + get_audio_level()`，返回 `0.0`，证明加载与调用均成功。对应源码不变量测试通过。

### 复盘

安装脚本产物不能代表 `flutter run/build` 的目录形态。跨语言各自解析同一资源时，候选顺序必须保持一致，并用最终 App 包验证。

## 第 2 轮：键盘 trampoline 拆卸竞态

### 现象

EventTap 回调直接调用全局 `dartCallback`，`stop_keyboard_listener` 则无同步地清指针并返回。Dart 随后关闭 `NativeCallable.listener`；若回调已经读到旧指针但尚未调用，就会触发释放后的 trampoline。

### 假设·判断原因

设备变化监听已有同类锁与完整生命周期说明，键盘监听却缺少同样的“stop 返回即无在途调用”边界。Flutter 的 EventTap 与 Dart isolate 不在同一执行线程，不能用调用顺序代替同步。

### 措施

所有按键上报统一经过 `emit_key_callback`，用 `keyCallbackMutex` 包住指针读取与立即返回的 listener trampoline 调用；stop 先关闭 monitoring，再等待在途调用并清指针。启动失败也清理回调状态。

### 验证结果

新增 Objective-C 并发宿主：回调被条件变量阻塞时，stop 必须保持未返回；释放回调后 stop 才完成且指针为空。故意移除 stop 侧锁后，测试稳定失败并报告“stop 未等待在途回调”；恢复修复后通过。

### 复盘

`NativeCallable.listener` 的“异步”只表示 trampoline 快速投递，不意味着它的函数指针生命周期自动安全。native stop 必须形成确定性的静默屏障，Dart 才能 close。

## 第 3 轮：Flutter 生命周期与系统权限文案

### 现象

AppDelegate 覆盖 `applicationDidFinishLaunching` 后没有调用父实现；FlutterAppDelegate 负责的默认菜单/窗口处理和插件生命周期转发因此被跳过。Info.plist 的麦克风、辅助功能说明也只有英文。

### 假设·判断原因

本机构建产物的 FlutterMacOS 头文件明确写明 FlutterAppDelegate 会转发生命周期。App 包中没有任何 `InfoPlist.strings`，中文系统只能展示英文权限说明。

### 措施

启动回调先调用父实现；新增 en / zh-Hans 的 `InfoPlist.strings` 并加入 Runner resources。

### 验证结果

第一次构建准确暴露 Xcode Resources group 的相对路径少一层；修正为 `Runner/*.lproj` 后构建通过，最终 App 包内两种资源均存在，`plutil` 读到对应中英文说明。

### 复盘

Xcode 工程文件“语法可解析”不等于资源路径正确，必须回查最终 bundle。覆盖框架生命周期方法时，父类行为也是接口契约的一部分。

## 第 4 轮：修复后复审

### 现象

重新检查 EventTap、AudioQueue、设备监听、AppDelegate、entitlements、Info.plist 与打包资源，未发现新的 P2+。

### 假设·判断原因

复审以当前启用的 macOS 主路径为边界；未启用计费、Windows/Linux 专属能力及已约定晚点复现的剪贴板事故不纳入本轮结论。

### 措施

重编 dylib，执行完整 Engine/Native 测试、静态分析、非下载全量测试、macOS Debug 构建和产物探针。

### 验证结果

Engine/Native 定向测试 354 通过 / 10 skip；非下载全量测试 886 通过 / 10 skip；`flutter analyze` 无问题；macOS Debug 构建与 dylib 产物探针通过。

### 复盘

Native/macOS 当前启用范围完成 review→修复→复审闭环；今后改回调生命周期或 bundle 布局时，应先跑可执行宿主与最终产物探针。
