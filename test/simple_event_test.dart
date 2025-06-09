import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';

void main() {
  group('Simple Event System Tests', () {
    test('basic publish and subscribe', () async {
      final eventSystem = EventSystem.instance;
      bool received = false;
      
      // Subscribe to a topic
      final token = eventSystem.subscribe<String>('test.topic', (data) {
        received = true;
        expect(data, equals('test data'));
      });
      
      // Publish to the topic
      eventSystem.publish('test.topic', 'test data');
      
      // Wait briefly for async propagation
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(received, isTrue);
      
      // Clean up
      eventSystem.unsubscribe(token);
      await eventSystem.reset();
    });
  });
}