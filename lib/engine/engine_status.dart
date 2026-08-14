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

  const EngineStatus(this.kind, this.message);

  const EngineStatus.idle() : kind = EngineStatusKind.idle, message = '';
  const EngineStatus.info(this.message) : kind = EngineStatusKind.info;
  const EngineStatus.ready(this.message) : kind = EngineStatusKind.ready;
  const EngineStatus.warning(this.message) : kind = EngineStatusKind.warning;
  const EngineStatus.error(this.message) : kind = EngineStatusKind.error;

  bool get isReady => kind == EngineStatusKind.ready || kind == EngineStatusKind.warning;
  bool get isProblem => kind == EngineStatusKind.error || kind == EngineStatusKind.warning;

  @override
  String toString() => '[$kind] $message';
}
