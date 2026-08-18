# FFI 失败状态闭环（2026-08-18）

## 第 1 轮：updater 启动状态

### 现象

自动更新的 `launch_updater` 导出为 `void`。即使 NSTask 启动失败，Dart 三个安装入口仍会在 500ms 后退出 SpeakOut，用户既没有收到错误提示，也无法在当前进程内重试。

### 假设·判断原因

这是 FFI 失败状态丢失，不是更新脚本自身的失败：原生 catch 只记日志，`NativeInputBase.launchUpdater` 无返回值，UI 因而无法区分 helper 是否真的启动。既有事故记录也把它列为尚未收尾的 P2。

### 措施

- 将 `launch_updater` 改为返回状态，并在启动前拒绝空路径、缺失文件和目录。
- Dart FFI 将状态转换为 `bool`。
- `UpdateService.launchInstall` 负责生成 helper、调用 launcher，并且只在 launcher 成功后进入 `installing`。
- 三个安装入口仅在成功后退出；失败时保留原状态并显示本地化横幅。
- 新增 service 行为测试和真实 dylib 的缺失 helper 探针。

### 验证结果

真实 dylib 对不存在的 helper 返回 0；Service 在 launcher 返回 false 时保持原状态，返回 true 后才进入 `installing`。定向测试通过。

### 复盘

“原生记了错误日志”不等于调用者知道失败。会触发进程退出的能力必须先把启动成功状态跨 FFI 传回来。

## 第 2 轮：退出前生命周期

### 现象

修复后的调用链复审发现，Overview 与旧 About 入口在 helper 启动成功后直接 `exit(0)`，没有像主窗口入口一样先 `AppService.dispose()`；待写聊天记录和日志可能未 flush。

### 假设·判断原因

这是同一更新退出链上的第二个 P2，不是独立重构：helper 启动成功只解决“能不能退出”，没有解决“退出前是否完成应用生命周期收尾”。

### 措施

两个入口都在延迟退出回调里等待 `AppService.dispose()`，与主窗口入口保持同一语义。

### 验证结果

全量架构测试与应用构建通过；三个退出入口现在都只在 helper 启动成功后退出，并在退出前完成生命周期收尾。

### 复盘

失败分支和成功分支要一起 review：前者不能误退出，后者不能绕过既有 flush 契约。

## 第 3 轮：AudioQueue 停止状态

### 现象

`stop_audio_recording` 忽略 `AudioQueueStop` 与 `AudioQueueDispose` 的 OSStatus 并返回 `void`。Dart 无法知道释放失败，仍会把硬件状态标为已停止。

### 假设·判断原因

本地 macOS SDK 的 `AudioQueue.h` 明确说明：`AudioQueueDispose` 返回后调用方不得再操作该 queue。因此正确语义不是“失败后保留句柄重试”，而是“始终清空句柄，同时把 Dispose 结果传给 Dart”。Stop 失败但 Dispose 成功时，关闭目标已经达成。

### 措施

- `stop_audio_recording` 改为返回状态；Dispose 成功返回 1，失败返回 0，返回后始终清空 native 句柄。
- 三个平台与 Dart typedef/接口同步签名，ABI 指纹更新为 `0x3e3abe`。
- CoreEngine 记录默认配置下也会落盘的错误，并用 `finally` 清理 `_audioStarted`。
- 新增替换真实 AudioQueue 系统调用的可执行宿主，覆盖幂等、Stop 失败但 Dispose 成功、Dispose 失败三种路径。

### 验证结果

可执行宿主三种路径全部通过；FFI/ABI/updater/service 定向测试共 69 例通过。`flutter analyze` 通过；`MODEL_TEST_MAX_MB=0 flutter test` 为 855 通过 / 10 跳过；Debug macOS 构建成功，包内 dylib 与重编译产物逐字节一致。

### 复盘

复审原先“Dispose 失败后保留句柄重试”的直觉时，回查 SDK 头文件发现这会违反系统 API 生命周期契约。系统层行为必须以确定性证据为准，不能凭常识补偿。

## 最终复审

macOS 当前启用 FFI 导出再次逐项检查后无 P2+。保留的 `void` 能力中：剪贴板 end 的异步失败由计数对账；权限请求本身是 fire-and-forget；设备 listener stop 会先清空回调且只在 shutdown 使用，移除失败属于低优先级资源诊断；偏好 UID setter 只是进程内复制。未启用的屏幕录制探测及 Windows/Linux 专属能力不纳入本轮功能范围。
