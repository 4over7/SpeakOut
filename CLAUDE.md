# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**子曰 SpeakOut** — macOS 离线优先 AI 语音输入系统。Flutter/Dart 构建，通过 FFI 调用原生 Objective-C 实现低延迟键盘监听和音频采集，支持离线 (Sherpa-ONNX) 和云端 (阿里云) ASR，集成 LLM 纠错和 MCP Agent 平台。

## Build & Development Commands

```bash
# 依赖
flutter pub get

# 静态分析
flutter analyze

# 运行测试
flutter test                          # 全部测试
flutter test test/services/llm_service_test.dart  # 单个测试文件

# 构建
flutter build macos --release

# 编译并安装到 /Applications
./scripts/install.sh

# 生成 DMG 安装程序
./scripts/create_styled_dmg.sh

# 原生库编译 (修改 native_input.m 后)
cd native_lib && clang -dynamiclib -framework Cocoa -framework Carbon -o libnative_input.dylib native_input.m

# Gateway 后端 (Cloudflare Workers)
cd gateway && npm run dev      # 本地开发
cd gateway && npm run deploy   # 部署
```

## Architecture

### 三层架构

- **Engine 层** (`lib/engine/`) — 核心编排器 (`CoreEngine`)、ASR 提供者抽象 (`ASRProvider`) 及其实现 (Sherpa 离线 / Aliyun 云端)、模型下载管理
- **Service 层** (`lib/services/`) — 业务逻辑：配置管理、LLM 调用与纠错、闪念笔记、聊天历史、音频设备管理、应用生命周期
- **UI 层** (`lib/ui/`) — macOS 原生风格 UI (`macos_ui`)：聊天页、设置页、录音悬浮窗、引导页

### 关键模块

| 模块 | 路径 | 说明 |
|------|------|------|
| CoreEngine | `lib/engine/core_engine.dart` | 主编排器：键盘监听、音频处理管道、ASR 路由、LLM 分发 |
| NativeInput FFI | `lib/ffi/native_input.dart` | Dart FFI 包装器，调用原生 dylib |
| 原生键盘/音频 | `native_lib/native_input.m` | Objective-C：CGEventTap 键盘监听 + AudioQueue Ring Buffer |
| ASR Providers | `lib/engine/providers/` | Sherpa (离线) 和 Aliyun (云端) ASR 实现 |
| Gateway | `gateway/src/index.js` | Cloudflare Workers 后端 (Hono)：许可证验证、Token 生成、额度计费 |

### 核心数据流

```
快捷键触发 → native_input.m (CGEventTap)
  → C Ring Buffer 采集 16kHz PCM 音频
  → CoreEngine FFI 轮询 → VAD/AGC 处理
  → ASR (Sherpa 离线 / Aliyun 云端)
  → LLM 纠错 (可选)
  → 模式分发: 文本注入 | 闪念笔记 | MCP Agent
```

### 设计模式

- **Singleton**: 全局服务 (`ConfigService()`, `CoreEngine()`, `ChatService()`)
- **Provider/Strategy**: ASR 提供者可切换 (`ASRProvider` 抽象类)
- **生命周期**: 所有引擎/服务遵循 `init() → start() → stop() → dispose()`
- **流式处理**: `StreamController` 实时传递 ASR 结果到 UI

## Key Technical Details

- **FFI 音频采集**: 使用 C Ring Buffer 而非 Dart 回调（避免跨 isolate 回调导致 SIGABRT）
- **macOS 26 兼容**: Globe/Fn 键 (keyCode 179) 需映射到标准 Fn (63)，并抑制双重事件
- **文本注入**: 通过 macOS Accessibility API 注入文本，终端应用回退到剪贴板粘贴
- **国际化**: 使用 `flutter_localizations` + ARB 文件，支持中英文 (`l10n.yaml`)
- **敏感配置**: `aliyun_config.json` 和 `llm_config.json` 已 gitignore，凭证存储于 SharedPreferences

## Testing

测试位于 `test/` 目录，使用 `flutter_test` + `mockito`：
- `test/services/` — 服务层单元测试
- `test/engine/` — 引擎层单元测试
- `test/integration_test.dart` — 集成测试
