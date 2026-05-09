# gateway/ — Cloudflare Workers 后端

> 单文件 `src/index.js`（616 行，Hono 框架）+ KV 存储。处理：版本检查、阿里云 NLS Token 中转、计费/许可、统计上报。

## 必读

- 上游：[../AGENTS.md](../AGENTS.md)
- 调用方：`lib/services/billing_service.dart` / `lib/services/update_service.dart`

## 这是干什么的

SpeakOut 客户端不能在本地存某些云端凭据（如阿里云的 access key 不能给用户暴露）+ 需要中心化的计费/版本/统计入口。Gateway 是这层薄中介：
- **版本/更新检查**（GET /version）— 客户端启动时拉，决定是否提示更新
- **阿里云 NLS Token 生成**（POST /aliyun/token）— 客户端 ASR 用，每次 token 5 分钟有效
- **许可证验证 + 计费**（POST /license / billing）— 收费用户的额度管理
- **版本/活跃统计**（KV 累加器）— `stats:version:{v}` + `stats:daily:{date}`，90 天 TTL

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

### 3. version 字段是 SSoT for client
客户端 `update_service.dart` 优先调 `GET /version` 拿 `dmg_url` + `version` + `build`，**降级**到 GitHub Releases API（私有 repo 时 GitHub API 不返回 assets，所以 Gateway 是主路径）。

发版流程必须**同步 gateway version**：`pubspec.yaml` 改 → `gateway/src/index.js` 同步 → `npm run deploy`。**写错版本号 = 用户看到旧版**。

### 4. 阿里云密钥服务器侧
阿里云 NLS Token 生成需要 `AccessKey ID/Secret`，**不能给客户端**（用户拿到后能调任意阿里云 API）。Gateway 中转：客户端发 license token，Gateway 用服务器侧密钥生成 NLS token 返回。

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
# 期望：{"version":"1.8.5", "build":235, "dmg_url":"...v1.8.5..."}
```

## 不要做什么

- ❌ **不要把阿里云/任何云端 secret 放进 wrangler.toml** — 用 Cloudflare Dashboard secret 或 wrangler secret put
- ❌ **不要在 Worker 里跑长任务** — Workers CPU 50ms 限制（付费 30s）
- ❌ **不要 sync version 写错** — 发版前 sed 替换时用 `0,/pattern/s` 锁第一处，避免误改支付宝 API version 字段
- ❌ **不要在 KV 里存大对象** — value 上限 25MB，但实际超过 1KB 就该考虑别的存储

## 计费 KV schema（参考）

```
license:{license_key}        → {plan, expires, quota}
balance:{license_key}        → {tokens_used, tokens_limit}
stats:version:{v}            → 累加计数
stats:daily:{YYYY-MM-DD}     → 当日活跃，90 天 TTL
```

## 测试

无单元测试（业务量 + Cloudflare Workers 测试基础设施成本不平衡）。靠：
- `curl` 验证 `/version` 等只读端点
- 客户端集成测试间接覆盖（`test/services/billing_service_test.dart`）
- 部署后人工冒烟
