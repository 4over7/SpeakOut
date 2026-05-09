# lib/models/ — Models 层

> 数据模型 / DTO。纯数据类 + JSON 序列化，不含业务逻辑。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md)

## 文件清单

| 文件 | 行 | 职责 |
|---|---|---|
| `cloud_account.dart` | 182 | 云账户：`CloudAccount` / `CloudProvider` / `CloudLLMModel` / `CloudASRModel` / `CredentialField` / 枚举 `CloudCapability` `LlmApiFormat` |
| `chat_model.dart` | 46 | 聊天消息：`ChatMessage`（含 `metadata: Map` 用于 dictation 气泡折叠原文等扩展字段） |
| `billing_model.dart` | 109 | 计费：`Balance` / `TokenUsage` / `LicenseInfo`（与 Cloudflare Workers Gateway 对接） |

## 关键设计决策

### 1. 纯数据 + JSON 序列化
每个 model 必须有 `toJson()` / `fromJson(Map)`。**不在 model 里写业务方法**——业务在 service 层。

### 2. 字段扩展走 metadata map
`ChatMessage` 早期加新字段会破坏 JSON 兼容（旧聊天历史读不出）。改用 `metadata: Map<String, dynamic>?` 容纳变化字段（如 `asrOriginal` 用于显示 ASR 原文）。**新加 message 字段先考虑 metadata，再考虑加主表 schema**。

### 3. 不写 `equals` / `hashCode`（除非必要）
Dart 默认引用相等。如果一定要值相等（如 set / map key），手写或用 `equatable`，**不要混着用**。

### 4. 枚举用 String 序列化
`CloudCapability.asrStreaming` 序列化成 `"asr_streaming"`（String）而不是 int。原因：枚举顺序变化不会破坏 JSON 兼容。

### 5. credentialKeys 是冗余字段
`CloudAccount.credentialKeys` 列出该账户已设置的凭证字段名（不存值，只存 key 列表）。便于 UI 快速判断"账户配置完整"，避免每次都遍历整个 keychain。

## 不要做什么

- ❌ **不要在 model 里 import flutter** — 模型应该能在纯 dart 测试中跑
- ❌ **不要在 model 写 HTTP 调用** — 业务去 service
- ❌ **不要在 model 直接读 SharedPreferences** — 通过 service
- ❌ **不要破坏 JSON schema**（删字段 / 改字段类型） — 加 metadata map 或加 nullable 新字段
- ❌ **不要 hardcode UI 字符串** — model 不该知道任何 i18n
