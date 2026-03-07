# 全模块黑盒测试方案

> 日期: 2026-03-07 | 版本: v1.5.1

## 核心问题

"AI 写代码 + AI 写测试 = 共同盲区" — 如果测试用例是基于实现代码生成的，测试和代码会共享同样的逻辑假设，无法发现根本性错误。

## 解决方案: 黑盒测试生成

```
需求文档 ──→ Agent（不看实现代码）──→ 测试用例
                                        │
实现代码 ──→ 测试运行 ←─────────────────┘
```

**关键约束**: 生成测试用例的 Agent 只接收需求描述，不 import 任何 `lib/` 私有文件，不读取实现代码。这确保测试用例来自对需求的独立理解，而非对实现的复述。

## 覆盖范围

### 已覆盖模块（10 个，406 用例）

| 模块 | 文件 | 用例 | 可测性 |
|------|------|------|--------|
| ConfigService | `config_service_blackbox_test.dart` | 115 | 完全可测 |
| LLMService | `llm_blackbox_test.dart` | 45 | 完全可测 |
| CoreEngine utils | `core_engine_blackbox_test.dart` | 43 | 完全可测 |
| VocabService | `vocab_blackbox_test.dart` | 42 | 完全可测 |
| ModelManager | `model_manager_blackbox_test.dart` | 39 | 元数据可测 |
| ChatService | `chat_service_blackbox_test.dart` | 39 | 完全可测 |
| NotificationService | `notification_service_blackbox_test.dart` | 30 | 完全可测 |
| AliyunTokenService | `aliyun_token_service_blackbox_test.dart` | 21 | Mock HTTP |
| ASRResult | `asr_result_blackbox_test.dart` | 17 | 数据类 |
| DiaryService | `diary_service_blackbox_test.dart` | 15 | 临时目录 |

### 未覆盖模块（5 个，依赖真实硬件/FFI）

| 模块 | 原因 |
|------|------|
| AudioDeviceService | 所有方法直接调 FFI 操作麦克风硬件 |
| SherpaProvider | 需要真实 Sherpa-ONNX 模型文件 + C FFI |
| OfflineSherpaProvider | 同上 |
| AliyunProvider | WebSocket 连接 + 阿里云协议 |
| AppService | 依赖 CoreEngine FFI 初始化 |

## 发现的 Bug

### AliyunTokenService 段错误（已修复）

**问题**: `generateToken` 返回 `json['Token']['Id']` 时，如果阿里云返回的 `Id` 是非字符串类型（如 int），Dart 会尝试将 `dynamic(int)` 当作 `String?` 返回，导致 VM 段错误。

**修复**: `return json['Token']['Id']?.toString();`

**发现过程**: 黑盒测试 Agent 从"API 响应可能返回非预期类型"这个通用边界条件出发生成了测试用例，完全不知道实现中存在此问题。

## 测试基础设施要点

### ConfigService Singleton 测试模式

```dart
bool _configInitialized = false;
Future<void> setupConfig({...}) async {
  final config = ConfigService();
  if (!_configInitialized) {
    SharedPreferences.setMockInitialValues({});
    await config.init();
    _configInitialized = true;
  }
  // 后续用 setter，不重新 init
  await config.setVocabEnabled(vocabEnabled);
}
```

### HTTP Mock 中文编码

```dart
// 错误: http.Response() 默认 Latin-1，中文会抛异常
return http.Response(cloudOk('中文'), 200);

// 正确: 使用 Response.bytes + UTF-8
return http.Response.bytes(
  utf8.encode(cloudOk('中文')),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
```

## 局限性

1. **需求文档本身也是 AI 写的** — 如果需求遗漏场景，测试也不会覆盖
2. **UI 交互未覆盖** — 按钮点击、开关联动等需要 Widget Test
3. **只验证已知预期** — 无法发现"没想到的场景"，可考虑模糊测试补充
