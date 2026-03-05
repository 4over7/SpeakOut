# 词汇增强 Phase 2：全模型纯音近距离匹配

> 实现日期：2026-03-05
> Commit：7eb2d26

---

## 背景

Phase 1（精确替换）已完成。Phase 2 目标：对 ASR 识别的音近字错误做软匹配替换（如"科博斯"→"Kubernetes"，即便用户未录入精确词条）。

**关键调研结论：**
- sherpa_onnx C API v1.12.19+ 已有 `ys_log_probs`（per-token 置信度），但仅**离线 Transducer** 模型有值
- 当前 app 全部模型均无置信度
- 决策：**全模型统一用纯音近距离**；未来若加入离线 Transducer 模型，置信度门控作为增强层叠加

---

## 新增文件

| 文件 | 说明 |
|------|------|
| `lib/engine/asr_result.dart` | ASRResult 数据类 |
| `test/services/vocab_service_test.dart` | Phase 2 单元测试 |

---

## 变更文件

| 文件 | 说明 |
|------|------|
| `lib/engine/asr_provider.dart` | `stop()` 返回 `ASRResult`（breaking change） |
| `lib/engine/model_manager.dart` | 新增 `ModelArch` 枚举 + `arch` 字段 |
| `lib/engine/providers/sherpa_provider.dart` | 返回 ASRResult |
| `lib/engine/providers/offline_sherpa_provider.dart` | 返回 ASRResult，预留置信度注释 |
| `lib/engine/providers/aliyun_provider.dart` | 返回 `ASRResult.textOnly` |
| `lib/engine/core_engine.dart` | 使用 ASRResult，接入 Phase 2 流水线 |
| `lib/services/vocab_service.dart` | 实现 `applyWithPhonetic` + 拼音缓存 |
| `lib/services/config_service.dart` | 新增 `vocabPhoneticEnabled` / `vocabPhoneticThreshold` |
| `lib/ui/vocab_settings_page.dart` | 追加音近匹配 UI 区块 |
| `lib/l10n/app_zh.arb` + `app_en.arb` | 新增 Phase 2 本地化 key |
| `pubspec.yaml` | 新增 `lpinyin: ^2.0.3` |

---

## ASRResult 数据类

```dart
class ASRResult {
  final String text;
  final List<String> tokens;          // 分词列表（所有模型均有）
  final List<double> timestamps;      // 时间戳
  final List<double>? tokenConfidence; // 仅 transducerOffline 有值，其余 null
}
```

---

## ModelArch 枚举

```dart
enum ModelArch {
  transducerStreaming, // Zipformer 双语（流式）
  transducerOffline,  // 未来离线 Transducer — 可读 ys_log_probs
  ctcStreaming,        // Paraformer 双语（流式）
  ctcOffline,         // Paraformer/SenseVoice/FireRedASR（离线）
  whisperLike,        // Whisper
}
```

当前模型置信度状态：

| 模型 | arch | 置信度 |
|------|------|--------|
| Zipformer 双语（流式）| transducerStreaming | ❌ |
| Paraformer 双语（流式）| ctcStreaming | ❌ |
| SenseVoice 2024/2025 | ctcOffline | ❌ |
| Paraformer 离线/方言 | ctcOffline | ❌ |
| Whisper Large-v3 | whisperLike | ❌ |
| FireRedASR Large | ctcOffline | ❌ |
| 未来离线 Zipformer | transducerOffline | ✅ 预留 |

---

## 音近匹配算法

### 流水线位置

```
Phase 1 精确替换
  → Phase 2 音近匹配（vocabPhoneticEnabled = true 时执行）
    → AI Correction
```

### 核心逻辑

```dart
Future<String> applyWithPhonetic(String text, {
  List<String>? tokens,
  List<double>? confidence,
})
```

1. **拼音缓存**（懒加载）：对所有激活词条的 `wrong` 字段预计算拼音，缓存到 `Map<String, String>`
2. **滑动窗口**：对文本每个位置，取与 `wrong` 等长的子串（2~6 字）
3. **方言归一化**：平翘舌（zh→z/ch→c/sh→s）、前后鼻音（l→n）视为等价
4. **Levenshtein 距离**：归一化拼音字符串的编辑距离 ≤ 阈值时执行替换
5. **缓存失效**：词条增删、开关切换时调用 `invalidatePinyinCache()`

### 默认阈值：1.5

- 阈值 1.0：仅允许 1 个字母差异（最严格）
- 阈值 1.5（默认）：容忍 1~2 个音节差异
- 阈值 3.0：最宽松，覆盖广但误判多

---

## 配置项

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `vocab_phonetic_enabled` | bool | false | Phase 2 总开关（默认关，避免误判） |
| `vocab_phonetic_threshold` | double | 1.5 | 音近距离阈值 |

---

## 依赖

- `lpinyin: ^2.0.3` — 纯 Dart 拼音转换库，无原生依赖

---

## 未来扩展（transducerOffline 置信度门控）

当加入离线 Zipformer 模型时，可在 `OfflineSherpaProvider.stop()` 中读取 `ys_log_probs`：

```dart
// offline_sherpa_provider.dart
// if (_currentModelArch == ModelArch.transducerOffline) {
//   final jsonPtr = SherpaOnnxBindings.getOfflineStreamResultAsJson(_stream!.ptr);
//   final json = jsonDecode(toDartString(jsonPtr));
//   confidence = (json['ys_log_probs'] as List?)?.cast<double>();
// }
```

置信度低的 token 对应位置优先做音近替换，高置信度位置跳过。
