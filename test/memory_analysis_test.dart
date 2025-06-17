import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/resource_manager.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/events/typed_event_system.dart';
import 'dart:io';
import 'dart:async';

void main() {
  group('Memory Management Analysis Tests', () {
    test('Actual ProcessInfo Memory Tracking', () async {
      print('=== ProcessInfo Memory Tracking Test ===');
      
      // Initial memory state
      final initialMemory = ProcessInfo.currentRss;
      print('Initial memory usage: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Perform memory-intensive operations
      var largeList = <List<int>>[];
      for (int i = 0; i < 10; i++) {
        // Generate approximately 1MB of data each
        largeList.add(List.filled(250000, i)); // 250k integers ≈ 1MB
      }
      
      final afterAllocationMemory = ProcessInfo.currentRss;
      final memoryIncrease = afterAllocationMemory - initialMemory;
      print('After memory allocation: ${(afterAllocationMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('Memory increase: ${(memoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Verify that memory actually increased
      expect(memoryIncrease, greaterThan(5 * 1024 * 1024)); // At least 5MB increase
      
      // Release memory
      largeList = []; // Replace with empty list
      
      // GC hint (not fully guaranteed but works in most cases)
      for (int i = 0; i < 3; i++) {
        var tempList = List.filled(100000, 0);
        tempList = []; // Replace with empty list
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      final afterCleanupMemory = ProcessInfo.currentRss;
      final memoryReclaimed = afterAllocationMemory - afterCleanupMemory;
      print('Memory after cleanup: ${(afterCleanupMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      print('Reclaimed memory: ${(memoryReclaimed / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // GC may not run immediately, so memory may not be fully reclaimed
      // But it should not increase drastically
      expect(afterCleanupMemory, lessThan(afterAllocationMemory + 50 * 1024 * 1024)); // Allow up to 50MB additional increase
    });

    test('MemoryManager Standalone Function Test', () async {
      print('=== MemoryManager Standalone Function Test ===');
      
      final memoryManager = MemoryManager.instance;
      bool highMemoryCallbackCalled = false;
      
      // Register high memory callback
      memoryManager.addHighMemoryCallback(() async {
        highMemoryCallbackCalled = true;
        print('High memory callback invoked!');
      });
      
      // Test with very low threshold (lower than current memory)
      final currentMemoryMB = (ProcessInfo.currentRss / 1024 / 1024).round();
      final lowThreshold = (currentMemoryMB * 0.5).round(); // 50% of current
      
      print('Current memory: ${currentMemoryMB}MB, Test threshold: ${lowThreshold}MB');
      
      // Start memory monitoring
      memoryManager.initialize(
        startMonitoring: true,
        monitoringInterval: Duration(milliseconds: 100),
        highMemoryThresholdMB: lowThreshold,
      );
      
      // Provide time for monitoring to execute
      await Future.delayed(Duration(milliseconds: 500));
      
      // Stop memory monitoring
      memoryManager.stopMemoryMonitoring();
      memoryManager.clearHighMemoryCallbacks();
      
      print('High memory callback invoked: $highMemoryCallbackCalled');
      
      // Callback should be invoked due to low threshold
      expect(highMemoryCallbackCalled, isTrue);
    });

    test('ResourceManager Dependency Management', () async {
      print('=== ResourceManager Dependency Management Test ===');
      
      final resourceManager = ResourceManager.instance;
      final disposedOrder = <String>[];
      final disposeCompleters = <String, Completer<void>>{};
      
      // Create dependency chain: A <- B <- C (C depends on B, B depends on A)
      
      // Resource A (lowest dependency)
      disposeCompleters['A'] = Completer<void>();
      resourceManager.register<String>(
        'A',
        'resourceA',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 50)); // Simulate cleanup time
          disposedOrder.add('A');
          disposeCompleters['A']!.complete();
          print('Resource A cleaned up');
        },
        priority: ResourceManager.highPriority,
      );
      
      // Resource B (depends on A)
      disposeCompleters['B'] = Completer<void>();
      resourceManager.register<String>(
        'B',
        'resourceB',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 30));
          disposedOrder.add('B');
          disposeCompleters['B']!.complete();
          print('Resource B cleaned up');
        },
        dependencies: ['A'],
        priority: ResourceManager.mediumPriority,
      );
      
      // Resource C (depends on B)
      disposeCompleters['C'] = Completer<void>();
      resourceManager.register<String>(
        'C',
        'resourceC',
        (resource) async {
          await Future.delayed(Duration(milliseconds: 20));
          disposedOrder.add('C');
          disposeCompleters['C']!.complete();
          print('Resource C cleaned up');
        },
        dependencies: ['B'],
        priority: ResourceManager.lowPriority,
      );
      
      // Attempt to dispose A (C, B must be disposed first due to dependencies)
      final disposeFuture = resourceManager.dispose('A');
      
      // Wait for all cleanup to complete
      await Future.wait([
        disposeCompleters['A']!.future,
        disposeCompleters['B']!.future,
        disposeCompleters['C']!.future,
      ]);
      
      await disposeFuture;
      
      print('Disposal order: $disposedOrder');
      
      // Verify disposal in dependency order (C -> B -> A)
      expect(disposedOrder.length, equals(3));
      expect(disposedOrder[0], equals('C')); // C first
      expect(disposedOrder[1], equals('B')); // B next
      expect(disposedOrder[2], equals('A')); // A last
    });

    test('Memory Chunk Processing Efficiency', () async {
      print('=== Memory Chunk Processing Efficiency Test ===');
      
      final initialMemory = ProcessInfo.currentRss;
      print('Initial memory: ${(initialMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Create large dataset
      final largeDataSet = List.generate(1000, (index) => 'item_$index' * 100); // Each item is approximately 500 bytes
      
      // Normal processing (all data at once)
      final normalResults = <String>[];
      for (final item in largeDataSet) {
        normalResults.add(item.toUpperCase());
      }
      
      final afterNormalMemory = ProcessInfo.currentRss;
      print('Memory after normal processing: ${(afterNormalMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      normalResults.clear(); // Release memory
      
      // Process by chunks
      final chunkResults = await MemoryManager.processInChunks<String, String>(
        items: largeDataSet,
        processItem: (item) async {
          return item.toUpperCase();
        },
        chunkSize: 50, // Process 50 items at a time
        pauseBetweenChunks: Duration(milliseconds: 5),
      );
      
      final afterChunkMemory = ProcessInfo.currentRss;
      print('Memory after chunk processing: ${(afterChunkMemory / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Verify results
      expect(chunkResults.length, equals(largeDataSet.length));
      expect(chunkResults.first, equals(largeDataSet.first.toUpperCase()));
      
      // Verify chunk processing is memory efficient (may not have big difference but should be stable)
      final normalMemoryIncrease = afterNormalMemory - initialMemory;
      final chunkMemoryIncrease = afterChunkMemory - initialMemory;
      
      print('Normal processing memory increase: ${(normalMemoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      print('Chunk processing memory increase: ${(chunkMemoryIncrease / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Chunk processing should show controlled memory usage
      expect(chunkMemoryIncrease, lessThan(100 * 1024 * 1024)); // Less than 100MB increase
    });

    test('Parallel Processing Concurrency Control', () async {
      print('=== Parallel Processing Concurrency Control Test ===');
      
      final concurrentTracker = <int>[];
      int maxConcurrent = 0;
      int currentConcurrent = 0;
      
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: List.generate(20, (i) => i),
        processItem: (item) async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          concurrentTracker.add(currentConcurrent);
          
          // Simulate work
          await Future.delayed(Duration(milliseconds: 50));
          
          currentConcurrent--;
          return item * 2;
        },
        maxConcurrent: 3, // Maximum 3 concurrent executions
        chunkSize: 5,
      );
      
      print('Maximum concurrent executions: $maxConcurrent');
      print('Concurrency tracking: ${concurrentTracker.take(10).toList()}...'); // Print only first 10
      
      // Verify results
      expect(results.length, equals(20));
      expect(results[5], equals(10)); // 5 * 2 = 10
      
      // Verify concurrency limit was respected
      expect(maxConcurrent, lessThanOrEqualTo(3));
      expect(maxConcurrent, greaterThan(0));
    });

    test('EventSystem Memory Event Propagation (Type Safe)', () async {
      print('=== EventSystem Type Safe Memory Event Test ===');
      
      // Clear cache before test
      TypedEventSystem.instance.clearCache();
      
      final eventSystem = EventSystem.instance;
      final receivedTypedEvents = <MemoryEvent>[];
      final receivedLegacyEvents = <Map<String, dynamic>>[];
      
      // Subscribe to type-safe memory events
      final typedToken = eventSystem.subscribeTyped<MemoryEvent>((event) {
        receivedTypedEvents.add(event);
        print('Type-safe memory event received: ${event.currentMB}MB');
      });
      
      // Subscribe to legacy memory events (backward compatibility)
      final legacyToken = eventSystem.subscribe<Map<String, dynamic>>('memory.high', (data) {
        receivedLegacyEvents.add(data);
        print('Legacy memory event received: ${data['currentMB']}MB');
      });
      
      // Publish type-safe event
      final memoryEvent = MemoryEvent(
        currentMB: 150,
        thresholdMB: 100,
        peakMB: 180,
      );
      
      eventSystem.publishTyped<MemoryEvent>(memoryEvent);
      
      // Provide time for event processing
      await Future.delayed(Duration(milliseconds: 100));
      
      // Verify type-safe events
      expect(receivedTypedEvents.length, equals(1));
      expect(receivedTypedEvents.first.currentMB, equals(150));
      expect(receivedTypedEvents.first.thresholdMB, equals(100));
      expect(receivedTypedEvents.first.peakMB, equals(180));
      expect(receivedTypedEvents.first.eventType, equals('memory.high'));
      
      // Verify backward compatibility
      expect(receivedLegacyEvents.length, equals(1));
      expect(receivedLegacyEvents.first['currentMB'], equals(150));
      expect(receivedLegacyEvents.first['thresholdMB'], equals(100));
      
      // Unsubscribe (TypedEventSystem's unsubscribe returns a Future)
      await TypedEventSystem.instance.unsubscribe(typedToken);
      eventSystem.unsubscribe(legacyToken);
      
      print('Type-safe event system confirmed working properly');
    });
  });
}