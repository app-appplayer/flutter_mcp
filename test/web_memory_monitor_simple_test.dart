// Pure-Dart smoke tests for WebMemoryMonitor — exercises the non-web
// branches (early-return guards on macOS host) plus the snapshot data
// classes. The full browser path needs `flutter test --platform chrome`
// and is out of scope here.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/web_memory_monitor.dart';

void main() {
  group('WebMemoryMonitor — singleton + non-web guards', () {
    test('instance is identical', () {
      expect(
        identical(WebMemoryMonitor.instance, WebMemoryMonitor.instance),
        isTrue,
      );
    });

    test('startMonitoring is a no-op on non-web', () {
      WebMemoryMonitor.instance.startMonitoring();
      // Should not throw; nothing to assert externally.
    });

    test('stopMonitoring when not running is a no-op', () {
      WebMemoryMonitor.instance.stopMonitoring();
    });

    test('getStatistics returns sensible empty shape when no snapshots', () {
      WebMemoryMonitor.instance.clearSnapshots();
      final stats = WebMemoryMonitor.instance.getStatistics();
      expect(stats, contains('isSupported'));
      expect(stats, contains('isMonitoring'));
      expect(stats, contains('snapshotCount'));
      expect(stats['snapshotCount'], 0);
    });

    test('getRecentSnapshots returns empty when nothing collected', () {
      WebMemoryMonitor.instance.clearSnapshots();
      expect(WebMemoryMonitor.instance.getRecentSnapshots(), isEmpty);
    });

    test('isMemoryAboveThreshold returns false when no snapshots', () {
      WebMemoryMonitor.instance.clearSnapshots();
      expect(
        WebMemoryMonitor.instance.isMemoryAboveThreshold(1000),
        isFalse,
      );
    });

    test('suggestGarbageCollection runs without error', () {
      WebMemoryMonitor.instance.suggestGarbageCollection();
    });

    test('exportData returns metadata + statistics + snapshots', () {
      WebMemoryMonitor.instance.clearSnapshots();
      final data = WebMemoryMonitor.instance.exportData();
      expect(data, contains('metadata'));
      expect(data, contains('statistics'));
      expect(data, contains('snapshots'));
    });

    test('dispose clears state without throwing', () {
      WebMemoryMonitor.instance.dispose();
    });

    test('getCurrentMemoryUsage returns a numeric value', () async {
      final v = await WebMemoryMonitor.instance.getCurrentMemoryUsage();
      expect(v, isA<int>());
      expect(v, greaterThanOrEqualTo(0));
    });
  });

  group('WebMemorySnapshot data class', () {
    test('toMap roundtrip', () {
      final ts = DateTime(2026);
      final s = WebMemorySnapshot(
        usedJSHeapSize: 100,
        totalJSHeapSize: 200,
        jsHeapSizeLimit: 1000,
        timestamp: ts,
        source: 'test',
      );
      final map = s.toMap();
      expect(map['usedJSHeapSize'], 100);
      expect(map['totalJSHeapSize'], 200);
      expect(map['jsHeapSizeLimit'], 1000);
      expect(map['source'], 'test');
      expect(map['timestamp'], ts.toIso8601String());
    });
  });
}
