import 'dart:async';

enum NotificationType {
  info,
  success,
  error,
}

class AppNotification {
  final String message;
  final NotificationType type;
  final Duration duration;

  AppNotification({
    required this.message, 
    required this.type,
    this.duration = const Duration(seconds: 3),
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
}
