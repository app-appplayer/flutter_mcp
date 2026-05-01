// Tests DesktopNotificationManager — driven via the standard
// flutter_mcp method-channel mock. Runs on macOS host (where
// Platform.isMacOS=true); Windows/Linux branches of _platformName aren't
// reachable from this host, but every method below routes through the same
// shared code so coverage applies.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/notification/desktop_notification.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart';
import 'package:flutter_mcp/src/config/notification_config.dart' as cfg;
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return; // skip on mobile hosts
  }

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool failConfigure;
  late bool failShow;
  late bool failHide;
  late bool failCancelAll;

  setUp(() {
    calls = [];
    failConfigure = false;
    failShow = false;
    failHide = false;
    failCancelAll = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'configureNotifications':
          if (failConfigure) throw PlatformException(code: 'cfg');
          return true;
        case 'showNotification':
          if (failShow) throw PlatformException(code: 'show');
          return {'success': true};
        case 'cancelNotification':
          if (failHide) throw PlatformException(code: 'hide');
          return true;
        case 'cancelAllNotifications':
          if (failCancelAll) throw PlatformException(code: 'all');
          return true;
        case 'updateNotification':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('DesktopNotificationManager — initialize', () {
    test('initialize without config uses defaults', () async {
      final m = DesktopNotificationManager();
      await m.initialize(null);
      expect(calls.where((c) => c.method == 'configureNotifications'),
          hasLength(1));
      await m.dispose();
    });

    test('initialize with config applies sound/priority/icon', () async {
      final m = DesktopNotificationManager();
      await m.initialize(cfg.NotificationConfig(
        channelId: 'c',
        channelName: 'n',
        enableSound: false,
        priority: cfg.NotificationPriority.high,
        icon: '/i.png',
      ));
      final call = calls.firstWhere((c) => c.method == 'configureNotifications');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['enableSound'], false);
      expect(args['icon'], '/i.png');
      await m.dispose();
    });

    test('initialize wraps native failure as MCPException', () async {
      failConfigure = true;
      final m = DesktopNotificationManager();
      await expectLater(
        m.initialize(null),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('DesktopNotificationManager — show / hide / update', () {
    late DesktopNotificationManager m;
    setUp(() async {
      m = DesktopNotificationManager();
      await m.initialize(null);
      calls.clear();
    });
    tearDown(() async => m.dispose());

    test('showNotification sends complete payload', () async {
      await m.showNotification(
        title: 't',
        body: 'b',
        id: 'n1',
        icon: '/x.png',
        actions: [
          NotificationAction(id: 'a1', title: 'A1'),
        ],
        data: {'k': 'v', 'subtitle': 'sub'},
        showProgress: true,
        progress: 30,
        maxProgress: 100,
        group: 'g',
        image: '/img.png',
        ongoing: true,
      );
      final call = calls.firstWhere((c) => c.method == 'showNotification');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['title'], 't');
      expect(args['body'], 'b');
      expect(args['id'], 'n1');
      expect(args['icon'], '/x.png');
      expect(args['actions'], hasLength(1));
      expect(args['subtitle'], 'sub');
      expect(args['progress'], 30);
      expect(args['ongoing'], true);
      expect(m.isNotificationActive('n1'), isTrue);
      expect(m.activeNotificationCount, 1);
    });

    test('showNotification wraps platform errors as MCPException', () async {
      failShow = true;
      await expectLater(
        m.showNotification(title: 't', body: 'b'),
        throwsA(isA<MCPException>()),
      );
    });

    test('hideNotification removes stored data', () async {
      await m.showNotification(title: 't', body: 'b', id: 'n2');
      expect(m.isNotificationActive('n2'), isTrue);
      await m.hideNotification('n2');
      expect(m.isNotificationActive('n2'), isFalse);
    });

    test('hideNotification wraps platform errors as MCPException', () async {
      await m.showNotification(title: 't', body: 'b', id: 'n3');
      failHide = true;
      await expectLater(
        m.hideNotification('n3'),
        throwsA(isA<MCPException>()),
      );
    });

    test('updateNotification only fires when id is tracked', () async {
      // Untracked id is a silent no-op (does not call channel).
      await m.updateNotification(id: 'absent', title: 'x');
      expect(
        calls.where((c) => c.method == 'updateNotification'),
        isEmpty,
      );
      await m.showNotification(title: 't', body: 'b', id: 'n4');
      calls.clear();
      await m.updateNotification(
        id: 'n4',
        title: 't2',
        body: 'b2',
        progress: 50,
        data: {'k': 'v'},
      );
      expect(calls, hasLength(1));
      expect(calls.first.method, 'updateNotification');
    });

    test('updateNotification swallows native errors', () async {
      // Make the channel throw for updateNotification.
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateNotification') {
          throw PlatformException(code: 'u');
        }
        return true;
      });
      // Pre-track an id by replaying initial config + show inline.
      // Since updateNotification only fires for tracked ids, we need to
      // skip showNotification (it would also throw), so add directly via
      // a separate manager+show on the original handler before swap:
      // Already did the show above; re-track:
      await m.showNotification(title: 't', body: 'b', id: 'pre');
      // Now swap to throw and call update.
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateNotification') {
          throw PlatformException(code: 'u');
        }
        return true;
      });
      await m.updateNotification(id: 'pre', title: 'x'); // should not throw
    });

    test('cancelAllNotifications clears tracking', () async {
      await m.showNotification(title: 't', body: 'b', id: 'a');
      await m.showNotification(title: 't', body: 'b', id: 'b');
      expect(m.activeNotificationCount, 2);
      await m.cancelAllNotifications();
      expect(m.activeNotificationCount, 0);
    });

    test('cancelAllNotifications swallows platform errors', () async {
      failCancelAll = true;
      // Should not throw — error is logged but swallowed.
      await m.cancelAllNotifications();
    });

    test('clearAllNotifications wraps native error as MCPException', () async {
      failCancelAll = true;
      await expectLater(
        m.clearAllNotifications(),
        throwsA(isA<MCPException>()),
      );
    });

    test('cancelNotification delegates to hideNotification', () async {
      await m.showNotification(title: 't', body: 'b', id: 'cn');
      await m.cancelNotification('cn');
      expect(m.isNotificationActive('cn'), isFalse);
    });

    test('requestPermission returns true (desktop has no prompt)', () async {
      expect(await m.requestPermission(), isTrue);
    });

    test('getActiveNotifications maps tracked entries to NotificationInfo',
        () async {
      await m.showNotification(title: 't1', body: 'b1', id: 'a');
      await m.showNotification(title: 't2', body: 'b2', id: 'b');
      final list = m.getActiveNotifications();
      expect(list, hasLength(2));
      expect(list.map((n) => n.id), containsAll(['a', 'b']));
      expect(list.firstWhere((n) => n.id == 'a').title, 't1');
    });
  });

  group('DesktopNotificationManager — click handlers', () {
    test('registerClickHandler/unregisterClickHandler manage the map',
        () async {
      final m = DesktopNotificationManager();
      await m.initialize(null);
      m.registerClickHandler('id1', (id, data) {});
      m.registerClickHandler('default', (id, data) {});
      m.unregisterClickHandler('id1');
      // No public way to read the map; verify no exceptions.
      await m.dispose();
    });
  });
}
