import '../../config/notification_config.dart' hide NotificationPriority;
import 'notification_models.dart';

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
    Map<String, dynamic>? data,
    List<NotificationAction>? actions,
    String? channelId,
    NotificationPriority priority = NotificationPriority.normal,
    bool showProgress = false,
    int? progress,
    int? maxProgress,
    String? group,
    String? image,
    bool ongoing = false,
  });

  /// Request notification permission
  Future<bool> requestPermission();

  /// Cancel a specific notification
  Future<void> cancelNotification(String id);

  /// Cancel all notifications
  Future<void> cancelAllNotifications();

  /// Update an existing notification
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  });

  /// Get active notifications
  List<NotificationInfo> getActiveNotifications();

  /// Hide notification (alias for cancel)
  Future<void> hideNotification(String id) => cancelNotification(id);

  /// Dispose the manager
  Future<void> dispose();
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
    Map<String, dynamic>? data,
    List<NotificationAction>? actions,
    String? channelId,
    NotificationPriority priority = NotificationPriority.normal,
    bool showProgress = false,
    int? progress,
    int? maxProgress,
    String? group,
    String? image,
    bool ongoing = false,
  }) async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> cancelNotification(String id) async {}

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  }) async {}

  @override
  List<NotificationInfo> getActiveNotifications() => [];

  @override
  Future<void> hideNotification(String id) async {}

  @override
  Future<void> dispose() async {}
}
