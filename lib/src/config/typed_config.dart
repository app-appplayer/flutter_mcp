/// Type-safe configuration classes to replace Map<String, dynamic> usage

/// App information configuration
class AppInfo {
  final String name;
  final String version;
  final String? description;
  final String? author;
  final String? homepage;
  
  AppInfo({
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.homepage,
  });
  
  factory AppInfo.fromMap(Map<String, dynamic> map) {
    return AppInfo(
      name: map['appName'] ?? map['name'] ?? 'MCP App',
      version: map['appVersion'] ?? map['version'] ?? '1.0.0',
      description: map['description'],
      author: map['author'],
      homepage: map['homepage'],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'version': version,
      if (description != null) 'description': description,
      if (author != null) 'author': author,
      if (homepage != null) 'homepage': homepage,
    };
  }
}

/// Feature flags configuration
class FeatureFlags {
  final bool useBackgroundService;
  final bool useNotification;
  final bool useTray;
  final bool secure;
  final bool lifecycleManaged;
  final bool autoStart;
  final PluginFeatures plugins;
  
  FeatureFlags({
    this.useBackgroundService = false,
    this.useNotification = false,
    this.useTray = false,
    this.secure = true,
    this.lifecycleManaged = true,
    this.autoStart = true,
    PluginFeatures? plugins,
  }) : plugins = plugins ?? PluginFeatures();
  
  factory FeatureFlags.fromMap(Map<String, dynamic> map) {
    return FeatureFlags(
      useBackgroundService: map['useBackgroundService'] ?? false,
      useNotification: map['useNotification'] ?? false,
      useTray: map['useTray'] ?? false,
      secure: map['secure'] ?? true,
      lifecycleManaged: map['lifecycleManaged'] ?? true,
      autoStart: map['autoStart'] ?? true,
      plugins: PluginFeatures.fromMap(map['plugins'] ?? {}),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'useBackgroundService': useBackgroundService,
      'useNotification': useNotification,
      'useTray': useTray,
      'secure': secure,
      'lifecycleManaged': lifecycleManaged,
      'autoStart': autoStart,
      'plugins': plugins.toMap(),
    };
  }
}

/// Plugin features configuration
class PluginFeatures {
  final bool autoLoad;
  final bool enableHotReload;
  final bool sandboxed;
  
  PluginFeatures({
    this.autoLoad = false,
    this.enableHotReload = false,
    this.sandboxed = true,
  });
  
  factory PluginFeatures.fromMap(Map<String, dynamic> map) {
    return PluginFeatures(
      autoLoad: map['autoLoadPlugins'] ?? map['autoLoad'] ?? false,
      enableHotReload: map['enableHotReload'] ?? false,
      sandboxed: map['sandboxed'] ?? true,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'autoLoad': autoLoad,
      'enableHotReload': enableHotReload,
      'sandboxed': sandboxed,
    };
  }
}

/// Network configuration
class NetworkConfig {
  final Duration timeout;
  final RetryConfig retryConfig;
  final Map<String, Duration> timeouts;
  
  NetworkConfig({
    Duration? timeout,
    RetryConfig? retryConfig,
    Map<String, Duration>? timeouts,
  }) : timeout = timeout ?? const Duration(seconds: 30),
       retryConfig = retryConfig ?? RetryConfig(),
       timeouts = timeouts ?? {
         'request': const Duration(seconds: 30),
         'connect': const Duration(seconds: 10),
       };
  
  factory NetworkConfig.fromMap(Map<String, dynamic> map) {
    final timeoutsMap = <String, Duration>{};
    if (map['timeouts'] is Map) {
      (map['timeouts'] as Map).forEach((key, value) {
        if (value is int) {
          timeoutsMap[key.toString()] = Duration(milliseconds: value);
        }
      });
    }
    
    // Handle llmRequestTimeoutMs for backward compatibility
    if (map['llmRequestTimeoutMs'] != null) {
      timeoutsMap['request'] = Duration(milliseconds: map['llmRequestTimeoutMs']);
    }
    
    return NetworkConfig(
      timeout: map['timeout'] != null 
          ? Duration(milliseconds: map['timeout']) 
          : null,
      retryConfig: RetryConfig.fromMap(map['retry'] ?? {}),
      timeouts: timeoutsMap.isNotEmpty ? timeoutsMap : null,
    );
  }
  
  Map<String, dynamic> toMap() {
    final timeoutsMap = <String, int>{};
    timeouts.forEach((key, duration) {
      timeoutsMap[key] = duration.inMilliseconds;
    });
    
    return {
      'timeout': timeout.inMilliseconds,
      'retry': retryConfig.toMap(),
      'timeouts': timeoutsMap,
    };
  }
}

/// Retry configuration
class RetryConfig {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  
  RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
  });
  
  factory RetryConfig.fromMap(Map<String, dynamic> map) {
    return RetryConfig(
      maxRetries: map['maxConnectionRetries'] ?? map['maxRetries'] ?? 3,
      initialDelay: Duration(
        milliseconds: map['initialDelayMs'] ?? 1000
      ),
      backoffMultiplier: (map['backoffMultiplier'] ?? 2.0).toDouble(),
      maxDelay: Duration(
        milliseconds: map['maxDelayMs'] ?? 30000
      ),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'maxRetries': maxRetries,
      'initialDelayMs': initialDelay.inMilliseconds,
      'backoffMultiplier': backoffMultiplier,
      'maxDelayMs': maxDelay.inMilliseconds,
    };
  }
}

/// Main typed configuration class
class TypedAppConfig {
  final AppInfo appInfo;
  final FeatureFlags features;
  final MemoryConfig memory;
  final LoggingConfig logging;
  final PerformanceConfig performance;
  final NetworkConfig network;
  final SecurityConfig security;
  final PlatformConfig platform;
  
  TypedAppConfig({
    required this.appInfo,
    required this.features,
    required this.memory,
    required this.logging,
    required this.performance,
    required this.network,
    required this.security,
    required this.platform,
  });
  
  factory TypedAppConfig.fromMap(Map<String, dynamic> map) {
    return TypedAppConfig(
      appInfo: AppInfo.fromMap(map),
      features: FeatureFlags.fromMap(map),
      memory: MemoryConfig.fromMap(map['memory'] ?? map),
      logging: LoggingConfig.fromMap(map['logging'] ?? map),
      performance: PerformanceConfig.fromMap(map['performance'] ?? map),
      network: NetworkConfig.fromMap(map['network'] ?? map),
      security: SecurityConfig.fromMap(map['security'] ?? {}),
      platform: PlatformConfig.fromMap(map['platform'] ?? {}),
    );
  }
  
  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};
    
    // Flatten app info and features at top level for backward compatibility
    result.addAll(appInfo.toMap());
    result.addAll(features.toMap());
    
    // Add nested configs
    result['memory'] = memory.toMap();
    result['logging'] = logging.toMap();
    result['performance'] = performance.toMap();
    result['network'] = network.toMap();
    result['security'] = security.toMap();
    result['platform'] = platform.toMap();
    
    return result;
  }
}

/// Memory management configuration
class MemoryConfig {
  final Duration monitoringInterval;
  final int maxReadings;
  final int initialSimulationMB;
  final double gcProbability;
  final int gcHintArraySize;
  final int highThresholdMB;
  final bool enableMonitoring;
  final bool enableCaching;
  final int maxCacheSize;
  
  MemoryConfig({
    this.monitoringInterval = const Duration(seconds: 30),
    this.maxReadings = 100,
    this.initialSimulationMB = 50,
    this.gcProbability = 0.1,
    this.gcHintArraySize = 10000,
    this.highThresholdMB = 500,
    this.enableMonitoring = true,
    this.enableCaching = true,
    this.maxCacheSize = 1000,
  });
  
  factory MemoryConfig.fromMap(Map<String, dynamic> map) {
    return MemoryConfig(
      monitoringInterval: Duration(
        seconds: map['monitoringIntervalSeconds'] ?? 30
      ),
      maxReadings: map['maxReadings'] ?? 100,
      initialSimulationMB: map['initialSimulationMB'] ?? 50,
      gcProbability: (map['gcProbability'] ?? 0.1).toDouble(),
      gcHintArraySize: map['gcHintArraySize'] ?? 10000,
      highThresholdMB: map['highMemoryThresholdMB'] ?? map['highThresholdMB'] ?? 500,
      enableMonitoring: map['enableMonitoring'] ?? true,
      enableCaching: map['enableCaching'] ?? true,
      maxCacheSize: map['maxCacheSize'] ?? 1000,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'monitoringIntervalSeconds': monitoringInterval.inSeconds,
      'maxReadings': maxReadings,
      'initialSimulationMB': initialSimulationMB,
      'gcProbability': gcProbability,
      'gcHintArraySize': gcHintArraySize,
      'highThresholdMB': highThresholdMB,
      'enableMonitoring': enableMonitoring,
      'enableCaching': enableCaching,
      'maxCacheSize': maxCacheSize,
    };
  }
}

/// Logging configuration
class LoggingConfig {
  final LogLevel level;
  final bool enabled;
  final bool enableConsole;
  final bool enableFile;
  final String? logFilePath;
  final int maxLogFileSize;
  final int maxLogFiles;
  final bool enableRemoteLogging;
  final String? remoteLogEndpoint;
  final List<String> excludeLoggers;
  
  LoggingConfig({
    this.level = LogLevel.info,
    this.enabled = true,
    this.enableConsole = true,
    this.enableFile = false,
    this.logFilePath,
    this.maxLogFileSize = 10 * 1024 * 1024, // 10MB
    this.maxLogFiles = 5,
    this.enableRemoteLogging = false,
    this.remoteLogEndpoint,
    this.excludeLoggers = const [],
  });
  
  factory LoggingConfig.fromMap(Map<String, dynamic> map) {
    // Handle loggingLevel string from config
    LogLevel logLevel = LogLevel.info;
    if (map['loggingLevel'] is String) {
      final levelStr = (map['loggingLevel'] as String).toLowerCase();
      switch (levelStr) {
        case 'trace':
        case 'finest':
          logLevel = LogLevel.finest;
          break;
        case 'debug':
        case 'fine':
          logLevel = LogLevel.fine;
          break;
        case 'info':
          logLevel = LogLevel.info;
          break;
        case 'warning':
          logLevel = LogLevel.warning;
          break;
        case 'error':
        case 'severe':
          logLevel = LogLevel.severe;
          break;
      }
    } else if (map['level'] != null) {
      try {
        logLevel = LogLevel.values.byName(map['level']);
      } catch (_) {
        // Default to info if parsing fails
      }
    }
    
    return LoggingConfig(
      level: logLevel,
      enabled: map['loggingLevel'] != null || (map['enabled'] ?? true),
      enableConsole: map['enableConsole'] ?? true,
      enableFile: map['enableFile'] ?? false,
      logFilePath: map['logFilePath'],
      maxLogFileSize: map['maxLogFileSize'] ?? 10 * 1024 * 1024,
      maxLogFiles: map['maxLogFiles'] ?? 5,
      enableRemoteLogging: map['enableRemoteLogging'] ?? false,
      remoteLogEndpoint: map['remoteLogEndpoint'],
      excludeLoggers: List<String>.from(map['excludeLoggers'] ?? []),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'level': level.name,
      'enabled': enabled,
      'enableConsole': enableConsole,
      'enableFile': enableFile,
      'logFilePath': logFilePath,
      'maxLogFileSize': maxLogFileSize,
      'maxLogFiles': maxLogFiles,
      'enableRemoteLogging': enableRemoteLogging,
      'remoteLogEndpoint': remoteLogEndpoint,
      'excludeLoggers': excludeLoggers,
    };
  }
}

enum LogLevel { finest, fine, info, warning, severe }

/// Performance monitoring configuration
class PerformanceConfig {
  final MonitoringConfig monitoring;
  final Duration sampleInterval;
  final int maxSamples;
  final bool enableProfiling;
  final double cpuThreshold;
  final double memoryThreshold;
  final List<String> enabledMetrics;
  
  PerformanceConfig({
    MonitoringConfig? monitoring,
    this.sampleInterval = const Duration(seconds: 5),
    this.maxSamples = 1000,
    this.enableProfiling = false,
    this.cpuThreshold = 80.0,
    this.memoryThreshold = 80.0,
    this.enabledMetrics = const ['memory', 'cpu', 'network'],
  }) : monitoring = monitoring ?? MonitoringConfig();
  
  factory PerformanceConfig.fromMap(Map<String, dynamic> map) {
    return PerformanceConfig(
      monitoring: MonitoringConfig.fromMap(map),
      sampleInterval: Duration(
        seconds: map['sampleIntervalSeconds'] ?? 5
      ),
      maxSamples: map['maxSamples'] ?? 1000,
      enableProfiling: map['enableProfiling'] ?? false,
      cpuThreshold: (map['cpuThreshold'] ?? 80.0).toDouble(),
      memoryThreshold: (map['memoryThreshold'] ?? 80.0).toDouble(),
      enabledMetrics: List<String>.from(map['enabledMetrics'] ?? ['memory', 'cpu', 'network']),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      ...monitoring.toMap(),
      'sampleIntervalSeconds': sampleInterval.inSeconds,
      'maxSamples': maxSamples,
      'enableProfiling': enableProfiling,
      'cpuThreshold': cpuThreshold,
      'memoryThreshold': memoryThreshold,
      'enabledMetrics': enabledMetrics,
    };
  }
}

/// Monitoring configuration
class MonitoringConfig {
  final bool enabled;
  final bool enableMetricsExport;
  final String? metricsExportPath;
  final String? metricsEndpoint;
  
  MonitoringConfig({
    this.enabled = true,
    this.enableMetricsExport = false,
    this.metricsExportPath,
    this.metricsEndpoint,
  });
  
  factory MonitoringConfig.fromMap(Map<String, dynamic> map) {
    return MonitoringConfig(
      enabled: map['enablePerformanceMonitoring'] ?? map['enableMonitoring'] ?? true,
      enableMetricsExport: map['enableMetricsExport'] ?? false,
      metricsExportPath: map['metricsExportPath'],
      metricsEndpoint: map['metricsEndpoint'],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enableMonitoring': enabled,
      'enableMetricsExport': enableMetricsExport,
      if (metricsExportPath != null) 'metricsExportPath': metricsExportPath,
      if (metricsEndpoint != null) 'metricsEndpoint': metricsEndpoint,
    };
  }
}

/// Security configuration
class SecurityConfig {
  final bool enableHttps;
  final bool validateCertificates;
  final Duration tokenExpiration;
  final bool enableRateLimit;
  final int maxRequestsPerMinute;
  final List<String> allowedOrigins;
  final bool enableEncryption;
  final String? encryptionKey;
  final bool enableAuditLog;
  
  SecurityConfig({
    this.enableHttps = true,
    this.validateCertificates = true,
    this.tokenExpiration = const Duration(hours: 24),
    this.enableRateLimit = true,
    this.maxRequestsPerMinute = 100,
    this.allowedOrigins = const ['localhost'],
    this.enableEncryption = false,
    this.encryptionKey,
    this.enableAuditLog = true,
  });
  
  factory SecurityConfig.fromMap(Map<String, dynamic> map) {
    return SecurityConfig(
      enableHttps: map['enableHttps'] ?? true,
      validateCertificates: map['validateCertificates'] ?? true,
      tokenExpiration: Duration(
        hours: map['tokenExpirationHours'] ?? 24
      ),
      enableRateLimit: map['enableRateLimit'] ?? true,
      maxRequestsPerMinute: map['maxRequestsPerMinute'] ?? 100,
      allowedOrigins: List<String>.from(map['allowedOrigins'] ?? ['localhost']),
      enableEncryption: map['enableEncryption'] ?? false,
      encryptionKey: map['encryptionKey'],
      enableAuditLog: map['enableAuditLog'] ?? true,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enableHttps': enableHttps,
      'validateCertificates': validateCertificates,
      'tokenExpirationHours': tokenExpiration.inHours,
      'enableRateLimit': enableRateLimit,
      'maxRequestsPerMinute': maxRequestsPerMinute,
      'allowedOrigins': allowedOrigins,
      'enableEncryption': enableEncryption,
      'encryptionKey': encryptionKey,
      'enableAuditLog': enableAuditLog,
    };
  }
}

/// Platform-specific configuration
class PlatformConfig {
  final NotificationPlatformConfig notification;
  final BackgroundPlatformConfig background;
  final TrayPlatformConfig tray;
  final StoragePlatformConfig storage;
  
  PlatformConfig({
    required this.notification,
    required this.background,
    required this.tray,
    required this.storage,
  });
  
  factory PlatformConfig.fromMap(Map<String, dynamic> map) {
    return PlatformConfig(
      notification: NotificationPlatformConfig.fromMap(map['notification'] ?? {}),
      background: BackgroundPlatformConfig.fromMap(map['background'] ?? {}),
      tray: TrayPlatformConfig.fromMap(map['tray'] ?? {}),
      storage: StoragePlatformConfig.fromMap(map['storage'] ?? {}),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'notification': notification.toMap(),
      'background': background.toMap(),
      'tray': tray.toMap(),
      'storage': storage.toMap(),
    };
  }
}

/// Notification platform configuration
class NotificationPlatformConfig {
  final bool enabled;
  final String? channelId;
  final String? channelName;
  final bool enableSound;
  final bool enableVibration;
  final NotificationPriority priority;
  final String? icon;
  final Duration timeoutDuration;
  
  NotificationPlatformConfig({
    this.enabled = true,
    this.channelId,
    this.channelName,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.high,
    this.icon,
    this.timeoutDuration = const Duration(seconds: 30),
  });
  
  factory NotificationPlatformConfig.fromMap(Map<String, dynamic> map) {
    return NotificationPlatformConfig(
      enabled: map['enabled'] ?? true,
      channelId: map['channelId'],
      channelName: map['channelName'],
      enableSound: map['enableSound'] ?? true,
      enableVibration: map['enableVibration'] ?? true,
      priority: NotificationPriority.values.byName(map['priority'] ?? 'high'),
      icon: map['icon'],
      timeoutDuration: Duration(
        seconds: map['timeoutSeconds'] ?? 30
      ),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'channelId': channelId,
      'channelName': channelName,
      'enableSound': enableSound,
      'enableVibration': enableVibration,
      'priority': priority.name,
      'icon': icon,
      'timeoutSeconds': timeoutDuration.inSeconds,
    };
  }
}

enum NotificationPriority { low, medium, high, urgent }

/// Background service platform configuration
class BackgroundPlatformConfig {
  final bool enabled;
  final Duration interval;
  final int maxConcurrentTasks;
  final bool enableWakeLock;
  final List<String> allowedNetworks;
  final bool enableBatteryOptimization;
  
  BackgroundPlatformConfig({
    this.enabled = true,
    this.interval = const Duration(minutes: 15),
    this.maxConcurrentTasks = 3,
    this.enableWakeLock = false,
    this.allowedNetworks = const ['wifi', 'cellular'],
    this.enableBatteryOptimization = true,
  });
  
  factory BackgroundPlatformConfig.fromMap(Map<String, dynamic> map) {
    return BackgroundPlatformConfig(
      enabled: map['enabled'] ?? true,
      interval: Duration(
        minutes: map['intervalMinutes'] ?? 15
      ),
      maxConcurrentTasks: map['maxConcurrentTasks'] ?? 3,
      enableWakeLock: map['enableWakeLock'] ?? false,
      allowedNetworks: List<String>.from(map['allowedNetworks'] ?? ['wifi', 'cellular']),
      enableBatteryOptimization: map['enableBatteryOptimization'] ?? true,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'intervalMinutes': interval.inMinutes,
      'maxConcurrentTasks': maxConcurrentTasks,
      'enableWakeLock': enableWakeLock,
      'allowedNetworks': allowedNetworks,
      'enableBatteryOptimization': enableBatteryOptimization,
    };
  }
}

/// System tray platform configuration
class TrayPlatformConfig {
  final bool enabled;
  final String? iconPath;
  final String? tooltip;
  final bool showOnStartup;
  final bool minimizeToTray;
  final List<TrayMenuItem> menuItems;
  
  TrayPlatformConfig({
    this.enabled = false,
    this.iconPath,
    this.tooltip,
    this.showOnStartup = false,
    this.minimizeToTray = false,
    this.menuItems = const [],
  });
  
  factory TrayPlatformConfig.fromMap(Map<String, dynamic> map) {
    return TrayPlatformConfig(
      enabled: map['enabled'] ?? false,
      iconPath: map['iconPath'],
      tooltip: map['tooltip'],
      showOnStartup: map['showOnStartup'] ?? false,
      minimizeToTray: map['minimizeToTray'] ?? false,
      menuItems: (map['menuItems'] as List<dynamic>?)
          ?.map((item) => TrayMenuItem.fromMap(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'iconPath': iconPath,
      'tooltip': tooltip,
      'showOnStartup': showOnStartup,
      'minimizeToTray': minimizeToTray,
      'menuItems': menuItems.map((item) => item.toMap()).toList(),
    };
  }
}

/// Tray menu item configuration
class TrayMenuItem {
  final String id;
  final String label;
  final bool enabled;
  final String? action;
  final List<TrayMenuItem> subItems;
  
  TrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.action,
    this.subItems = const [],
  });
  
  factory TrayMenuItem.fromMap(Map<String, dynamic> map) {
    return TrayMenuItem(
      id: map['id'] as String,
      label: map['label'] as String,
      enabled: map['enabled'] ?? true,
      action: map['action'],
      subItems: (map['subItems'] as List<dynamic>?)
          ?.map((item) => TrayMenuItem.fromMap(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'enabled': enabled,
      'action': action,
      'subItems': subItems.map((item) => item.toMap()).toList(),
    };
  }
}

/// Storage platform configuration
class StoragePlatformConfig {
  final bool enableSecureStorage;
  final String? encryptionKey;
  final Duration cacheExpiration;
  final int maxCacheSize;
  final bool enablePersistence;
  final String? storagePath;
  
  StoragePlatformConfig({
    this.enableSecureStorage = true,
    this.encryptionKey,
    this.cacheExpiration = const Duration(hours: 24),
    this.maxCacheSize = 100 * 1024 * 1024, // 100MB
    this.enablePersistence = true,
    this.storagePath,
  });
  
  factory StoragePlatformConfig.fromMap(Map<String, dynamic> map) {
    return StoragePlatformConfig(
      enableSecureStorage: map['enableSecureStorage'] ?? true,
      encryptionKey: map['encryptionKey'],
      cacheExpiration: Duration(
        hours: map['cacheExpirationHours'] ?? 24
      ),
      maxCacheSize: map['maxCacheSize'] ?? 100 * 1024 * 1024,
      enablePersistence: map['enablePersistence'] ?? true,
      storagePath: map['storagePath'],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'enableSecureStorage': enableSecureStorage,
      'encryptionKey': encryptionKey,
      'cacheExpirationHours': cacheExpiration.inHours,
      'maxCacheSize': maxCacheSize,
      'enablePersistence': enablePersistence,
      'storagePath': storagePath,
    };
  }
}