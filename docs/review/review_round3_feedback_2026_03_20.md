# 第三轮复核意见

日期：2026-03-20  
身份：独立第三方技术评审

## 结论

本轮针对第二轮评审指出的问题，我已完成第三轮复核。

结论是：**本次整改已完成大部分关键修复，但目前仍不能认定为“全部完成”或“可签字关闭”。**  
主要原因不是之前指出的接线问题仍未修，而是我在实际复跑测试时，**测试套件仍然失败退出**，因此当前状态不满足“整改完成并通过验证”的标准。

## 已确认完成的整改项

### 1. 凭证迁移闭环已完成

此前第二轮评审指出：

- `ConfigService` 旧路径仍将阿里云与 LLM 凭证保存在 `SharedPreferences`
- 安全存储迁移只完成了一部分，旧不安全副本仍然存在

本轮复核结果：

- `setAliyunCredentials()` 已改为写入 `flutter_secure_storage`
- `setLlmApiKey()` 已改为写入 `flutter_secure_storage`
- 启动时 `_preloadSecureKeys()` 会将旧的 `SharedPreferences` 凭证迁移到安全存储
- 迁移后会删除旧的 `SharedPreferences` 项

因此，**P1-1 本轮可以认定为已闭环完成。**

涉及位置：

- `lib/services/config_service.dart:153`
- `lib/services/config_service.dart:232`
- `lib/services/config_service.dart:349`

### 2. 火山引擎字段名错配已修复

此前第二轮评审指出：

- 注册表暴露的是 `asr_app_id` / `asr_token`
- 工厂读取的是 `app_key` / `access_token`
- 导致 UI 可填、运行时不可用

本轮复核结果：

- `ASRProviderFactory` 已改为读取 `asr_app_id` 和 `asr_token`

因此，**该项接线错误已修复。**

涉及位置：

- `lib/engine/providers/asr_provider_factory.dart:62`

### 3. 腾讯云 `app_id` 缺失问题已修复

此前第二轮评审指出：

- 注册表未暴露 `app_id`
- 但 Provider 初始化要求 `appId` 必填

本轮复核结果：

- 腾讯云注册表中已新增 `app_id`
- 工厂已将 `app_id` 透传到 Provider 初始化配置

因此，**该项可认定为修复完成。**

涉及位置：

- `lib/config/cloud_providers.dart:297`
- `lib/engine/providers/asr_provider_factory.dart:73`

### 4. 腾讯云 `_stopCompleter` 生命周期 bug 已修复

此前第二轮评审指出：

- `_stopCompleter` 为单个 `final` 实例
- 第二次 `start()` 后 `stop()` 会复用旧 future

本轮复核结果：

- `_stopCompleter` 已改为可重建
- `start()` 时会重新创建 completer
- `stop()` 路径也已改为基于当前实例等待结果

因此，**该生命周期 bug 修复成立。**

涉及位置：

- `lib/engine/providers/tencent_asr_provider.dart:37`
- `lib/engine/providers/tencent_asr_provider.dart:64`
- `lib/engine/providers/tencent_asr_provider.dart:123`

## 本轮未通过项

### 1. 不能认可“全部完成”，因为全量测试仍然失败

我在本轮实际复跑了：

```bash
flutter test
```

结果是：**测试套件退出失败**，并非“519 测试通过，仅 1 个 flaky 且与本次改动无关”。

当前可明确复现并定位的失败点为：

- `test/services/llm_service_test.dart:37`

失败用例：

- `LLMService Tests (Cloud) correctText returns modified text on success`

失败现象：

- 期望值：`"Cleaned Text"`
- 实际值：`"Dirty Text"`

这说明当前代码在至少一条测试链路上仍未满足既有行为预期，因此从独立评审角度，**本轮整改不能标记为“全部完成”。**

涉及位置：

- `test/services/llm_service_test.dart:29`
- `test/services/llm_service_test.dart:37`

## 残余风险与保留意见

### 1. 新增 ASR provider 仍缺少自动化测试覆盖

虽然这轮接线问题大多已修复，但我仍未检索到以下新增链路对应的专门测试：

- Volcengine ASR
- Xfyun ASR
- Tencent ASR
- 相关 factory 映射路径

这意味着当前更多是“代码结构上已打通”，但缺少自动化回归保护。  
因此，这一部分我只能给出“实现已明显改善”的评价，还不能给“充分验证”的评价。

### 2. 火山引擎仍存在轻微配置漂移

当前配置层仍暴露：

- `asr_cluster`

但在 Provider 实现中，相关资源标识仍然是写死值，未见该字段被实际消费。  
这不是阻断问题，但说明配置声明与运行时行为尚未完全一致。

涉及位置：

- `lib/config/cloud_providers.dart:46`
- `lib/engine/providers/volcengine_asr_provider.dart:74`

### 3. 静态分析 warning 已清零，但并非完全无提示

本轮我实际复跑了：

```bash
dart analyze lib test gateway
```

结果为：

- `0 error`
- `0 warning`
- `13 info`

因此：

- “warning 清零”这一表述成立
- “静态分析完全清零”这一表述仍不成立

## 最终意见

本轮修复质量比上一轮明显更高，且第二轮评审指出的几处关键代码问题，大部分都已被实质性修正。  
其中，**凭证迁移闭环、火山字段名对齐、腾讯云 `app_id` 补齐、腾讯云 stop 生命周期问题**，我均予以认可。

但是，只要全量测试仍然失败，我就不能作为独立第三方评审给出“整改全部完成”的结论。  
建议项目方先处理 `LLMService` 相关失败用例，并补充新增 ASR provider 的最小自动化覆盖，然后再提交下一轮复核。
