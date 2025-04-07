import '../../config/notification_config.dart';

/// Notification Manager Interface
abstract class NotificationManager {
  /// Initialize notification manager
  Future<void> initialize(NotificationConfig? config);

  /// Show notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  });

  /// Hide notification
  Future<void> hideNotification(String id);
}

/// No-operation notification manager (for unsupported platforms)
class NoOpNotificationManager implements NotificationManager {
  @override
  Future<void> initialize(NotificationConfig? config) async {}

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {}

  @override
  Future<void> hideNotification(String id) async {}
}
