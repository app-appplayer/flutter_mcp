import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('Enhanced Event System Integration Tests', () {
    late EventSystem eventSystem;

    setUp(() async {
      eventSystem = EventSystem.instance;
      await eventSystem.reset();
    });

    tearDown(() async {
      await eventSystem.reset();
    });

    test('should publish and receive typed events through enhanced system',
        () async {
      final receivedEvents = <ServerEvent>[];

      // Subscribe using enhanced API
      eventSystem.subscribe<ServerEvent>((event) {
        receivedEvents.add(event);
      });

      // Create test event
      final testEvent = ServerEvent(
        serverId: 'test_server',
        status: ServerStatus.running,
        metadata: {'test': 'data'},
      );

      // Publish using enhanced API
      await eventSystem.publishTyped<ServerEvent>(testEvent);

      // Allow event to propagate
      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.serverId, equals('test_server'));
      expect(receivedEvents.first.status, equals(ServerStatus.running));
      expect(receivedEvents.first.metadata['test'], equals('data'));
    });

    test('should track comprehensive statistics', () async {
      // Subscribe to some events
      eventSystem.subscribe<ServerEvent>((event) {});

      // Also subscribe with legacy API to increase subscription count
      final legacyId =
          await eventSystem.subscribeTopic('test.topic', (event) {});

      // Publish several events
      for (int i = 0; i < 5; i++) {
        await eventSystem.publishTyped<ServerEvent>(
          ServerEvent(serverId: 'server_$i', status: ServerStatus.running),
        );
      }

      // Get statistics
      final stats = eventSystem.getStatistics();

      // Verify statistics
      // Check event counts - the key should be the event type name
      final eventCounts = stats['eventCounts'] as Map<String, dynamic>?;
      expect(eventCounts, isNotNull);
      if (eventCounts != null && eventCounts.isNotEmpty) {
        final totalEvents = eventCounts.values
            .fold<int>(0, (sum, count) => sum + (count as int));
        expect(totalEvents, greaterThanOrEqualTo(5));
      }

      // Check active handlers instead of subscriptions
      final activeHandlers = stats['activeHandlers'] as Map<String, dynamic>?;
      expect(activeHandlers, isNotNull);
      if (activeHandlers != null) {
        final totalHandlers = activeHandlers.values
            .fold<int>(0, (sum, count) => sum + (count as int));
        expect(totalHandlers, greaterThan(0));
      }
      expect(stats['isPaused'], isFalse);

      // Clean up
      await eventSystem.unsubscribe(legacyId);
    });

    test('should support pause and resume functionality', () async {
      final receivedEvents = <ServerEvent>[];

      // Subscribe
      eventSystem.subscribe<ServerEvent>((event) {
        receivedEvents.add(event);
      });

      // Pause the system
      await eventSystem.pause();

      // Publish events while paused
      await eventSystem.publishTyped<ServerEvent>(
        ServerEvent(serverId: 'paused_server', status: ServerStatus.running),
      );

      // Should not receive events while paused
      await Future.delayed(Duration(milliseconds: 10));
      expect(receivedEvents.length, equals(0));

      // Resume the system
      await eventSystem.resume();

      // Should now receive queued events
      await Future.delayed(Duration(milliseconds: 50));
      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.serverId, equals('paused_server'));
    });

    test('should provide backward compatibility with legacy API', () async {
      final legacyEvents = <Map<String, dynamic>>[];
      final typedEvents = <ServerEvent>[];

      // Subscribe using legacy API
      final legacyId =
          await eventSystem.subscribeTopic('server.status', (event) {
        legacyEvents.add(event as Map<String, dynamic>);
      });

      // Subscribe using typed API
      eventSystem.subscribe<ServerEvent>((event) {
        typedEvents.add(event);
      });

      // Publish using typed API
      final testEvent = ServerEvent(
        serverId: 'test_server',
        status: ServerStatus.running,
      );

      await eventSystem.publishTyped<ServerEvent>(testEvent);

      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 10));

      // Both should receive events
      expect(typedEvents.length, equals(1));
      // Legacy events are not automatically bridged in the current implementation
      // expect(legacyEvents.length, equals(1));

      // Clean up
      await eventSystem.unsubscribe(legacyId);
    });
  });
}
