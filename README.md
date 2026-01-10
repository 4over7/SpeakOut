# 子曰 SpeakOut 🎙️

> **Your Voice, Your AI Operating System.**  
> Offline-First. Privacy-Focused. Limitless Capabilities.

SpeakOut is not just a dictation tool. It is a **Next-Generation AI Assistant** that lives on your Mac, turning your voice into structured notes, actionable commands, and high-quality text—completely private by default.

---

## 🌟 Core Features

### 1. ⚡️ Instant Voice Input (Offline)

Press a hotkey (default: `Left Option`). Speak. Done.

- **Ultra-Low Latency**: Powered by **Sherpa-ONNX** running locally on CPU/GPU.
- **Multilingual**: Supports mixed Chinese/English recognition with high accuracy.
- **Privacy Core**: No audio leaves your device by default.

### 2. 📝 Flash Notes (Diary Mode)

Capture fleeting thoughts without context switching.

- **Hotkey**: `Right Option` (Configurable).
- **Auto-Save**: Thoughts are automatically timestamped and appended to a daily Markdown file (e.g., `2024-01-10.md`).
- **AI Correction**: Optional LLM post-processing to fix homophones and punctuation.

### 3. 🤖 MCP Agent Platform (New in v3.5)

SpeakOut acts as a "Universal Dispatcher" for the **Model Context Protocol (MCP)**.

- **Natural Language Actions**: "Add a meeting tomorrow at 2pm" -> Executes Calendar Script.
- **Extensible Skills**: Add any Python/Node.js script as a "Tool". SpeakOut handles the intent parsing.
- **HITL Security**: "Human-in-the-Loop" confirmation ensures the AI never executes dangerous commands without your approval.

### 4. 💬 Unified Chat Interface

A timeline of your digital life.

- View all your voice notes, agent execution results, and AI dialogues in one place.
- Manually archive interesting chat bubbles to your Diary.
- **Persistent History**: Conversations are saved locally and securely.

---

## 🛠️ Architecture

### The "Tri-Force" Engine

1. **Audio Native (Sherpa)**: Converts speech to text in <0.2s.
2. **LLM Router (Qwen/Aliyun)**: Analyzes text intent.
    - If "Note" -> Save to Diary.
    - If "Command" -> Construct JSON-RPC call.
3. **MCP Client**: Connects to local or remote agents via Stodio/SSE.

### Privacy by Design

- **Local First**: ASR is 100% offline.
- **Sandboxed**: App runs in macOS Sandbox, accessing only authorized directories.
- **Transparency**: You see exactly what tool is being called and with what arguments.

---

## 🚀 Getting Started

1. **Install**: Download the latest `.dmg` from Releases.
2. **Grant Permissions**: Allow Microphone and Accessibility (for text injection).
3. **Configure**:
    - **Models**: improved accuracy? Switch to Aliyun Cloud Engine (Optional).
    - **Intelligence**: Set up your LLM (Local or Remote) for smarter routing.
4. **Add Skills**:
    - Go to `Settings -> Agent Tools`.
    - Add a local script (e.g., `python3 scripts/mcp_calendar.py`).

---

## 🔧 Developer Guide

### Building from Source

```bash
# 1. Install Flutter (3.10+) & Rust (for FFI)
brew install flutter rust

# 2. Get Dependencies
flutter pub get

# 3. Build & Install
./scripts/install.sh
```

### Running Tests

```bash
flutter test test/agent_suite_test.dart
```

---

*Made with ❤️ by Leon. Powered by Flutter & Sherpa-ONNX.*
