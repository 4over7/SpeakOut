# 启动后永久黑屏 + 菊花（v1.11.0 发版当晚）

> **不变量（改 `lib/main.dart` 首屏前必读）**：
> 首屏三态（加载 / 引导 / 主界面）必须在**路由内部**切换。
> `WidgetsApp.home` 只用于生成 Navigator 的**初始路由**，首帧压栈之后改 `home` 换不掉它。
> 写成 `home: 条件 ? A : B` 就是一颗定时炸弹。

## 背景

v1.11.0 发布后装到 `/Applications`，启动只有黑底 + 一个菊花，主界面永远出不来。
`flutter analyze` 干净、896 个测试全绿、公证与签名全通过 —— 全部质量门都放行了它。

## 第 1 轮：`io.flutter.ui` 线程不见了

### 现象
进程活着（CPU 15%），但应用日志自旧进程退出后一行未写。`sample` 抓到的线程里没有 `io.flutter.ui`。

### 假设·判断原因
Dart isolate 没起来，Flutter 壳在等一个永不到来的引擎。

### 措施
从终端直接跑二进制看 stderr。

### 验证结果
**假设被推翻。** stdout 第一行写着 `Running with merged UI and platform thread. Experimental.` ——
新版 Flutter 在 macOS 上合并了 UI 与 platform 线程，Dart 就跑在主线程上，没有 `io.flutter.ui` 是正常的。

### 复盘
拿"缺少某个线程"当断言，前提是知道该版本的线程模型。差点据此判定引擎没起来。

## 第 2 轮：AppDelegate 的未捕获异常

### 现象
unified log 里有 `An uncaught exception was raised`：
`-[SpeakOut.AppDelegate applicationDidFinishLaunching:]: unrecognized selector`，栈帧指向我们自己的方法。

### 假设·判断原因
`6c8a2e6` 新增的 `super.applicationDidFinishLaunching(notification)` —— `FlutterAppDelegate`
并未实现这个 `NSApplicationDelegate` 可选协议方法，Swift 允许 `override` 编译通过，
运行时 `objc_msgSendSuper` 直接找不到。异常在方法第一行抛出，其后的 bookmark 恢复与
MethodChannel 注册全部被跳过 —— 看起来足以解释"平台通道无人应答"。

### 措施
删掉该行，原地留注释说明为什么不能加。重新构建。

### 验证结果
**异常归零，但仍然黑屏。** 这是一个真缺陷，但**不是**黑屏的根因。

### 复盘
"修掉了一个真 bug" 与 "修好了这个故障" 是两件事。差点在这里宣布收工 ——
是截图逼停的：日志干净了，画面还是黑的。

## 第 3 轮：窗口状态恢复

### 现象
异常前一行是 `restoreWindowWithIdentifier:...: Unable to find className=(null)`。

### 假设·判断原因
窗口状态恢复失败 → Flutter 窗口没建好 → `MainFlutterWindow.awakeFromNib` 里的
`RegisterGeneratedPlugins` 没跑 → 平台通道无人应答。链条自洽。

### 措施
查 `~/Library/Saved Application State/com.speakout.speakout.savedState`。

### 验证结果
**假设被推翻。** 该目录根本不存在，`className=(null)` 只是"没东西可恢复"的常规提示。

## 第 4 轮：配置数据与残留沙盒容器

### 现象
debug 版插桩显示 `_showOnboarding = true` —— 判成了首次启动。
而 `~/Library/Preferences/com.speakout.speakout.plist` 里 `flutter.onboarding_completed` 明明是 `true`。

### 假设·判断原因
怀疑 `~/Library/Containers/com.speakout.speakout/` 残留容器劫持了 defaults（见反模式记录）。

### 措施
① 把主 plist 移走（等于全新配置）跑一次；② 对比三个构建产物的 entitlement。

### 验证结果
- 清空配置照样黑屏 → 与配置数据无关。
- **entitlement 差异才是这一轮的真相**：Debug 构建 `app-sandbox=true`，读的是容器里那份 38 键的 plist；
  Release / DMG 都是 `app-sandbox=false`，读主目录那份 82 键的。
  `onboarding=true` 是 **debug 版沙盒隔离的产物**，release 版实测是 `onboarding=false`。

### 复盘
**差点用 debug 版的现象去解释 release 版的故障。** 诊断构建与故障构建的沙盒状态不同，
读到的就是两份完全不同的配置。用 debug 版排查 release 故障前，先确认 entitlement 一致。

## 第 5 轮：定位到路由（根因）

### 现象
在 release 版上插桩（每一步 print），同一次运行里拿到：

```
[DIAG] BUILD -> LoadingScreen      ← 首帧先渲染了加载页
[DIAG] 2 prefs ok                  ← 初始化才刚读完 prefs
[DIAG] 6 init complete
[DIAG] B ConfigService.init returned, mounted=true
[DIAG] C setState done init=true onboarding=false
```

状态全部正确，`build` 也走了 HomePage 分支（loading 分支不再打印），但画面纹丝不动。

### 假设·判断原因
`MacosApp.home` 的条件切换换不掉 Navigator 里已压栈的初始路由。

### 措施
不改代码，直接用 VM service 取证：`ext.flutter.debugDumpRenderTree` / `debugDumpApp` 看树，
再调 `ext.flutter.reassemble` 强制重建。

### 验证结果
**确证。**
- render tree 里**一个文字节点都没有**，只有 `CupertinoActivityIndicator ← Center ← ContentArea`，
  正是 `_LoadingScreen` 的形状；widget tree 里挂的也是 `_LoadingScreen`。
- `reassemble` 之后，widget tree 里 `_LoadingScreen` **立刻变成 `HomePage`** ——
  状态一直是对的，只是路由没换。

修法：`home` 固定为 `_RootGate`，三态由它自己 `setState` 在路由内部切换。
装回 `/Applications` 后主界面正常，`InputMonitoring=true / Accessibility=true / Listener start success`。

### 复盘
这是一条**长期潜伏的竞态**，不是 v1.11.0 引入的：1.10.0 同样写法。
谁快谁赢 —— `ConfigService().init()` 抢在首帧前完成就正常，慢一步就永久黑屏。
用户那个进程从 8/17 起没关过，赢了那次；重启就输。
所以 1.10.0 / 1.11.0、debug / release、`/Applications` / DMG 原包**六种组合全部黑屏**，
而版本、路径、配置数据三个方向全是死胡同。

## 这次事故最该记住的三条

1. **构建通过 ≠ 能用。** analyze 干净、896 测试全绿、公证通过，全放行了一个装完就黑屏的包。
   Swift 层和"首帧时序"都不在 Dart 测试覆盖内 —— 发版前必须**真的把 App 启动起来看一眼**。
2. **修掉一个真 bug 不等于修好了故障。** 第 2 轮的 `super` 调用确实是缺陷，
   但黑屏照旧；是截图把"我以为好了"摁了回去。
3. **诊断工具本身会骗人。** debug 版带沙盒，读的配置和 release 版是两份；
   `sample` 的线程列表要配合 Flutter 的线程模型才能读。
   最终定案靠的是 `reassemble` 前后 widget tree 的对比 —— 一个能推翻/证实假设的确定性实验。
