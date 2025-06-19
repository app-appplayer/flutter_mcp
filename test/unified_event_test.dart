import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('Unified EventSystem Tests', () {
    late EventSystem eventSystem;

    setUp(() {
      eventSystem = EventSystem.instance;
      eventSystem.reset();
    });

    test('should publish and subscribe to typed events', () async {
      var received = false;
      MemoryEvent? receivedEvent;

      // Subscribe to typed events
      final subscription = eventSystem.subscribe<MemoryEvent>((event) {
        received = true;
        receivedEvent = event;
      });

      // Publish typed event using publishTyped
      final event = MemoryEvent(
        currentMB: 512,
        thresholdMB: 500,
        peakMB: 600,
      );

      await eventSystem.publishTyped<MemoryEvent>(event);

      // Allow time for event processing
      await Future.delayed(Duration(milliseconds: 10));

      expect(received, isTrue);
      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.currentMB, equals(512));
      expect(receivedEvent!.thresholdMB, equals(500));
      expect(receivedEvent!.peakMB, equals(600));

      // Cleanup
      await eventSystem.unsubscribe(subscription);
    });

    test('should publish and subscribe to topic-based events', () async {
      var received = false;
      Map<String, dynamic>? receivedData;

      // Subscribe to topic
      final subscription =
          await eventSystem.subscribeTopic('test.topic', (data) {
        received = true;
        receivedData = data;
      });

      // Publish to topic
      await eventSystem.publishTopic('test.topic', {
        'message': 'Hello',
        'value': 42,
      });

      // Allow time for event processing
      await Future.delayed(Duration(milliseconds: 10));

      expect(received, isTrue);
      expect(receivedData, isNotNull);
      expect(receivedData!['message'], equals('Hello'));
      expect(receivedData!['value'], equals(42));

      // Cleanup
      await eventSystem.unsubscribe(subscription);
    });

    test('typed and topic-based systems should coexist', () async {
      var typedReceived = false;
      var topicReceived = false;

      // Subscribe to typed event
      final typedSub = eventSystem.subscribe<ServerEvent>((event) {
        typedReceived = true;
      });

      // Subscribe to topic
      final topicSub =
          await eventSystem.subscribeTopic('server.status', (data) {
        topicReceived = true;
      });

      // Publish typed event
      final event = ServerEvent(
        serverId: 'server1',
        status: ServerStatus.running,
      );
      await eventSystem.publish(event);

      // Publish topic event
      await eventSystem.publishTopic('server.status', {
        'serverId': 'server2',
        'status': 'stopped',
      });

      // Allow time for event processing
      await Future.delayed(Duration(milliseconds: 10));

      expect(typedReceived, isTrue);
      expect(topicReceived, isTrue);

      // Cleanup
      await eventSystem.unsubscribe(typedSub);
      await eventSystem.unsubscribe(topicSub);
    });
  });
}
