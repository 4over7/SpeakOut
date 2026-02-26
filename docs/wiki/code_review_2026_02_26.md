# SpeakOut 代码评审报告

> 日期：2026-02-26 | 标准：Linus Torvalds 式评审（简洁、正确、无废话）

## 总评

项目架构思路清晰——三层分离（Engine/Service/UI）、FFI 原生性能、离线优先设计都是正确的方向。但在**资源管理纪律**、**并发安全**和**Gateway 安全性**三个方面有明显短板。按 Linus 的话说："代码能跑不等于代码是对的。"

---

## P0 — 必须立即修复

### 1. Gateway: Stripe Webhook 无签名验证（可被利用的漏洞）
`gateway/src/index.js:197-233`

任何人都可以伪造 `checkout.session.completed` 事件，给任意 license key 充值 360000 秒。代码注释已承认不安全但仍在生产运行。

### 2. Gateway: CORS 完全开放 + 管理接口暴露
`gateway/src/index.js:9`

`Access-Control-Allow-Origin: *` 意味着攻击者从任意网页都能调用 `/admin/generate`。结合已知的 header 认证方式，风险极高。

### 3. Gateway: 无速率限制
所有接口（`/verify`、`/token`、`/redeem`、`/admin/generate`）都没有限流。攻击者可暴力枚举 license key 和充值码。

### 4. Gateway: `/redeem` TOCTOU 竞态
`gateway/src/index.js:121-157`

检查卡密→标记已用→增加余额分三步执行，KV 无事务，并发请求可让一张卡被多次使用。

### 5. Gateway: 充值码用 `Math.random()` 生成
`gateway/src/index.js:172`

不是密码学安全的 PRNG，且只有 6 个 Base36 字符（~31 bit 熵），可被预测和碰撞。

---

## P1 — 高优先级

### 6. 原生代码: `va_list` 双重消费（未定义行为）
`native_lib/native_input.m:33-53`

`vfprintf` 消费 `args` 后，又传给 `initWithFormat:arguments:`。生产环境每次日志调用都会触发。必须用 `va_copy`。

### 7. 原生代码: `CFStringRef` 内存泄漏
`native_lib/native_input.m:682`

`AudioObjectGetPropertyData` 返回的 `CFStringRef` 用简单 C cast `(NSString *)` 转换，未通过 `__bridge_transfer`，ARC 不会释放。每次调用 `get_audio_input_devices()` 都泄漏多个字符串。

### 8. 原生代码: Ring Buffer 游标非原子操作
`native_lib/native_input.m:462-465`

`volatile` 不等于原子性。`ringWritePos`/`ringReadPos` 应使用 `_Atomic uint64_t`。当前在 ARM64 上碰巧安全，但不符合 C 标准，且不可移植。

### 9. Aliyun Provider: Token 永不刷新
`lib/engine/providers/aliyun_provider.dart:134-141`

只检查 `_token == null`，`_tokenExpireTime` 声明了但从未使用。Token 过期（通常 24h）后连接会静默失败。

### 10. Core Engine: `stopRecording` 无防重入
`lib/engine/core_engine.dart:668-783`

设置了 `_isStopping = true` 但入口不检查。Watchdog timer 和用户按键释放可能同时触发。

### 11. Core Engine: `_pollBuffer` 原生内存永不释放
`lib/engine/core_engine.dart:562`

`calloc<Int16>` 分配的内存没有对应的 `calloc.free()`。`CoreEngine` 是单例无 `dispose()`。

### 12. LLM Service: HTTP Client 泄漏
`lib/services/llm_service.dart:49,117`

每次请求创建 `http.Client()` 但从不 `close()`。Socket 连接持续积累。

### 13. Settings Page: 每次 build 创建新 TextEditingController
`lib/ui/settings_page.dart:742,982`

导致光标重置、输入丢失、内存泄漏。

### 14. Settings Page: 双重嵌套 SingleChildScrollView
`lib/ui/settings_page.dart:376`

两层 `SingleChildScrollView` 嵌套，复制粘贴错误，滚动行为异常。

---

## P2 — 中优先级

### 15. Aliyun Provider: 心跳 Timer 空操作
`lib/engine/providers/aliyun_provider.dart:96-108`

每 30 秒触发但什么都不做。连接实际无保活，长时间空闲后会断开。

### 16. Aliyun Provider: `_pendingBuffer` 无上限
`lib/engine/providers/aliyun_provider.dart:146`

WebSocket 握手卡住时，音频数据无限积累，可导致 OOM。

### 17. Aliyun Provider: WebSocket 连接竞态
`lib/engine/providers/aliyun_provider.dart:73-93`

`_isConnected` 在握手完成前就设为 true，`stop()` 中用硬编码 2 秒等待握手（`_startCompleter` 已声明但未使用）。

### 18. Aliyun Provider: 错误通过文本流发送
`lib/engine/providers/aliyun_provider.dart:84`

`Connection Error` 作为普通文本发给 UI，UI 无法区分识别结果和错误消息。

### 19. Model Manager: 下载中 sink/client 异常未关闭
`lib/engine/model_manager.dart:376,288`

网络断开时 `IOSink` 和 `http.Client` 不会被关闭。应使用 `try-finally`。

### 20. Model Manager: 标点模型下载/检测路径不一致
`lib/engine/model_manager.dart:436 vs 451`

`isPunctuationModelDownloaded` 和 `getPunctuationModelPath` 对目录层级的假设不一致。

### 21. Chat Service: `_saveHistory` fire-and-forget 并发写入
`lib/services/chat_service.dart:74`

`_addMessage` 调用 `_saveHistory()` 但不 await，快速连续消息可导致文件写入竞态和数据丢失。

### 22. Chat Service: 聊天记录绑定日记目录
`lib/services/chat_service.dart:81,105`

用户更改日记目录后旧聊天记录"消失"。

### 23. Config Service: `init()` 竞态 + setter 静默失败
`lib/services/config_service.dart:33-56`

多次并发 `init()` 无保护；`_prefs == null` 时写入静默丢弃。

### 24. AudioDeviceService: 混合单例 + `_instance` 可能为 null
`lib/services/audio_device_service.dart:56-76,120-123`

原生回调触发时如果 `_instance` 未设置，设备切换事件静默丢失。

### 25. 原生代码: `deviceChangeCallback` 线程竞态
`native_lib/native_input.m:1008-1033`

CoreAudio 线程回调和主线程 `stop_device_change_listener` 之间有微小竞态窗口。

### 26. 原生代码: active event tap 权限过大
`native_lib/native_input.m:209`

使用 `kCGEventTapOptionDefault`（可修改/丢弃事件），但实际只是监听。应用 `kCGEventTapOptionListenOnly`。

### 27. Main Page: Stream subscription 未 cancel
`lib/main.dart:196,214,226,239`

四个 `.listen()` 都未存储 subscription 引用，`dispose()` 中无法取消。

### 28. Core Engine: 同步文件 I/O 日志在热路径
`lib/engine/core_engine.dart:118`

`writeAsStringSync` 在音频处理路径上阻塞 Dart 事件循环。

### 29. Core Engine: AGC 死代码
`lib/engine/core_engine.dart:606-615`

`rawPeak` 计算了但没用，`dynamicGain` 硬编码为 1.0。整个扫描循环浪费 CPU。

### 30. Sherpa Provider: 解码循环阻塞主 isolate
`lib/engine/providers/sherpa_provider.dart:121-123`

`while (isReady) decode()` 在主 isolate 执行，可能导致 UI 卡顿。

---

## P3 — 低优先级 / 代码卫生

| # | 位置 | 问题 |
|---|------|------|
| 31 | `core_engine.dart:79-101` | 5 个 StreamController + NativeCallable 永不释放 |
| 32 | `sherpa_provider.dart:12` | `_textController` 未关闭 |
| 33 | `sherpa_provider.dart:194` | `_recognizer` FFI 对象未调用 free() |
| 34 | `model_manager.dart:124,418` | `firstWhere` 无 orElse 保护 |
| 35 | `aliyun_provider.dart:233-235` | JSON 解析异常被静默吞噬 |
| 36 | `aliyun_provider.dart:298-305` | dispose 后 isReady 仍为 true |
| 37 | `native_input.m:308-311` | CGEventSource 创建结果未 NULL 检查 |
| 38 | `native_input.m:20-31` | 日志路径惰性初始化非线程安全 |
| 39 | `chat_page.dart:128` | 每次 StreamBuilder rebuild 都强制滚动到底部 |
| 40 | `chat_page.dart` | 缺少 dispose() 释放 Controller |
| 41 | `settings_page.dart:46-48` | 3 个 TextEditingController 未在 dispose 中释放 |
| 42 | `main.dart:290` | 波形 5 元素 vs 7 个 bar，模运算导致视觉重复 |
| 43 | `settings_page.dart:441` | 成功提示用了 `_showError` 方法 |
| 44 | `gateway/src/index.js:237-255` | `generateAliyunToken` 返回 mock 数据 |
| 45 | `gateway/src/index.js` | 错误响应格式不一致 |

---

## 测试覆盖率

**当前：约 27%（4/15 核心模块有测试）**

| 状态 | 模块 |
|------|------|
| 有测试 | `asr_provider`, `model_manager`, `config_service`, `llm_service` |
| **无测试** | `core_engine`, `app_service`, `chat_service`, `diary_service`, `notification_service`, `audio_device_service`, `sherpa_provider`, `aliyun_provider`, `aliyun_token_service`, `chat_model`, `native_input` |

**测试质量问题：**
- `asr_provider_test.dart` 和 `integration_test.dart` 测试的是 Mock 自身行为，非真实实现
- `integration_test.dart` 实际是纯单元测试，命名误导
- `run_tests.sh:13` 引用了不存在的 `test/core_engine_test.dart`，脚本会失败
- `test/offline_debug.dart` 是硬编码路径的调试工具，不应放在 test/ 目录

---

## 架构层面总结

**做得好的：**
- Engine/Service/UI 三层分离，方向正确
- FFI 用 Ring Buffer 替代回调避免 SIGABRT，是正确的工程决策
- ASRProvider 抽象接口设计干净，离线/云端可切换
- 离线优先 + 低延迟的产品定位明确

**核心问题：**
1. **资源管理纪律差** — 到处都是"分配了不释放"：StreamController、NativeCallable、HTTP Client、FFI 内存、CGEventTap。单例模式不是不写 dispose 的理由。
2. **并发意识薄弱** — 多个 async 方法无防重入，init() 无并发保护，文件写入无互斥，Ring Buffer 用 volatile 当原子用。
3. **Gateway 是安全重灾区** — Webhook 无签名、CORS 全开、无限流、TOCTOU 竞态、弱随机数，几乎每个接口都有问题。
4. **测试形同虚设** — 覆盖率 27%，现有测试多在测 Mock 而非真实逻辑，测试脚本本身都跑不通。
5. **错误处理哲学混乱** — 有的吞异常、有的打印到 /tmp 日志、有的通过文本流发送错误，没有统一策略。
