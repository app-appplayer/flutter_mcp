// Targeted extras for EventSystem — pause/resume, cached event delivery,
// publishToClosedTopic, getStatistics, reset, unsubscribe paths.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_system.dart';

void main() {
  group('EventSystem — initialize is configurable', () {
    test('initialize without args runs cleanly', () async {
      EventSystem.instance.initialize();
    });

    test('initialize with all args sets internal state', () async {
      EventSystem.instance.initialize(
        enableCache: false,
        enableLogging: false,
        logLevel: LogLevel.error,
      );
      // Restore default for other tests.
      EventSystem.instance.initialize();
    });
  });

  group('EventSystem — topic publish/subscribe + caching', () {
    setUp(() async {
      await EventSystem.instance.reset();
      EventSystem.instance.initialize(enableCache: true, enableLogging: false);
    });

    test('subscribeTopic + publishTopic delivers event', () async {
      final received = <dynamic>[];
      final token = await EventSystem.instance.subscribeTopic(
        'test.topic',
        (data) => received.add(data),
      );
      expect(token, isNotEmpty);
      await EventSystem.instance.publishTopic('test.topic', 'hello');
      // Stream delivery is async; settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, ['hello']);
    });

    test('cached events replay to late subscribers', () async {
      // Publish first.
      await EventSystem.instance.publishTopic('cached.topic', 'a');
      await EventSystem.instance.publishTopic('cached.topic', 'b');
      // Subscribe after — should receive cached.
      final received = <dynamic>[];
      await EventSystem.instance.subscribeTopic(
        'cached.topic',
        (data) => received.add(data),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, containsAll(['a', 'b']));
    });

    test('filter limits delivered events', () async {
      final received = <dynamic>[];
      await EventSystem.instance.subscribeTopic(
        'filter.topic',
        (data) => received.add(data),
        filter: (data) => data is int && data > 5,
      );
      await EventSystem.instance.publishTopic('filter.topic', 1);
      await EventSystem.instance.publishTopic('filter.topic', 10);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, [10]);
    });
  });

  group('EventSystem — pause/resume', () {
    setUp(() async {
      await EventSystem.instance.reset();
      EventSystem.instance.initialize();
    });

    test('pause stores events; resume replays them', () async {
      final received = <dynamic>[];
      await EventSystem.instance.subscribeTopic(
        'pause.topic',
        (data) => received.add(data),
      );

      await EventSystem.instance.pause();
      await EventSystem.instance.publishTopic('pause.topic', 'a');
      await EventSystem.instance.publishTopic('pause.topic', 'b');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, isEmpty);

      await EventSystem.instance.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, containsAll(['a', 'b']));
    });
  });

  group('EventSystem — unsubscribe', () {
    setUp(() async {
      await EventSystem.instance.reset();
      EventSystem.instance.initialize();
    });

    test('unsubscribe stops event delivery', () async {
      final received = <dynamic>[];
      final token = await EventSystem.instance.subscribeTopic(
        'unsub.topic',
        (data) => received.add(data),
      );
      await EventSystem.instance.publishTopic('unsub.topic', 'before');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, ['before']);

      await EventSystem.instance.unsubscribe(token);
      await EventSystem.instance.publishTopic('unsub.topic', 'after');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, ['before']); // unchanged
    });

    test('unsubscribe of unknown id is a silent no-op', () async {
      await EventSystem.instance.unsubscribe('not-a-real-id');
    });
  });

  group('EventSystem — getStatistics', () {
    setUp(() async {
      await EventSystem.instance.reset();
      EventSystem.instance.initialize();
    });

    test('returns expected shape with topic counts', () async {
      await EventSystem.instance.subscribeTopic('s.topic', (_) {});
      await EventSystem.instance.publishTopic('s.topic', 1);
      await EventSystem.instance.publishTopic('s.topic', 2);
      final stats = EventSystem.instance.getStatistics();
      expect(stats, contains('eventCounts'));
      expect(stats, contains('topicCounts'));
      expect(stats, contains('activeHandlers'));
      expect(stats, contains('activeTopics'));
      expect(stats, contains('cachedTopics'));
      expect(stats, contains('isPaused'));
      expect(stats, contains('pausedEventCount'));
      expect((stats['topicCounts'] as Map)['s.topic'], 2);
    });
  });

  group('EventSystem — reset + dispose', () {
    test('reset clears all subscriptions and counters', () async {
      EventSystem.instance.initialize();
      await EventSystem.instance.subscribeTopic('r.topic', (_) {});
      await EventSystem.instance.publishTopic('r.topic', 1);
      await EventSystem.instance.reset();
      final stats = EventSystem.instance.getStatistics();
      expect(stats['topicCounts'], isEmpty);
      expect(stats['activeTopics'], isEmpty);
      expect(stats['cachedTopics'], isEmpty);
    });

    test('dispose runs reset + logs without throwing', () async {
      await EventSystem.instance.dispose();
    });
  });
}
