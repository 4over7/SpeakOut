/// Service 层对外暴露的 engine 数据类型 re-export。
///
/// UI 层 import 本文件（而非直接 import `lib/engine/...`）以满足三层架构约束：
/// UI → Service → Engine（见 lib/ui/AGENTS.md）。
/// 行为/能力走 [AppService] 的 facade；这里只暴露 UI 需要的纯数据类型。
library;

export '../engine/model_manager.dart' show ModelInfo, ModelArch;
