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

  /// Whether to request permission on initialization
  final bool requestPermissionOnInit;

  /// Default notification icon
  final String? defaultIcon;

  NotificationConfig({
    this.channelId,
    this.channelName,
    this.channelDescription,
    this.icon,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.normal,
    this.requestPermissionOnInit = true,
    this.defaultIcon,
  });

  /// Default configuration
  static NotificationConfig defaultConfig() {
    return NotificationConfig(
      channelId: 'flutter_mcp_default',
      channelName: 'MCP Notifications',
      channelDescription: 'Notifications from Flutter MCP',
      enableSound: true,
      enableVibration: true,
      priority: NotificationPriority.normal,
      requestPermissionOnInit: true,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'channelName': channelName,
        'channelDescription': channelDescription,
        'icon': icon,
        'enableSound': enableSound,
        'enableVibration': enableVibration,
        'priority': priority.name,
        'requestPermissionOnInit': requestPermissionOnInit,
        'defaultIcon': defaultIcon,
      };

  /// Convert to Map (for platform channel)
  Map<String, dynamic> toMap() => toJson();
}

/// Notification priority
enum NotificationPriority {
  min,
  low,
  normal,
  high,
  max,
}
