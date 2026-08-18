# gateway/ — Cloudflare Workers 后端

> 单文件 `src/index.js`（Hono 框架）+ KV 存储。处理：版本检查、许可证、设备注册、计费与支付（支付宝 / Stripe）、统计上报。

## 必读

- 上游：[../AGENTS.md](../AGENTS.md)
- 调用方：`lib/services/billing_service.dart` / `lib/services/update_service.dart`

## 这是干什么的

SpeakOut 客户端不能在本地存某些云端凭据（如阿里云的 access key 不能给用户暴露）+ 需要中心化的计费/版本/统计入口。Gateway 是这层薄中介。

**实际路由全集**（以 `src/index.js` 里的 `app.get/post` 为准）：

| 分组 | 路由 |
|---|---|
| 版本 / 统计 | `GET /version`（客户端启动拉取，决定是否提示更新）、`GET /stats` |
| 许可证 | `POST /verify`、`POST /redeem`、`POST /admin/generate`（管理端，鉴权 fail-closed） |
| 设备 | `POST /device/register` |
| 计费 | `GET /billing/status`、`POST /billing/usage`、`POST /billing/order`、`GET /billing/order/:orderId`、`GET /billing/plans` |
| 支付 | `POST /payment/alipay`、`POST /payment/stripe`、`GET /payment/stripe/success`、`GET /payment/stripe/cancel` |

> ⚠️ 没有 `/license` 路由（旧文档写过，实为 `/verify` + `/redeem`）。
> ⚠️ 没有 `/aliyun/token` 路由 —— 规划中未实现，详见下「阿里云密钥」。

## 文件清单

| 文件 | 职责 |
|---|---|
| `src/index.js` | 全部业务（Hono routes + KV 操作）|
| `wrangler.toml` | Cloudflare Workers 配置（KV namespace ID / 环境变量）|
| `package.json` | 依赖（Hono + 类型）|

## 关键设计决策

### 1. 单文件 vs 拆模块
v1.x 起一直保持单文件。Cloudflare Workers 部署单 entry，业务量小（< 1000 行），多文件反而增加心智负担。**新功能优先在 index.js 加 route，不要急着拆**。

### 2. KV 而非 D1
Cloudflare KV 简单，符合 SpeakOut 的"键值统计 + 配置"场景。**不用 D1（SQL）**——查询模式都是 key lookup，关系数据无价值。

### 3. version + build 是客户端更新真源
客户端 `update_service.dart` 优先调 `GET /version` 拿 `dmg_url` + `version` + `build`，**降级**到 GitHub Releases API（私有 repo 时 GitHub API 不返回 assets，所以 Gateway 是主路径）。语义版本相同时继续比较 build，DMG 缓存也用两者共同隔离。

发版流程必须**同步 gateway version**：`pubspec.yaml` 改 → `gateway/src/index.js` 同步 → `npm run deploy`。**写错版本号 = 用户看到旧版**。

### 4. 阿里云密钥（⚠️ 目标态 vs 现状）
**目标**：`AccessKey ID/Secret` 不给客户端（用户拿到能调任意阿里云 API）；由 Gateway 中转——客户端发 license token，Gateway 用服务器侧密钥生成 NLS token 返回。
**现状（2026-06-13 核实）**：`/aliyun/token` 路由尚未实现；legacy `AliyunProvider` 仍在客户端本地用 AK/SK 做 HMAC 签名换 token（endpoint 已从 http 改 https 止血）。这是 legacy「阿里云 NLS 旧版」路径，新用户走 DashScope/其他 provider。**TODO（需单独排期/决策）**：实现 Gateway `/aliyun/token`，或直接下线 legacy NLS。

### 5. 公证签名 + Stapled
DMG URL 指向 GitHub Release（已签名 + Apple Notarized + Stapled）。`/version` 返回的 `dmg_url` 带版本号路径，CDN cache 友好。

## 部署

```bash
cd gateway
npm run dev      # 本地开发
npm run deploy   # 部署到 Cloudflare
```

部署后**必须验证** `/version` 返回值：
```bash
curl https://<your-worker>/version | jq
# 期望 version/build 与 pubspec.yaml 完全一致，例如 {"version":"1.9.1","build":239,"dmg_url":"...v1.9.1..."}
# index.js 里版本行带 `// @speakout-version` 标记，sed 替换时认这个锚点
```

## 不要做什么

- ❌ **不要把阿里云/任何云端 secret 放进 wrangler.toml** — 用 Cloudflare Dashboard secret 或 wrangler secret put
- ❌ **不要在 Worker 里跑长任务** — Workers CPU 50ms 限制（付费 30s）
- ❌ **不要 sync version 写错** — 发版前 sed 替换时用 `0,/pattern/s` 锁第一处，避免误改支付宝 API version 字段
- ❌ **不要在 KV 里存大对象** — value 上限 25MB，但实际超过 1KB 就该考虑别的存储

## KV schema（参考）

```
license:{license_key}        → {plan, expires, quota}
balance:{license_key}        → {tokens_used, tokens_limit}
stats:versions               → 有界版本计数 map（旧 stats:version:{v} 只读兼容）
stats:daily:{YYYY-MM-DD}     → 当日更新检查次数，90 天 TTL
```

版本统计只接受有界 SemVer，并限制 map 中可独立跟踪的版本数；其余聚合为 `unknown` / `other`，不能再让公共查询参数无限制造 KV key。`daily` 是启动/手动检查次数的粗略近似，不是去重用户数。

## 测试

```bash
cd gateway && npm test
node --check src/index.js
```

`test/` 用 Node 内置测试器 + 内存 KV 覆盖当前启用的 `/version`、统计基数、旧数据分页兼容和 `/stats` fail-closed。部署后仍需用 `curl` 冒烟线上 `/version`。

> **注意：计费/许可证链仍没有自动化安全网** —— `BillingService` 未启用且无单测。改那组路由时必须另建测试与端到端验证，不能拿当前更新/统计测试当覆盖。
