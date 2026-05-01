import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart';

void main() {
  group('NotificationPriority enum', () {
    test('exposes all four levels with stable ordering', () {
      expect(NotificationPriority.values, hasLength(4));
      expect(NotificationPriority.low.index, 0);
      expect(NotificationPriority.normal.index, 1);
      expect(NotificationPriority.high.index, 2);
      expect(NotificationPriority.critical.index, 3);
    });
  });

  group('NotificationAction', () {
    test('toMap with all fields', () {
      const a = NotificationAction(
        id: 'a1',
        title: 'Yes',
        icon: '/i.png',
        requiresInput: true,
        inputPlaceholder: 'reply',
      );
      expect(a.toMap(), {
        'id': 'a1',
        'title': 'Yes',
        'icon': '/i.png',
        'requiresInput': true,
        'inputPlaceholder': 'reply',
      });
    });

    test('toMap with optional fields null/false defaults', () {
      const a = NotificationAction(id: 'a', title: 'A');
      final map = a.toMap();
      expect(map['id'], 'a');
      expect(map['title'], 'A');
      expect(map['icon'], isNull);
      expect(map['requiresInput'], isFalse);
      expect(map['inputPlaceholder'], isNull);
    });

    test('fromMap roundtrip', () {
      const original = NotificationAction(
        id: 'x',
        title: 'X',
        icon: '/i',
        requiresInput: true,
      );
      final restored = NotificationAction.fromMap(original.toMap());
      expect(restored.id, 'x');
      expect(restored.title, 'X');
      expect(restored.icon, '/i');
      expect(restored.requiresInput, isTrue);
      expect(restored.inputPlaceholder, isNull);
    });

    test('fromMap defaults requiresInput when missing', () {
      final a = NotificationAction.fromMap({'id': 'a', 'title': 't'});
      expect(a.requiresInput, isFalse);
    });
  });

  group('NotificationInfo', () {
    test('default constructor + toMap', () {
      final shown = DateTime(2026, 5, 1);
      final info = NotificationInfo(
        id: 'n1',
        title: 'T',
        body: 'B',
        shownAt: shown,
        data: {'k': 'v'},
      );
      final map = info.toMap();
      expect(map['id'], 'n1');
      expect(map['title'], 'T');
      expect(map['body'], 'B');
      expect(map['shownAt'], shown.toIso8601String());
      expect(map['data'], {'k': 'v'});
    });

    test('default data is empty map', () {
      final info = NotificationInfo(
        id: 'n1',
        title: 'T',
        body: 'B',
        shownAt: DateTime(2026),
      );
      expect(info.data, isEmpty);
    });

    test('fromMap roundtrip', () {
      final shown = DateTime(2026, 5, 1, 12, 30);
      final original = NotificationInfo(
        id: 'n1',
        title: 'T',
        body: 'B',
        shownAt: shown,
        data: {'a': 1},
      );
      final restored = NotificationInfo.fromMap(original.toMap());
      expect(restored.id, 'n1');
      expect(restored.shownAt, shown);
      expect(restored.data, {'a': 1});
    });

    test('fromMap with missing data normalizes to empty', () {
      final shown = DateTime(2026);
      final restored = NotificationInfo.fromMap({
        'id': 'n',
        'title': 'T',
        'body': 'B',
        'shownAt': shown.toIso8601String(),
      });
      expect(restored.data, isEmpty);
    });
  });

  group('ScheduledNotificationInfo', () {
    test('toMap + fromMap roundtrip with all fields', () {
      final created = DateTime(2026);
      final scheduled = DateTime(2026, 5, 1, 9);
      final original = ScheduledNotificationInfo(
        id: 's1',
        title: 'T',
        body: 'B',
        icon: '/i.png',
        priority: NotificationPriority.high,
        actions: const [
          NotificationAction(id: 'a1', title: 'A1'),
          NotificationAction(id: 'a2', title: 'A2', requiresInput: true),
        ],
        imageUrl: 'https://x/y.png',
        progress: 50,
        groupKey: 'g1',
        data: {'k': 1},
        scheduledTime: scheduled,
        repeatInterval: const Duration(hours: 1),
        createdAt: created,
      );
      final restored = ScheduledNotificationInfo.fromMap(original.toMap());
      expect(restored.id, 's1');
      expect(restored.title, 'T');
      expect(restored.body, 'B');
      expect(restored.icon, '/i.png');
      expect(restored.priority, NotificationPriority.high);
      expect(restored.actions, hasLength(2));
      expect(restored.actions[1].requiresInput, isTrue);
      expect(restored.imageUrl, 'https://x/y.png');
      expect(restored.progress, 50);
      expect(restored.groupKey, 'g1');
      expect(restored.data, {'k': 1});
      expect(restored.scheduledTime, scheduled);
      expect(restored.repeatInterval, const Duration(hours: 1));
      expect(restored.createdAt, created);
    });

    test('default priority is normal and actions/data empty', () {
      final info = ScheduledNotificationInfo(
        id: 's',
        title: 't',
        scheduledTime: DateTime(2026),
        createdAt: DateTime(2026),
      );
      expect(info.priority, NotificationPriority.normal);
      expect(info.actions, isEmpty);
      expect(info.data, isEmpty);
      expect(info.repeatInterval, isNull);
    });

    test('fromMap defaults priority to normal when missing', () {
      final restored = ScheduledNotificationInfo.fromMap({
        'id': 's',
        'title': 't',
        'scheduledTime': DateTime(2026).toIso8601String(),
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(restored.priority, NotificationPriority.normal);
      expect(restored.actions, isEmpty);
      expect(restored.repeatInterval, isNull);
    });
  });

  group('NotificationCapabilities', () {
    test('toMap reflects all flags', () {
      const c = NotificationCapabilities(
        actions: true,
        images: false,
        progress: true,
        grouping: false,
        scheduling: true,
      );
      expect(c.toMap(), {
        'actions': true,
        'images': false,
        'progress': true,
        'grouping': false,
        'scheduling': true,
      });
    });

    test('fromMap with missing keys defaults to false', () {
      final c = NotificationCapabilities.fromMap({});
      expect(c.actions, isFalse);
      expect(c.images, isFalse);
      expect(c.progress, isFalse);
      expect(c.grouping, isFalse);
      expect(c.scheduling, isFalse);
    });

    test('fromMap roundtrip', () {
      const original = NotificationCapabilities(
        actions: true,
        images: true,
        progress: false,
        grouping: true,
        scheduling: false,
      );
      final restored = NotificationCapabilities.fromMap(original.toMap());
      expect(restored.actions, isTrue);
      expect(restored.images, isTrue);
      expect(restored.progress, isFalse);
      expect(restored.grouping, isTrue);
      expect(restored.scheduling, isFalse);
    });
  });

  group('Notification event payloads (constructor smoke + field reads)', () {
    test('NotificationInitializedEvent', () {
      final e = NotificationInitializedEvent(
        platform: 'macos',
        capabilities: const NotificationCapabilities(
          actions: true,
          images: false,
          progress: false,
          grouping: false,
          scheduling: false,
        ),
      );
      expect(e.platform, 'macos');
      expect(e.capabilities.actions, isTrue);
    });

    test('NotificationScheduledEvent', () {
      final t = DateTime(2026);
      final e = NotificationScheduledEvent(
        id: 'n', title: 'T', scheduledTime: t,
        repeatInterval: const Duration(minutes: 1),
      );
      expect(e.id, 'n');
      expect(e.scheduledTime, t);
      expect(e.repeatInterval, const Duration(minutes: 1));
    });

    test('ScheduledNotificationShownEvent', () {
      final t = DateTime(2026);
      final t2 = t.add(const Duration(seconds: 2));
      final e = ScheduledNotificationShownEvent(
        id: 'n', scheduledTime: t, actualTime: t2,
      );
      expect(e.scheduledTime, t);
      expect(e.actualTime, t2);
    });

    test('NotificationShownEvent', () {
      final e = NotificationShownEvent(
        id: 'n', title: 'T', body: 'B',
        priority: NotificationPriority.high,
      );
      expect(e.priority, NotificationPriority.high);
    });

    test('NotificationClickedEvent', () {
      final e = NotificationClickedEvent(
        id: 'n', actionId: 'a', data: {'x': 1},
      );
      expect(e.actionId, 'a');
      expect(e.data, {'x': 1});
    });

    test('NotificationDismissedEvent', () {
      final e = NotificationDismissedEvent(id: 'n');
      expect(e.id, 'n');
    });

    test('NotificationActionEvent', () {
      final e = NotificationActionEvent(
        id: 'n', actionId: 'a', data: {},
      );
      expect(e.id, 'n');
      expect(e.actionId, 'a');
    });

    test('NotificationCancelledEvent', () {
      final e = NotificationCancelledEvent(
        id: 'n', title: 'T', wasScheduled: true,
      );
      expect(e.wasScheduled, isTrue);
    });

    test('AllNotificationsCancelledEvent', () {
      final e = AllNotificationsCancelledEvent(
        count: 5, includesScheduled: false,
      );
      expect(e.count, 5);
      expect(e.includesScheduled, isFalse);
    });

    test('NotificationUpdatedEvent', () {
      final e = NotificationUpdatedEvent(
        id: 'n', title: 'T', body: 'B', progress: 50,
      );
      expect(e.title, 'T');
      expect(e.progress, 50);
    });
  });
}
