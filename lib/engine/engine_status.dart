/// 引擎状态事件。
///
/// 此前 statusStream 是裸 `Stream<String>`，UI 只能靠字符串匹配判断状态：
/// ```dart
/// if (msg.startsWith("Error")) ...
/// else if (msg.contains("就绪") || msg.contains("Ready")) ...
/// ```
/// 两个问题：① 改一句文案就可能让 `_ready` 判断失效；
/// ② 控制流依赖中文字面量，文案一旦本地化就直接崩。
///
/// 现在 UI 只看 [kind]，[message] 纯粹用于展示。
enum EngineStatusKind {
  /// 清空状态栏
  idle,

  /// 过程提示：连接中、加载中、处理中
  info,

  /// 就绪，功能完全可用
  ready,

  /// 可用但有降级（例如监听已启动却缺「辅助功能」，注入不可用）
  warning,

  /// 不可用
  error,
}

class EngineStatus {
  final EngineStatusKind kind;

  /// 展示文案。目前由引擎直接给出；后续本地化时只需换这里的生成方式，
  /// UI 的分支逻辑不受影响 —— 这正是引入 kind 的目的。
  final String message;

  /// 稳定的错误标识码，供 UI 去 i18n 表里取文案；为 null 时回退到 [message]。
  ///
  /// 引擎层不能 import `AppLocalizations`（三层架构铁律：Engine 不依赖 UI），
  /// 所以这里**只给码、不给文案**。新增用户可见错误时给码，
  /// 别再往 [message] 里塞硬编码中文 —— 那会在英文环境下直接漏出去。
  final String? code;

  const EngineStatus(this.kind, this.message, {this.code});

  const EngineStatus.idle()
      : kind = EngineStatusKind.idle,
        message = '',
        code = null;
  const EngineStatus.info(this.message)
      : kind = EngineStatusKind.info,
        code = null;
  const EngineStatus.ready(this.message)
      : kind = EngineStatusKind.ready,
        code = null;
  const EngineStatus.warning(this.message)
      : kind = EngineStatusKind.warning,
        code = null;
  const EngineStatus.error(this.message, {this.code})
      : kind = EngineStatusKind.error;

  bool get isReady => kind == EngineStatusKind.ready || kind == EngineStatusKind.warning;
  bool get isProblem => kind == EngineStatusKind.error || kind == EngineStatusKind.warning;

  @override
  String toString() => '[$kind] $message';
}
