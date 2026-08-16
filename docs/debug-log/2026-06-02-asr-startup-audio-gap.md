# ASR 启动「开头丢字」排查 — 2026-06-02

## 背景
用户反馈：按下快捷键后马上说话，要过两三秒才"正式识别"，悬浮窗波形开头不动，
最终识别结果**开头几个字被吞**。用户配置（plist 实证）：
- `flutter.work_mode = smart`（智能模式 = 本地识别 + AI 润色）
- `flutter.active_model_id = sensevoice_zh_en_int8`（SenseVoice **非流式**）
- 无 `audioInputDeviceId` → 系统默认麦克风

---

## 第 1 轮 — 定位到 AudioQueue 冷启动空窗

### 现象
- 按键后悬浮窗音频波形开头不动（约 1~2s）
- 最终识别结果开头几个字丢失
- 用户两条语音输入消息开头本身就被吞，二次印证

### 假设 / 判断原因
非流式 `OfflineSherpaProvider` 录音全程只累积音频、`stop()` 时一次性解码
（`offline_sherpa_provider.dart:217` 注释 "no real-time decoding"），
所以"开头丢字"只能是**录音开头那段音频根本没进 ring buffer**。

逐段证伪自己的代码：
- `native_input.m:867-892` `AudioInputCallback`：被回调即写入**全部** samples，无 warm-up 丢弃逻辑
- `native_input.m:819-855` `get_audio_level`：基于 ring buffer 最新数据算 RMS，无数据→返回 0→波形不动
- `_pollAudioRingBuffer` → `acceptWaveform`：有多少读多少，ring buffer 60s 容量不会丢

→ 代码没主动吞开头。唯一可能：`AudioInputCallback` 在开头一两秒没产出有效音频。

根因：`start_audio_recording`（`native_input.m:936-1022`）**每次按键才冷启动**
`AudioQueueNewInput` + `AllocateBuffer×10` + `AudioQueueStart`，无预热/常驻机制
（grep `warm` 零命中）。`AudioQueueStart` 返回 ≠ 麦克风立即出声，macOS 激活
输入硬件管线有延迟；蓝牙麦克风（HFP/SCO 建链）冷启动 1~2s 常见。

### 措施
待定（与用户对齐方案后执行）。候选：
- A. 麦克风预热/常驻 + ring buffer pre-roll（零空窗，代价：指示灯常亮，做成可选"低延迟模式"）
- B. app 启动时预创建 AudioQueue，按键只 Start（省创建开销，治标，蓝牙激活延迟仍在）
- C. 等首帧有效音频再算"录音开始" + 提示（不能挽回已说出口的字）

### 验证结果
待回填。需要的确定性证据：加一行 native 日志，量测
`AudioQueueStart` 返回 → 首个有效 callback / 首个 level>0 的时间差。

### 复盘
待回填。
