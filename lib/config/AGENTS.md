# lib/config/ — Config 层

> 静态常量、云服务商注册表、日志、发行渠道开关。用户配置状态在 `lib/services/config_service.dart`；
> `AppLog` 只维护日志 sink、timer 与运行期开关。

## 必读

- 上游：[../../AGENTS.md](../../AGENTS.md)
- 关联：`lib/services/config_service.dart` 是配置**读写**入口；本目录是**默认值/常量**来源

## 文件清单

| 文件 | 职责 |
|---|---|
| `app_constants.dart` | 全局常量：默认值、超时、URL、Prompt 模板、模型列表（不在 model_manager 里的部分）+ 枚举 `LlmApiFormat` |
| `cloud_providers.dart` | **云服务商注册表** — `CloudProviders.all` 里每个 provider 的 metadata（base URL / 凭证字段 / 模型清单 / 鉴权方式），取用走 `CloudProviders.getById(id)` |
| `app_log.dart` | 全局日志：`AppLog.d/e`，写文件 + verbose 控制台输出，timer 异步刷盘 |
| `distribution.dart` | 渠道开关：`DISTRIBUTION=appstore` 时禁用更新检查、隐藏内购等 |

## 关键设计决策

### 1. 常量集中 vs 散落
所有"用户偏好的默认值"（`kDefault*`）+ "全局调谐参数"（`kPause*`、`kLlm*Timeout`、`kAnthropicMax*`）必须在 `app_constants.dart`。**禁止**散落在 service / engine 内的局部 const。

### 2. cloud_providers 是当前账户体系的 SSoT
所有当前 provider 的元数据（默认模型、凭证字段定义、API 格式枚举）集中在 `CloudProviders.all`。
**禁止**在 UI 或 LLMService 写死特定 provider 的 baseUrl / 字段名。`AppConstants.kLlmPresets` 是旧无账户配置的
遗留定义，不是当前注册表；协议分流也必须查 `CloudProviders`，否则列表缺项会误落到错误协议。

### 3. 凭证字段 scope
`CredentialField.scope: Set<CloudCapability>` 定义这个字段属于哪种能力（asrStreaming / asrBatch / llm 或通用）。UI 据此分组渲染（通用灰 / ASR 蓝 / LLM 橙）。新增 provider 时**必须正确标 scope**。

### 4. AppLog 不用 print
**禁止** `print()` 出现在 lib/ 任何文件。普通调试信息走 `AppLog.d`，受 verbose 开关控制；
回滚失败、凭证残留等默认也必须落盘的稀少错误走 `AppLog.e`。初始化、切目录与销毁必须串行，失败后必须可重试。

### 5. distribution 守卫
`Distribution.isAppStore` 用来分流 GitHub / App Store 行为。守卫粒度按"本质上是否合规"判定，不是简单 bool 开关：
- ❌ 模型解压不用守卫——靠 try/catch 自然回退即可
- ✅ 自动更新检查必须守卫——App Store 版本不能调 GitHub Releases API

## 不要做什么

- ❌ **不要在 config 层加用户配置状态** — 状态去 services/config_service.dart；AppLog 生命周期状态除外
- ❌ **不要 hardcode provider 信息** — 走 `CloudProviders.getById(id)` 拿
- ❌ **不要 print** — 走 `AppLog`
- ❌ **不要新增散落的用户可见字符串** — 通用 UI 文案走 `lib/l10n/app_*.arb`；provider 注册表的既有 metadata 集中留在 `cloud_providers.dart`
- ❌ **不要让 const String 包含敏感信息**（API key / token） — 通过 `dart-define` 或 SharedPreferences 注入

## cloud_providers 分组顺序

列表顺序就是 UI 顺序：全功能流式 → 全功能非流式 → 纯 LLM → 纯 ASR → Legacy。
新增 provider 时放入对应能力分组，并让 `test/config/cloud_providers_invariants_test.dart` 覆盖 ID、模型、默认值和凭证 scope。
