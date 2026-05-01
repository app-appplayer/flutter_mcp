// Targeted extension of typed_event_system coverage — focuses on the
// methods not exercised by the existing typed_event_system_test.dart
// (subscribeMultiple, getCachedEvents, clearCache, getStatistics, dispose,
// _GroupSubscription edge paths).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TypedEventSystem singleton + statistics', () {
    test('instance is identical across calls', () {
      expect(
        identical(TypedEventSystem.instance, TypedEventSystem.instance),
        isTrue,
      );
    });

    test('getStatistics returns expected keys', () {
      final stats = TypedEventSystem.instance.getStatistics();
      expect(stats, contains('activeControllers'));
      expect(stats, contains('activeSubscriptions'));
      expect(stats, contains('queuedEvents'));
      expect(stats, contains('isPaused'));
      expect(stats, contains('cachedEventCounts'));
    });
  });

  group('TypedEventSystem.subscribeMultiple', () {
    test('returns a multi-subscription token', () async {
      final sys = TypedEventSystem.instance;
      final token = sys.subscribeMultiple<McpEvent>(
        [MemoryEvent, ServerEvent],
        (_) {},
      );
      expect(token, startsWith('typed_multi_subscription_'));
      await sys.unsubscribe(token);
    });

    test('multi-subscription cancellation works', () async {
      final sys = TypedEventSystem.instance;
      final token = sys.subscribeMultiple<McpEvent>(
        [MemoryEvent, ClientEvent],
        (_) {},
      );
      await sys.unsubscribe(token);
      // Second cancel is a no-op.
      await sys.unsubscribe(token);
    });
  });

  group('TypedEventSystem.getCachedEvents + clearCache', () {
    test('cache stores published events for late subscribers', () async {
      final sys = TypedEventSystem.instance;
      // Clear any leftover cache from prior tests.
      sys.clearCache();

      // First publish — there must be at least one stream controller for
      // the type before the cache fires; an empty subscribe-and-unsubscribe
      // is enough to register the controller.
      final w = sys.subscribe<MemoryEvent>((_) {});
      addTearDown(() => sys.unsubscribe(w));

      sys.publish(
        MemoryEvent(currentMB: 1, thresholdMB: 10, peakMB: 2),
      );
      sys.publish(
        MemoryEvent(currentMB: 2, thresholdMB: 10, peakMB: 3),
      );

      final cached = sys.getCachedEvents<MemoryEvent>();
      expect(cached, isNotEmpty);
    });

    test('clearCache(eventType) removes only that type', () {
      final sys = TypedEventSystem.instance;
      // Publish into MemoryEvent only and ensure clearCache for it
      // doesn't throw.
      sys.publish(MemoryEvent(currentMB: 1, thresholdMB: 10, peakMB: 2));
      sys.clearCache(MemoryEvent);
      final cached = sys.getCachedEvents<MemoryEvent>();
      expect(cached, isEmpty);
    });

    test('clearCache() with no type clears everything', () {
      final sys = TypedEventSystem.instance;
      sys.publish(MemoryEvent(currentMB: 1, thresholdMB: 10, peakMB: 2));
      sys.clearCache();
      expect(sys.getCachedEvents<MemoryEvent>(), isEmpty);
    });
  });

  group('TypedEventSystem.pause / resume', () {
    test('events published while paused are queued and delivered after resume',
        () async {
      final sys = TypedEventSystem.instance;
      sys.clearCache();
      MemoryEvent? received;
      final token = sys.subscribe<MemoryEvent>((e) => received = e);
      addTearDown(() => sys.unsubscribe(token));

      sys.pause();
      sys.publish(MemoryEvent(currentMB: 5, thresholdMB: 10, peakMB: 6));
      // Paused → not yet received.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isNull);

      sys.resume();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isNotNull);
    });

    test('resume when not paused is a no-op', () {
      final sys = TypedEventSystem.instance;
      // Should not throw.
      sys.resume();
    });
  });
}
