# Models 兼容边界追查

## 第一轮：凭证完整性仍有提前通过路径

### 现象

旧 review 指出“任一通用字段非空即可启用”。当前代码改成“全部通用字段齐全即可启用”，但 provider 若同时有
通用字段和能力专属字段，仍会在专属字段缺失时提前返回 true。

### 假设 · 判断原因

账户能否启用的真实条件不是“通用字段是否齐全”，而是“至少一项声明能力的整套适用字段是否齐全”。

### 措施

`hasAnyValidCredentials` 直接遍历 provider 声明的 capabilities，并复用 `hasValidCredentialsFor` 判断完整能力组。

### 验证结果

合成“tenant 通用字段 + LLM api_key 专属字段”的 provider，确认只填 tenant 不可启用、两者都填才可启用；
腾讯只填 SecretId 的当前注册表回归也被直接覆盖。恢复通用字段提前通过后测试失败。

### 复盘

凭证校验应围绕可执行能力建模，不能把字段分组本身当成成功条件。复用单能力判定也消除了枚举硬编码。

## 第二轮：未知聊天角色拖垮整份历史

### 现象

`ChatMessage.fromJson` 对未知字符串调用无 fallback 的 `firstWhere`，对越界旧整数直接索引枚举；任一消息抛错后，
`ChatService` 的整批加载进入 catch，历史无法显示。

### 假设 · 判断原因

角色是展示语义，消息正文才是用户数据。遇到新版角色或异常旧索引时，用中性的 system 展示比丢掉整份历史安全。

### 措施

集中解析 role：合法 string 与旧 int 保持原义，未知 string / 越界 int 降级为 `ChatRole.system`；缺失或错误类型仍明确抛
`FormatException`。

### 验证结果

两种未知 role 都保留正文并降级为 system；临时恢复抛错后两项测试均失败。既有合法字符串、旧整数和 JSON 往返测试全绿。

### 复盘

持久化枚举要区分“字段缺失”和“值来自未来”：前者是坏 schema，后者应尽可能保留用户数据。

## 收敛验证

- 第三轮复审：未发现新的 P2+。
- `flutter analyze`：无问题。
- `MODEL_TEST_MAX_MB=1 flutter test`：851 通过 / 10 skip / 0 失败。
- `flutter build macos --debug`：成功。

## 不变量

1. 账户只有在至少一项声明能力的完整凭证组齐全时才能启用。
2. Chat role 新值或异常旧索引不能让整份历史不可读；正文必须保留。
3. role 缺失或类型错误仍视为坏 schema，不静默伪造消息。
