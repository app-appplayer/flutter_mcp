import 'background_config.dart';
import 'background_job.dart';

/// Enhanced background service configuration
class EnhancedBackgroundConfig extends BackgroundConfig {
  /// Maximum retry attempts for failed tasks
  final int maxRetries;

  /// Scheduled jobs
  final List<Job>? schedule;

  /// Battery optimization settings
  final bool requestBatteryOptimization;

  /// Minimum battery level to run tasks (percentage)
  final int minBatteryLevel;

  /// Only run tasks when charging
  final bool requireCharging;

  /// Only run tasks on WiFi
  final bool requireWifi;

  /// Task execution timeout
  final Duration taskTimeout;

  /// Enable crash recovery
  final bool enableCrashRecovery;

  /// Enable task persistence
  final bool enableTaskPersistence;

  EnhancedBackgroundConfig({
    // Base config
    super.notificationChannelId,
    super.notificationChannelName,
    super.notificationDescription,
    super.notificationIcon,
    super.autoStartOnBoot = false,
    super.intervalMs = 5000,
    super.keepAlive = true,
    super.enableForegroundService = false,
    super.notificationTitle,
    super.notificationChannelDescription,
    super.wakeLock = false,
    super.wifiLock = false,

    // Enhanced config
    this.maxRetries = 3,
    this.schedule,
    this.requestBatteryOptimization = false,
    this.minBatteryLevel = 20,
    this.requireCharging = false,
    this.requireWifi = false,
    this.taskTimeout = const Duration(minutes: 5),
    this.enableCrashRecovery = true,
    this.enableTaskPersistence = true,
  });

  /// Create default enhanced configuration
  factory EnhancedBackgroundConfig.defaultConfig() {
    return EnhancedBackgroundConfig(
      notificationChannelId: 'flutter_mcp_enhanced',
      notificationChannelName: 'MCP Enhanced Service',
      notificationDescription: 'MCP Enhanced Background Service',
      notificationTitle: 'MCP Service Running',
      autoStartOnBoot: false,
      intervalMs: 5000,
      keepAlive: true,
      enableForegroundService: false,
      wakeLock: false,
      wifiLock: false,
      maxRetries: 3,
      requestBatteryOptimization: false,
      minBatteryLevel: 20,
      requireCharging: false,
      requireWifi: false,
      taskTimeout: const Duration(minutes: 5),
      enableCrashRecovery: true,
      enableTaskPersistence: true,
    );
  }

  /// Create from base config
  factory EnhancedBackgroundConfig.fromBase(BackgroundConfig base) {
    return EnhancedBackgroundConfig(
      notificationChannelId: base.notificationChannelId,
      notificationChannelName: base.notificationChannelName,
      notificationDescription: base.notificationDescription,
      notificationIcon: base.notificationIcon,
      autoStartOnBoot: base.autoStartOnBoot,
      intervalMs: base.intervalMs,
      keepAlive: base.keepAlive,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'enableForegroundService': enableForegroundService,
      'notificationTitle': notificationTitle,
      'notificationChannelDescription': notificationChannelDescription,
      'wakeLock': wakeLock,
      'wifiLock': wifiLock,
      'maxRetries': maxRetries,
      'schedule': schedule?.map((j) => j.toJson()).toList(),
      'requestBatteryOptimization': requestBatteryOptimization,
      'minBatteryLevel': minBatteryLevel,
      'requireCharging': requireCharging,
      'requireWifi': requireWifi,
      'taskTimeoutMs': taskTimeout.inMilliseconds,
      'enableCrashRecovery': enableCrashRecovery,
      'enableTaskPersistence': enableTaskPersistence,
    });
    return json;
  }

  /// Validate configuration
  bool validate() {
    if (minBatteryLevel < 0 || minBatteryLevel > 100) {
      return false;
    }

    if (enableForegroundService && notificationTitle == null) {
      return false;
    }

    if (schedule != null) {
      for (final job in schedule!) {
        if (!job.validate()) {
          return false;
        }
      }
    }

    return true;
  }
}
