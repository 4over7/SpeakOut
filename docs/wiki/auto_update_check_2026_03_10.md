# 自动检测更新 (2026-03-10)

## 架构

```
App 启动 → AppService.init() 末尾 fire-and-forget
  → UpdateService.checkForUpdate()
    → 主路径: GitHub Releases API (api.github.com)
    → 降级:   Gateway GET /version (Cloudflare Workers)
    → 版本比较 (语义化 major.minor.patch)
    → 有新版本 → NotificationService 弹通知 + "查看更新" 按钮
    → 点击 → url_launcher 打开 GitHub Releases 页面
```

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 主数据源 | GitHub Releases API | 零运维，发 Release 即生效 |
| 降级数据源 | Gateway `/version` | 国内可访问，独立于 GitHub |
| 通知方式 | 应用内横幅 | 非阻塞，10 秒自动消失 |
| 检查频率 | 仅启动时一次 | 简单可靠，避免轮询 |
| 自动安装 | 不做 | Sparkle 复杂度高，当前阶段不需要 |

## 发版检查清单

每次发版需同步更新：

1. `pubspec.yaml` — `version` 字段
2. `gateway/src/index.js` — `/version` 端点的 `version` 和 `build`
3. GitHub 创建 Release，tag 格式 `v1.x.x`

## 涉及文件

- `lib/services/update_service.dart` — 核心逻辑
- `lib/services/app_service.dart` — 调用入口
- `lib/config/app_constants.dart` — URL 常量
- `gateway/src/index.js` — 降级端点
- `test/services/update_service_test.dart` — 9 个版本比较测试
