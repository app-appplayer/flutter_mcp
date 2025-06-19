import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/web_memory_monitor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  group('Web Memory Monitor Tests', () {
    late WebMemoryMonitor monitor;

    setUp(() {
      monitor = WebMemoryMonitor.instance;
    });

    tearDown(() {
      monitor.dispose();
    });

    test('Singleton instance returns same object', () {
      final instance1 = WebMemoryMonitor.instance;
      final instance2 = WebMemoryMonitor.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('Initial state is correct', () {
      expect(monitor.getStatistics()['isMonitoring'], isFalse);
      expect(monitor.getStatistics()['snapshotCount'], equals(0));
    });

    test('Start and stop monitoring', () {
      if (kIsWeb) {
        monitor.startMonitoring();
        expect(monitor.getStatistics()['isMonitoring'], isTrue);

        monitor.stopMonitoring();
        expect(monitor.getStatistics()['isMonitoring'], isFalse);
      } else {
        // On non-web platforms, monitoring should handle gracefully
        monitor.startMonitoring();
        // Should not crash
        monitor.stopMonitoring();
      }
    });

    test('getCurrentMemoryUsage returns valid value', () async {
      final memoryUsage = await monitor.getCurrentMemoryUsage();
      expect(memoryUsage, isA<int>());
      expect(memoryUsage, greaterThanOrEqualTo(0));
    });

    test('getStatistics returns complete data structure', () {
      final stats = monitor.getStatistics();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('isSupported'), isTrue);
      expect(stats.containsKey('isMonitoring'), isTrue);
      expect(stats.containsKey('snapshotCount'), isTrue);
      expect(stats.containsKey('currentUsageMB'), isTrue);
      expect(stats.containsKey('peakUsageMB'), isTrue);
      expect(stats.containsKey('averageUsageMB'), isTrue);
    });

    test('Memory threshold checking', () {
      final isAboveThreshold = monitor.isMemoryAboveThreshold(100.0);
      expect(isAboveThreshold, isA<bool>());
    });

    test('Recent snapshots retrieval', () {
      final snapshots = monitor.getRecentSnapshots(count: 10);
      expect(snapshots, isA<List>());
    });

    test('Garbage collection suggestion', () {
      // Should not throw
      expect(() => monitor.suggestGarbageCollection(), returnsNormally);
    });

    test('Export data functionality', () {
      final exportData = monitor.exportData();

      expect(exportData, isA<Map<String, dynamic>>());
      expect(exportData.containsKey('metadata'), isTrue);
      expect(exportData.containsKey('statistics'), isTrue);
      expect(exportData.containsKey('snapshots'), isTrue);
    });

    test('Clear snapshots functionality', () {
      monitor.clearSnapshots();
      expect(monitor.getStatistics()['snapshotCount'], equals(0));
    });

    test('Memory monitoring with custom interval', () {
      const customInterval = Duration(seconds: 2);

      if (kIsWeb) {
        monitor.startMonitoring(interval: customInterval);
        expect(monitor.getStatistics()['isMonitoring'], isTrue);
        monitor.stopMonitoring();
      }
    });

    test('WebMemorySnapshot data structure', () {
      final snapshot = WebMemorySnapshot(
        timestamp: DateTime.now(),
        usedJSHeapSize: 100,
        totalJSHeapSize: 150,
        jsHeapSizeLimit: 2048,
        source: 'test',
      );

      expect(snapshot.usedJSHeapSize, equals(100));
      expect(snapshot.totalJSHeapSize, equals(150));
      expect(snapshot.jsHeapSizeLimit, equals(2048));
      expect(snapshot.source, equals('test'));
      expect(snapshot.memoryUsagePercentage, closeTo(66.67, 0.1));
    });

    test('WebMemorySnapshot toMap conversion', () {
      final snapshot = WebMemorySnapshot(
        timestamp: DateTime.now(),
        usedJSHeapSize: 100,
        totalJSHeapSize: 150,
        jsHeapSizeLimit: 2048,
        source: 'test',
      );

      final map = snapshot.toMap();
      expect(map, isA<Map<String, dynamic>>());
      expect(map.containsKey('timestamp'), isTrue);
      expect(map.containsKey('usedJSHeapSize'), isTrue);
      expect(map.containsKey('totalJSHeapSize'), isTrue);
      expect(map.containsKey('jsHeapSizeLimit'), isTrue);
      expect(map.containsKey('source'), isTrue);
    });
  });

  group('Web Memory Monitor Error Handling', () {
    test('Handles monitoring errors gracefully', () {
      final monitor = WebMemoryMonitor.instance;

      // Should not throw even if browser APIs are not available
      expect(() => monitor.startMonitoring(), returnsNormally);
      expect(() => monitor.stopMonitoring(), returnsNormally);
    });

    test('Handles memory measurement errors gracefully', () async {
      final monitor = WebMemoryMonitor.instance;

      // Should return valid value even if measurement fails
      final memoryUsage = await monitor.getCurrentMemoryUsage();
      expect(memoryUsage, isA<int>());
      expect(memoryUsage, greaterThanOrEqualTo(0));
    });
  });
}
