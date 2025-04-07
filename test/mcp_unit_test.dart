import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/core/client_manager.dart';
import 'package:flutter_mcp/src/core/server_manager.dart';
import 'package:flutter_mcp/src/core/llm_manager.dart';
import 'package:flutter_mcp/src/platform/platform_services.dart';
import 'package:flutter_mcp/src/utils/resource_manager.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';

// Generate mocks
@GenerateMocks([
  PlatformServices,
  MCPClientManager,
  MCPServerManager,
  MCPLlmManager,
  ResourceManager,
])
void main() {
  // Set up logging for tests
  setUp(() {
    MCPLogger.setDefaultLevel(LogLevel.debug);
  });

  group('MCPConfig Tests', () {
    test('Create default config', () {
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      expect(config.appName, 'Test App');
      expect(config.appVersion, '1.0.0');
      expect(config.useBackgroundService, true);
      expect(config.useNotification, true);
      expect(config.useTray, true);
    });

    test('Create development config', () {
      final config = MCPConfig.development(
        appName: 'Dev App',
        appVersion: '0.1.0',
      );

      expect(config.appName, 'Dev App');
      expect(config.appVersion, '0.1.0');
      expect(config.loggingLevel, LogLevel.debug);
      expect(config.enablePerformanceMonitoring, true);
    });

    test('Create production config', () {
      final config = MCPConfig.production(
        appName: 'Prod App',
        appVersion: '1.0.0',
      );

      expect(config.appName, 'Prod App');
      expect(config.appVersion, '1.0.0');
      expect(config.loggingLevel, LogLevel.info);
      expect(config.enablePerformanceMonitoring, false);
      expect(config.background?.autoStartOnBoot, true);
    });

    test('Config validation succeeds with valid data', () {
      // This should not throw
      final config = MCPConfig(
        appName: 'Valid App',
        appVersion: '1.0.0',
        highMemoryThresholdMB: 1024,
        lowBatteryWarningThreshold: 20,
      );

      expect(config.highMemoryThresholdMB, 1024);
      expect(config.lowBatteryWarningThreshold, 20);
    });

    test('Config validation throws with invalid data', () {
      expect(() => MCPConfig(
        appName: '',  // Empty app name
        appVersion: '1.0.0',
      ), throwsArgumentError);

      expect(() => MCPConfig(
        appName: 'Test App',
        appVersion: '',  // Empty app version
      ), throwsArgumentError);

      expect(() => MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        highMemoryThresholdMB: -100,  // Negative memory threshold
      ), throwsArgumentError);
    });

    test('Config copyWith creates proper copy', () {
      final original = MCPConfig(
        appName: 'Original App',
        appVersion: '1.0.0',
      );

      final copy = original.copyWith(
        appName: 'Modified App',
        useBackgroundService: false,
      );

      expect(copy.appName, 'Modified App');
      expect(copy.appVersion, '1.0.0');  // Unchanged
      expect(copy.useBackgroundService, false);
      expect(copy.useNotification, true);  // Unchanged
    });
  });

  group('BackgroundConfig Tests', () {
    test('Create default background config', () {
      final config = BackgroundConfig.defaultConfig();

      expect(config.notificationChannelId, 'flutter_mcp_channel');
      expect(config.autoStartOnBoot, false);
      expect(config.intervalMs, 5000);
      expect(config.keepAlive, true);
    });

    test('Create custom background config', () {
      final config = BackgroundConfig(
        notificationChannelId: 'custom_channel',
        notificationChannelName: 'Custom Channel',
        autoStartOnBoot: true,
        intervalMs: 10000,
        keepAlive: false,
      );

      expect(config.notificationChannelId, 'custom_channel');
      expect(config.notificationChannelName, 'Custom Channel');
      expect(config.autoStartOnBoot, true);
      expect(config.intervalMs, 10000);
      expect(config.keepAlive, false);
    });
  });

  group('NotificationConfig Tests', () {
    test('Create default notification config', () {
      final config = NotificationConfig();

      expect(config.enableSound, true);
      expect(config.enableVibration, true);
      expect(config.priority, NotificationPriority.normal);
    });

    test('Create custom notification config', () {
      final config = NotificationConfig(
        channelId: 'custom_notification',
        channelName: 'Custom Notification',
        enableSound: false,
        enableVibration: false,
        priority: NotificationPriority.high,
      );

      expect(config.channelId, 'custom_notification');
      expect(config.channelName, 'Custom Notification');
      expect(config.enableSound, false);
      expect(config.enableVibration, false);
      expect(config.priority, NotificationPriority.high);
    });
  });

  group('MemoryManager Tests', () {
    test('Initialize memory manager', () {
      final memoryManager = MemoryManager.instance;

      memoryManager.initialize(
        startMonitoring: true,
        highMemoryThresholdMB: 1024,
        monitoringInterval: Duration(seconds: 10),
      );

      // Cleanup
      memoryManager.dispose();
    });

    test('Process data in chunks', () async {
      // Create test data
      final testData = List.generate(100, (index) => 'Item $index');

      // Process function that doubles the string
      Future<String> processItem(String item) async {
        return '$item-processed';
      }

      // Process in chunks of 10
      final result = await MemoryManager.processInChunks(
        items: testData,
        processItem: processItem,
        chunkSize: 10,
        pauseBetweenChunks: Duration(milliseconds: 10),
      );

      // Verify results
      expect(result.length, 100);
      expect(result[0], 'Item 0-processed');
      expect(result[99], 'Item 99-processed');
    });
  });

  group('MemoryAwareCache Tests', () {
    test('Basic cache operations', () {
      final cache = MemoryAwareCache<String, String>(maxSize: 3);

      cache.put('key1', 'value1');
      cache.put('key2', 'value2');
      cache.put('key3', 'value3');

      expect(cache.get('key1'), 'value1');
      expect(cache.get('key2'), 'value2');
      expect(cache.get('key3'), 'value3');
      expect(cache.size, 3);

      // Add one more item to exceed max size
      cache.put('key4', 'value4');

      // Oldest item should be evicted
      expect(cache.get('key1'), null);
      expect(cache.get('key4'), 'value4');
      expect(cache.size, 3);

      // Test removal
      cache.remove('key2');
      expect(cache.get('key2'), null);
      expect(cache.size, 2);

      // Test clearing
      cache.clear();
      expect(cache.size, 0);
      expect(cache.get('key3'), null);
    });

    test('Cache with TTL', () async {
      final cache = MemoryAwareCache<String, String>(
        maxSize: 10,
        entryTTL: Duration(milliseconds: 50),
      );

      cache.put('key1', 'value1');
      expect(cache.get('key1'), 'value1');

      // Wait for the entry to expire
      await Future.delayed(Duration(milliseconds: 100));

      // Entry should have expired
      expect(cache.get('key1'), null);
    });
  });

  group('ResourceManager Tests', () {
    test('Register and dispose resources', () async {
      final resourceManager = ResourceManager();
      bool resourceDisposed = false;

      // Register a test resource
      resourceManager.register<String>(
        'test_resource',
        'Test Value',
            (value) async {
          resourceDisposed = true;
        },
      );

      // Verify resource is registered
      expect(resourceManager.hasResource('test_resource'), true);
      expect(resourceManager.get<String>('test_resource'), 'Test Value');

      // Dispose the resource
      await resourceManager.dispose('test_resource');

      // Verify resource is disposed
      expect(resourceDisposed, true);
      expect(resourceManager.hasResource('test_resource'), false);
    });

    test('Resource dependencies', () async {
      final resourceManager = ResourceManager();
      final disposedResources = <String>[];

      // Register resources with dependencies
      resourceManager.register<String>(
        'resource1',
        'Value 1',
            (value) async {
          disposedResources.add('resource1');
        },
      );

      resourceManager.register<String>(
        'resource2',
        'Value 2',
            (value) async {
          disposedResources.add('resource2');
        },
      );

      // Add dependency: resource2 depends on resource1
      resourceManager.addDependency('resource2', 'resource1');

      // Dispose resource1 - should also dispose resource2
      await resourceManager.dispose('resource1');

      // Verify resources were disposed in correct order
      expect(disposedResources.length, 2);
      expect(disposedResources[0], 'resource2'); // Dependent first
      expect(disposedResources[1], 'resource1'); // Dependency second

      // Verify all resources are gone
      expect(resourceManager.hasResource('resource1'), false);
      expect(resourceManager.hasResource('resource2'), false);
    });

    test('Register with tag and dispose by tag', () async {
      final resourceManager = ResourceManager();
      final disposedResources = <String>[];

      // Register resources with the same tag
      resourceManager.registerWithTag<String>(
        'resource1',
        'Value 1',
            (value) async {
          disposedResources.add('resource1');
        },
        'test_tag',
      );

      resourceManager.registerWithTag<String>(
        'resource2',
        'Value 2',
            (value) async {
          disposedResources.add('resource2');
        },
        'test_tag',
      );

      resourceManager.registerWithTag<String>(
        'resource3',
        'Value 3',
            (value) async {
          disposedResources.add('resource3');
        },
        'different_tag',
      );

      // Get resources by tag
      final taggedResources = resourceManager.getKeysByTag('test_tag');
      expect(taggedResources.length, 2);
      expect(taggedResources.contains('resource1'), true);
      expect(taggedResources.contains('resource2'), true);

      // Dispose by tag
      await resourceManager.disposeByTag('test_tag');

      // Verify resources with test_tag were disposed
      expect(disposedResources.contains('resource1'), true);
      expect(disposedResources.contains('resource2'), true);
      expect(disposedResources.contains('resource3'), false);

      // Verify resource states
      expect(resourceManager.hasResource('resource1'), false);
      expect(resourceManager.hasResource('resource2'), false);
      expect(resourceManager.hasResource('resource3'), true);

      // Clean up
      await resourceManager.dispose('resource3');
    });
  });
}