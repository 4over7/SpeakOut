# 火山引擎 ASR 从接入至今从未跑通

**日期**：2026-08-11
**触发场景**：用户切到云端识别模式，录音无反应；改用火山引擎后仍然只出空结果
**结论**：四个缺陷叠加。前两个让这条路径**根本切不过去**，后两个是路径本身**坏的**

---

## 轮次 1：切云端模式后录音无反应

**现象**：日志 `Provider Init Failed: Exception: Aliyun Config Missing` → `ASR Provider not ready!`。
用户误以为「用了一会儿断了」，实际是切模式那一刻就没起来，11 秒后按键才暴露。

**假设·判断原因**：报错指向阿里云 NLS 旧版，但用户用的是 DashScope，凭证齐全。
查 `initASR`：走云账户系统的前提是 `selectedAsrAccountId != null`，
而配置里**压根没有这个键**（对照 `selected_llm_account_id` 是有值的）。
条件不成立 → fall through 到 legacy Aliyun NLS 分支。
LLM 侧有 `pickRecommendedLlmAccount()` 兜底，ASR 这条路径当初漏了。

**措施**：新增 `pickRecommendedAsrAccount()`，凭证完整性按**能力**判断
（讯飞需 app_id+api_key+api_secret，火山有独立 asr_api_key，不能只看 api_key）。

**验证结果**：启动日志变为 `Initializing 阿里云百炼 ASR` → `ASR Provider initialized: dashscope`，
不再进 legacy 分支。

**复盘**：假设准确。但这个 bug 的**报错方向是误导性的** ——
指向用户根本没配置的旧版服务，很容易让人跑去填 NLS 凭证。

---

## 轮次 2：界面显示火山，引擎却连阿里云

**现象**：用户截图显示下拉里「火山引擎（豆包）」已勾选，日志却是 dashscope。

**假设·判断原因**：两边各写各的回退 ——

```dart
// UI (mode_tab.dart)
final effectiveAsrId = pool.any((a) => a.id == selectedAsrId) ? selectedAsrId! : pool.first.id;
// Engine (我在轮次 1 新加的)
selectedAsrAccountId ?? pickRecommendedAsrAccount()?.id
```

UI 回退到池中第一个（火山），Engine 按推荐顺序（dashscope）。
更糟的是 UI 那个「已勾选」**从不落盘** —— 用户以为配好了，引擎一无所知。

**措施**：收敛为 `CloudAccountService.effectiveAsrAccount()`，UI 与 Engine 共用同一入口。
顺带发现 LLM 侧 `settings_shared.resolveLlmApiKey()` 有同样问题（回退到 first），
会算出 A 的 key 却把请求发给 B —— 一并对齐。

**验证结果**：用户手动选火山后配置真正写入，重启日志 `ASR Provider initialized: volcengine_asr`。

**复盘**：**是我在轮次 1 引入的不一致**（新加的兜底与既有 UI 逻辑不同）。
教训：加兜底之前先搜清楚同一决策在别处是怎么做的，否则修一个引一个。

---

## 轮次 3：火山连上了，但只返回空结果

**现象**：`[VolcengineASR] Response parse error: FormatException`，
payload 前多一个字节、JSON 被截断；`duration` 逐帧递增说明连接与上行都正常。

**假设·判断原因**（两次推测**全错**）：

| 轮次 | 推测 | 结果 |
|---|---|---|
| 3a | 多出的字节是 payload_size 低位 → header_size 应为 2 | 错。改完错误变成 `Unexpected extension byte`，仍不通 |
| 3b | 偏移还差一点 | 错。继续瞎调 |

**措施**：停止反推，**直接打印原始字节**（前 5 帧）。

**验证结果**：一眼看穿 ——

```
11 91 10 00 | 00 00 00 01 | 00 00 00 6e | 7b 22 61 75 ...
└ header 4 ┘ └ sequence 4┘ └ p_size 4 ┘ └ payload(0x6e=110) ┘   总长 122 ✅
```

`byte0=0x11` → header_size=**1**（我猜的 2 是错的）；
`byte1=0x91` → flags=0x1，**bit0 表示其后跟 4 字节 sequence**，逐帧递增 01 02 03 04 05。
旧代码写死「4 字节头 + 紧跟 payload_size」，于是 payload_size 读成了序列号（值 1），
payload 只截到 1 字节。

**复盘**：**协议解析是完全可观测的，第一时间就该打字节。**
我却从异常消息反推了两轮，浪费了用户两次真机测试。
这与 2026-08-10 那次「合成 Cmd+V」的教训**一模一样** ——
那次也是绕了十轮才想到拿现成的 CGEventTap 当探针。
**共同点：手上有直接观测手段却不用，偏要从错误信息反推。**

---

## 轮次 4：帧解出来了，字段类型又不对

**现象**：错误变为 `'_Map<String, dynamic>' is not a subtype of 'List<dynamic>?'`。

**假设·判断原因**：帧层已通（JSON 能解析），是 `_processResponse` 里
`json['result'] as List?` 的类型假设错了。实际结构：

```json
{"audio_info":{"duration":0},
 "result":{"additions":{"log_id":"..."},"text":""}}
```

**措施**：兼容 Map / List 两种形态；`type` 缺省时按「累积文本」处理
（流式响应并不总带 type）。同时打印前两条完整响应以确认字段名。

**验证结果**：识别成功并注入（11 字），全程无 parse error。
确认字段就是 `result.text`。随后**移除**完整响应打印 —— 那会把识别文本写进日志（隐私）；
只保留帧头采样（仅字节，不含内容）。

**复盘**：这一轮做对了 —— 改动同时带上诊断输出，一次拿到真实结构，没让用户多跑一轮。

---

## 为什么潜伏这么久

默认走 dashscope，火山要**手动切**才会碰到；而「手动切」恰好被轮次 1、2 的 bug 挡死
（切不过去 / 切了不落盘）。两层遮蔽叠在一起，把整条路径藏得严严实实。

## 流程教训

除了上面「该打字节不打字节」，还有一次低级失误：
用 python 脚本做代码替换时 `assert old in s` 失败（前一步插入的诊断日志把待匹配代码块切断了），
但命令里 python 与 `install.sh` 之间**没有 `&&`**，脚本报错后照样编译安装了未修改的版本，
白白浪费用户一轮测试。此后改为**先 grep 校验改动确实落盘，再执行安装**。
