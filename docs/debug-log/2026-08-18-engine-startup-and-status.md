# Engine 启动事务与状态本地化（2026-08-18）

## 第一轮：录音启动失败后遗留 ASR session

### 现象

`provider.start()` 已成功后，原生麦克风启动失败只清 Dart 状态，没有停止 provider。
录音启动期间取消又可能先 `stop()`，而网络 `start()` 随后才真正建好 session。

### 假设·判断原因

启动跨越 ASR provider 和 native AudioQueue，但旧逻辑把它当成两个无关步骤；
`Future.timeout`/状态早退也不会自动取消底层会话。

### 措施

原生录音失败时显式 stop ASR，stop 失败则拆订阅并 dispose provider。
`provider.start()` 每个 await 后重验 `starting`；取消只把状态切到 `stopping`，
由原启动任务在 start 真正返回后统一回滚。启动异常时也先关真实音频硬件再清标志。

### 验证结果

`recording_startup_invariants_test.dart` 锁定 provider start 后状态重验、ASR 回滚顺序、
权限早退清理和 starting 取消所有权；与热键/stop 定向集合共 42 例通过。

### 复盘

状态标志复位不等于资源已回滚。跨层启动必须明确资源所有者，
尤其要防「stop 完成后 start 才完成」的反向时序。

## 第二轮：热键与临时意图跨会话泄漏

### 现象

Toggle 停止/shared-key 只比 keyCode；麦克风权限失败时会遗留
`_isToggleMode` 或 `_translateOverride`，影响下一次普通 PTT。

### 假设·判断原因

快捷键身份被简化成 keyCode，与设置页「keyCode + modifiers」的语义不同；
权限早退发生在正式进入 `starting` 前，因此没走通用清理。

### 措施

shared-key 只接受完全相同的 keyCode/modifiers，Toggle 二次按下也调用统一匹配。
权限与启动早退统一清理 toggle、translate、active key 和计时器。

### 验证结果

新增 shared-key 身份行为测试，并与现有 modifiers 精确匹配/设置冲突测试一起通过。

### 复盘

用于路由的快捷键身份必须与用于触发的匹配语义相同；
任何启动早退都要清理「本次会话」临时意图。

## 第三轮：状态栏、浮窗和通知串语言

### 现象

EngineStatus 大部分直接透传中文或英文；录音浮窗与 Swift 静音提示也有各自的硬编码。

### 假设·判断原因

Engine 不能持有 `BuildContext`，旧代码因此把「不在 Engine 里查 ARB」误等同于
「Engine 可直接生成展示文案」，三个展示面各自漂移。

### 措施

EngineStatus 扩展为 code + params，`engine_status_localizer.dart` 根据配置/系统语言查同一份 ARB。
macOS/Windows/Linux 状态栏、Dart 浮窗文案和通知都经该映射；Swift 静音提示改为接收 Dart 文本。

### 验证结果

中英 ARB 可解析且成功生成；状态码覆盖测试会扫描启用路径的字面量 code，
确认两种语言都不落回 fallback，动态 provider/model/error 参数不丢失。
`flutter analyze` 无问题。

### 复盘

「Engine 不依赖 UI」的正确边界是 Engine 发语义化 code/params，由无 Context 的共享服务查 ARB；
不能让 fallback 字符串成为事实上的用户文案。

## 第四轮：ASR 切换 await 窗口与退出截断

### 现象

`_initASRUnsafe` 虽在入口检查 idle，但取消旧订阅的 await 期间仍可开始录音，
切换任务恢复后会 dispose 正在录音的 provider。另外 `AppService.dispose()` 未等待
Engine 正在进行的 stop，闪念落盘/识别收尾仍可被 `exit(0)` 截断。

### 假设·判断原因

「入口时为 idle」不能保证整个异步临界区仍为 idle；同理，外层 await 一个同步
`dispose()` 并不会自动等待它之前启动的 Future。

### 措施

`initASR` 在进入 unsafe 前设置 `_asrSwitchInProgress`，并用 finally 解锁；录音入口在权限和
provider 启动前检查该锁。初始化失败也显式 dispose 局部 provider。
start/stop 登记在途 Future，`CoreEngine.dispose()` 改为异步，等它们完成后才关 provider 与状态流。

### 验证结果

ASR 切换锁的设置/解锁顺序、录音入口守卫、两条初始化失败 dispose 路径，
以及 dispose 等待 start/stop 后再关资源都有结构回归测试；Engine/native 相关定向 102 例通过，
`flutter analyze` 无问题。首次全量回归暴露架构守卫把 `dispose()` 返回类型硬编码为 `void`；
同步为异步签名后，`MODEL_TEST_MAX_MB=0 flutter test` 870 例通过、10 例按设计跳过，
`flutter build macos --debug` 成功。

### 复盘

异步状态机的不变量要覆盖整个 await 区间，不是只检查入口；
退出流程也是状态机的一部分，必须显式加入在途操作。
