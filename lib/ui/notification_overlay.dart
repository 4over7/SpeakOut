import 'dart:async';

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../services/notification_service.dart';
import 'theme.dart';

/// 全局通知横幅。
///
/// **必须挂在 MacosApp.builder 上，不能放进某个页面里。**
/// 原先它长在 _HomePageState 的 Stack 里，而聊天页与设置页是压在 Home 之上的
/// 不透明 MaterialPageRoute —— 订阅照收，横幅却被完全遮住。
/// 结果是「导出配置」「复制消息」这些**恰恰发生在那些页面上**的操作，
/// 提示一条也看不见（等于把抛异常换成了静默）。
///
/// 消费端带一个短队列：DiaryService 写盘失败会先发一条红色 error，
/// 调用方紧接着再发一条 info，同一事件循环里直接替换的话，用户根本看不到错误。
/// 现在未过期的高优先级通知不会被低优先级的挤掉，后者排队等待。
class NotificationOverlay extends StatefulWidget {
  final Widget child;
  const NotificationOverlay({super.key, required this.child});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  StreamSubscription<AppNotification>? _sub;
  Timer? _timer;
  AppNotification? _current;
  final List<AppNotification> _queue = [];

  /// 队列上限。5 秒错误横幅期间可能连续来一串提示，无上限的话会积压成
  /// 几十秒的连播，用户看到的全是过时信息。超出就丢最旧的低优先级那条。
  static const int _maxQueue = 3;

  /// 数值越大越重要。低优先级不得顶掉尚未过期的高优先级。
  static int _rank(NotificationType t) => switch (t) {
        NotificationType.error => 3,
        NotificationType.audioDeviceSwitch => 2,
        NotificationType.success => 1,
        NotificationType.info => 0,
      };

  @override
  void initState() {
    super.initState();
    _sub = NotificationService().stream.listen(_onNotification);
  }

  void _onNotification(AppNotification n) {
    if (!mounted) return;
    final cur = _current;
    if (cur != null && _rank(n.type) < _rank(cur.type)) {
      _queue.add(n); // 别把还在展示的错误顶掉
      if (_queue.length > _maxQueue) {
        // 丢最旧且最不重要的那条，保住时效性
        var worst = 0;
        for (var i = 1; i < _queue.length; i++) {
          if (_rank(_queue[i].type) < _rank(_queue[worst].type)) worst = i;
        }
        _queue.removeAt(worst);
      }
      return;
    }
    _show(n);
  }

  void _show(AppNotification n) {
    setState(() => _current = n);
    _timer?.cancel();
    _timer = Timer(n.duration, () {
      if (!mounted) return;
      setState(() => _current = null);
      _showNext();
    });
  }

  /// 出队按优先级，不是 FIFO —— 否则 error 展示期间先入队的 info 会排在
  /// 后入队但更紧急的 audioDeviceSwitch 前面。同优先级内保持先进先出。
  void _showNext() {
    if (_queue.isEmpty) return;
    var best = 0;
    for (var i = 1; i < _queue.length; i++) {
      if (_rank(_queue[i].type) > _rank(_queue[best].type)) best = i;
    }
    _show(_queue.removeAt(best));
  }

  void _dismiss() {
    _timer?.cancel();
    setState(() => _current = null);
    _showNext();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Color _bg(NotificationType t) => switch (t) {
        NotificationType.error => AppTheme.errorColor,
        NotificationType.success => MacosColors.systemGreenColor,
        NotificationType.audioDeviceSwitch => MacosColors.systemOrangeColor,
        NotificationType.info => MacosColors.systemBlueColor,
      };

  @override
  Widget build(BuildContext context) {
    final n = _current;
    return Stack(
      children: [
        widget.child,
        if (n != null)
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _bg(n.type),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          n.message,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (n.actionLabel != null && n.onAction != null) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            n.onAction!();
                            _dismiss();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              n.actionLabel!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
