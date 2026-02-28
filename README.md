<div align="center">

  <img src="assets/app_icon_rounded.png" width="160" height="160" alt="SpeakOut Icon" />

# 子曰 SpeakOut

  **Offline-First AI Voice Input for macOS**
  *Hold a key. Speak. Auto-type.*

  [Download Latest Release](https://github.com/4over7/SpeakOut/releases/latest)

</div>

---

## Features

### Voice Input (Offline)

Two trigger modes: **Hold to Speak (PTT)** — hold a key, speak, release to type; **Tap to Toggle** — tap to start, tap again to stop.

- **8 ASR Models** — SenseVoice, Paraformer, Whisper Large-v3, FireRedASR, and more. Choose by accuracy, size, or language.
- **Streaming & Offline Modes** — Real-time subtitles while speaking (streaming), or higher accuracy after release (offline).
- **Toggle Mode** — Tap once to start recording, tap again to stop. Ideal for hands-free or walking scenarios. Supports max duration protection.
- **Multilingual** — Chinese, English, Japanese, Korean, Cantonese, dialects, and 90+ languages (Whisper).
- **Fully Offline** — Powered by [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx). No audio leaves your device.

### Flash Notes

Capture thoughts without switching apps.

- **Dedicated Hotkey** — `Right Option` (configurable). Hold to speak, release, auto-saved. Or tap to toggle.
- **Daily Markdown** — Timestamped entries appended to `YYYY-MM-DD.md`.
- **Custom Save Directory** — Choose where notes are stored.
- **Toggle Mode** — Same tap-to-toggle workflow available for note capture.

### AI Smart Correction (Beta)

Optional LLM post-processing to remove filler words and polish text.

- **Cloud API** — Any OpenAI-compatible endpoint.
- **Ollama (Local)** — Run LLM locally for full privacy. Latency as low as 130ms.

### Cloud ASR (Optional)

Switch to Aliyun Smart Voice for cloud-based recognition when needed.

---

## Install

1. Download `SpeakOut.dmg` from [Releases](https://github.com/4over7/SpeakOut/releases/latest).
2. Drag to `/Applications`.
3. First launch: run `xattr -cr /Applications/SpeakOut.app` in Terminal (required until we have Developer ID signing).
4. Grant permissions: **Input Monitoring**, **Accessibility**, **Microphone**.
5. Follow the onboarding wizard to download a voice model.

### System Requirements

- macOS 13+ (Ventura or later)
- ~230MB disk space for default model (SenseVoice), up to ~1.4GB for large models

---

## Architecture

```
Hotkey → native_input.m (CGEventTap)
  → C Ring Buffer (16kHz PCM audio)
  → CoreEngine FFI polling → VAD/AGC
  → ASR (Sherpa offline / Aliyun cloud)
  → LLM correction (optional)
  → Text injection (Accessibility API) | Flash Note | Agent (planned)
```

| Layer | Path | Description |
|-------|------|-------------|
| Engine | `lib/engine/` | CoreEngine orchestrator, ASR providers, model management |
| Service | `lib/services/` | Config, LLM, diary, audio devices, app lifecycle |
| UI | `lib/ui/` | macOS-native UI (macos_ui), settings, onboarding, overlay |
| Native | `native_lib/native_input.m` | Objective-C: CGEventTap keyboard + AudioQueue ring buffer |
| Gateway | `gateway/` | Cloudflare Workers backend (Hono) |

---

## Build from Source

```bash
# Dependencies
flutter pub get

# Static analysis
flutter analyze

# Run tests
flutter test

# Build
flutter build macos --release

# Install to /Applications (with code signing)
./scripts/install.sh

# Create DMG
./scripts/create_styled_dmg.sh

# Compile native library (after modifying native_input.m)
cd native_lib && clang -dynamiclib -framework Cocoa -framework Carbon \
  -framework AVFoundation -framework AudioToolbox -framework CoreAudio \
  -framework Accelerate -o libnative_input.dylib native_input.m -fobjc-arc
```

---

## Supported Models

### Streaming (Real-time)

| Model | Languages | Size |
|-------|-----------|------|
| Zipformer Bilingual | Zh/En | ~490MB |
| Paraformer Bilingual | Zh/En | ~1GB |

### Offline (High Accuracy)

| Model | Languages | Size | Notes |
|-------|-----------|------|-------|
| **SenseVoice 2024** | Zh/En/Ja/Ko/Yue | ~228MB | Built-in punctuation (default) |
| SenseVoice 2025 | Zh/En/Ja/Ko/Yue | ~158MB | Cantonese enhanced |
| Paraformer Offline | Zh/En | ~217MB | Mature & stable |
| Paraformer Dialect 2025 | Zh/En + dialects | ~218MB | Sichuan/Chongqing |
| Whisper Large-v3 | 99 languages | ~1.0GB | Best multilingual |
| FireRedASR Large | Zh/En + dialects | ~1.4GB | Highest capacity |

---

## i18n

Full Chinese and English localization. Language follows system setting or can be manually set in Settings.

---

## License

Copyright © 2026 Leon. All Rights Reserved.

---

<div align="center">

# 子曰 SpeakOut

  **macOS 离线优先 AI 语音输入**
  *按住按键，说话，自动输入。*

  [下载最新版](https://github.com/4over7/SpeakOut/releases/latest)

</div>

---

## 功能

### 语音输入（离线）

两种触发方式：**长按说话 (PTT)** — 按住说话，松开输入；**单击切换 (Toggle)** — 单击开始，再次单击结束。

- **8 款语音模型** — SenseVoice、Paraformer、Whisper Large-v3、FireRedASR 等，按精度、体积或语言自由选择。
- **流式 & 离线模式** — 边说边出字（流式），或松开后高精度识别（离线）。
- **Toggle 模式** — 单击开始录音，再次单击结束。适合走动、站立等不方便长按的场景，支持最大时长保护。
- **多语言** — 中、英、日、韩、粤语、方言，以及 90+ 种语言（Whisper）。
- **完全离线** — 基于 [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx)，音频不出设备。

### 闪念笔记

无需切换应用即可捕捉灵感。

- **独立热键** — `Right Option`（可配置），按住说话松开保存，或单击切换。
- **每日 Markdown** — 带时间戳，追加写入 `YYYY-MM-DD.md`。
- **自定义保存目录** — 自由选择笔记存放位置。
- **Toggle 模式** — 闪念笔记同样支持单击切换录音。

### AI 智能纠错（Beta）

可选的 LLM 后处理，去除口水词、润色文本。

- **云端 API** — 支持任何 OpenAI 兼容接口。
- **Ollama 本地** — 本地运行 LLM，完全私密，延迟低至 130ms。

### 云端识别（可选）

需要时可切换到阿里云智能语音进行云端识别。

---

## 安装

1. 从 [Releases](https://github.com/4over7/SpeakOut/releases/latest) 下载 `SpeakOut.dmg`。
2. 拖到 `/Applications`。
3. 首次启动前在终端执行：`xattr -cr /Applications/SpeakOut.app`（无 Developer ID 签名前必需）。
4. 授权权限：**输入监控**、**辅助功能**、**麦克风**。
5. 按引导流程下载语音模型即可使用。

### 系统要求

- macOS 13+（Ventura 或更高）
- 磁盘空间：默认模型（SenseVoice）约 230MB，最大模型（FireRedASR）约 1.4GB

---

*Made with ❤️ by Leon. Powered by Flutter, Sherpa-ONNX, Aliyun NLS & Ollama.*
</content>
</invoke>