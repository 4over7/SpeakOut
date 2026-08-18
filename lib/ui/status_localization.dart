import 'package:flutter/widgets.dart';

import '../engine/engine_status.dart';
import '../services/engine_status_localizer.dart';

/// 把引擎给的稳定状态码翻成用户语言。
///
/// **三端共用一份**（macOS / Windows / Linux 的 Home 都调它）——
/// 在各自的 Home 里各抄一个 switch 必然漂移：
/// 上一版只有 macOS 走了映射，Windows/Linux 直接显示 `status.message`，
/// 中文环境下用户看到的是引擎里那句英文 fallback。
///
/// 没有码的临时 UI 消息仍回退到 `message`。
String localizedEngineStatus(BuildContext context, EngineStatus status) {
  return localizedEngineStatusForLocale(
    status,
    Localizations.localeOf(context),
  );
}
