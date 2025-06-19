import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';

void main() {
  group('Legacy Event System Tests', () {
    late EventSystem eventSystem;

    setUp(() {
      eventSystem = EventSystem.instance;
    });

    tearDown(() async {
      await eventSystem.reset();
    });

    test('simple legacy event publish test', () async {
      bool received = false;

      // Subscribe using legacy API
      final subscriptionId =
          await eventSystem.subscribeTopic('test.event', (event) {
        received = true;
      });

      // Publish using legacy API
      eventSystem.publishTopic('test.event', {'test': 'data'});

      // Wait for event propagation
      await Future.delayed(Duration(milliseconds: 10));

      expect(received, isTrue);

      // Unsubscribe
      await eventSystem.unsubscribe(subscriptionId);
    });
  });
}
