import 'package:flutter/widgets.dart';
import 'package:speakout/l10n/generated/app_localizations.dart';

import '../engine/engine_status.dart';

/// 把引擎给的稳定错误码翻成用户语言。
///
/// **三端共用一份**（macOS / Windows / Linux 的 Home 都调它）——
/// 在各自的 Home 里各抄一个 switch 必然漂移：
/// 上一版只有 macOS 走了映射，Windows/Linux 直接显示 `status.message`，
/// 中文环境下用户看到的是引擎里那句英文 fallback。
///
/// 没有码的老状态回退到 `message`。那批中文硬编码是既有技术债，
/// 逐步用码替换，不在这里一次性重写。
String localizedEngineStatus(BuildContext context, EngineStatus status) {
  final loc = AppLocalizations.of(context);
  final code = status.code;
  if (loc == null || code == null) return status.message;
  switch (code) {
    case 'inject_failed':
      return loc.engineInjectFailed;
    case 'inject_partial':
      return loc.engineInjectPartial;
    default:
      return status.message;
  }
}
