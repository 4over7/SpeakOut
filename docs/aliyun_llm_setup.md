# 阿里云百炼 (通义千问) API 配置指南

SpeakOut 的 AI 纠错功能完美兼容 **阿里云百炼 (DashScope)** 平台。您可以直接使用通义千问大模型来优化语音识别结果。

## 1. 开通服务

1. 访问 [阿里云百炼控制台](https://bailian.console.aliyun.com/)。
2. 登录您的阿里云账号。
3. 如果是首次使用，请根据提示开通 "模型服务 (DashScope)"。

## 2. 获取 API Key

1. 在控制台左侧菜单中，点击 **API-KEY 管理** (通常在右上角头像菜单或“算力/API Key”板块)。
2. 点击 **创建新的 API-KEY**。
3. 复制生成的 Key (例如: `sk-xxxxxxxxxxxxxxxxxxxxxxxx`)。
   > ⚠️ **注意**: API Key 只会在创建时显示一次，请妥善保存。

## 3. 在 SpeakOut 中配置

打开 SpeakOut 的 **设置 (Settings)** -> **AI 智能纠错**，填写以下信息：

* **API Key**: 粘贴您刚才复制的 key (例如 `sk-d123...`)
* **Base URL**: `https://dashscope.aliyuncs.com/compatible-mode/v1`
  * *注意：必须完全一致，包含 `/compatible-mode/v1`*
* **Model Name**: 推荐使用 `qwen-plus` 或 `qwen-max`
  * `qwen-turbo`: 速度快，成本极低
  * `qwen-plus`: 效果与速度的平衡 (推荐)
  * `qwen-max`: 效果最好，但稍慢

## 4. 验证

配置完成后，开启 "AI 智能纠错" 开关。
随便说一句话（包含一些“嗯、啊”等口语），看悬浮窗是否显示 "🤖 AI 优化中..." 并最终输出润色后的文本。

---

### 常见问题

* **Q: 需要付费吗？**
  * A: 阿里云通常为新用户提供一定的免费额度（如几百万 token）。长期使用费用也非常低廉（相比 GPT-4 便宜很多）。
* **Q: 速度如何？**
  * A: 通义千问在国内访问速度极快，通常在 1 秒左右即可完成纠错。
