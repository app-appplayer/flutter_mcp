import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/config_loader.dart';
import 'package:flutter_mcp/src/config/typed_config.dart' as typed;

void main() {
  group('Configuration Integration Test', () {
    test('should parse basic configuration with typed config', () async {
      final jsonConfig = '''
      {
        "appName": "Test App",
        "appVersion": "1.0.0",
        "useBackgroundService": true,
        "useNotification": true,
        "useTray": false,
        "secure": true,
        "lifecycleManaged": true,
        "autoStart": false,
        "loggingLevel": "info",
        "enablePerformanceMonitoring": true,
        "highMemoryThresholdMB": 300,
        "llmRequestTimeoutMs": 5000
      }
      ''';

      final config = ConfigLoader.loadFromString(jsonConfig);

      expect(config.appName, equals('Test App'));
      expect(config.appVersion, equals('1.0.0'));
      expect(config.useBackgroundService, isTrue);
      expect(config.useNotification, isTrue);
      expect(config.useTray, isFalse);
      expect(config.secure, isTrue);
      expect(config.lifecycleManaged, isTrue);
      expect(config.autoStart, isFalse);
      expect(config.enablePerformanceMonitoring, isTrue);
      expect(config.highMemoryThresholdMB, equals(300));
      expect(config.llmRequestTimeoutMs, equals(5000));
    });

    test('should create TypedAppConfig from map', () {
      final map = {
        'appName': 'Test App',
        'appVersion': '2.0.0',
        'highMemoryThresholdMB': 512,
        'loggingLevel': 'debug',
        'enablePerformanceMonitoring': true,
        'llmRequestTimeoutMs': 10000,
      };

      final typedConfig = typed.TypedAppConfig.fromMap(map);

      expect(typedConfig.appInfo.name, equals('Test App'));
      expect(typedConfig.appInfo.version, equals('2.0.0'));
      expect(typedConfig.memory.highThresholdMB, equals(512));
      expect(typedConfig.logging.level, equals(typed.LogLevel.fine));
      expect(typedConfig.performance.monitoring.enabled, isTrue);
      expect(typedConfig.network.timeouts['request']?.inMilliseconds,
          equals(10000));
    });

    test('should handle feature flags correctly', () {
      final map = {
        'useBackgroundService': true,
        'useNotification': false,
        'useTray': true,
        'plugins': {
          'autoLoadPlugins': true,
        }
      };

      final features = typed.FeatureFlags.fromMap(map);

      expect(features.useBackgroundService, isTrue);
      expect(features.useNotification, isFalse);
      expect(features.useTray, isTrue);
      expect(features.plugins.autoLoad, isTrue);
    });
  });
}
