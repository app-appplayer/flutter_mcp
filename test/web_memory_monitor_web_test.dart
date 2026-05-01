// @TestOn('browser')
//
// Browser-only tests for WebMemoryMonitor. Run with:
//     flutter test --platform chrome test/web_memory_monitor_web_test.dart
//
// On chrome, kIsWeb=true so the monitor exercises the actual estimation
// pipeline (performance.memory / PerformanceObserver / NavigatorUAData
// fall-back chain) instead of returning early on every guard.

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/web_memory_monitor.dart';

void main() {
  group('WebMemoryMonitor — browser path', () {
    setUp(() {
      WebMemoryMonitor.instance.clearSnapshots();
    });

    tearDown(() {
      WebMemoryMonitor.instance.stopMonitoring();
      WebMemoryMonitor.instance.clearSnapshots();
    });

    test('startMonitoring collects an initial snapshot', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 1),
      );
      // Allow the initial collection to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final snapshots = WebMemoryMonitor.instance.getRecentSnapshots();
      expect(snapshots, isNotEmpty);
      // The snapshot has populated JS heap fields.
      final s = snapshots.first;
      expect(s.usedJSHeapSize, greaterThan(0));
      expect(s.totalJSHeapSize, greaterThan(0));
      expect(s.jsHeapSizeLimit, greaterThan(0));
    });

    test('startMonitoring twice is a no-op (already-running guard)', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 5),
      );
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 5),
      );
      // No throw; the second call should just log and return.
    });

    test('stopMonitoring after start cleanly stops the timer', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 1),
      );
      WebMemoryMonitor.instance.stopMonitoring();
      // Clean stop — second call is also a no-op.
      WebMemoryMonitor.instance.stopMonitoring();
    });

    test('getStatistics reflects collected snapshots', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stats = WebMemoryMonitor.instance.getStatistics();
      expect(stats['snapshotCount'], greaterThan(0));
      expect(stats['isSupported'], isTrue);
      expect(stats['isMonitoring'], isTrue);
      expect(stats, contains('currentUsageMB'));
      expect(stats, contains('averageUsageMB'));
      expect(stats, contains('peakUsageMB'));
    });

    test('isMemoryAboveThreshold returns false for huge threshold', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Browser test heap won't be 99 GB.
      expect(
        WebMemoryMonitor.instance.isMemoryAboveThreshold(99 * 1024),
        isFalse,
      );
    });

    test('exportData populates the snapshots key', () async {
      WebMemoryMonitor.instance.startMonitoring(
        interval: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final data = WebMemoryMonitor.instance.exportData();
      expect(data['snapshots'], isA<List>());
      expect((data['snapshots'] as List), isNotEmpty);
    });

    test('getCurrentMemoryUsage returns a positive value on browser',
        () async {
      final v = await WebMemoryMonitor.instance.getCurrentMemoryUsage();
      expect(v, greaterThan(0));
    });

    test('suggestGarbageCollection runs without throwing', () {
      WebMemoryMonitor.instance.suggestGarbageCollection();
    });
  });
}
