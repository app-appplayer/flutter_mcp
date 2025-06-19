import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/typed_config.dart';
import 'package:flutter_mcp/src/config/app_config.dart';

void main() {
  group('Typed Configuration Tests', () {
    test('should create MemoryConfig from map', () {
      print('=== MemoryConfig FromMap Test ===');

      final map = {
        'monitoringIntervalSeconds': 60,
        'maxReadings': 200,
        'initialSimulationMB': 100,
        'gcProbability': 0.2,
        'gcHintArraySize': 5000,
        'highMemoryThresholdMB': 1000,
        'enableMonitoring': false,
        'enableCaching': false,
        'maxCacheSize': 500,
      };

      final config = MemoryConfig.fromMap(map);

      expect(config.monitoringInterval, equals(Duration(seconds: 60)));
      expect(config.maxReadings, equals(200));
      expect(config.initialSimulationMB, equals(100));
      expect(config.gcProbability, equals(0.2));
      expect(config.gcHintArraySize, equals(5000));
      expect(config.highThresholdMB, equals(1000));
      expect(config.enableMonitoring, equals(false));
      expect(config.enableCaching, equals(false));
      expect(config.maxCacheSize, equals(500));

      print('MemoryConfig creation and parsing successful');
    });

    test('should create LoggingConfig with enum values', () {
      print('=== LoggingConfig Enum Test ===');

      final map = {
        'level': 'warning',
        'enableConsole': false,
        'enableFile': true,
        'logFilePath': '/var/log/mcp.log',
        'maxLogFileSize': 20971520, // 20MB
        'maxLogFiles': 10,
        'enableRemoteLogging': true,
        'remoteLogEndpoint': 'https://logs.example.com',
        'excludeLoggers': ['debug_logger', 'test_logger'],
      };

      final config = LoggingConfig.fromMap(map);

      expect(config.level, equals(LogLevel.warning));
      expect(config.enableConsole, equals(false));
      expect(config.enableFile, equals(true));
      expect(config.logFilePath, equals('/var/log/mcp.log'));
      expect(config.maxLogFileSize, equals(20971520));
      expect(config.maxLogFiles, equals(10));
      expect(config.enableRemoteLogging, equals(true));
      expect(config.remoteLogEndpoint, equals('https://logs.example.com'));
      expect(config.excludeLoggers, equals(['debug_logger', 'test_logger']));

      print('LoggingConfig enum and collection parsing successful');
    });

    test('should handle complex nested TrayConfig', () {
      print('=== Nested TrayConfig Test ===');

      final map = {
        'enabled': true,
        'iconPath': '/app/icons/tray.png',
        'tooltip': 'MCP Application',
        'showOnStartup': true,
        'minimizeToTray': true,
        'menuItems': [
          {
            'id': 'show',
            'label': 'Show Window',
            'enabled': true,
            'action': 'show_window',
            'subItems': [],
          },
          {
            'id': 'settings',
            'label': 'Settings',
            'enabled': true,
            'action': 'open_settings',
            'subItems': [
              {
                'id': 'general',
                'label': 'General',
                'enabled': true,
                'action': 'settings_general',
                'subItems': [],
              },
            ],
          },
          {
            'id': 'quit',
            'label': 'Quit',
            'enabled': true,
            'action': 'quit_app',
            'subItems': [],
          },
        ],
      };

      final config = TrayPlatformConfig.fromMap(map);

      expect(config.enabled, equals(true));
      expect(config.iconPath, equals('/app/icons/tray.png'));
      expect(config.tooltip, equals('MCP Application'));
      expect(config.showOnStartup, equals(true));
      expect(config.minimizeToTray, equals(true));

      expect(config.menuItems.length, equals(3));
      expect(config.menuItems[0].id, equals('show'));
      expect(config.menuItems[0].label, equals('Show Window'));
      expect(config.menuItems[0].action, equals('show_window'));

      // Test nested menu items
      expect(config.menuItems[1].subItems.length, equals(1));
      expect(config.menuItems[1].subItems[0].id, equals('general'));
      expect(config.menuItems[1].subItems[0].label, equals('General'));

      print('Nested TrayConfig parsing successful');
    });

    test('should create TypedAppConfig from complete map', () {
      print('=== Complete TypedAppConfig Test ===');

      final completeMap = {
        'memory': {
          'monitoringIntervalSeconds': 45,
          'maxReadings': 150,
          'enableMonitoring': true,
        },
        'logging': {
          'level': 'info',
          'enableConsole': true,
          'enableFile': false,
        },
        'performance': {
          'enableMonitoring': true,
          'sampleIntervalSeconds': 10,
          'maxSamples': 500,
        },
        'security': {
          'enableHttps': true,
          'validateCertificates': true,
          'tokenExpirationHours': 12,
        },
        'platform': {
          'notification': {
            'enabled': true,
            'enableSound': false,
            'priority': 'medium',
          },
          'background': {
            'enabled': true,
            'intervalMinutes': 30,
            'maxConcurrentTasks': 5,
          },
          'tray': {
            'enabled': false,
          },
          'storage': {
            'enableSecureStorage': true,
            'maxCacheSize': 52428800, // 50MB
          },
        },
      };

      final config = TypedAppConfig.fromMap(completeMap);

      // Test memory config
      expect(config.memory.monitoringInterval, equals(Duration(seconds: 45)));
      expect(config.memory.maxReadings, equals(150));
      expect(config.memory.enableMonitoring, equals(true));

      // Test logging config
      expect(config.logging.level, equals(LogLevel.info));
      expect(config.logging.enableConsole, equals(true));
      expect(config.logging.enableFile, equals(false));

      // Test performance config
      expect(config.performance.monitoring.enabled, equals(true));
      expect(config.performance.sampleInterval, equals(Duration(seconds: 10)));
      expect(config.performance.maxSamples, equals(500));

      // Test security config
      expect(config.security.enableHttps, equals(true));
      expect(config.security.validateCertificates, equals(true));
      expect(config.security.tokenExpiration, equals(Duration(hours: 12)));

      // Test platform configs
      expect(config.platform.notification.enabled, equals(true));
      expect(config.platform.notification.enableSound, equals(false));
      expect(config.platform.notification.priority,
          equals(NotificationPriority.medium));

      expect(config.platform.background.enabled, equals(true));
      expect(
          config.platform.background.interval, equals(Duration(minutes: 30)));
      expect(config.platform.background.maxConcurrentTasks, equals(5));

      expect(config.platform.tray.enabled, equals(false));

      expect(config.platform.storage.enableSecureStorage, equals(true));
      expect(config.platform.storage.maxCacheSize, equals(52428800));

      print('Complete TypedAppConfig creation and validation successful');
    });

    test('should handle round-trip serialization', () {
      print('=== Round-trip Serialization Test ===');

      final originalConfig = TypedAppConfig(
        appInfo: AppInfo(name: 'Test App', version: '1.0.0'),
        features: FeatureFlags(),
        network: NetworkConfig(),
        memory: MemoryConfig(
          monitoringInterval: Duration(seconds: 30),
          maxReadings: 100,
          enableMonitoring: true,
        ),
        logging: LoggingConfig(
          level: LogLevel.fine,
          enableConsole: true,
          excludeLoggers: ['test'],
        ),
        performance: PerformanceConfig(
          monitoring: MonitoringConfig(enabled: false),
          cpuThreshold: 90.0,
          enabledMetrics: ['memory', 'network'],
        ),
        security: SecurityConfig(
          enableHttps: false,
          allowedOrigins: ['localhost', '127.0.0.1'],
        ),
        platform: PlatformConfig(
          notification: NotificationPlatformConfig(
            enabled: false,
          ),
          background: BackgroundPlatformConfig(
            enabled: true,
          ),
          tray: TrayPlatformConfig(
            enabled: false,
          ),
          storage: StoragePlatformConfig(
            enableSecureStorage: true,
          ),
        ),
      );

      // Convert to map and back
      final map = originalConfig.toMap();
      final restoredConfig = TypedAppConfig.fromMap(map);

      // Verify memory config
      expect(restoredConfig.memory.monitoringInterval,
          equals(originalConfig.memory.monitoringInterval));
      expect(restoredConfig.memory.maxReadings,
          equals(originalConfig.memory.maxReadings));
      expect(restoredConfig.memory.enableMonitoring,
          equals(originalConfig.memory.enableMonitoring));

      // Verify logging config
      expect(
          restoredConfig.logging.level, equals(originalConfig.logging.level));
      expect(restoredConfig.logging.excludeLoggers,
          equals(originalConfig.logging.excludeLoggers));

      // Verify performance config
      expect(restoredConfig.performance.monitoring.enabled,
          equals(originalConfig.performance.monitoring.enabled));
      expect(restoredConfig.performance.cpuThreshold,
          equals(originalConfig.performance.cpuThreshold));
      expect(restoredConfig.performance.enabledMetrics,
          equals(originalConfig.performance.enabledMetrics));

      // Verify security config
      expect(restoredConfig.security.enableHttps,
          equals(originalConfig.security.enableHttps));
      expect(restoredConfig.security.allowedOrigins,
          equals(originalConfig.security.allowedOrigins));

      print('Round-trip serialization successful');
    });

    test('should integrate with AppConfig', () async {
      print('=== AppConfig Integration Test ===');

      // Test with default configuration from AppConfig
      final appConfig = AppConfig.instance;

      // Test typed config retrieval with defaults
      final memoryConfig = appConfig.getMemoryConfig();
      expect(memoryConfig.monitoringInterval.inSeconds, greaterThan(0));
      expect(memoryConfig.maxReadings, greaterThan(0));
      expect(memoryConfig.initialSimulationMB, greaterThan(0));

      final loggingConfig = appConfig.getLoggingConfig();
      expect(loggingConfig.level, isNotNull);
      expect(loggingConfig.enableConsole, isA<bool>());
      expect(loggingConfig.enableFile, isA<bool>());

      // Test complete typed config
      final typedConfig = appConfig.getTypedConfig();
      expect(typedConfig.memory, isNotNull);
      expect(typedConfig.logging, isNotNull);
      expect(typedConfig.performance, isNotNull);
      expect(typedConfig.security, isNotNull);
      expect(typedConfig.platform, isNotNull);

      print('AppConfig integration test successful');
    });

    test('should handle default values correctly', () {
      print('=== Default Values Test ===');

      // Create configs with empty maps (should use defaults)
      final memoryConfig = MemoryConfig.fromMap({});
      final loggingConfig = LoggingConfig.fromMap({});
      final performanceConfig = PerformanceConfig.fromMap({});

      // Verify defaults
      expect(memoryConfig.monitoringInterval, equals(Duration(seconds: 30)));
      expect(memoryConfig.maxReadings, equals(100));
      expect(memoryConfig.enableMonitoring, equals(true));
      expect(memoryConfig.gcProbability, equals(0.1));

      expect(loggingConfig.level, equals(LogLevel.info));
      expect(loggingConfig.enableConsole, equals(true));
      expect(loggingConfig.enableFile, equals(false));
      expect(loggingConfig.maxLogFiles, equals(5));

      expect(performanceConfig.monitoring.enabled, equals(true));
      expect(performanceConfig.sampleInterval, equals(Duration(seconds: 5)));
      expect(performanceConfig.cpuThreshold, equals(80.0));
      expect(performanceConfig.enabledMetrics,
          equals(['memory', 'cpu', 'network']));

      print('Default values test successful');
    });
  });
}
