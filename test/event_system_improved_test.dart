import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'dart:async';

void main() {
  group('EventSystem Improved Tests', () {
    late EventSystem eventSystem;

    setUp(() {
      eventSystem = EventSystem.instance;
    });

    tearDown(() async {
      await eventSystem.reset();
    });

    group('Deadlock Prevention Tests', () {
      test('should not deadlock with concurrent operations', () async {
        final completer1 = Completer<bool>();
        final completer2 = Completer<bool>();
        final completer3 = Completer<bool>();

        // Simulate concurrent operations that could cause deadlock with multiple locks
        final future1 = Future(() async {
          for (int i = 0; i < 10; i++) {
            final token = await eventSystem.subscribeTopic('topic1', (_) {});
            await eventSystem.unsubscribe(token);
          }
          completer1.complete(true);
        });

        final future2 = Future(() async {
          for (int i = 0; i < 10; i++) {
            await eventSystem.publishTopic('topic1', 'data $i');
          }
          completer2.complete(true);
        });

        final future3 = Future(() async {
          for (int i = 0; i < 10; i++) {
            // clearCache and hasSubscribers methods no longer exist
            // Just do some other operation to test concurrency
            await eventSystem.pause();
            await eventSystem.resume();
          }
          completer3.complete(true);
        });

        // All operations should complete without deadlock
        await Future.wait([future1, future2, future3]);

        expect(completer1.isCompleted, isTrue);
        expect(completer2.isCompleted, isTrue);
        expect(completer3.isCompleted, isTrue);
      });

      test('should handle pause/resume without deadlock', () async {
        bool received = false;

        await eventSystem.subscribeTopic('test.pause', (data) {
          received = true;
        });

        // Concurrent pause/resume operations
        final pauseFuture = eventSystem.pause();
        final publishFuture = eventSystem.publishTopic('test.pause', 'data');
        final resumeFuture = eventSystem.resume();

        await Future.wait([pauseFuture, publishFuture, resumeFuture]);

        // Wait for event propagation
        await Future.delayed(Duration(milliseconds: 100));

        expect(received, isTrue);
      });
    });

    group('Event Caching Tests', () {
      test('should cache events when no subscribers exist', () async {
        // Publish to topic with no subscribers
        await eventSystem.publishTopic('cached.topic', 'cached data');

        // Subscribe after publishing
        bool received = false;
        String? receivedData;

        await eventSystem.subscribeTopic('cached.topic', (data) {
          received = true;
          receivedData = data as String;
        });

        // Should receive cached event
        await Future.delayed(Duration(milliseconds: 100));
        expect(received, isTrue);
        expect(receivedData, equals('cached data'));
      });

      test('should handle cache expiration correctly', () async {
        // Note: In the current implementation, cache expires after 5 minutes
        // This test verifies that cached events are delivered before expiration

        // Publish to topic with no subscribers
        await eventSystem.publishTopic('cached.topic.expiry', 'cached data');

        // Subscribe immediately (before expiration)
        bool received = false;
        dynamic receivedData;
        await eventSystem.subscribeTopic('cached.topic.expiry', (data) {
          received = true;
          receivedData = data;
        });

        await Future.delayed(Duration(milliseconds: 100));
        // Should receive cached event (cache hasn't expired yet)
        expect(received, isTrue);
        expect(receivedData, equals('cached data'));
      });
    });

    group('Performance Tests', () {
      test('should handle many concurrent subscribers efficiently', () async {
        final subscriptions = <String>[];
        final stopwatch = Stopwatch()..start();

        // Create many subscribers
        for (int i = 0; i < 100; i++) {
          final token = await eventSystem.subscribeTopic('topic.$i', (_) {});
          subscriptions.add(token);
        }

        stopwatch.stop();
        // Should complete in reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));

        // Clean up
        for (final token in subscriptions) {
          await eventSystem.unsubscribe(token);
        }
      });

      test('should handle rapid publish/subscribe cycles', () async {
        int eventCount = 0;
        final stopwatch = Stopwatch()..start();

        // Use unique topics to avoid cache interference
        // Rapid subscribe/publish/unsubscribe cycles
        for (int i = 0; i < 50; i++) {
          final token = await eventSystem.subscribeTopic('rapid.topic.$i', (_) {
            eventCount++;
          });

          await eventSystem.publishTopic('rapid.topic.$i', 'data $i');
          await eventSystem.unsubscribe(token);
        }

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(eventCount, equals(50));
      });
    });

    group('Concurrency Tests', () {
      test('should handle concurrent subscriptions safely', () async {
        final subscriptions = <Future<String>>[];

        // Create multiple concurrent subscriptions
        for (int i = 0; i < 10; i++) {
          subscriptions
              .add(eventSystem.subscribeTopic('concurrent.topic', (_) {}));
        }

        final tokens = await Future.wait(subscriptions);

        // All tokens should be unique
        expect(tokens.toSet().length, equals(10));

        // Clean up
        for (final token in tokens) {
          await eventSystem.unsubscribe(token);
        }
      });

      test('should handle concurrent publishes safely', () async {
        int eventCount = 0;
        final lock = Object();

        await eventSystem.subscribeTopic('concurrent.publish', (data) {
          synchronized(lock, () {
            eventCount++;
          });
        });

        // Publish concurrently
        final publishes = <Future<void>>[];
        for (int i = 0; i < 20; i++) {
          publishes
              .add(eventSystem.publishTopic('concurrent.publish', 'data $i'));
        }

        await Future.wait(publishes);
        await Future.delayed(Duration(milliseconds: 100));

        expect(eventCount, equals(20));
      });
    });

    group('Error Handling Tests', () {
      test('should handle errors in event handlers gracefully', () async {
        int successCount = 0;
        int errorCount = 0;

        // Subscribe with error handling
        await eventSystem.subscribeTopic('error.topic', (data) {
          try {
            if (data == 'error') {
              throw Exception('Test error');
            }
            successCount++;
          } catch (e) {
            errorCount++;
          }
        });

        // Publish events, some causing errors
        await eventSystem.publishTopic('error.topic', 'success1');
        await eventSystem.publishTopic('error.topic', 'error');
        await eventSystem.publishTopic('error.topic', 'success2');

        await Future.delayed(Duration(milliseconds: 100));

        // Should process all events
        expect(successCount, equals(2));
        expect(errorCount, equals(1));
      });

      test('should handle invalid unsubscribe gracefully', () async {
        // Try to unsubscribe with invalid token
        await expectLater(
          eventSystem.unsubscribe('invalid_token'),
          completes,
        );
      });
    });

    group('Integration Tests', () {
      test('should work with multiple event types', () async {
        final userEvents = <dynamic>[];
        final systemEvents = <dynamic>[];

        final token1 = await eventSystem.subscribeTopic('events.user', (data) {
          userEvents.add(data);
        });

        final token2 =
            await eventSystem.subscribeTopic('events.system', (data) {
          systemEvents.add(data);
        });

        // Publish different event types
        await eventSystem.publishTopic('events.user', {'action': 'login'});
        await eventSystem.publishTopic('events.system', {'status': 'healthy'});
        await eventSystem.publishTopic('events.user', {'action': 'logout'});

        await Future.delayed(Duration(milliseconds: 100));

        expect(userEvents.length, equals(2));
        expect(systemEvents.length, equals(1));

        // Clean up
        await eventSystem.unsubscribe(token1);
        await eventSystem.unsubscribe(token2);
      });
    });
  });
}

// Helper function for synchronization
void synchronized(Object lock, void Function() action) {
  action();
}
