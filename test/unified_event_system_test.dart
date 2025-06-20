import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

// Test event types
class TestEvent extends Event {
  final String message;
  final int value;

  TestEvent({required this.message, required this.value, DateTime? timestamp})
      : super(timestamp: timestamp);

  String get eventType => 'test.event';

  Map<String, dynamic> toMap() => {
        'message': message,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
      };
}

class AnotherTestEvent extends Event {
  final String data;

  AnotherTestEvent({required this.data, DateTime? timestamp})
      : super(timestamp: timestamp);

  String get eventType => 'test.another';

  Map<String, dynamic> toMap() => {
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}

void main() {
  group('Event System Tests', () {
    late EventSystem eventSystem;

    setUp(() async {
      eventSystem = EventSystem.instance;
      await eventSystem.reset();
    });

    tearDown(() async {
      await eventSystem.reset();
    });

    test('should handle typed events correctly', () async {
      final receivedEvents = <TestEvent>[];

      // Subscribe to typed events
      eventSystem.subscribe<TestEvent>((event) {
        receivedEvents.add(event);
      });

      // Publish typed event
      final testEvent = TestEvent(message: 'Hello', value: 42);
      await eventSystem.publish(testEvent);

      // Allow event to propagate
      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedEvents.length, equals(1));
      expect(receivedEvents.first.message, equals('Hello'));
      expect(receivedEvents.first.value, equals(42));
    });

    test('should handle topic-based events', () async {
      final receivedData = <Map<String, dynamic>>[];

      // Subscribe to topic
      await eventSystem.subscribeTopic('test.topic', (data) {
        receivedData.add(data as Map<String, dynamic>);
      });

      // Publish to topic
      await eventSystem.publishTopic('test.topic', {'hello': 'world'});

      // Allow event to propagate
      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData.length, equals(1));
      expect(receivedData.first['hello'], equals('world'));
    });

    test('should support multiple event types', () async {
      final testEvents = <TestEvent>[];
      final anotherEvents = <AnotherTestEvent>[];

      // Subscribe to different event types
      eventSystem.subscribe<TestEvent>((event) {
        testEvents.add(event);
      });

      eventSystem.subscribe<AnotherTestEvent>((event) {
        anotherEvents.add(event);
      });

      // Publish different event types
      await eventSystem.publish(TestEvent(message: 'Test', value: 1));
      await eventSystem.publish(AnotherTestEvent(data: 'Another'));

      // Allow events to propagate
      await Future.delayed(Duration(milliseconds: 10));

      expect(testEvents.length, equals(1));
      expect(anotherEvents.length, equals(1));
      expect(testEvents.first.message, equals('Test'));
      expect(anotherEvents.first.data, equals('Another'));
    });

    test('should handle unsubscription correctly', () async {
      final receivedEvents = <TestEvent>[];

      // Subscribe
      final subscriptionId = eventSystem.subscribe<TestEvent>((event) {
        receivedEvents.add(event);
      });

      // Publish first event
      await eventSystem.publish(TestEvent(message: 'First', value: 1));
      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedEvents.length, equals(1));

      // Unsubscribe
      await eventSystem.unsubscribe(subscriptionId);

      // Publish second event
      await eventSystem.publish(TestEvent(message: 'Second', value: 2));
      await Future.delayed(Duration(milliseconds: 10));

      // Should still have only 1 event
      expect(receivedEvents.length, equals(1));
    });
  });
}
