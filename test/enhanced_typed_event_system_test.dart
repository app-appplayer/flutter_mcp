import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/enhanced_typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

class _SilentMiddleware implements EventMiddleware {
  @override
  String get name => 'silent';
  @override
  int get priority => 0;
  @override
  FutureOr<McpEvent?> onPublish(McpEvent event) => event;
  @override
  FutureOr<McpEvent?> onDeliver(McpEvent event, String handlerId) => event;
  @override
  void onError(Object error, StackTrace stackTrace, McpEvent event) {}
}

class _BlockingMiddleware implements EventMiddleware {
  @override
  String get name => 'blocker';
  @override
  int get priority => 100;
  @override
  FutureOr<McpEvent?> onPublish(McpEvent event) => null;
  @override
  FutureOr<McpEvent?> onDeliver(McpEvent event, String handlerId) => event;
  @override
  void onError(Object error, StackTrace stackTrace, McpEvent event) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EventHandler', () {
    test('shouldHandle returns true initially', () {
      final h = EventHandler<MemoryEvent, MemoryEvent>(
        id: 'h',
        handler: (_) {},
      );
      final e = MemoryEvent(currentMB: 100, thresholdMB: 200, peakMB: 150);
      expect(h.shouldHandle(e), isTrue);
    });

    test('filter rejects events that fail the predicate', () {
      final h = EventHandler<MemoryEvent, MemoryEvent>(
        id: 'h',
        handler: (_) {},
        filter: (e) => e.currentMB > 100,
      );
      expect(
        h.shouldHandle(
            MemoryEvent(currentMB: 50, thresholdMB: 100, peakMB: 60)),
        isFalse,
      );
      expect(
        h.shouldHandle(
            MemoryEvent(currentMB: 150, thresholdMB: 200, peakMB: 160)),
        isTrue,
      );
    });

    test('maxInvocations stops the handler after limit', () {
      var calls = 0;
      final h = EventHandler<MemoryEvent, MemoryEvent>(
        id: 'h',
        handler: (_) => calls++,
        maxInvocations: 2,
      );
      final e = MemoryEvent(currentMB: 1, thresholdMB: 1, peakMB: 1);
      h.handle(e);
      h.handle(e);
      h.handle(e); // should be rejected by shouldHandle
      expect(calls, 2);
    });

    test('timeout prevents reinvocation within window', () {
      var calls = 0;
      final h = EventHandler<MemoryEvent, MemoryEvent>(
        id: 'h',
        handler: (_) => calls++,
        timeout: const Duration(seconds: 1),
      );
      final e = MemoryEvent(currentMB: 1, thresholdMB: 1, peakMB: 1);
      h.handle(e);
      h.handle(e); // within 1 second → rejected
      expect(calls, 1);
    });

    test('transform converts event before invoking handler', () {
      String? captured;
      final h = EventHandler<MemoryEvent, String>(
        id: 'h',
        handler: (s) => captured = s,
        transform: (e) => 'memory=${e.currentMB}',
      );
      h.handle(MemoryEvent(currentMB: 42, thresholdMB: 100, peakMB: 50));
      expect(captured, 'memory=42');
    });

    test('getStatistics reports invocation count', () {
      final h = EventHandler<MemoryEvent, MemoryEvent>(
        id: 'h',
        handler: (_) {},
      );
      h.handle(MemoryEvent(currentMB: 1, thresholdMB: 1, peakMB: 1));
      final stats = h.getStatistics();
      expect(stats['id'], 'h');
      expect(stats['invocations'], 1);
      expect(stats['hasFilter'], isFalse);
      expect(stats['hasTransform'], isFalse);
    });
  });

  group('EventReplaySystem', () {
    test('start/stop recording flips internal state', () {
      final r = EventReplaySystem();
      r.startRecording();
      r.recordEvent(
        MemoryEvent(currentMB: 1, thresholdMB: 1, peakMB: 1),
      );
      r.stopRecording();
      // Recording stopped — additional records should not affect history.
      r.recordEvent(
        MemoryEvent(currentMB: 2, thresholdMB: 1, peakMB: 2),
      );
      // No public history accessor; just exercise clearHistory.
      r.clearHistory();
    });
  });

  group('EnhancedTypedEventSystem — basics', () {
    test('singleton instance is identical across calls', () {
      expect(
        identical(EnhancedTypedEventSystem.instance,
            EnhancedTypedEventSystem.instance),
        isTrue,
      );
    });

    test('subscribe returns a token and unsubscribe removes it', () async {
      final sys = EnhancedTypedEventSystem.instance;
      final token = sys.subscribe<MemoryEvent>((_) {});
      expect(token, isA<String>());
      expect(sys.getSubscription(token), isNotNull);
      await sys.unsubscribe(token);
      // After unsubscribe the entry is gone.
      expect(sys.getSubscription(token), isNull);
    });

    test('subscribeAdvanced + publish delivers the event to the handler',
        () async {
      final sys = EnhancedTypedEventSystem.instance;
      MemoryEvent? received;
      final token = sys.subscribeAdvanced<MemoryEvent, MemoryEvent>(
        handler: (e) => received = e,
        description: 'memory listener',
      );
      addTearDown(() => sys.unsubscribe(token));

      await sys.publish(
        MemoryEvent(currentMB: 200, thresholdMB: 256, peakMB: 220),
      );
      // _publishImmediately is fire-and-forget; allow microtasks to drain.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isNotNull);
      expect(received!.currentMB, 200);
    });

    test('removeMiddleware re-enables delivery', () async {
      final sys = EnhancedTypedEventSystem.instance;
      MemoryEvent? received;
      final token = sys.subscribeAdvanced<MemoryEvent, MemoryEvent>(
        handler: (e) => received = e,
      );
      final blocker = _BlockingMiddleware();
      sys.addMiddleware(blocker);
      sys.removeMiddleware(blocker.name);
      addTearDown(() => sys.unsubscribe(token));

      await sys.publish(
        MemoryEvent(currentMB: 5, thresholdMB: 10, peakMB: 6),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isNotNull);
    });

    test('silent middleware passes events through', () async {
      final sys = EnhancedTypedEventSystem.instance;
      MemoryEvent? received;
      final token = sys.subscribeAdvanced<MemoryEvent, MemoryEvent>(
        handler: (e) => received = e,
      );
      final mw = _SilentMiddleware();
      sys.addMiddleware(mw);
      addTearDown(() {
        sys.removeMiddleware(mw.name);
        return sys.unsubscribe(token);
      });

      await sys.publish(
        MemoryEvent(currentMB: 7, thresholdMB: 10, peakMB: 8),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isNotNull);
    });

    test('pause + resume can be called without throwing', () async {
      final sys = EnhancedTypedEventSystem.instance;
      sys.pause();
      await sys.resume();
    });

    test('getStatistics + getActiveSubscriptions', () async {
      final sys = EnhancedTypedEventSystem.instance;
      final t1 = sys.subscribe<MemoryEvent>((_) {});
      final t2 = sys.subscribe<ServerEvent>((_) {});
      addTearDown(() async {
        await sys.unsubscribe(t1);
        await sys.unsubscribe(t2);
      });

      final subs = sys.getActiveSubscriptions();
      expect(subs.any((s) => s.id == t1), isTrue);
      expect(subs.any((s) => s.id == t2), isTrue);

      final stats = sys.getStatistics();
      expect(stats, isA<Map>());
    });

    test('EventSubscription.toMap reports core fields', () async {
      final sys = EnhancedTypedEventSystem.instance;
      final token = sys.subscribe<MemoryEvent>((_) {});
      addTearDown(() => sys.unsubscribe(token));
      final sub = sys.getSubscription(token)!;
      final map = sub.toMap();
      expect(map['id'], token);
      expect(map, contains('eventType'));
      expect(map, contains('createdAt'));
      expect(map, contains('isActive'));
    });

    test('unsubscribe with unknown id is a no-op', () async {
      await EnhancedTypedEventSystem.instance.unsubscribe('absent');
    });
  });
}
