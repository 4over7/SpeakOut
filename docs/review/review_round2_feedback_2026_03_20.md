# 第二轮复核反馈

> 日期：2026-03-20
> 身份：独立第三方技术团队
> 复核对象：针对 2026-03-19 评审意见的整改代码

## 一、结论摘要

本轮复核基于实际代码、提交历史、测试结果和静态分析结果完成，不依据口头汇报。

我的结论是：

- 多数整改项已经真实落地，尤其是日志治理、Gateway 版本同步、README 修正、静态分析 warning 清零，这些我认可。
- 但“全部完成”这一说法目前仍不成立。
- 至少有两项高优先级问题还没有真正闭环：
  - `P1-1` 凭证迁移到安全存储仅完成了一部分
  - `P1-3` 新增的部分 ASR provider 代码虽已添加，但运行链路尚未完全打通

因此，我当前的综合判断是：

**本轮整改取得了明显进展，但还不能判定为全部完成。**

## 二、我已确认完成或基本完成的部分

### 1. `P1-2` LLMService 日志治理

这一项我认可为已基本完成。

复核证据：

- `LLMService` 已不再向 `/tmp/SpeakOut.log` 直接写盘
- 日志统一走 `AppLog.d`
- 原始文本日志已改为仅记录长度，不再默认落明文内容

相关代码：

- `lib/services/llm_service.dart`
- `lib/config/app_log.dart`

结论：

- “日志迁移到 AppLog”成立
- “原始语音文本脱敏”成立
- “全局独立日志路径清理”基本成立

### 2. `P2-1` Gateway 版本号同步与自动化

这一项我认可。

复核证据：

- `gateway/src/index.js` 当前 `/version` 返回 `1.5.13` / `114`
- `pubspec.yaml` 当前版本为 `1.5.13+114`
- `scripts/install.sh` 与 `scripts/create_styled_dmg.sh` 已新增同步 Gateway version/build 的脚本逻辑

相关代码：

- `gateway/src/index.js`
- `pubspec.yaml`
- `scripts/install.sh`
- `scripts/create_styled_dmg.sh`

结论：

- “Gateway 版本号同步”成立
- “Gateway 版本号自动化（build 脚本）”成立

### 3. `P2-1` README 测试数量修正

这一项我认可。

复核证据：

- README 已移除“549 tests”之类的硬编码数量，改为通用的 `flutter test` 说明

相关代码：

- `README.md`

### 4. `P2-2` 静态分析 warning 清零

这一项我基本认可，但表述需要更精确。

我实际运行结果：

- `flutter test`：**520 tests passed**
- `dart analyze lib test gateway`：**0 warning / 0 error，仍有 13 条 info**

因此准确说法应是：

- “warning 清零”成立
- “静态分析完全清零”不成立

## 三、仍未闭环的问题

### 1. `P1-1` 凭证迁移到 `flutter_secure_storage` 尚未真正完成

`CloudAccountService` 的确已迁移到 `flutter_secure_storage`，这一部分改动是真实的。

但旧配置路径仍然存在以下问题：

- `ConfigService.setAliyunCredentials()` 仍然把阿里云凭证写入 `SharedPreferences`
- `ConfigService.setLlmApiKey()` 仍然把 LLM API key 写入 `SharedPreferences`
- 启动时 `_preloadSecureKeys()` 仍从 `SharedPreferences` 读取这些值到缓存

也就是说：

- 新的 CloudAccount 凭证路径变安全了
- 但旧的配置入口仍在生成不安全副本
- 因此“凭证迁移到安全存储”不能算彻底完成

相关代码：

- `lib/services/cloud_account_service.dart`
- `lib/services/config_service.dart`

结论：

**`P1-1` 当前只能算部分完成，不能关闭。**

### 2. `P1-3` 火山引擎 ASR provider 运行链路未打通

火山引擎 Provider 文件已经新增，但当前配置链路存在明显不一致：

- 注册表暴露给用户填写的 ASR 字段是：
  - `asr_app_id`
  - `asr_token`
  - `asr_cluster`
- `ASRProviderFactory.buildConfig()` 却读取：
  - `app_key`
  - `access_token`
- `VolcengineASRProvider.initialize()` 又要求 `appKey` 和 `accessKey` 非空

这意味着当前从 UI 正常填写火山引擎账户后，运行时大概率仍会初始化失败。

相关代码：

- `lib/config/cloud_providers.dart`
- `lib/ui/cloud_accounts_page.dart`
- `lib/engine/providers/asr_provider_factory.dart`
- `lib/engine/providers/volcengine_asr_provider.dart`

结论：

**火山引擎 ASR 还不能判定为完成。当前更像“Provider 文件已添加，但接线未闭环”。**

### 3. `P1-3` 腾讯云 ASR provider 运行链路与生命周期仍有缺口

腾讯云也存在两个问题：

#### 问题 A：UI 无法提供完整凭证

注册表中腾讯云仅定义了：

- `secret_id`
- `secret_key`

但 `ASRProviderFactory` 与 `TencentASRProvider.initialize()` 又都要求：

- `appId`

也就是说，当前 UI 根本没有这个必填字段，用户无法通过正常配置路径满足 Provider 初始化条件。

#### 问题 B：`_stopCompleter` 生命周期错误

`TencentASRProvider` 中：

- `_stopCompleter` 被定义为单个 `final Completer`
- `start()` 时没有重新创建
- `stop()` 每次都返回同一个 future

这会导致第二次及之后的录音会话复用第一次已完成的 completer，生命周期逻辑是错误的。

相关代码：

- `lib/config/cloud_providers.dart`
- `lib/engine/providers/asr_provider_factory.dart`
- `lib/engine/providers/tencent_asr_provider.dart`

结论：

**腾讯云 ASR 目前不能算完成，且存在实质性生命周期 bug。**

## 四、需要更准确表述的地方

如果要更新整改汇总，我建议将当前结论改成以下更客观的版本：

- `P1-2`：已完成
- `P2-1`：已完成
- `P2-2`：warning 已清零，info 仍有少量残留
- `P1-1`：部分完成，CloudAccount 已迁移，ConfigService 旧路径未迁移
- `P1-3`：部分完成，新增 3 个 provider 文件，但火山引擎与腾讯云未完全打通；讯飞代码已落地，仍需真实账号验证
- `P1-4`：未做，维持原结论

## 五、测试与验证结论

我本轮实际运行的验证结果如下：

- `flutter test`：**520 tests passed**
- `dart analyze lib test gateway`：**13 info，0 warning，0 error**

这说明：

- 现有代码总体没有明显回归
- 工程卫生比上一轮有明显提升
- 但新增 provider 尚无对应测试覆盖，现有 520 个测试不能证明这 3 条新 ASR 链路已经可靠

## 六、下一步建议

我建议开发团队按以下顺序继续收尾：

1. 完成 `ConfigService` 旧凭证路径到安全存储的迁移与清理
2. 修正火山引擎 ASR 的字段命名与 UI/Factory/Provider 对齐
3. 为腾讯云补齐 `app_id` 配置入口，并修复 `_stopCompleter` 生命周期问题
4. 为新增 3 个 ASR provider 至少补一层单元测试/协议测试
5. 完成真实账号端到端验证后，再更新“全部完成”的结论

## 七、最终意见

本轮整改不是无效，相反，已经完成了相当多真实且有价值的工作。

但如果以“独立第三方复核”的标准判断，我当前只能给出：

**“大部分整改已完成，少数关键项仍未闭环”**

而不能给出：

**“全部完成”**

等上述剩余问题修正后，我可以继续进行下一轮复核。
