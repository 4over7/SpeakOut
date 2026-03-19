# 评审回复：SpeakOut 独立技术评审意见响应（修订版）

> 回复日期：2026-03-19
> 修订日期：2026-03-19（根据复评意见修订措辞）
> 回复方：SpeakOut 开发团队
> 针对：`independent_technical_review_2026_03_19.md`

## 总体评价

感谢评审团队严谨、务实的评审。报告对项目的定位判断（离线优先语音输入而非聊天产品）、架构评价（热路径留原生层）、工程节奏评价（先定方案再落实现）均准确到位，说明评审方确实深入阅读了代码和文档，而非浮于表面。

以下逐项回应。

---

## P1 意见回应

### P1-1. 凭证安全模型名实不符

**结论：采纳，确认为真实问题。**

评审方的证据链完全准确：
- `cloud_account_service.dart` 凭证存储在 SharedPreferences（`cloud_cred_*` 键）
- `flutter_secure_storage` 已引入依赖但**从未在任何位置 import 或调用**
- 项目以"隐私优先"为卖点，凭证存储与宣称存在落差

**现状承认**：
- macOS 上 SharedPreferences 底层是 `NSUserDefaults`，数据存放在 `~/Library/Preferences/` 的 plist 文件中，非加密
- `flutter_secure_storage` 在 macOS 上对接 Keychain，是正确的安全存储方案
- 该依赖是早期引入但迁移工作一直未完成，属于技术债
- 当前代码中没有任何位置使用加密存储

**整改计划**：
1. 将 API key / access key 等敏感凭证迁移到 `flutter_secure_storage`（Keychain）
2. 普通配置（语言、模式、界面偏好）保留 SharedPreferences
3. 编写迁移逻辑：首次启动时从旧路径读取并写入 Keychain，然后删除旧条目
4. 迁移完成前，不在文档或 UI 中使用暗示"加密存储"的措辞

**完成判定标准**：
- 所有包含 `api_key`、`access_key`、`access_key_secret` 的存储路径均改为 `flutter_secure_storage`
- SharedPreferences 中不再存在任何敏感凭证条目
- 旧数据迁移逻辑经测试验证（新装 + 升级两种场景）
- `flutter_secure_storage` 的 import 和调用出现在 `cloud_account_service.dart` 中

### P1-2. LLMService 日志绕过统一开关，记录原始语音文本

**结论：采纳，确认为真实问题。**

评审方的证据完全准确。LLMService 有独立的 `_log()` 方法直接写 `/tmp/SpeakOut.log`，且无条件记录用户原始口述文本（`RAW INPUT: $input`）。

**现状承认**：
- CoreEngine 的独立日志已在评审前（2026-03-19 日常开发中）迁移到 `AppLog.d`，该项为既有改动，不属于本次评审后的新增整改动作
- LLMService 的独立日志**尚未迁移**，评审方指出的问题仍然存在
- 其他 Service 是否存在类似独立日志路径，尚未全面排查

**整改计划**：
1. LLMService `_log()` 统一改为 `AppLog.d`，受 verbose 开关控制
2. 默认日志中不记录原始文本内容，仅记录长度和处理耗时
3. 原始文本仅在 verbose 模式下记录，并在日志中标注 `[SENSITIVE]`
4. 全局搜索其他 Service 是否存在类似的独立日志路径，一并清理

**完成判定标准**：
- 代码中不存在任何绕过 `AppLog` 直接写文件的日志路径（`File('/tmp/...')` 等）
- `AppLog.enabled == false` 时，无任何用户内容被写入磁盘
- `grep -r "RAW INPUT" lib/` 返回零结果，或所有匹配均受 verbose 开关保护

### P1-3. 云能力注册表与真实可运行能力存在落差

**结论：采纳。**

评审方指出的事实准确：`cloud_providers.dart` 注册了 15 个服务商，但 `asr_provider_factory.dart` 仅实现了 4 个 ASR provider。

**需要补充的上下文**：
- 注册表中的服务商分两类能力：ASR（语音识别）和 LLM（AI 润色）
- **LLM 能力**：大多数 LLM 服务商（DeepSeek、智谱、Kimi、MiniMax、Gemini、火山引擎等）具备通用接入能力（OpenAI 兼容协议），理论上可用，但尚未逐服务商做完整的端到端验证
- **ASR 能力**：火山引擎、讯飞、腾讯云的 ASR provider 确实未实现，用户若配置这些服务商的 ASR 账户会在运行时失败
- 注册表中纯 LLM 服务商（DeepSeek、智谱等）不会出现在 ASR 选择器中，不会触发 ASR 工厂的未实现路径

**整改计划**：
1. 补齐全部未实现的 ASR provider：火山引擎（Seed-ASR WebSocket）、讯飞（实时语音听写 WebSocket）、腾讯云（实时语音识别 WebSocket）
2. 每个 provider 实现完整的 ASRProvider 接口（initialize / start / acceptWaveform / stop / dispose）
3. 在 `asr_provider_factory.dart` 中注册，确保注册表与运行时能力完全一致
4. 配合真实账号进行端到端测试验证

**完成判定标准**：
- `asr_provider_factory.dart` 中所有 `// TODO` 注释消除
- `cloud_providers.dart` 中声明 ASR 能力的每个服务商，都能在 `asr_provider_factory.dart` 中成功创建 provider 实例
- 每个新增 provider 至少通过一次真实账号的录音→识别→返回文本端到端验证

### P1-4. Gateway 计费与权益逻辑风险

**结论：采纳，确认为真实风险。**

评审方对 `/report` 端点的分析精准：
- 注释语义（"累计时长"）与实现逻辑（"按本次值直接扣减"）不一致
- 缺乏幂等性保护，重复上报会重复扣减
- `/redeem` 的 KV 分步读改写在高并发下有竞态风险
- `/admin/generate` 缺少限流和防重

**现状承认**：
- 风险成立。虽然 `/report` 和 `/redeem` 当前未被客户端调用，但端点已存在且语义不自洽，从第三方审视角度风险判断成立
- 付费功能正在规划中，计划基于 token 额度而非时长计费，现有时长计费逻辑将被替换
- 优先级与付费功能落地节奏协同处理

**整改计划**：
1. 付费功能实现时将重新设计计费接口，采用会话 ID + 序列号的幂等模式
2. 余额变更引入乐观锁（KV 的 metadata version 或 Durable Objects）
3. 补充速率限制和审计日志
4. 在此之前，不对外暴露 `/report` 和 `/redeem` 端点

**完成判定标准**：
- `/report` 接口支持幂等调用（相同请求重复发送不会重复扣费）
- 余额变更有原子性保证（乐观锁或 Durable Objects）
- 所有计费接口有速率限制和审计日志
- 接口注释与实现语义完全一致

---

## P2 意见回应

### P2-1. 版本信息多处复制源

**结论：采纳，确认失配存在。**

- `gateway/src/index.js` 的 `/version` 端点返回 `1.5.11` build `97`，与当前客户端版本严重失配
- `README.md` 中"549 tests"与实际测试用例数不一致

**现状承认**：
- Gateway 版本在发版流程中应同步更新，但近几个版本遗漏了此步骤
- README 中的测试数量因多次重构后未同步更新

**整改计划**：
1. 立即更新 Gateway `/version` 端点版本号
2. README 中移除具体测试数量，改为 `flutter test` 命令说明
3. 发版清单中强化版本号检查步骤，考虑在 CI 中加自动校验

**完成判定标准**：
- `gateway/src/index.js` 中 `/version` 返回的版本号与最新 `pubspec.yaml` 一致
- `README.md` 中不包含硬编码的测试数量
- 发版清单文档中明确包含"Gateway 版本号同步"检查项

### P2-2. 静态分析尚未收口

**结论：采纳。**

评审方的观察准确。当前 `dart analyze` 有若干 info/warning 级别问题，主要集中在：
- 测试代码中的未使用导入和字段
- 少量不规范的局部变量命名（下划线开头）
- 无关紧要的字符串插值格式

这些不影响运行但确实说明静态规范没有完全跟上功能迭代速度。

**整改计划**：
1. 近期集中清理现有 warning 和明确的 info 问题
2. 在 CI 中配置 `dart analyze` 失败阈值（warning = fail）
3. 保留少量有意为之的 info 级别 suppress（如防 GC 的未使用字段引用）

**完成判定标准**：
- `dart analyze lib test` 输出零 warning
- info 级别问题数量 ≤ 5，且每个都有明确的 suppress 注释说明原因

---

## 关于评审总体结论的回应

评审方给出的三项优先事项：

1. **统一敏感信息存储与日志治理** — 完全认同。日志治理方面，CoreEngine 已在评审前迁移（既有改动），LLMService 及其他 Service 的迁移为待执行整改项。凭证迁移将作为下一优先级。
2. **建立"已实现能力"与"规划能力"的单一真源** — 完全认同。LLM 层大多已具备通用接入能力，仍需逐服务商实测验证。ASR 层将补齐全部未实现的 provider（火山引擎、讯飞、腾讯云），消除注册表与运行时的落差。
3. **强化 Gateway 的计费、幂等和版本一致性机制** — 完全认同。风险成立，优先级与付费功能落地节奏协同处理。

评审方将项目定位为"强原型/成熟中的产品工程"是准确的判断。我们认同当前阶段最需要补的是安全与一致性治理，而非新功能。

---

## 已确认的整改项与现状说明

| 整改项 | 现状 | 来源 | 说明 |
|--------|------|------|------|
| CoreEngine 日志统一到 AppLog | ✅ 既有改动 | 日常开发 | 评审前已完成，非评审触发 |
| AppLog 异步缓冲 + try-catch 兜底 | ✅ 既有改动 | 日常开发 | 评审前已完成，非评审触发 |
| LLM 调用 15 秒超时保护 | ✅ 既有改动 | 日常开发 | 评审前已完成，非评审触发 |
| LLMService 日志迁移到 AppLog | 🔲 待落代码 | 本次评审 P1-2 | 含原始文本脱敏处理 |
| 全局独立日志路径排查清理 | 🔲 待落代码 | 本次评审 P1-2 | 确保无遗漏 |
| 凭证迁移到 flutter_secure_storage | 🔲 待落代码 | 本次评审 P1-1 | 含旧数据迁移逻辑 |
| 实现火山引擎 ASR provider | 🔲 待落代码 | 本次评审 P1-3 | Seed-ASR WebSocket |
| 实现讯飞 ASR provider | 🔲 待落代码 | 本次评审 P1-3 | 实时语音听写 WebSocket |
| 实现腾讯云 ASR provider | 🔲 待落代码 | 本次评审 P1-3 | 实时语音识别 WebSocket |
| Gateway 版本号同步 | 🔲 待落代码 | 本次评审 P2-1 | `/version` 端点更新 |
| README 测试数量修正 | 🔲 待落代码 | 本次评审 P2-1 | 移除硬编码数字 |
| 静态分析 warning 清零 | 🔲 待落代码 | 本次评审 P2-2 | `dart analyze` 收口 |
