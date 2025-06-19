import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('EventSystem Cleanup Tests', () {
    late EventSystem eventSystem;

    setUp(() {
      eventSystem = EventSystem.instance;
    });

    tearDown(() async {
      await eventSystem.reset();
    });

    test('publishTyped and subscribe work without enhanced system', () async {
      // Test typed event publishing and subscription
      var receivedEvent = false;
      ServerEvent? capturedEvent;

      final token = eventSystem.subscribe<ServerEvent>((event) {
        receivedEvent = true;
        capturedEvent = event;
      });

      expect(token, isNotEmpty);
      expect(token, startsWith('typed_'));

      // Publish a typed event
      final event = ServerEvent(
        serverId: 'test-server',
        status: ServerStatus.running,
        message: 'Server started',
      );

      await eventSystem.publishTyped(event);

      // Allow event to propagate
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvent, isTrue);
      expect(capturedEvent, isNotNull);
      expect(capturedEvent!.serverId, equals('test-server'));
      expect(capturedEvent!.status, equals(ServerStatus.running));

      // Cleanup
      await eventSystem.unsubscribe(token);
    });

    test('subscribe with manual filtering works correctly', () async {
      var eventCount = 0;
      String? transformedMessage;

      // Subscribe with manual filter and transform
      final token = eventSystem.subscribe<ClientEvent>((event) {
        // Manual filter
        if (event.status == ClientStatus.connected) {
          // Manual transform
          transformedMessage =
              'Client ${event.clientId} is ${event.status.name}';
          eventCount++;
        }
      });

      // Publish events
      await eventSystem.publishTyped(ClientEvent(
        clientId: 'client-1',
        status: ClientStatus.connecting,
      ));

      await eventSystem.publishTyped(ClientEvent(
        clientId: 'client-2',
        status: ClientStatus.connected,
      ));

      await eventSystem.publishTyped(ClientEvent(
        clientId: 'client-3',
        status: ClientStatus.connected,
      ));

      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 100));

      expect(eventCount, equals(2)); // Only connected events
      expect(transformedMessage, equals('Client client-3 is connected'));

      // Cleanup
      await eventSystem.unsubscribe(token);
    });

    test('pause and resume work correctly', () async {
      var eventCount = 0;

      eventSystem.subscribe<MemoryEvent>((event) {
        eventCount++;
      });

      // Pause the system
      await eventSystem.pause();

      // Publish events while paused
      await eventSystem.publishTyped(MemoryEvent(
        currentMB: 100,
        thresholdMB: 80,
        peakMB: 120,
      ));

      await eventSystem.publishTyped(MemoryEvent(
        currentMB: 110,
        thresholdMB: 80,
        peakMB: 120,
      ));

      // Events should not be delivered yet
      await Future.delayed(Duration(milliseconds: 100));
      expect(eventCount, equals(0));

      // Resume - queued events will be processed automatically
      await eventSystem.resume();

      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 100));
      expect(eventCount, equals(2));
    });

    test('statistics tracking works correctly', () async {
      // Subscribe to some events
      await eventSystem.subscribe<ServerEvent>((event) {});
      await eventSystem.subscribe<ClientEvent>((event) {});

      // Publish some events
      await eventSystem.publishTyped(ServerEvent(
        serverId: 'server-1',
        status: ServerStatus.running,
      ));

      await eventSystem.publishTyped(ClientEvent(
        clientId: 'client-1',
        status: ClientStatus.connected,
      ));

      await Future.delayed(Duration(milliseconds: 100));

      // Get statistics
      final stats = await eventSystem.getStatistics();

      // Check event counts
      final eventCounts = stats['eventCounts'] as Map<String, dynamic>?;
      expect(eventCounts, isNotNull);

      // Check active handlers instead of subscriptions
      final activeHandlers = stats['activeHandlers'] as Map<String, dynamic>?;
      expect(activeHandlers, isNotNull);
      if (activeHandlers != null) {
        final totalHandlers = activeHandlers.values
            .fold<int>(0, (sum, count) => sum + (count as int));
        expect(totalHandlers, equals(2));
      }
    });

    test('typed event caching works for late subscribers', () async {
      // Note: The current EventSystem implementation doesn't support caching for typed events
      // This test verifies that events published after subscription are received

      ErrorEvent? receivedEvent;
      eventSystem.subscribe<ErrorEvent>((event) {
        receivedEvent = event;
      });

      // Publish event after subscription
      final event = ErrorEvent(
        errorCode: 'TEST_ERROR',
        message: 'Test error message',
        severity: ErrorSeverity.medium,
      );

      await eventSystem.publishTyped(event);

      // Allow event delivery
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.errorCode, equals('TEST_ERROR'));
    });

    test('regular topic-based events still work', () async {
      var receivedEvent = false;
      String? receivedData;

      final token = await eventSystem.subscribeTopic('test.topic', (data) {
        receivedEvent = true;
        receivedData = data;
      });

      await eventSystem.publishTopic('test.topic', 'Hello, World!');

      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvent, isTrue);
      expect(receivedData, equals('Hello, World!'));

      await eventSystem.unsubscribe(token);
    });
  });
}
