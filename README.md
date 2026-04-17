<div align="center">

  <img src="assets/app_icon_rounded.png" width="160" height="160" alt="SpeakOut Icon" />

# 子曰 SpeakOut

  **Offline-First AI Voice Input for macOS**
  *Hold a key. Speak. Auto-type.*

  [Download](https://github.com/4over7/SpeakOut/releases/latest) · [Wiki](https://github.com/4over7/SpeakOut/wiki) · [Changelog](CHANGELOG.md)

  ![Platform](https://img.shields.io/badge/platform-macOS%2013+-blue)
  ![Version](https://img.shields.io/badge/version-1.7.1-brightgreen)
  ![Tests](https://img.shields.io/badge/tests-598%20passed-brightgreen)
  ![License](https://img.shields.io/badge/license-proprietary-lightgrey)

</div>

---

## What is SpeakOut?

A macOS desktop app that turns your voice into text — offline by default, with optional cloud enhancement. Press a hotkey, speak naturally, and text appears at your cursor. Supports 11 languages, real-time translation, and AI-powered text polishing.

**Works 100% offline with production-quality results.** No account, no API key, no internet required. Just install, download a model, and start speaking. Cloud features (AI polish, translation, cloud ASR) are optional enhancements — the core voice input experience is fully local.

**Core principles**: privacy first (audio never leaves your device in offline mode), low latency (sub-second response), and zero configuration (works out of the box).

---

## Features

### Voice Input

| | Offline Mode | Smart Mode | Cloud Mode |
|---|---|---|---|
| **ASR Engine** | Sherpa-ONNX (local) | Sherpa-ONNX (local) | Cloud ASR (Groq, DashScope, etc.) |
| **AI Polish** | — | LLM correction + translation | — |
| **Privacy** | 100% offline | ASR offline, LLM via cloud | Audio sent to cloud |
| **Latency** | Fastest | +0.5~1s for LLM | Depends on network |

- **8 Offline Models** — SenseVoice, Paraformer, Whisper Large-v3, FireRedASR, and more
- **Two Trigger Modes** — Hold to Speak (PTT) or Tap to Toggle
- **Streaming & Offline** — Real-time subtitles while speaking, or higher accuracy after release

### 11 Languages + Translation

| Languages | Input | Output | Translation |
|-----------|-------|--------|-------------|
| Chinese, English, Japanese, Korean, Cantonese | All modes | All modes | — |
| Spanish, French, German, Russian, Portuguese | Whisper / Cloud | Smart Mode | Via LLM |

- **Auto-detect** — Let the model detect what language you're speaking
- **Translation Mode** — Set different input/output languages (e.g., speak Chinese → output English). Requires Smart Mode.
- **Script Control** — Choose Simplified or Traditional Chinese output

### Cloud ASR (6 Providers)

| Provider | Protocol | Highlights |
|----------|----------|------------|
| **DashScope** (Aliyun) | WebSocket | Paraformer realtime, Chinese optimized |
| **Groq** | REST (Whisper) | Fast, 99 languages |
| **OpenAI** | REST (Whisper/GPT-4o) | Most accurate multilingual |
| **Volcengine** (ByteDance) | WebSocket (binary) | Seed-ASR, highest Chinese accuracy |
| **iFlytek** | WebSocket | 202 dialects |
| **Tencent Cloud** | WebSocket | 5h/month free |

### AI Polish (Smart Mode)

LLM post-processing: fix homophones, remove filler words, translate, enforce output language.

- **12 LLM Providers** — DashScope, DeepSeek, Volcengine, OpenAI, Anthropic, Zhipu, Kimi, MiniMax, Gemini, iFlytek, Groq, Ollama (local)
- **Professional Vocabulary** — Industry dictionaries (Tech/Medical/Legal/Finance/Education) + personal dictionary
- **Typewriter Mode** (Alpha) — Stream LLM output character by character to cursor

### ⚡ Superpowers

Hotkey-driven productivity features on top of voice input:

- **Flash Notes** — Dedicated hotkey, speak and auto-save as timestamped Markdown to any folder
- **AI Organize** — Select any text, press hotkey, LLM restructures logic and appends below the original (keeps source intact)
- **Instant Translation** — Speak source language, output target language in real time (works with any AI Polish LLM)
- **Correction Feedback** — Spot an ASR/LLM mistake? Fix it inline, press the feedback hotkey — LLM diffs against the last recording trace and auto-learns the term into your vocabulary
- **AI Debug** — Hold hotkey to capture screenshot + voice description of a bug, auto-sent to Claude Code / Cursor / bound AI coding windows (up to 5 slots)

### Smart Audio

- **Bluetooth Detection** — Auto-detects headset connect/disconnect
- **Device Selection** — Choose preferred mic in settings
- **Pre-segmentation** — 3s pause triggers background decoding, minimizing final wait on stop

---

## Install

1. Download `SpeakOut.dmg` from [Releases](https://github.com/4over7/SpeakOut/releases/latest)
2. Drag to `/Applications`
3. First launch: `xattr -cr /Applications/SpeakOut.app` (required until Developer ID signing)
4. Grant permissions: **Input Monitoring**, **Accessibility**, **Microphone**
5. Follow the onboarding wizard to download a voice model

### System Requirements

- macOS 13+ (Ventura or later)
- ~230MB for default model, up to ~1.4GB for Whisper/FireRedASR

---

## Offline Models

### Streaming (Real-time subtitles)

| Model | Languages | Size |
|-------|-----------|------|
| Zipformer Bilingual | Zh/En | ~490MB |
| Paraformer Streaming | Zh/En | ~1GB |

### Offline (Higher accuracy)

| Model | Languages | Size | Notes |
|-------|-----------|------|-------|
| **SenseVoice 2024** | Zh/En/Ja/Ko/Yue | ~228MB | Default, built-in punctuation |
| SenseVoice 2025 | Zh/En/Ja/Ko/Yue | ~158MB | Cantonese enhanced |
| Paraformer Offline | Zh/En | ~217MB | Mature & stable |
| Paraformer Dialect | Zh/En + Sichuan | ~218MB | Dialect support |
| Whisper Large-v3 | 99 languages | ~1.0GB | Best multilingual |
| FireRedASR Large | Zh/En + dialects | ~1.4GB | Highest capacity |

---

## Architecture

```
Hotkey → native_input.m (CGEventTap)
  → C Ring Buffer (16kHz PCM)
  → CoreEngine FFI polling
  → ASR (8 offline models / 6 cloud providers)
  → LLM polish + translation (optional, 12 providers)
  → Clipboard paste to active app
```

| Layer | Path | Description |
|-------|------|-------------|
| Engine | `lib/engine/` | CoreEngine, ASR providers, model management |
| Service | `lib/services/` | Config, LLM, billing, diary, audio devices |
| UI | `lib/ui/` | macOS-native UI (macos_ui), settings, overlay |
| Native | `native_lib/` | Objective-C: CGEventTap + AudioQueue ring buffer |
| Gateway | `gateway/` | Cloudflare Workers (Hono): license, billing, version check |

**Codebase**: ~29,000 lines across 86 files. 598 tests.

---

## Build from Source

```bash
flutter pub get          # Dependencies
flutter analyze          # Static analysis (0 issues)
flutter test             # Run tests (598 tests)
flutter build macos --release  # Build
./scripts/install.sh     # Install to /Applications
./scripts/create_styled_dmg.sh  # Create DMG

# Native library (after modifying native_input.m)
cd native_lib && clang -dynamiclib -framework Cocoa -framework Carbon \
  -framework AVFoundation -framework AudioToolbox -framework CoreAudio \
  -framework Accelerate -o libnative_input.dylib native_input.m -fobjc-arc
```

---

## Security

- **Offline Mode** — Audio never leaves your device
- **Credentials** — API keys stored in SharedPreferences (local, not synced); export/backup includes plaintext keys with explicit user confirmation
- **Logging** — User speech content never logged by default; developer mode logs may include input/output text for debugging
- **Independent Review** — Passed 4 rounds of independent third-party security review

---

## License

Copyright © 2026 Leon. All Rights Reserved.

---

<div align="center">

# 子曰 SpeakOut

  **macOS 离线优先 AI 语音输入**
  *按住按键，说话，自动输入。*

  [下载最新版](https://github.com/4over7/SpeakOut/releases/latest) · [Wiki](https://github.com/4over7/SpeakOut/wiki) · [更新日志](CHANGELOG.md)

</div>

---

## 功能亮点

### 语音输入
- **完全离线可用** — 无需账号、无需联网、无需 API Key，安装即用。8 款本地模型基于 [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx)，中英识别准确率媲美云端，音频不出设备
- **三种工作模式** — 纯离线（隐私优先）/ 智能（离线识别 + AI 润色）/ 云端（高精度）
- **两种触发方式** — 按住说话（PTT）或单击切换（Toggle）；PTT 和 Toggle 可共用一个键
- **预分段识别** — 录音中检测到 3 秒停顿自动后台解码，停止时只等最后一段，显著减少等待

### 11 种语言 + 口译
- 中英日韩粤 + 西法德俄葡，支持输入/输出自动检测
- **口译模式** — 输入中文→输出英文等任意组合，LLM 自动翻译（需智能模式）

### ⚡ 超能力（热键驱动）
- **闪念笔记** — 独立热键，语音直接保存为 Markdown，按天归档到自定义目录
- **AI 梳理** — 选中文字按快捷键，LLM 深度重组逻辑结构并追加在原文下一行
- **即时翻译** — 按住说话自动翻译为目标语言，不影响正常录音
- **纠错反馈** — 发现识别错误，改完按反馈键，LLM 对比最近录音自动学入词汇表
- **AI 一键调试** — 按住截屏+语音描述 bug，自动发送到绑定的 Claude Code / Cursor 窗口（最多 5 槽位）

### 云端服务（可选增强）
- **6 家云端 ASR** — 阿里云百炼（DashScope 实时）、Groq、OpenAI、火山引擎、讯飞、腾讯云
- **12 家 LLM** — 百炼、DeepSeek、豆包、OpenAI、Claude、智谱、Kimi、MiniMax、Gemini、讯飞、Groq、Ollama 本地
- **服务商预置** — 新用户打开云账户即可看到完整列表，点击配置即用
- **账户导入/导出** — 跨设备迁移，JSONL 格式，含凭证

### 专业词汇 & 安全
- **行业词典 + 个人词库** — 术语注入 LLM 实现领域感知
- **API 密钥本地存储** — SharedPreferences，不上云、不同步；导出备份含明文密钥需用户确认
- **签名公证** — Developer ID 签名 + Apple 公证，下载双击即用，无 Gatekeeper 警告

## 安装

1. 从 [Releases](https://github.com/4over7/SpeakOut/releases/latest) 下载 `SpeakOut.dmg`
2. 拖到 `/Applications`
3. 首次启动前：`xattr -cr /Applications/SpeakOut.app`
4. 授权：**输入监控**、**辅助功能**、**麦克风**
5. 按引导下载语音模型即可使用

**系统要求**：macOS 13+，磁盘空间 230MB ~ 1.4GB（取决于模型选择）

---

## Contact

<a href="https://x.com/4over7"><img src="https://img.shields.io/badge/X-@4over7-000?logo=x" alt="X" /></a>

<img src="assets/wx.jpg" width="200" alt="WeChat" />
