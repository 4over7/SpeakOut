# lib/models/ — Models 层

> 数据模型 / DTO。纯数据类 + JSON 序列化，不含业务逻辑。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md)

## 文件清单

| 文件 | 声明的类型 |
|---|---|
| `cloud_account.dart` | `CloudAccount` / `CloudProvider` / `CloudLLMModel` / `CloudASRModel` / `CredentialField` + 枚举 `CloudCapability`。<br>⚠️ 枚举 `LlmApiFormat` **不在这里**，在 `lib/config/app_constants.dart` |
| `chat_model.dart` | `ChatMessage`（含 `metadata: Map` 承载 dictation 气泡折叠原文等扩展字段）+ 枚举 `ChatRole` |
| `billing_model.dart` | `BillingStatus` / `BillingPlan` / `BillingOrder`（与 Cloudflare Workers Gateway 对接） |

## 关键设计决策

### 1. 纯数据 + JSON 序列化
每个 model 必须有 `toJson()` / `fromJson(Map)`。**不在 model 里写业务方法**——业务在 service 层。

### 2. 字段扩展走 metadata map
`ChatMessage` 早期加新字段会破坏 JSON 兼容（旧聊天历史读不出）。改用 `metadata: Map<String, dynamic>?` 容纳变化字段（如 `asrOriginal` 用于显示 ASR 原文）。**新加 message 字段先考虑 metadata，再考虑加主表 schema**。

### 3. 不写 `equals` / `hashCode`（除非必要）
Dart 默认引用相等。如果一定要值相等（如 set / map key），手写或用 `equatable`，**不要混着用**。

### 4. 枚举不进 JSON
`CloudCapability` 只出现在 `CloudProvider` 静态注册表（`CloudProviders.all`，const，不做 JSON 往返），`CloudAccount.toJson()` 也不序列化它。
**新增需要持久化的枚举时用 String（不是 index）**，否则枚举顺序一变就破坏旧数据兼容。

### 5. 凭证值不进 model JSON
`CloudAccount.toJson()` 只写 `credentialKeys`（凭证字段名列表，**不含值**），值单独存储、`fromJson` 时 `credentials: {}` 由上层回填。
便于 UI 快速判断"账户配置是否完整"而不碰密文。

> ⚠️ **凭证目前存在 SharedPreferences 明文**，不是 Keychain —— `config_service.dart` / `cloud_account_service.dart`
> 里的 `TODO: 拿到苹果开发者账号后迁移到 Keychain` 尚未做。代码里若干注释写着 "loaded from Keychain"，是超前描述，别当真。

## 不要做什么

- ❌ **不要在 model 里 import flutter** — 模型应该能在纯 dart 测试中跑
- ❌ **不要在 model 写 HTTP 调用** — 业务去 service
- ❌ **不要在 model 直接读 SharedPreferences** — 通过 service
- ❌ **不要破坏 JSON schema**（删字段 / 改字段类型） — 加 metadata map 或加 nullable 新字段
- ❌ **不要 hardcode UI 字符串** — model 不该知道任何 i18n
