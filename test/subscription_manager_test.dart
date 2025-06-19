import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/subscription_manager.dart';
import 'dart:async';

void main() {
  group('SubscriptionManager Tests', () {
    late SubscriptionManager subscriptionManager;

    setUp(() async {
      subscriptionManager = SubscriptionManager.instance;
      // Clear any existing subscriptions before each test
      await subscriptionManager.clearAll();
    });

    tearDown(() async {
      await subscriptionManager.clearAll();
    });

    test('should track and untrack subscriptions', () async {
      final controller = StreamController<String>();
      final subscription = controller.stream.listen((_) {});

      // Track subscription
      subscriptionManager.trackSubscription('test-token-1', subscription);

      // Get info
      final infos = await subscriptionManager.getAllActive();
      expect(infos.length, equals(1));
      expect(infos.first.token, equals('test-token-1'));
      expect(infos.first.source, equals('EventSystem'));

      // Untrack subscription
      subscriptionManager.untrackSubscription('test-token-1');

      // Verify removed
      await Future.delayed(Duration(milliseconds: 10));
      final remainingInfos = await subscriptionManager.getAllActive();
      expect(remainingInfos.length, equals(0));

      // Clean up
      subscription.cancel();
      controller.close();
    });

    test('should register subscriptions with metadata', () async {
      final controller = StreamController<int>();
      final subscription = controller.stream.listen((_) {});

      // Register with metadata
      final token = await subscriptionManager.register(
        subscription: subscription,
        source: 'TestSource',
        description: 'Test subscription',
        autoCleanup: false,
      );

      expect(token, isNotNull);
      expect(token, startsWith('sub_'));

      // Get info
      final info = await subscriptionManager.getInfo(token);
      expect(info, isNotNull);
      expect(info!.source, equals('TestSource'));
      expect(info.description, equals('Test subscription'));

      // Unregister
      await subscriptionManager.unregister(token);

      // Clean up
      controller.close();
    });

    test('should handle multiple subscriptions from same source', () async {
      final controllers = <StreamController>[];
      final tokens = <String>[];

      // Create multiple subscriptions
      for (int i = 0; i < 5; i++) {
        final controller = StreamController<int>();
        controllers.add(controller);

        final subscription = controller.stream.listen((_) {});
        final token = await subscriptionManager.register(
          subscription: subscription,
          source: 'MultiSource',
          description: 'Subscription $i',
        );
        tokens.add(token);
      }

      // Verify all registered
      final allSubs = await subscriptionManager.getAllActive();
      final sourceSubs =
          allSubs.where((s) => s.source == 'MultiSource').toList();
      expect(sourceSubs.length, equals(5));

      // Unregister by source
      await subscriptionManager.unregisterBySource('MultiSource');

      // Verify all removed
      final remainingAll = await subscriptionManager.getAllActive();
      final remaining =
          remainingAll.where((s) => s.source == 'MultiSource').toList();
      expect(remaining.length, equals(0));

      // Clean up
      for (final controller in controllers) {
        controller.close();
      }
    });

    test('should cleanup old subscriptions', () async {
      final controller1 = StreamController<String>();
      final controller2 = StreamController<String>();

      // Register subscriptions
      final token1 = await subscriptionManager.register(
        subscription: controller1.stream.listen((_) {}),
        source: 'CleanupTest',
        description: 'Old subscription',
      );

      // Wait a bit
      await Future.delayed(Duration(milliseconds: 100));

      final token2 = await subscriptionManager.register(
        subscription: controller2.stream.listen((_) {}),
        source: 'CleanupTest',
        description: 'New subscription',
      );

      // Cleanup subscriptions older than 50ms
      final cleaned = await subscriptionManager.cleanup(
        maxAge: Duration(milliseconds: 50),
      );

      expect(cleaned, equals(1)); // Only token1 should be cleaned

      // Verify token2 still exists
      final info2 = await subscriptionManager.getInfo(token2);
      expect(info2, isNotNull);

      // Verify token1 is gone
      final info1 = await subscriptionManager.getInfo(token1);
      expect(info1, isNull);

      // Clean up
      await subscriptionManager.clearAll();
      controller1.close();
      controller2.close();
    });

    test('should track statistics', () async {
      final controllers = <StreamController>[];

      // Create and register some subscriptions
      for (int i = 0; i < 3; i++) {
        final controller = StreamController<int>();
        controllers.add(controller);

        await subscriptionManager.register(
          subscription: controller.stream.listen((_) {}),
          source: 'StatsTest',
        );
      }

      // Get statistics
      final stats = await subscriptionManager.getStatistics();

      expect(stats.totalCreated, greaterThanOrEqualTo(3));
      expect(stats.totalActive, equals(3));
      expect(stats.bySource['StatsTest'], equals(3));

      // Clean up
      await subscriptionManager.clearAll();

      // Verify cleanup stats
      final finalStats = await subscriptionManager.getStatistics();
      expect(finalStats.totalActive, equals(0));
      expect(finalStats.totalDisposed, greaterThanOrEqualTo(3));

      // Clean up controllers
      for (final controller in controllers) {
        controller.close();
      }
    });

    test('should handle subscription that completes', () async {
      final controller = StreamController<String>();

      // Register subscription
      final subscription = controller.stream.listen((_) {});
      final token = await subscriptionManager.register(
        subscription: subscription,
        source: 'CompleteTest',
        autoCleanup: true,
      );

      // Verify registered
      var info = await subscriptionManager.getInfo(token);
      expect(info, isNotNull);

      // Close stream (triggers onDone)
      await controller.close();

      // Give time for cleanup
      await Future.delayed(Duration(milliseconds: 10));

      // Verify auto-cleaned due to onDone
      info = await subscriptionManager.getInfo(token);
      expect(info, isNull);
    });

    test('concurrent operations should be thread-safe', () async {
      final futures = <Future<Map<String, dynamic>>>[];

      // Concurrent registrations
      for (int i = 0; i < 20; i++) {
        final index = i;
        futures.add(Future(() async {
          final controller = StreamController<int>();
          final subscription = controller.stream.listen((_) {});

          final token = await subscriptionManager.register(
            subscription: subscription,
            source: 'ConcurrentTest',
            description: 'Sub $index',
          );

          // Simulate some work
          await Future.delayed(Duration(milliseconds: 5));

          // Sometimes unregister immediately
          bool wasUnregistered = false;
          if (index % 3 == 0) {
            await subscriptionManager.unregister(token);
            wasUnregistered = true;
          }

          return {'controller': controller, 'unregistered': wasUnregistered};
        }));
      }

      final results = await Future.wait(futures);
      final unregisteredCount =
          results.where((r) => r['unregistered'] as bool).length;
      final expectedActive = 20 - unregisteredCount;

      // Verify correct number of active subscriptions before closing controllers
      final active = await subscriptionManager.getAllActive();
      final concurrentActive =
          active.where((s) => s.source == 'ConcurrentTest').length;
      expect(concurrentActive, equals(expectedActive));

      // Now close all controllers
      for (final result in results) {
        final controller = result['controller'] as StreamController;
        await controller.close();
      }

      // Clean up remaining
      await subscriptionManager.clearAll();
    });
  });
}
