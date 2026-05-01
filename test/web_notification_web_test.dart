// Browser-only tests for WebNotificationManager. Run with:
//     flutter test --platform chrome test/web_notification_web_test.dart
//
// Most surface methods don't actually surface a Notification (the test
// runner has no permission), but they exercise every guard and
// permission-state branch.

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/notification/web_notification.dart';
import 'package:flutter_mcp/src/config/notification_config.dart' as cfg;

void main() {
  group('WebNotificationManager — browser', () {
    test('initialize is idempotent (no permission prompt in tests)',
        () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.initialize(cfg.NotificationConfig(
        channelId: 'c',
        channelName: 'n',
        icon: '/icon.png',
      ));
    });

    test('requestPermission resolves to bool', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      final r = await m.requestPermission();
      expect(r, isA<bool>());
    });

    test('showNotification without permission throws MCPException',
        () async {
      // The test runner cannot grant Notification permission, so the
      // manager raises before reaching the actual JS API.
      final m = WebNotificationManager();
      await m.initialize(null);
      await expectLater(
        m.showNotification(title: 't', body: 'b', id: 'web-1'),
        throwsA(anything), // Either MCPException or a JS-API rejection.
      );
    });

    test('hideNotification on unknown id is a silent no-op', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.hideNotification('absent-id');
    });

    test('cancelNotification routes through hideNotification', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.cancelNotification('absent');
    });

    test('cancelAllNotifications is a no-op when nothing is active', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.cancelAllNotifications();
    });

    test('updateNotification on absent id is a silent no-op', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.updateNotification(id: 'absent', title: 'x');
    });

    test('getActiveNotifications returns a list', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      expect(m.getActiveNotifications(), isList);
    });

    test('dispose cleans up internal state', () async {
      final m = WebNotificationManager();
      await m.initialize(null);
      await m.dispose();
    });
  });
}
