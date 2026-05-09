# ADR-001: 自动更新不走 Sparkle，用自研 UpdateService

**日期**: 2026-04-23
**状态**: ✅ Accepted（v1.8.1 落地，v1.8.5 实测验证 3 秒完成全流程）
**决策者**: 项目所有者 + AI agent 协助调研

## 背景

v1.8.1 规划阶段的初始想法：「集成业界标准的 [Sparkle](https://sparkle-project.org/) 框架做 macOS 自动更新」——理由是「长期主义，选业界标准」。

但调研后发现已经有大量基础设施：
- `lib/services/update_service.dart` 实现了完整的检查 + 下载 + 进度（含断点续传 v1.8.4 加的）+ 失败重试
- `lib/main.dart` 实现了状态化 update badge UI
- `native_lib/native_input.m` 的 `launch_updater` 启动独立 bash helper 完成 mount/replace/restart
- 缺的只是「设置页 hero 没接通 UpdateService UI」——半天工作量

引入 Sparkle 意味着：
- 替换上面整套自研基础设施
- 接入新的签名验证（Sparkle EdDSA）+ 新的 appcast.xml 协议
- macOS 23+ 系统行为变化适配（Sparkle 跟进慢）
- 整套迁移 1-2 周工作量

## 选项

### A. 集成 Sparkle 完整替换
- ✅ 业界标准、社区维护
- ✅ EdDSA 双签 + 增量更新
- ❌ 替换成本高（1-2 周）
- ❌ 现有自研基础设施全部废弃（已经稳定运行）

### B. 只接通现有 UpdateService UI（半天）
- ✅ 改动最小，零风险
- ✅ 复用既有断点续传/进度/失败处理
- ❌ 没有 EdDSA 双签（但 macOS 自带 Apple 公证 + hdiutil attach 自动验证 codesign）
- ❌ 没有增量更新（DMG 53 MB 全量下载）

### C. 实现 EdDSA 单独验证层（自研增强）
- ✅ 不引入 Sparkle 但提升完整性保护
- ❌ 又要自己实现一套，反而违反"用业界标准"原则

## 决策

**选 B：接通现有 UpdateService**。

**为什么不是 A**：「长期主义」原则不等于「无脑选最重的方案」。它的真正含义是「**基于完整事实选最优方案**」。盘清事实后：

1. macOS `hdiutil attach` 挂载 DMG 时自动验证 codesign，篡改的 DMG 拒绝挂载——**完整性已有兜底**
2. SpeakOut DMG 53 MB，增量更新的边际价值小
3. 我们的 UpdateService 已经实现了 Sparkle 90% 的能力（下载/进度/重试/续传）

Sparkle 的真正不可替代价值（EdDSA + 增量）对当前体量收益不足以抵消迁移成本。

## 后果

**正面**：
- v1.8.1 半天就发出（实际工作量 vs 1-2 周）
- 自研代码完全可控，遇到 macOS 系统行为变化（如 v1.8.2 那次 `hdiutil` 输出格式 bug）能立刻定位修复
- 实测 v1.8.5 自更新 3 秒完成全流程（用户报告验证）

**负面**：
- 没有 EdDSA 双签——理论上如果攻击者能获得 Apple Developer ID 私钥，可以发恶意 DMG。但这也是绕过 Sparkle 的攻击路径（Sparkle 假设 Apple 公证可信）
- 增量更新缺失——未来 DMG 如果膨胀到 200 MB+，全量下载会变成体验问题

**触发重启评估的条件**：
- DMG 体积涨到 200 MB+（增量更新成本不可忽视）
- 用户反馈下载完整性问题（macOS codesign 验证失败案例）
- v2.0 重做发布渠道时一并评估

## 相关

- v1.8.1 memory 归档：`~/.claude/projects/-Users-leon-Apps-speakout/memory/project_v181_plan.md`
- 实测验证：v1.8.5 升级 16:51:33 helper 启动 → 16:51:36 done，3 秒全流程
- 看到 "应该选业界标准" 的诱惑时回看本文 — 业界标准的真实成本要算清楚
