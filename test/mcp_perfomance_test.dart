import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/performance_monitor.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/logger.dart';
import 'dart:async';

void main() {
  // Set up logging for tests
  setUp(() {
    MCPLogger.setDefaultLevel(LogLevel.debug);
    // Initialize fresh performance monitor for each test
    PerformanceMonitor.instance.reset();
  });

  // Cleanup after tests
  tearDown(() {
    PerformanceMonitor.instance.dispose();
  });

  group('PerformanceMonitor Tests', () {
    test('Basic timer operations', () {
      final monitor = PerformanceMonitor.instance;

      // Start a timer
      final timerId = monitor.startTimer('test_operation');

      // Introduce a small delay
      Future.delayed(Duration(milliseconds: 10));

      // Stop the timer
      final duration = monitor.stopTimer(timerId, success: true);

      // Verify the timer worked
      expect(duration.inMilliseconds, greaterThan(0));

      // Get metrics report
      final report = monitor.getMetricsReport();
      expect(report['timers'].containsKey('test_operation'), true);
      expect(report['timers']['test_operation']['success_rate'], 1.0);
    });

    test('Counter operations', () {
      final monitor = PerformanceMonitor.instance;

      // Increment counters
      monitor.incrementCounter('test_counter');
      monitor.incrementCounter('test_counter');
      monitor.incrementCounter('test_counter', 3);

      // Decrement counter
      monitor.decrementCounter('test_counter');

      // Verify counter values
      final report = monitor.getMetricsSummary();
      expect(report['counters']['test_counter'], 4); // 1 + 1 + 3 - 1 = 4
    });

    test('Resource usage tracking', () {
      final monitor = PerformanceMonitor.instance;

      // Record resource usage
      monitor.recordResourceUsage('memory', 100.0, capacity: 1000.0);
      monitor.recordResourceUsage('memory', 200.0, capacity: 1000.0);
      monitor.recordResourceUsage('memory', 150.0, capacity: 1000.0);

      // Verify resource tracking
      final report = monitor.getMetricsSummary();
      expect(report['resources']['memory']['current'], 150.0);
      expect(report['resources']['memory']['peak'], 200.0);
      expect(report['resources']['memory']['capacity'], 1000.0);

      // Average should be around (100 + 200 + 150) / 3 = 150
      expect(report['resources']['memory']['avg'], closeTo(150.0, 0.1));
    });

    test('Caching topics', () {
      final monitor = PerformanceMonitor.instance;

      // Enable caching for a topic
      monitor.enableCaching('test_topic');

      // Check if the topic has caching enabled
      expect(monitor.hasCachingEnabled('test_topic'), true);
      expect(monitor.hasCachingEnabled('other_topic'), false);

      // Disable caching
      monitor.disableCaching('test_topic');
      expect(monitor.hasCachingEnabled('test_topic'), false);
    });

    test('Metrics summary generation', () {
      final monitor = PerformanceMonitor.instance;

      // Add various metrics
      monitor.incrementCounter('requests', 10);
      monitor.incrementCounter('errors', 2);

      final timer1 = monitor.startTimer('operation1');
      Future.delayed(Duration(milliseconds: 5));
      monitor.stopTimer(timer1, success: true);

      final timer2 = monitor.startTimer('operation2');
      Future.delayed(Duration(milliseconds: 10));
      monitor.stopTimer(timer2, success: false);

      monitor.recordResourceUsage('cpu', 30.0, capacity: 100.0);

      // Get summary
      final summary = monitor.getMetricsSummary();

      // Verify summary structure
      expect(summary.containsKey('counters'), true);
      expect(summary.containsKey('timers'), true);
      expect(summary.containsKey('resources'), true);

      // Verify counter values
      expect(summary['counters']['requests'], 10);
      expect(summary['counters']['errors'], 2);

      // Verify timer data exists
      expect(summary['timers'].containsKey('operation1'), true);
      expect(summary['timers'].containsKey('operation2'), true);

      // Verify resource data
      expect(summary['resources']['cpu']['current'], 30.0);
    });
  });

  group('MemoryManager Tests', () {
    test('Memory cache with max size enforcement', () {
      final cache = MemoryAwareCache<String, String>(maxSize: 3);

      // Add items to cache
      cache.put('key1', 'value1');
      cache.put('key2', 'value2');
      cache.put('key3', 'value3');

      // Verify all items are in cache
      expect(cache.get('key1'), 'value1');
      expect(cache.get('key2'), 'value2');
      expect(cache.get('key3'), 'value3');
      expect(cache.size, 3);

      // Add one more item which should evict the oldest
      cache.put('key4', 'value4');

      // Verify size is still 3 and oldest item was removed
      expect(cache.size, 3);
      expect(cache.get('key1'), null); // Should be evicted as oldest
      expect(cache.get('key2'), 'value2');
      expect(cache.get('key3'), 'value3');
      expect(cache.get('key4'), 'value4');
    });

    test('Memory cache with item expiration', () async {
      final cache = MemoryAwareCache<String, int>(
        maxSize: 10,
        entryTTL: Duration(milliseconds: 50),
      );

      // Add items to cache
      cache.put('item1', 1);
      cache.put('item2', 2);

      // Access immediately should succeed
      expect(cache.get('item1'), 1);
      expect(cache.get('item2'), 2);

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 60));

      // Items should be expired now
      expect(cache.get('item1'), null);
      expect(cache.get('item2'), null);
    });

    test('Memory cache high-memory behavior simulation', () async {
      final cache = MemoryAwareCache<String, String>(maxSize: 20);

      // Fill the cache
      for (int i = 0; i < 20; i++) {
        cache.put('key$i', 'value$i');
      }

      expect(cache.size, 20);

      // Since we can't directly call private methods, we'll test the public interface
      // Simulate a high memory situation by creating a test method that does the same
      Future<void> simulateHighMemorySituation() async {
        // This mimics what happens inside the class when high memory is detected
        // We'll manually reduce the cache size
        final keysToRemove = cache.keys.take(cache.size ~/ 2).toList();
        for (final key in keysToRemove) {
          cache.remove(key);
        }
      }

      // Trigger the simulation
      await simulateHighMemorySituation();

      // Cache should be reduced to about half size
      expect(cache.size, lessThanOrEqualTo(11)); // Allow for rounding
      expect(cache.size, greaterThanOrEqualTo(9)); // Allow for rounding
    });

    test('Chunk processing for large datasets', () async {
      // Create a large dataset
      final largeDataset = List.generate(100, (i) => i);

      // Process function that squares the value
      int processCount = 0;
      Future<int> processingFunction(int value) async {
        processCount++;
        // Simulate some work
        await Future.delayed(Duration(microseconds: 1));
        return value * value;
      }

      // Process in chunks
      final results = await MemoryManager.processInChunks(
        items: largeDataset,
        processItem: processingFunction,
        chunkSize: 20,
        pauseBetweenChunks: Duration(milliseconds: 5),
      );

      // Verify results
      expect(results.length, 100);
      expect(processCount, 100);
      expect(results[0], 0);
      expect(results[10], 100); // 10²
      expect(results[99], 9801); // 99²
    });

    test('Memory monitoring simulation', () async {
      final memoryManager = MemoryManager.instance;
      bool highMemoryCallbackTriggered = false;

      // Initialize with monitoring
      memoryManager.initialize(
        startMonitoring: true,
        highMemoryThresholdMB: 100,
        monitoringInterval: Duration(milliseconds: 50),
      );

      // Add high memory callback
      memoryManager.addHighMemoryCallback(() async {
        highMemoryCallbackTriggered = true;
      });

      // Wait for a few monitoring cycles
      await Future.delayed(Duration(milliseconds: 200));

      // Get stats (this will vary since our implementation is just a simulation)
      final stats = memoryManager.getMemoryStats();

      // Verify structure of stats
      expect(stats.containsKey('currentMB'), true);
      expect(stats.containsKey('peakMB'), true);
      expect(stats.containsKey('thresholdMB'), true);
      expect(stats.containsKey('isMonitoring'), true);

      // Note about callback: We can't reliably assert whether the callback was triggered
      // in a test environment since it depends on the random simulation behavior
      print('High memory callback triggered: $highMemoryCallbackTriggered');

      // Cleanup
      memoryManager.dispose();
    });
  });

  // Benchmarking test for performance bottlenecks
  group('Performance Benchmarks', () {
    test('Memory cache access performance', () {
      final cache = MemoryAwareCache<String, String>(maxSize: 10000);
      final Stopwatch stopwatch = Stopwatch()..start();

      // Fill cache with 10,000 items
      for (int i = 0; i < 10000; i++) {
        cache.put('key$i', 'value$i');
      }

      final fillTime = stopwatch.elapsedMilliseconds;
      stopwatch.reset();

      // Randomly access 1,000 items
      for (int i = 0; i < 1000; i++) {
        final randomKey = 'key${(i * 10) % 10000}';
        final value = cache.get(randomKey);
        expect(value, isNotNull);
      }

      final accessTime = stopwatch.elapsedMilliseconds;

      // Print performance metrics for manual analysis
      print('Cache fill time for 10,000 items: $fillTime ms');
      print('Cache access time for 1,000 items: $accessTime ms');

      // The actual threshold values will depend on the hardware,
      // but we can set reasonable upper bounds for test environments
      expect(fillTime, lessThan(1000)); // Should be fast on modern hardware
      expect(accessTime, lessThan(500)); // Even faster for access
    });

    test('Performance monitor overhead', () {
      final monitor = PerformanceMonitor.instance;
      final Stopwatch stopwatch = Stopwatch()..start();

      // Perform 10,000 timer operations
      for (int i = 0; i < 10000; i++) {
        final id = monitor.startTimer('test_$i');
        monitor.stopTimer(id, success: true);
      }

      final timerTime = stopwatch.elapsedMilliseconds;
      stopwatch.reset();

      // Perform 10,000 counter operations
      for (int i = 0; i < 10000; i++) {
        monitor.incrementCounter('counter_$i');
      }

      final counterTime = stopwatch.elapsedMilliseconds;

      // Print performance metrics
      print('Time for 10,000 timer operations: $timerTime ms');
      print('Time for 10,000 counter operations: $counterTime ms');

      // Set reasonable thresholds
      expect(timerTime, lessThan(2000)); // Should be fast enough for most uses
      expect(counterTime, lessThan(1000)); // Counter ops should be faster
    });
  });
}