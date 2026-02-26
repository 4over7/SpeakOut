# 语音输入管道重构报告

> 日期：2026-02-26 | 版本：v1.2.27

## 背景

CoreEngine 经过多次迭代膨胀到 ~800 行，包含 9 个布尔状态标记、散落在 2 个文件中的 overlay 控制、调试残留代码。需要系统性梳理和简化。

## 重构内容

### Phase 1: 清理与去冗余

删除死代码和调试残留，不改变架构。

| 删除项 | 说明 |
|--------|------|
| `_audioDumpSink` | 音频 dump 调试功能，startRecording/processAudioData/stopRecording 中的写入逻辑 |
| `_audioBuffer` | 调试数组，收集后从未使用 |
| `_modelPath` | 赋值后从未读取 |
| `_startTime` | 赋值后从未读取 |
| `_isInit` | 被 `_isListenerRunning` 替代，遗留标记 |
| `_partialSubscribed` (main.dart) | 改用 `_partialSub != null` 判断 |

### Phase 2: 录音状态机

用枚举状态机替代布尔标记。

```dart
enum RecordingState { idle, starting, recording, stopping, processing }
enum RecordingMode { ptt, diary }
```

**替换的标记**: `_isRecording`, `_isStopping`, `_isDiaryMode`
**保留的标记**: `_pttKeyHeld`/`_diaryKeyHeld`（物理边沿检测），`_isListenerRunning`（引擎初始化），`_punctuationEnabled`（功能开关），`_audioStarted`（硬件状态）

**状态转换**:
```
idle → starting     (startRecording 入口)
starting → recording (音频启动成功)
starting → idle     (启动失败)
recording → stopping (key-up 或 watchdog)
stopping → processing (音频停止，进入后处理)
processing → idle    (文本输出完成)
```

**统一边沿检测**: 提取 `_handleModeKey()` 方法，PTT 和日记共用。

### Phase 3: 提取 OverlayController

新增 `lib/services/overlay_controller.dart` 单例，统一所有 overlay MethodChannel 调用。

**之前**: CoreEngine 调 show/hide/updateStatus，main.dart 也调 updateStatus（partial text）— 两处更新可能竞态。
**之后**: 只有 CoreEngine 通过 OverlayController 更新 overlay，main.dart 只更新 Flutter UI。

### Phase 4: 消除硬编码延迟

- `Future.delayed(10ms)` → `Future(() {})` 语义明确的 yield
- `Future.delayed(200ms)` → 删除，provider.stop() 已内含尾部处理

## 代码质量清理

在重构基础上，全面修复了 flutter analyze 报告的 144 个问题：

| 类别 | 数量 | 修复方式 |
|------|------|---------|
| unused_import | ~20 | 直接删除 |
| unused_field | ~10 | 删除字段及赋值 |
| deprecated_member_use (`withOpacity`) | 28 | → `withValues(alpha:)` |
| avoid_print | 40+ | → `debugPrint()` |
| curly_braces_in_flow_control_structures | ~10 | 添加花括号 |
| unnecessary_non_null_assertion | 5 | 删除多余的 `!` |
| unnecessary_null_aware_operator | 3 | `?.` → `.` |
| depend_on_referenced_packages | 2 | 添加 dev_dependencies |
| 其他 (interpolation, import 等) | ~5 | 逐个修复 |

## 影响评估

| 指标 | 之前 | 之后 |
|------|------|------|
| CoreEngine 行数 | ~800 | ~700 |
| 布尔状态标记 | 9 个 | 4 个 (+ 1 枚举) |
| overlay 更新来源 | 2 处 | 1 处 (OverlayController) |
| flutter analyze issues | 144 | 0 |
| 测试通过 | 17/17 | 17/17 |

## 关键文件变更

| 文件 | 变更 |
|------|------|
| `lib/engine/core_engine.dart` | 状态机、边沿检测、overlay 替换、清理 |
| `lib/services/overlay_controller.dart` | **新增** — overlay 统一控制器 |
| `lib/main.dart` | 删除 overlay 调用、清理 import/field |
| `lib/engine/providers/*.dart` | 移除 unused import/field，print→debugPrint |
| `lib/services/*.dart` | 移除 unused import/field，print→debugPrint |
| `lib/ui/*.dart` | withOpacity→withValues，curly_braces 修复 |
| `pubspec.yaml` | 版本 1.2.27，添加 test dev_dependencies |
