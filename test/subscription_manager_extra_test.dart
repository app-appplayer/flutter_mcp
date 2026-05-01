// Targeted extra coverage for SubscriptionManager — focuses on the
// methods not exercised by the existing subscription_manager_test.dart
// (track/untrack, unregisterBySource, isActive, getInfo, getStatistics,
// cleanup, clearAll, info/statistics toJson).

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/subscription_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SubscriptionManager is a singleton; clean up between tests.
  Future<void> drain() async {
    await SubscriptionManager.instance.clearAll();
  }

  setUp(drain);
  tearDown(drain);

  group('register / isActive / getInfo / unregister', () {
    test('register returns a token starting with "sub_"', () async {
      final ctrl = StreamController<int>();
      final sub = ctrl.stream.listen((_) {});
      final token = await SubscriptionManager.instance.register(
        subscription: sub,
        source: 'test',
        description: 'unit',
      );
      expect(token, startsWith('sub_'));
      expect(await SubscriptionManager.instance.isActive(token), isTrue);
      await ctrl.close();
    });

    test('getInfo returns SubscriptionInfo for a known token', () async {
      final ctrl = StreamController<int>();
      final sub = ctrl.stream.listen((_) {});
      final token = await SubscriptionManager.instance.register(
        subscription: sub,
        source: 'src',
        description: 'desc',
        autoCleanup: false,
      );
      final info = await SubscriptionManager.instance.getInfo(token);
      expect(info, isNotNull);
      expect(info!.source, 'src');
      expect(info.description, 'desc');
      expect(info.autoCleanup, isFalse);
      // toJson covers the data class.
      final json = info.toJson();
      expect(json['source'], 'src');
      expect(json['autoCleanup'], isFalse);
      expect(json, contains('ageSeconds'));
      await ctrl.close();
    });

    test('getInfo returns null for unknown token', () async {
      expect(
        await SubscriptionManager.instance.getInfo('absent'),
        isNull,
      );
    });

    test('unregister returns false for unknown token', () async {
      expect(
        await SubscriptionManager.instance.unregister('absent'),
        isFalse,
      );
    });

    test('unregister cancels and removes', () async {
      final ctrl = StreamController<int>();
      final sub = ctrl.stream.listen((_) {});
      final token = await SubscriptionManager.instance.register(
        subscription: sub,
        source: 'src',
      );
      expect(await SubscriptionManager.instance.unregister(token), isTrue);
      expect(await SubscriptionManager.instance.isActive(token), isFalse);
      await ctrl.close();
    });
  });

  group('unregisterBySource', () {
    test('removes only matching source', () async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final t1 = await SubscriptionManager.instance.register(
        subscription: c1.stream.listen((_) {}),
        source: 'src-a',
      );
      final t2 = await SubscriptionManager.instance.register(
        subscription: c2.stream.listen((_) {}),
        source: 'src-b',
      );

      final removed =
          await SubscriptionManager.instance.unregisterBySource('src-a');
      expect(removed, 1);
      expect(await SubscriptionManager.instance.isActive(t1), isFalse);
      expect(await SubscriptionManager.instance.isActive(t2), isTrue);

      await c1.close();
      await c2.close();
    });

    test('returns 0 when no matching source', () async {
      expect(
        await SubscriptionManager.instance.unregisterBySource('nope'),
        0,
      );
    });
  });

  group('getAllActive + getStatistics', () {
    test('lists every active subscription', () async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      await SubscriptionManager.instance.register(
        subscription: c1.stream.listen((_) {}),
        source: 'a',
      );
      await SubscriptionManager.instance.register(
        subscription: c2.stream.listen((_) {}),
        source: 'b',
      );
      final list = await SubscriptionManager.instance.getAllActive();
      expect(list, hasLength(2));
      await c1.close();
      await c2.close();
    });

    test('getStatistics buckets by source', () async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final c3 = StreamController<int>();
      await SubscriptionManager.instance.register(
        subscription: c1.stream.listen((_) {}),
        source: 'a',
      );
      await SubscriptionManager.instance.register(
        subscription: c2.stream.listen((_) {}),
        source: 'a',
      );
      await SubscriptionManager.instance.register(
        subscription: c3.stream.listen((_) {}),
        source: 'b',
      );
      final stats = await SubscriptionManager.instance.getStatistics();
      expect(stats.totalActive, 3);
      expect(stats.bySource['a'], 2);
      expect(stats.bySource['b'], 1);
      // toJson covers the statistics data class.
      final json = stats.toJson();
      expect(json['totalActive'], 3);
      expect(json, contains('percentLeaked'));
      await c1.close();
      await c2.close();
      await c3.close();
    });

    test('SubscriptionStatistics toJson handles zero totalCreated', () async {
      // After clearAll the counters might still have history, but a fresh
      // process-wide counter could be zero — verify toJson doesn't throw.
      final stats = await SubscriptionManager.instance.getStatistics();
      expect(() => stats.toJson(), returnsNormally);
    });
  });

  group('cleanup', () {
    test('returns 0 when nothing meets the maxAge cutoff', () async {
      final ctrl = StreamController<int>();
      await SubscriptionManager.instance.register(
        subscription: ctrl.stream.listen((_) {}),
        source: 'fresh',
      );
      final cleaned = await SubscriptionManager.instance
          .cleanup(maxAge: const Duration(hours: 1));
      expect(cleaned, 0);
      await ctrl.close();
    });

    test('removes subscriptions older than maxAge', () async {
      final ctrl = StreamController<int>();
      await SubscriptionManager.instance.register(
        subscription: ctrl.stream.listen((_) {}),
        source: 'old',
      );
      // Yield to let the subscription's recorded timestamp predate the
      // cleanup call. Without this Windows can pin both timestamps to
      // the same low-resolution tick and the cleanup sees age == 0.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // maxAge = 0 → everything is "older."
      final cleaned = await SubscriptionManager.instance
          .cleanup(maxAge: Duration.zero);
      expect(cleaned, 1);
      await ctrl.close();
    });
  });

  group('trackSubscription / untrackSubscription', () {
    test('tracked subscription appears in active list', () async {
      final ctrl = StreamController<int>();
      final sub = ctrl.stream.listen((_) {});
      SubscriptionManager.instance.trackSubscription('event-token', sub);
      // Async lock takes a microtask — settle it.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        await SubscriptionManager.instance.isActive('event-token'),
        isTrue,
      );
      SubscriptionManager.instance.untrackSubscription('event-token');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        await SubscriptionManager.instance.isActive('event-token'),
        isFalse,
      );
      await ctrl.close();
    });
  });

  group('clearAll', () {
    test('removes all entries', () async {
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      await SubscriptionManager.instance.register(
        subscription: c1.stream.listen((_) {}),
        source: 'x',
      );
      await SubscriptionManager.instance.register(
        subscription: c2.stream.listen((_) {}),
        source: 'y',
      );
      await SubscriptionManager.instance.clearAll();
      expect(
        await SubscriptionManager.instance.getAllActive(),
        isEmpty,
      );
      await c1.close();
      await c2.close();
    });
  });
}
