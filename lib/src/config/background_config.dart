/// Background service configuration
class BackgroundConfig {
  /// Notification channel ID (Android)
  final String? notificationChannelId;

  /// Notification channel name (Android)
  final String? notificationChannelName;

  /// Notification channel description (Android)
  final String? notificationDescription;

  /// Notification channel description (Android)
  final String? notificationChannelDescription;

  /// Notification icon (Android)
  final String? notificationIcon;

  /// Notification title
  final String? notificationTitle;

  /// Enable foreground service (Android)
  final bool enableForegroundService;

  /// Wake lock (Android)
  final bool wakeLock;

  /// WiFi lock (Android)
  final bool wifiLock;

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
    this.notificationChannelDescription,
    this.notificationIcon,
    this.notificationTitle,
    this.enableForegroundService = false,
    this.wakeLock = false,
    this.wifiLock = false,
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
      notificationChannelDescription: 'MCP Background Service Channel',
      notificationTitle: 'MCP Service',
      enableForegroundService: false,
      wakeLock: false,
      wifiLock: false,
      autoStartOnBoot: false,
      intervalMs: 5000,
      keepAlive: true,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'notificationChannelId': notificationChannelId,
      'notificationChannelName': notificationChannelName,
      'notificationDescription': notificationDescription,
      'notificationChannelDescription': notificationChannelDescription,
      'notificationIcon': notificationIcon,
      'notificationTitle': notificationTitle,
      'enableForegroundService': enableForegroundService,
      'wakeLock': wakeLock,
      'wifiLock': wifiLock,
      'autoStartOnBoot': autoStartOnBoot,
      'intervalMs': intervalMs,
      'keepAlive': keepAlive,
    };
  }

  /// Convert to map (alias for toJson)
  Map<String, dynamic> toMap() => toJson();
}
