/// Background service configuration
class BackgroundConfig {
  /// Notification channel ID (Android)
  final String? notificationChannelId;

  /// Notification channel name (Android)
  final String? notificationChannelName;

  /// Notification channel description (Android)
  final String? notificationDescription;

  /// Notification icon (Android)
  final String? notificationIcon;

  /// Auto start on boot
  final bool autoStartOnBoot;

  /// Background task interval (milliseconds)
  final int intervalMs;

  /// Keep connection alive
  final bool keepAlive;

  BackgroundConfig({
    this.notificationChannelId,
    this.notificationChannelName,
    this.notificationDescription,
    this.notificationIcon,
    this.autoStartOnBoot = false,
    this.intervalMs = 5000,
    this.keepAlive = true,
  });

  /// Create default configuration
  factory BackgroundConfig.defaultConfig() {
    return BackgroundConfig(
      notificationChannelId: 'flutter_mcp_channel',
      notificationChannelName: 'MCP Service',
      notificationDescription: 'MCP Background Service',
      autoStartOnBoot: false,
      intervalMs: 5000,
      keepAlive: true,
    );
  }
}
