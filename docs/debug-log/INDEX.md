# 调试日志索引（L3）

> 每篇按轮次记录：现象 / 假设·判断原因 / 措施 / 验证结果 / 复盘。
> **这里装的是「为什么代码长这样」** —— 动相关模块前扫一眼对应那篇，
> 能省下重新踩一遍的时间。ADR 记选型、反模式记教训、本目录记**具体事故的追查过程**。

## 什么时候读这里

- 要改的模块在下表里 → 先读对应那篇的「复盘」和「不变量」部分
- 遇到「这段代码为什么写得这么绕」 → 大概率这里有答案
- 想改掉某个看起来多余的判断 → **先确认它不是某次事故的产物**

## 按模块

| 模块 | 文档 | 一句话 |
|---|---|---|
| 剪贴板注入 | [2026-08-16-paste-yields-previous-recognition](./2026-08-16-paste-yields-previous-recognition.md) | ⭐ 注入文字滞留剪贴板。**改注入前必读** —— 事务协调器四条不变量的全部来由；根因至今未定案 |
| 剪贴板注入 | [2026-08-10-synthetic-cmdv-not-recognized](./2026-08-10-synthetic-cmdv-not-recognized.md) | 合成 Cmd+V 序列不完整，Flutter 应用完全收不到 |
| native 层 | [2026-08-16-batch5-native-findings](./2026-08-16-batch5-native-findings.md) | EventTap 禁用不恢复、回调内同步 I/O、麦克风授权同步阻塞、音量平滑随调用频率失真 |
| 音频设备 | [2026-08-18-audio-device-lifecycle](./2026-08-18-audio-device-lifecycle.md) | 设备监听重试/拆卸、蓝牙回调禁止全量枚举、native 与偏好配置原子提交 |
| 配置服务 | [2026-08-18-config-service-consistency](./2026-08-18-config-service-consistency.md) | 初始化失败后可重试，切换主配置时不得遗留旧从属字段 |
| 配置备份 | [2026-08-18-config-backup-transaction](./2026-08-18-config-backup-transaction.md) | 导出永久排除秘密与本机标识，导入先验证、写失败回滚 |
| Config / 日志 | [2026-08-18-config-registry-and-log-lifecycle](./2026-08-18-config-registry-and-log-lifecycle.md) | provider 协议真源、日志操作串行化与清空目录跨语言一致性 |
| 云端 ASR | [2026-08-11-volcengine-asr-never-worked](./2026-08-11-volcengine-asr-never-worked.md) | 火山 ASR 自接入起从未跑通（帧解析漏 sequence） |
| ASR 启动 | [2026-06-02-asr-startup-audio-gap](./2026-06-02-asr-startup-audio-gap.md) | 录音起始丢音 |
| 全局 | [2026-06-13-review-fixes](./2026-06-13-review-fixes.md) | 三份 review 的修复批次；多处旧逻辑已变，改代码前值得扫 |

## 写新篇的规矩

- 文件名 `<日期>-<topic>.md`，日期用事故/追查发生的那天
- **验证完才回填「验证结果」和「复盘」** —— 没验证的不要当通过写进去
- 归因到系统/框架层**必须有确定性证据**（reproducer / 官方文档明确说明 /
  公认 known issue 的 issue 编号）。没证据就继续挖到自己代码里能改的地方。
  本目录里有一条现成的反面教材：曾把根因写成「屏幕共享代理推高了 changeCount」，
  探针一跑就塌了（连采 5 次都没观察到），已作废并留档
- 写完记得在本文件加一行
