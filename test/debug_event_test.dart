import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('Debug Event System Tests', () {
    late EventSystem eventSystem;

    setUp(() {
      print('Setting up test...');
      eventSystem = EventSystem.instance;
    });

    tearDown(() async {
      print('Tearing down test...');
      try {
        await eventSystem.reset().timeout(Duration(seconds: 5));
        print('Test teardown complete');
      } catch (e) {
        print('Teardown error: $e');
      }
    });

    test('simple event publish test', () async {
      print('Starting simple event publish test');

      bool received = false;

      // Subscribe
      print('Subscribing to events...');
      final subscriptionId = eventSystem.subscribe<ServerEvent>((event) {
        print('Received event: ${event.serverId}');
        received = true;
      });

      print('Subscription created: $subscriptionId');

      // Create test event
      final testEvent = ServerEvent(
        serverId: 'test_server',
        status: ServerStatus.running,
      );

      print('Publishing event...');
      await eventSystem.publishTyped<ServerEvent>(testEvent);

      print('Waiting for event propagation...');
      await Future.delayed(Duration(milliseconds: 100));

      print('Checking if event was received: $received');
      expect(received, isTrue);

      print('Test complete');
    });
  });
}
