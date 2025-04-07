/// Notification configuration
class NotificationConfig {
  /// Notification channel ID (Android)
  final String? channelId;

  /// Notification channel name (Android)
  final String? channelName;

  /// Notification channel description (Android)
  final String? channelDescription;

  /// Notification icon
  final String? icon;

  /// Whether to enable notification sound
  final bool enableSound;

  /// Whether to enable notification vibration
  final bool enableVibration;

  /// Notification priority
  final NotificationPriority priority;

  NotificationConfig({
    this.channelId,
    this.channelName,
    this.channelDescription,
    this.icon,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.normal,
  });
}

/// Notification priority
enum NotificationPriority {
  min,
  low,
  normal,
  high,
  max,
}
