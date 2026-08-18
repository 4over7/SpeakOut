# Gateway 已启用更新与统计链 review（2026-08-18）

## 范围

只处理当前产品实际调用的 `/version`、其统计副作用、管理员 `/stats` 和客户端 `UpdateService` 消费链。许可证、设备计费和支付路由未启用，本轮不动；它们的既有 findings 继续留在 review handoff。

## 第 1 轮：公共版本参数制造无限 KV key

### 现象

`/version?v=` 把任意字符串直接拼成 `stats:version:{v}`。公共请求可以持续换参数制造新 key；只校验字符或长度也不能挡住无限多个形似 SemVer 的值。

### 假设·判断原因

根因不是单个脏字符，而是“外部输入决定存储 key 基数”。因此格式白名单只能缩小单 key 大小，不能关闭基数膨胀。

### 措施

版本计数迁到固定 `stats:versions` JSON map：非法版本聚合为 `unknown`，独立版本数量达到上限后聚合为 `other`。`/stats` 同时合并旧的 `stats:version:{v}`，不丢历史数据。

### 验证结果

Node 行为测试连续提交多个非法值和 140 个合法 SemVer，只产生一个版本统计 KV key，map 保持固定上限。把上限从 128 变异为 256 后测试按预期失败（140 项而非 129 项）。

### 复盘

最初方案只做 SemVer 白名单，复审时发现仍可无限生成合法形状，假设不完整。真正的不变量是“公共参数不能决定 KV key 数量”。

## 第 2 轮：统计分页静默丢数据

### 现象

`/stats` 对两个 prefix 各调用一次 KV `list()`，只消费第一页；旧版本 key 超过单页上限后不会报错，只返回不完整结果。

### 假设·判断原因

返回结构包含 cursor，但旧实现未继续读取，属于确定性的分页遗漏。

### 措施

集中到 `readCounters()`，按 cursor 读取全部页；同页 value 按 [Cloudflare KV 批量读取上限](https://developers.cloudflare.com/kv/api/read-key-value-pairs/)每 100 个 key 分批。结果对象用无原型 map 承接历史外部 key，再与新版本 map 合并。

### 验证结果

内存 KV 强制每页只返回一个 key，测试确认三条版本记录和两天记录全部返回；另以 205 个历史 key 确认恰好拆成 3 次批量读取。把循环变异为第一页后立即退出，以及退回逐 key 读取，测试均按预期失败。

### 复盘

分页问题和基数问题互相放大：即使新 schema 已有界，也必须兼容并完整读取线上旧 key。复审时进一步确认逐 key 读取会快速消耗 Worker 单次调用的外部操作配额，因此分页正确和读取批量化必须同时成立。

## 第 3 轮：Gateway build 在客户端被忽略

### 现象

Gateway 返回 `version` 和 `build`，但客户端只比较 version；同版本的新 build 不提示更新。DMG 缓存文件名也只有 version，即使补上比较仍会复用旧 build 文件。

### 假设·判断原因

发布元数据已明确把 build 作为递增修订号，客户端却在解析层丢弃，比较、缓存身份和 UI 判断因此出现三个不一致真源。

### 措施

`UpdateService` 保存并比较远端 build；只有语义版本相同时才比较 build。缓存文件名加入 build。当前可达的 `OverviewPage` 直接消费 service 的 `hasUpdate`，不再自行只比版本号。

### 验证结果

Dart 测试覆盖同版本高/同/低 build 和语义版本优先级；Helper 脚本测试确认缓存路径含 `1.10.0+241`。分别去掉 build 比较和缓存 build 后，两条测试均按预期失败。

### 复盘

只修比较函数仍不闭环：修复后复审才发现 UI 重算和缓存命名仍保留旧语义。跨层元数据必须在解析、决策、缓存三处保持一致。

## 第 4 轮：检查失败被显示成“已是最新”

### 现象

Gateway 和 GitHub 都失败时，`checkForUpdate()` 吞掉错误并正常返回；当前设置页随后把 `latestVersion == null` 显示为“已是最新”。

### 假设·判断原因

“没有拿到远端版本”与“确认没有新版”被压成同一个空值分支，UI 无法区分。

### 措施

`checkForUpdate()` 返回本次是否成功取得有效远端信息，并记住最近一次检查结果；`OverviewPage` 分别展示检查失败、新版可用和已是最新。新增中英文 i18n 文案。

### 验证结果

Gateway 5 个行为测试与 `node --check` 通过；UpdateService、版本、UI mounted/error discipline 定向测试通过；完整 `flutter test`、`flutter analyze` 和 macOS Debug 构建均通过。

### 复盘

网络失败不能伪装成肯定结论。Service 提供事实状态，UI 只展示，不重复推导业务判断。
