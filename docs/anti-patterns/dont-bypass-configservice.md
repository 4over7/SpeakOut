# 不要直接 `SharedPreferences.getInstance()`，必须走 `ConfigService`

## 真实事件

**多次预防性约束**，落进架构铁律。最近一次相关：2026-05-09 v1.8 sidebar 重构后清理路径。

scan 全 codebase 仍偶尔出现「为了图方便直接调 SharedPreferences」的诱惑：
- "我只是临时存个状态"
- "ConfigService 还没暴露这个 key"
- "writeAsync 太慢，我自己写更直接"

每次都被驳回。原因不是 ConfigService 性能更好，是**它是配置变更的副作用聚合点**。

## 为什么会发生

SharedPreferences API 简单（getString / setString），看起来没必要包一层。但**配置变更经常带副作用**：

- 改音频设备 → 通知 `AudioDeviceService` 重启采集
- 改 LLM 账户 → 通知 `LLMService` 清缓存
- 改默认语言 → 通知 i18n locale 切换
- 改快捷键 → 通知 `CoreEngine` 重新注册

如果 UI 直接 `prefs.setString('audio_input_device_id', ...)`，没人触发副作用——音频采集还在用旧设备，用户体验崩。

## 如何避免

**100% 走 ConfigService**：

```dart
// ❌ 错
final prefs = await SharedPreferences.getInstance();
prefs.setString('llm_api_key', key);

// ✅ 对
await ConfigService().setLlmApiKey(key);
```

如果 ConfigService 没有你需要的字段：
1. 在 `lib/services/config_service.dart` 加 getter / setter pair
2. 默认值放 `lib/config/app_constants.dart` 的 `kDefaultXxx` 常量
3. 如有副作用，在 setter 里 broadcast / 调相关 service

如果只是临时状态（生命周期与 widget 同），用 `setState` / `Provider` 的 state，不要进 SharedPreferences。

## 修复模式

发现 codebase 已有直接 `SharedPreferences` 调用：

1. 评估是否是临时状态——如果是，迁出 SharedPreferences 到 widget state
2. 否则，加 ConfigService getter/setter，迁移调用点
3. 如果迁移后发现"原来漏的副作用应该补上"，借机修复（这种情况算 bug fix，不算 feature creep）

## 相关

- `lib/services/AGENTS.md` 设计决策 #2「ConfigService 是配置唯一入口」
- 单元测试中 ConfigService 不能 fresh new（singleton），用 setter 重置（见 `test/helpers/test_helpers.dart`）
