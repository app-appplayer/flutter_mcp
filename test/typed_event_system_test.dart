import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/events/typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_system.dart';

void main() {
  group('Typed Event System Tests', () {
    late TypedEventSystem typedEventSystem;
    late EventSystem eventSystem;

    setUp(() {
      typedEventSystem = TypedEventSystem.instance;
      eventSystem = EventSystem.instance;
    });

    tearDown(() async {
      await typedEventSystem.dispose();
    });

    test('should publish and receive typed memory events', () async {
      print('=== Typed Memory Event Test ===');

      final receivedEvents = <MemoryEvent>[];

      // Subscribe to memory events
      final token = typedEventSystem.subscribe<MemoryEvent>((event) {
        receivedEvents.add(event);
        print('Received typed memory event: ${event.currentMB}MB');
      });

      // Publish a memory event
      final memoryEvent = MemoryEvent(
        currentMB: 150,
        thresholdMB: 100,
        peakMB: 180,
      );

      typedEventSystem.publish<MemoryEvent>(memoryEvent);

      // Give time for event processing
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.currentMB, equals(150));
      expect(receivedEvents.first.thresholdMB, equals(100));
      expect(receivedEvents.first.peakMB, equals(180));
      expect(receivedEvents.first.eventType, equals('memory.high'));

      await typedEventSystem.unsubscribe(token);
    });

    test('should publish and receive typed server events', () async {
      print('=== Typed Server Event Test ===');

      final receivedEvents = <ServerEvent>[];

      // Subscribe to server events
      final token = typedEventSystem.subscribe<ServerEvent>((event) {
        receivedEvents.add(event);
        print(
            'Received typed server event: ${event.serverId} - ${event.status.name}');
      });

      // Publish a server event
      final serverEvent = ServerEvent(
        serverId: 'test-server-123',
        status: ServerStatus.running,
        message: 'Server is now running',
        metadata: {'port': 8080, 'transport': 'sse'},
      );

      typedEventSystem.publish<ServerEvent>(serverEvent);

      // Give time for event processing
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.serverId, equals('test-server-123'));
      expect(receivedEvents.first.status, equals(ServerStatus.running));
      expect(receivedEvents.first.message, equals('Server is now running'));
      expect(receivedEvents.first.metadata['port'], equals(8080));

      await typedEventSystem.unsubscribe(token);
    });

    test('should support multiple event type subscriptions', () async {
      print('=== Multiple Event Type Test ===');

      final receivedMemoryEvents = <MemoryEvent>[];
      final receivedServerEvents = <ServerEvent>[];

      // Subscribe to multiple event types
      final memoryToken = typedEventSystem.subscribe<MemoryEvent>((event) {
        receivedMemoryEvents.add(event);
      });

      final serverToken = typedEventSystem.subscribe<ServerEvent>((event) {
        receivedServerEvents.add(event);
      });

      // Publish different event types
      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 200,
        thresholdMB: 150,
        peakMB: 220,
      ));

      typedEventSystem.publish<ServerEvent>(ServerEvent(
        serverId: 'test-server-456',
        status: ServerStatus.stopped,
      ));

      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 180,
        thresholdMB: 150,
        peakMB: 220,
      ));

      // Give time for event processing
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedMemoryEvents.length, equals(2));
      expect(receivedServerEvents.length, equals(1));
      expect(receivedMemoryEvents.first.currentMB, equals(200));
      expect(receivedServerEvents.first.serverId, equals('test-server-456'));

      await typedEventSystem.unsubscribe(memoryToken);
      await typedEventSystem.unsubscribe(serverToken);
    });

    test('should provide cached events to late subscribers', () async {
      print('=== Cached Events Test ===');

      // Publish events before subscribing
      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 100,
        thresholdMB: 80,
        peakMB: 120,
      ));

      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 110,
        thresholdMB: 80,
        peakMB: 120,
      ));

      // Give time for caching
      await Future.delayed(Duration(milliseconds: 50));

      final receivedEvents = <MemoryEvent>[];

      // Subscribe after events were published
      final token = typedEventSystem.subscribe<MemoryEvent>((event) {
        receivedEvents.add(event);
      });

      // Give time for cached event delivery
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(2));
      expect(receivedEvents.first.currentMB, equals(100));
      expect(receivedEvents.last.currentMB, equals(110));

      await typedEventSystem.unsubscribe(token);
    });

    test('should work with EventSystem integration', () async {
      print('=== EventSystem Integration Test ===');

      final typedEvents = <MemoryEvent>[];
      final legacyEvents = <Map<String, dynamic>>[];

      // Subscribe to typed events
      final typedToken = await eventSystem.subscribe<MemoryEvent>((event) {
        typedEvents.add(event);
        print('Received via typed subscription: ${event.currentMB}MB');
      });

      // Subscribe to legacy topic-based events
      final legacyToken =
          await eventSystem.subscribeTopic('memory.high', (event) {
        legacyEvents.add(event as Map<String, dynamic>);
        print(
            'Received via legacy subscription: ${(event as Map)['currentMB']}MB');
      });

      // Publish via new typed API
      final memoryEvent = MemoryEvent(
        currentMB: 175,
        thresholdMB: 150,
        peakMB: 200,
      );

      await eventSystem.publishTyped<MemoryEvent>(memoryEvent);

      // Also publish to topic for legacy test
      await eventSystem.publishTopic('memory.high', {
        'currentMB': memoryEvent.currentMB,
        'thresholdMB': memoryEvent.thresholdMB,
        'peakMB': memoryEvent.peakMB,
        'eventType': memoryEvent.eventType,
      });

      // Give time for event processing
      await Future.delayed(Duration(milliseconds: 100));

      expect(typedEvents.length, equals(1));
      expect(legacyEvents.length, equals(1));
      expect(typedEvents.first.currentMB, equals(175));
      expect(legacyEvents.first['currentMB'], equals(175));

      await eventSystem.unsubscribe(typedToken);
      await eventSystem.unsubscribe(legacyToken);
    });

    test('should handle event system statistics', () async {
      print('=== Statistics Test ===');

      // Subscribe to some events
      final token1 = typedEventSystem.subscribe<MemoryEvent>((event) {});
      final token2 = typedEventSystem.subscribe<ServerEvent>((event) {});

      // Publish some events
      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 100,
        thresholdMB: 80,
        peakMB: 120,
      ));

      final stats = typedEventSystem.getStatistics();

      expect(stats['activeControllers'], greaterThan(0));
      expect(stats['activeSubscriptions'], equals(2));
      expect(stats['isPaused'], equals(false));

      print('Event system statistics: $stats');

      await typedEventSystem.unsubscribe(token1);
      await typedEventSystem.unsubscribe(token2);
    });

    test('should support pause and resume functionality', () async {
      print('=== Pause/Resume Test ===');

      final receivedEvents = <MemoryEvent>[];

      final token = typedEventSystem.subscribe<MemoryEvent>((event) {
        receivedEvents.add(event);
      });

      // Pause the system
      typedEventSystem.pause();

      // Publish events while paused
      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 100,
        thresholdMB: 80,
        peakMB: 120,
      ));

      typedEventSystem.publish<MemoryEvent>(MemoryEvent(
        currentMB: 110,
        thresholdMB: 80,
        peakMB: 120,
      ));

      // Give time for processing (should be none while paused)
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(0));

      // Resume the system
      typedEventSystem.resume();

      // Give time for queued events to process
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(2));

      await typedEventSystem.unsubscribe(token);
    });
  });
}
