import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/background/background_service.dart';
import 'package:flutter_mcp/src/platform/notification/notification_manager.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart';

void main() {
  group('NoOpBackgroundService', () {
    test('isRunning is always false', () {
      final svc = NoOpBackgroundService();
      expect(svc.isRunning, isFalse);
    });

    test('initialize / start / stop complete safely', () async {
      final svc = NoOpBackgroundService();
      await svc.initialize(null);
      expect(await svc.start(), isFalse);
      expect(await svc.stop(), isFalse);
    });

    test('implements BackgroundService', () {
      expect(NoOpBackgroundService(), isA<BackgroundService>());
    });
  });

  group('NoOpNotificationManager', () {
    final m = NoOpNotificationManager();

    test('initialize completes silently', () async {
      await m.initialize(null);
    });

    test('showNotification completes silently', () async {
      await m.showNotification(
        title: 'T',
        body: 'B',
      );
      await m.showNotification(
        title: 'T',
        body: 'B',
        icon: 'i',
        id: 'n1',
        data: const {'k': 'v'},
        actions: const [NotificationAction(id: 'a', title: 'A')],
        channelId: 'ch',
        priority: NotificationPriority.high,
        showProgress: true,
        progress: 50,
        maxProgress: 100,
        group: 'g',
        image: 'img',
        ongoing: true,
      );
    });

    test('requestPermission returns false', () async {
      expect(await m.requestPermission(), isFalse);
    });

    test('cancelNotification / cancelAllNotifications complete silently',
        () async {
      await m.cancelNotification('n1');
      await m.cancelAllNotifications();
    });

    test('updateNotification completes silently', () async {
      await m.updateNotification(id: 'n1');
      await m.updateNotification(
        id: 'n1',
        title: 't',
        body: 'b',
        progress: 30,
        data: const {'a': 1},
      );
    });

    test('getActiveNotifications returns empty list', () {
      expect(m.getActiveNotifications(), isEmpty);
    });

    test('hideNotification completes silently', () async {
      await m.hideNotification('n1');
    });

    test('dispose completes silently', () async {
      await m.dispose();
    });

    test('implements NotificationManager', () {
      expect(NoOpNotificationManager(), isA<NotificationManager>());
    });
  });
}
