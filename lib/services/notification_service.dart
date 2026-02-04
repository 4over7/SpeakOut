import 'dart:async';

enum NotificationType {
  info,
  success,
  error,
  audioDeviceSwitch, // New: for audio device auto-switch notifications
}

class AppNotification {
  final String message;
  final NotificationType type;
  final Duration duration;
  final String? actionLabel;
  final void Function()? onAction;

  AppNotification({
    required this.message, 
    required this.type,
    this.duration = const Duration(seconds: 3),
    this.actionLabel,
    this.onAction,
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _ctrl = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get stream => _ctrl.stream;

  void notify(String message, {NotificationType type = NotificationType.info}) {
    _ctrl.add(AppNotification(message: message, type: type));
  }
  
  void notifyError(String message) {
    _ctrl.add(AppNotification(message: message, type: NotificationType.error, duration: const Duration(seconds: 5)));
  }
  
  void notifySuccess(String message) {
    _ctrl.add(AppNotification(message: message, type: NotificationType.success));
  }
  
  /// Notify with an action button (e.g., "Undo" for audio device switch)
  void notifyWithAction({
    required String message,
    required String actionLabel,
    required void Function() onAction,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 5),
  }) {
    _ctrl.add(AppNotification(
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    ));
  }
}
