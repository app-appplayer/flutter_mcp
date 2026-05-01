// Coverage tests for memory_manager — exercises MemoryAwareCache,
// Semaphore, processInChunks / processInParallelChunks / streamInChunks,
// and the MemoryManager singleton's stats / lifecycle.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';

void main() {
  group('MemoryAwareCache', () {
    test('put/get roundtrip', () {
      final c = MemoryAwareCache<String, int>();
      c.put('a', 1);
      expect(c.get('a'), 1);
      expect(c.size, 1);
      expect(c.containsKey('a'), isTrue);
    });

    test('get on missing key returns null', () {
      final c = MemoryAwareCache<String, int>();
      expect(c.get('missing'), isNull);
    });

    test('remove returns the value and shrinks cache', () {
      final c = MemoryAwareCache<String, int>();
      c.put('a', 42);
      expect(c.remove('a'), 42);
      expect(c.size, 0);
      expect(c.remove('a'), isNull);
    });

    test('clear empties the cache', () {
      final c = MemoryAwareCache<String, int>();
      c.put('a', 1);
      c.put('b', 2);
      c.clear();
      expect(c.size, 0);
      expect(c.keys, isEmpty);
    });

    test('eviction kicks in when maxSize exceeded', () {
      final c = MemoryAwareCache<int, String>(maxSize: 3);
      c.put(1, 'a');
      c.put(2, 'b');
      c.put(3, 'c');
      c.put(4, 'd');
      // Cache should have evicted the oldest entry (key 1).
      expect(c.size, 3);
      expect(c.containsKey(1), isFalse);
      expect(c.containsKey(4), isTrue);
    });

    test('TTL-expired entries return null on get', () async {
      final c = MemoryAwareCache<String, int>(
        entryTTL: const Duration(milliseconds: 20),
      );
      c.put('a', 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.get('a'), isNull);
      expect(c.size, 0); // expired entry is removed on read
    });

    test('keys iterator reflects current state', () {
      final c = MemoryAwareCache<String, int>();
      c.put('a', 1);
      c.put('b', 2);
      expect(c.keys.toSet(), {'a', 'b'});
    });
  });

  group('Semaphore', () {
    test('acquire under limit returns immediately', () async {
      final s = Semaphore(2);
      await s.acquire();
      await s.acquire();
      // Both slots taken — release once and verify next acquire works.
      s.release();
      await s.acquire();
    });

    test('acquire over limit waits for release', () async {
      final s = Semaphore(1);
      await s.acquire();

      var thirdAcquired = false;
      final f = s.acquire().then((_) => thirdAcquired = true);

      // Allow microtasks to settle — third should still be queued.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(thirdAcquired, isFalse);

      s.release();
      await f;
      expect(thirdAcquired, isTrue);
    });

    test('release with no waiters decrements counter', () async {
      final s = Semaphore(2);
      await s.acquire();
      s.release();
      // Should be able to acquire two again.
      await s.acquire();
      await s.acquire();
    });
  });

  group('MemoryManager.processInChunks', () {
    test('processes items in declared chunk size', () async {
      final results = await MemoryManager.processInChunks<int, int>(
        items: List.generate(10, (i) => i),
        processItem: (i) async => i * 2,
        chunkSize: 3,
      );
      expect(results, [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]);
    });

    test('default chunk size = 10 still produces full result', () async {
      final results = await MemoryManager.processInChunks<int, int>(
        items: List.generate(5, (i) => i),
        processItem: (i) async => i,
      );
      expect(results, [0, 1, 2, 3, 4]);
    });

    test('pauseBetweenChunks delays execution', () async {
      final stopwatch = Stopwatch()..start();
      await MemoryManager.processInChunks<int, int>(
        items: List.generate(4, (i) => i),
        processItem: (i) async => i,
        chunkSize: 2,
        pauseBetweenChunks: const Duration(milliseconds: 25),
      );
      stopwatch.stop();
      // 2 chunks → 1 inter-chunk pause; should be at least 25ms.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(20));
    });
  });

  group('MemoryManager.processInParallelChunks', () {
    test('returns results in chunk order', () async {
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: List.generate(6, (i) => i),
        processItem: (i) async => i,
        maxConcurrent: 2,
        chunkSize: 3,
      );
      expect(results, [0, 1, 2, 3, 4, 5]);
    });

    test('default args produce results without crashing', () async {
      final results = await MemoryManager.processInParallelChunks<int, int>(
        items: [1, 2, 3],
        processItem: (i) async => i + 1,
      );
      expect(results, [2, 3, 4]);
    });

    test('pauseBetweenChunks adds delay', () async {
      final stopwatch = Stopwatch()..start();
      await MemoryManager.processInParallelChunks<int, int>(
        items: [1, 2, 3, 4],
        processItem: (i) async => i,
        chunkSize: 2,
        pauseBetweenChunks: const Duration(milliseconds: 30),
      );
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(20));
    });
  });

  group('MemoryManager.streamInChunks', () {
    test('streams every transformed item', () async {
      final results = <int>[];
      await for (final r in MemoryManager.streamInChunks<int, int>(
        items: [10, 20, 30, 40],
        processItem: (i) async => i ~/ 10,
        chunkSize: 2,
      )) {
        results.add(r);
      }
      expect(results, [1, 2, 3, 4]);
    });

    test('default chunk size still works', () async {
      final results = <int>[];
      await for (final r in MemoryManager.streamInChunks<int, int>(
        items: [1, 2, 3],
        processItem: (i) async => i,
      )) {
        results.add(r);
      }
      expect(results, [1, 2, 3]);
    });
  });

  group('MemoryManager singleton — stats + lifecycle', () {
    test('instance is identical across calls', () {
      expect(
        identical(MemoryManager.instance, MemoryManager.instance),
        isTrue,
      );
    });

    test('getMemoryStats returns expected shape', () {
      final m = MemoryManager.instance;
      final stats = m.getMemoryStats();
      expect(stats, contains('currentMB'));
      expect(stats, contains('peakMB'));
      expect(stats, contains('thresholdMB'));
      expect(stats, contains('recentReadings'));
      expect(stats, contains('isMonitoring'));
      expect(stats, contains('monitoringIntervalSeconds'));
    });

    test('addHighMemoryCallback / clearHighMemoryCallbacks', () {
      final m = MemoryManager.instance;
      Future<void> cb() async {}
      m.addHighMemoryCallback(cb);
      m.clearHighMemoryCallbacks();
    });

    test('performMemoryCleanup runs without error', () {
      MemoryManager.instance.performMemoryCleanup();
    });

    test('start/stop monitoring is idempotent', () {
      final m = MemoryManager.instance;
      // Make sure we don't start a real monitor with a long interval.
      m.stopMemoryMonitoring();
      m.stopMemoryMonitoring(); // double stop is a no-op
    });

    test('current/peak getters return ints', () {
      final m = MemoryManager.instance;
      expect(m.currentMemoryUsageMB, isA<int>());
      expect(m.peakMemoryUsageMB, isA<int>());
    });
  });
}
