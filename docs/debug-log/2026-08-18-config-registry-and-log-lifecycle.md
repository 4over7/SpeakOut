# Config 注册表与日志生命周期追查

## 第一轮：AppLog 瞬时失败被永久缓存

### 现象

`AppLog.init()` 在打开文件前就记录“已尝试”和当前目录；同一路径首次创建失败后，后续调用直接跳过。

### 假设 · 判断原因

成功状态的提交时机早于文件 sink 真正建立，瞬时权限或目录冲突会被误当成已初始化。

### 措施

只在 sink 建立后提交成功状态；失败清空活动目录，并让初始化、切目录、销毁进入同一串行队列。

### 验证结果

`app_log_lifecycle_test.dart` 先用普通文件阻塞目标目录，再移除阻塞并重试，确认日志成功写入；
把失败分支改回“已初始化”后测试会失败。

### 复盘

生命周期完成位必须描述已完成事实，不能描述“尝试过”。只有跟踪第一笔 Future 也不够，销毁必须排在所有已提交操作之后。

## 第二轮：旧 LLM 配置误走 Anthropic 协议

### 现象

云账户失效后会退回旧配置。Groq、讯飞等 provider 不在 `AppConstants.kLlmPresets`，旧代码缺项时取列表末尾
`custom_anthropic`，于是请求被发往 `/v1/messages`。

### 假设 · 判断原因

遗留 preset 列表已不再是当前 provider 注册表，却仍被用于决定协议；缺项默认值恰好改变了请求格式。

### 措施

旧配置的协议也按 `CloudProviders` metadata 判断，并单独保留 `custom_anthropic` 的兼容分支。

### 验证结果

`llm_legacy_fallback_format_test.dart` 用真实 HTTP mock 验证 Groq 仍请求
`/openai/v1/chat/completions`，并验证自定义 Anthropic 仍请求 `/v1/messages`；强制 Groq 的
`isAnthropic=true` 后测试失败。

### 复盘

同一概念存在新旧两份列表时，旧列表只能承担迁移数据，不能继续决定当前协议或能力。

## 第三轮：清空日志目录没有恢复默认值

### 现象

设置页清空日志目录后显示“未设置”，但 `AppService` 只在非空时更新 Dart/native，两个运行时仍沿用旧路径。

### 假设 · 判断原因

空字符串在配置层代表恢复默认值，但应用边界和 native setter 都把它当成 no-op，三层语义不一致。

### 措施

`AppService` 每次都同步目录：空值映射为 Dart 的 `null`，并原样传给 native；native 收到空值时清除覆盖路径。

### 验证结果

`app_service_log_directory_test.dart` 和独立 native 可执行宿主均通过；临时恢复两端旧行为后，两项测试同时失败。

### 复盘

“清空配置”是一次有意义的状态转换，不是缺少输入。跨语言 setter 必须对清空语义达成一致。

## 第四轮：目录切换与销毁、native 读写存在竞态

### 现象

目录切换的第二笔初始化可能排在第一笔之后，但旧 `dispose()` 只等待第一笔；native 后台日志线程也会与
`set_log_directory` 并发读写同一字符数组。

### 假设 · 判断原因

只记录当前 in-flight Future 表达不了完整操作顺序；C 字符数组在没有同步时并发读写属于数据竞争。

### 措施

AppLog 用单一 Future 队列串行 init / reconfigure / dispose；native 用窄 mutex 保护路径设置与快照复制，
写盘使用锁内复制出的本地路径。

### 验证结果

确定性交错测试让默认目录解析暂停，依次排入切目录和 dispose，最终确认 sink 关闭；绕过队列后测试失败。
native 宿主编译运行通过，dylib 零警告重编成功。

### 复盘

资源生命周期的正确抽象是操作序列，不是单个“正在初始化”标志。跨线程共享 C 缓冲区即使只存路径也必须同步。

## 收敛验证

- 第五轮复审：未发现新的 P2+。
- `flutter analyze`：无问题。
- `MODEL_TEST_MAX_MB=1 flutter test`：846 通过 / 10 skip / 0 失败。
- native dylib：按 `native_lib/AGENTS.md` 命令重编，零警告。
- `flutter build macos --debug`：成功。

## 不变量

1. AppLog 初始化、切目录、销毁按调用顺序串行；失败不能留下成功完成位。
2. 清空日志目录必须同时让 Dart 与 native 恢复默认路径。
3. native 日志线程只使用锁内复制出的路径快照。
4. LLM 协议由当前 provider 注册表决定，遗留 preset 列表不能充当当前 schema。
