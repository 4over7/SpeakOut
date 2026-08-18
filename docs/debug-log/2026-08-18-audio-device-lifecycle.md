# 音频设备监听生命周期与蓝牙枚举阻塞

## 第一轮：退出已接线，但重试会重复注册

### 现象

旧 review 的 P1 指出退出时没有释放 `AudioDeviceService`。当前代码已由
`AppService.dispose → CoreEngine.dispose → AudioDeviceService.dispose` 接通，但服务没有行为测试；
键盘监听启动失败后，`CoreEngine.init()` 可以重试，并会再次调用设备服务的 `initialize()`。

### 假设·判断原因

`initialize()` 每次都新建 `NativeCallable`。第一次设备 listener 已成功、后续键盘 listener 失败时，
第二次初始化会覆盖 Dart 侧引用并重复向 native 注册，旧 trampoline 无法释放。
设备 listener 自身注册失败时，native 也已先保存 callback 指针，Dart 不能直接 close。

### 措施

初始化以现存 `NativeCallable` 为成功标记实现幂等；注册失败时先调用 native stop 清指针，再 close
并置空，允许下次重试。`dispose()` 同样幂等。回调改为实例方法，移除静态 service 引用。

### 验证结果

新增行为测试覆盖成功后重复初始化、失败后重试和重复 dispose。变异探针删除初始化守卫后，
测试从期望注册 1 次变为实际 2 次并失败；恢复后通过。

### 复盘

旧 P1 的“退出链已调用”只能证明一个调用点存在，不能证明服务生命周期闭合。可重试的上游 init
要求下游 listener 初始化同样幂等；native 保存了回调指针时，失败清理顺序仍是 stop → close。

## 第二轮：非阻塞注释被调用方绕过

### 现象

服务回调已有注释禁止在蓝牙协商期间全量枚举，但失效偏好分支会调用带 `refreshDevices()` 的
`clearPreferredDevice()`；设置页收到 `deviceChanges` 后也立刻全量刷新；服务启动同样无条件枚举。

### 假设·判断原因

保护只写在回调的一条直线路径上，没有沿调用图检查 helper、订阅者和启动路径。结果仍可能在
CoreAudio 正协商蓝牙设备时阻塞主 isolate，连带冻结 CGEventTap 快捷键处理。

### 措施

清偏好不再枚举；设备回调只失效缓存并分发当前设备快照；设置页消费快照，不立即刷新完整列表；
启动和 `currentDevice` getter 只查询当前设备，完整列表仅在用户主动进入设置页时加载。

### 验证结果

行为测试直接通过真实 `NativeCallable.listener` 指针触发回调，确认回调、清偏好和启动均不会调用
全设备枚举。分别恢复回调枚举与启动枚举的两个变异探针都使对应计数断言失败。

### 复盘

“本函数不调用慢操作”不是完整不变量；异步事件的订阅者同属回调链。以后审查实时回调时要沿
helper 和 stream consumer 追到副作用终点。

## 第三轮：native 状态、配置与 UI 必须同一事务

### 现象

手动切换失败仍会把目标 UID 写入配置；蓝牙提醒的一键操作无论失败都提示成功，成功时又只改
native 内存、不持久化；提醒开关也只存在于 service 字段，重启恢复默认值。设备事件还先于旧偏好
清理发出，订阅者可能读到旧状态。

### 假设·判断原因

一次用户动作被拆成 native、SharedPreferences、通知和 UI 四段，各调用方自行拼接但没有按成败提交。
这会形成“显示 A、实际跑 B”，或当次有效、重启丢失。

### 措施

UI 仅在 native 切换成功后持久化；一键切换成功后读取 native 的实际 preferred UID 再落盘，失败
显示错误且不谎报成功；提醒开关进入 `ConfigService`；设备事件在偏好对账完成后再广播。所有新增
通知走应用语言的 l10n。

### 验证结果

行为测试覆盖失败通知、英文 locale、成功后 UID 持久化、提醒开关恢复和旧当前设备缓存清理。
删除提醒配置读取、删除一键切换落盘的两个变异探针均使测试失败。最终全量测试 828 通过、
10 跳过，`flutter analyze` 无问题，macOS debug 构建成功。

### 复盘

设备选择的提交点是“native 成功 + 配置落盘”；成功通知只能在两者都完成后发。设备变化 stream
是状态完成后的通知，不是状态变更的起点。

## 不变量

- listener 初始化与 dispose 都必须幂等；注册失败先 stop native callback，再 close Dart callable。
- 蓝牙设备变化回调、订阅者和启动路径都不得全量枚举设备。
- native 切换失败不得落盘或提示成功；一键切换成功必须持久化实际 preferred UID。
- 先完成偏好对账，再广播 `deviceChanges`。
