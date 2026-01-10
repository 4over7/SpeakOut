# 阿里云智能语音配置指南 (Aliyun NLS Setup Guide)

SpeakOut 支持接入阿里云智能语音交互（Nuatural Language Interaction）服务，以获得更精准的云端语音识别体验。

本指南将协助您获取所需的 **AccessKey ID**、**AccessKey Secret** 和 **AppKey**。

---

## 第一步：准备阿里云账号

1. 访问 [阿里云官网 (www.aliyun.com)](https://www.aliyun.com/)。
2. 注册或登录您的阿里云账号。
3. 完成**实名认证**（使用云产品必须步骤）。

## 第二步：开通智能语音交互服务

1. 访问 [智能语音交互控制台](https://nls-portal.console.aliyun.com/overview)。
2. 点击 **“立即开通”**（绝大多数功能提供 **3个月免费试用**）。
3. 在控制台左侧菜单，选择 **“全部项目”** -> **“创建项目”**。
4. 填写项目名称（例如 `SpeakOut`），选择场景（如“通用”）。
5. **重要**：创建成功后，您会在项目列表中看到一个 **AppKey**。
    * 🏷 **AppKey**: 请复制并保存，稍后填入 SpeakOut。

## 第三步：获取 AccessKey (密钥)

为了安全访问云服务，您需要创建一个 AccessKey。

1. 将鼠标悬停在阿里云控制台右上角的头像上，选择 **“AccessKey 管理”**。
2. (推荐) 选择 **“开始使用子用户 AccessKey”** 以获得更高安全性：
    * 创建一个新用户（例如 `speakout-user`）。
    * 勾选 **“OpenAPI 调用访问”**。
    * 创建后，系统会显示 **AccessKey ID** 和 **AccessKey Secret**。
    * **注意**：`AccessKey Secret` 只显示一次，请务必立即复制保存！
3. **授权**：
    * 在“用户管理”列表中点击新建的用户。
    * 点击 **“添加权限”**。
    * 搜索 `NLS`，添加 **“AliyunNLSFullAccess”**（智能语音交互完全管理权限）。

---

## 第四步：在 SpeakOut 中配置

1. 打开 **SpeakOut** 应用。
2. 点击主界面右上角的 **设置 (Settings)** ⚙️ 图标。
3. 在设置顶部，点击 **“☁️ 阿里云 (Cloud)”** 切换引擎模式。
4. 在下方表单中填入：
    * **AccessKey ID**
    * **AccessKey Secret**
    * **AppKey**
5. 点击 **“保存并应用” (Save & Apply)**。

✅ **配置完成！** 现在您可以尝试按住快捷键说话，体验云端识别的高精度。

## 常见问题 (FAQ)

* **Q: 收费吗？**
  * A: 阿里云提供 3 个月的免费试用版。试用期结束后，按使用量（调用时长）计费，具体请参考阿里云官网定价。
* **Q: 为什么提示 "Authentication Failed"？**
  * A: 请检查 AccessKey 是否正确，以及该 Key 对应的用户是否拥有 `AliyunNLSFullAccess` 权限。
