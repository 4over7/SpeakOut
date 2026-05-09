# lib/config/ — Config 层

> 静态常量、云服务商注册表、日志、发行渠道开关。**只读**——所有可变状态在 `lib/services/config_service.dart`。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md)
- 关联：`lib/services/config_service.dart` 是配置**读写**入口；本目录是**默认值/常量**来源

## 文件清单

| 文件 | 行 | 职责 |
|---|---|---|
| `app_constants.dart` | 284 | 全局常量：默认值、超时、URL、Prompt 模板、模型列表（不在 model_manager 里的部分） |
| `cloud_providers.dart` | 342 | **云服务商注册表** — 14 个 provider 的 metadata（base URL / 凭证字段 / 模型清单 / 鉴权方式） |
| `app_log.dart` | 105 | 全局日志：`AppLog.d/i/w/e`，写文件 + verbose 控制台输出，`flush_timer` 异步刷盘 |
| `distribution.dart` | 19 | 渠道开关：`DISTRIBUTION=appstore` 时禁用更新检查、隐藏内购等 |

## 关键设计决策

### 1. 常量集中 vs 散落
所有"用户偏好的默认值"（`kDefault*`）+ "全局调谐参数"（`kPause*`、`kLlm*Timeout`、`kAnthropicMax*`）必须在 `app_constants.dart`。**禁止**散落在 service / engine 内的局部 const。

### 2. cloud_providers 是 SSoT
14 个 provider 的所有元数据（包括默认模型、凭证字段定义、API 格式枚举）在这一份注册表里。新增 provider 只改这一份文件。**禁止**在 UI 或 LLMService 写死特定 provider 的 baseUrl / 字段名。

### 3. 凭证字段 scope
`CredentialField.scope: Set<CloudCapability>` 定义这个字段属于哪种能力（asrStreaming / asrBatch / llm 或通用）。UI 据此分组渲染（通用灰 / ASR 蓝 / LLM 橙）。新增 provider 时**必须正确标 scope**。

### 4. AppLog 不用 print
**禁止** `print()` 出现在 lib/ 任何文件。`AppLog.d` 异步写文件 + 用户开 verbose 时双写控制台。生产环境默认只记 INFO 以上。

### 5. distribution 守卫
`Distribution.isAppStore` 用来分流 GitHub / App Store 行为。守卫粒度按"本质上是否合规"判定，不是简单 bool 开关：
- ❌ 模型解压不用守卫——靠 try/catch 自然回退即可
- ✅ 自动更新检查必须守卫——App Store 版本不能调 GitHub Releases API

## 不要做什么

- ❌ **不要在 config 层加状态** — config 是常量。状态去 services/config_service.dart
- ❌ **不要 hardcode provider 信息** — 走 `CloudProviders.getById(id)` 拿
- ❌ **不要 print** — 走 `AppLog`
- ❌ **不要在 const 里硬编码用户可见字符串** — 那是 i18n 的活，去 `lib/l10n/app_*.arb`
- ❌ **不要让 const String 包含敏感信息**（API key / token） — 通过 `dart-define` 或 SharedPreferences 注入

## cloud_providers 分组顺序（用户看到的顺序）

1. 流式 ASR + LLM：阿里云百炼、火山、讯飞
2. 非流式 ASR + LLM：Groq、OpenAI
3. 纯 LLM：DeepSeek、智谱、Kimi、MiniMax、Gemini、Anthropic
4. 纯流式 ASR：腾讯云
5. Legacy：阿里云 NLS（旧版）

新增 provider 时按这个分组找位置插入。
