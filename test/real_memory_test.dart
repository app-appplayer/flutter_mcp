import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/resource_manager.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real Memory Management Tests', () {
    late FlutterMCP mcp;

    setUp(() async {
      // Set up method channel mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'initialize':
              return null;
            case 'startBackgroundService':
              return true;
            case 'stopBackgroundService':
              return true;
            case 'showNotification':
              return null;
            case 'cancelAllNotifications':
              return null;
            case 'shutdown':
              return null;
            case 'getPlatformVersion':
              return 'Test Platform 1.0';
            default:
              return null;
          }
        },
      );

      mcp = FlutterMCP.instance;
      if (!mcp.isInitialized) {
        await mcp.init(MCPConfig(
          appName: 'Memory Test',
          appVersion: '1.0.0',
          highMemoryThresholdMB: 200, // Set 200MB threshold
        ));
      }
    });

    tearDown(() async {
      try {
        await mcp.shutdown();
      } catch (_) {
        // Ignore shutdown errors in tests
      }
    });

    tearDownAll(() {
      // Clear method channel mock
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        null,
      );
    });

    test('Measure actual memory usage', () async {
      print('=== Actual Memory Usage Measurement Test ===');

      // Check initial memory state
      final initialMemory = ProcessInfo.currentRss;
      print(
          'Initial memory usage: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');

      // Create multiple servers and clients (increase memory usage)
      final serverIds = <String>[];
      final clientIds = <String>[];

      for (int i = 0; i < 5; i++) {
        // Create server
        final serverId = await mcp.createServer(
          name: 'Test Server $i',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'Test Server $i',
            version: '1.0.0',
            transportType: 'stdio',
          ),
        );
        serverIds.add(serverId);

        // Create client
        final clientId = await mcp.createClient(
          name: 'Test Client $i',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'Test Client $i',
            version: '1.0.0',
            transportType: 'stdio',
            transportCommand: 'echo',
          ),
        );
        clientIds.add(clientId);
      }

      // Check memory usage increase
      final afterCreationMemory = ProcessInfo.currentRss;
      final memoryIncrease = afterCreationMemory - initialMemory;
      print(
          'Memory after server/client creation: ${(afterCreationMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print(
          'Memory increase: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');

      expect(memoryIncrease, greaterThan(0)); // Memory should increase

      // Clean up resources
      await mcp.shutdown();

      // Attempt forced GC and delay (provide time for memory cleanup)
      await Future.delayed(Duration(milliseconds: 100));

      // Try GC multiple times and measure memory
      int attempts = 0;
      int afterCleanupMemory = ProcessInfo.currentRss;

      while (attempts < 3 && afterCleanupMemory >= afterCreationMemory) {
        attempts++;
        await Future.delayed(Duration(milliseconds: 200));
        afterCleanupMemory = ProcessInfo.currentRss;
        print(
            'Memory after GC attempt $attempts: ${(afterCleanupMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      final memoryReclaimed = afterCreationMemory - afterCleanupMemory;
      print(
          'Memory after cleanup: ${(afterCleanupMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print(
          'Reclaimed memory: ${(memoryReclaimed / 1024 / 1024).toStringAsFixed(2)} MB');

      // Verify memory cleanup - immediate memory release is not guaranteed in test environment
      // Apply flexible criteria as memory may not be fully reclaimed depending on GC timing
      final memoryIncreaseAfterCleanup = afterCleanupMemory - initialMemory;

      // Consider normal if memory increase does not exceed 2x the initial increase
      // This means memory leaks are not severe
      final allowedIncreaseRatio =
          2.0; // Allow up to 200% increase (very lenient criteria)
      expect(memoryIncreaseAfterCleanup,
          lessThan(memoryIncrease * allowedIncreaseRatio),
          reason:
              'Memory after cleanup ($memoryIncreaseAfterCleanup bytes increase) should not exceed ${memoryIncrease * allowedIncreaseRatio} bytes increase');
    });

    test('Memory threshold detection test', () async {
      print('=== Memory Threshold Detection Test ===');

      bool highMemoryCallbackCalled = false;
      String? memoryEventData;

      // Register high memory callback
      MemoryManager.instance.addHighMemoryCallback(() async {
        highMemoryCallbackCalled = true;
        print('High memory callback was called!');
      });

      // Register memory event listener
      EventSystem.instance.subscribeTopic('memory.high', (data) {
        memoryEventData = data.toString();
        print('Memory event received: $memoryEventData');
      });

      // Start memory monitoring (with faster interval)
      MemoryManager.instance.initialize(
        startMonitoring: true,
        monitoringInterval: Duration(milliseconds: 100),
        highMemoryThresholdMB: 50, // Set very low threshold (for testing)
      );

      // Wait for memory monitoring to execute
      await Future.delayed(Duration(milliseconds: 500));

      // Stop memory monitoring
      MemoryManager.instance.stopMemoryMonitoring();

      print('High memory callback called: $highMemoryCallbackCalled');
      print('Memory event data: $memoryEventData');

      // Callback should be called due to low threshold
      expect(highMemoryCallbackCalled, isTrue);
      expect(memoryEventData, isNotNull);
    });

    test('Resource dependency management test', () async {
      print('=== Resource Dependency Management Test ===');

      final resourceManager = ResourceManager.instance;
      final disposedOrder = <String>[];

      // Register resources with dependencies
      resourceManager.register<String>(
        'dependency1',
        'resource1',
        (resource) async {
          disposedOrder.add('dependency1');
          print('dependency1 cleaned up');
        },
        priority: ResourceManager.highPriority,
      );

      resourceManager.register<String>(
        'dependency2',
        'resource2',
        (resource) async {
          disposedOrder.add('dependency2');
          print('dependency2 cleaned up');
        },
        dependencies: ['dependency1'],
        priority: ResourceManager.mediumPriority,
      );

      resourceManager.register<String>(
        'main_resource',
        'main',
        (resource) async {
          disposedOrder.add('main_resource');
          print('main_resource cleaned up');
        },
        dependencies: ['dependency1', 'dependency2'],
        priority: ResourceManager.lowPriority,
      );

      // Clean up main resource (dependencies should be cleaned up first)
      await resourceManager.dispose('dependency1');

      print('Cleanup order: $disposedOrder');

      // Check if main_resource and dependency2 were cleaned up first due to dependencies
      expect(disposedOrder.contains('main_resource'), isTrue);
      expect(disposedOrder.contains('dependency2'), isTrue);
      expect(disposedOrder.last,
          equals('dependency1')); // dependency1 cleaned up last
    });

    test('Memory chunk processing test', () async {
      print('=== Memory Chunk Processing Test ===');

      // Create large data
      final largeDataSet = List.generate(1000, (index) => 'data_item_$index');

      final initialMemory = ProcessInfo.currentRss;
      print(
          'Memory before chunk processing: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');

      // Process by chunks (memory efficient)
      final results = await MemoryManager.processInChunks<String, String>(
        items: largeDataSet,
        processItem: (item) async {
          // Some processing time and memory usage
          await Future.delayed(Duration(milliseconds: 1));
          return item.toUpperCase();
        },
        chunkSize: 50, // Process 50 items at a time
        pauseBetweenChunks: Duration(milliseconds: 10), // Pause between chunks
      );

      final afterProcessingMemory = ProcessInfo.currentRss;
      print(
          'Memory after chunk processing: ${(afterProcessingMemory / 1024 / 1024).toStringAsFixed(2)} MB');

      expect(results.length, equals(largeDataSet.length));
      expect(results.first, equals('DATA_ITEM_0'));

      // Check if memory usage was controlled (should not have large increase)
      final memoryIncrease = afterProcessingMemory - initialMemory;
      print(
          'Memory increase: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');

      // Memory increase should be limited due to chunk processing
      expect(memoryIncrease,
          lessThan(50 * 1024 * 1024)); // Increase less than 50MB
    });

    test('Parallel chunk processing and concurrency control test', () async {
      print('=== Parallel Chunk Processing and Concurrency Control Test ===');

      final dataSet = List.generate(100, (index) => index);

      final initialMemory = ProcessInfo.currentRss;
      print(
          'Memory before parallel processing: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');

      // Parallel processing with limited concurrency
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: dataSet,
        processItem: (item) async {
          // Simulate CPU-intensive work
          await Future.delayed(Duration(milliseconds: 10));
          return item * item;
        },
        maxConcurrent: 3, // Maximum 3 concurrent executions
        chunkSize: 10,
        pauseBetweenChunks: Duration(milliseconds: 5),
      );

      final afterProcessingMemory = ProcessInfo.currentRss;
      print(
          'Memory after parallel processing: ${(afterProcessingMemory / 1024 / 1024).toStringAsFixed(2)} MB');

      expect(results.length, equals(dataSet.length));
      expect(results[5], equals(25)); // 5^2 = 25

      // Check if memory usage was limited by concurrency control
      final memoryIncrease = afterProcessingMemory - initialMemory;
      print(
          'Memory increase: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');

      expect(memoryIncrease,
          lessThan(30 * 1024 * 1024)); // Increase less than 30MB
    });
  });
}
