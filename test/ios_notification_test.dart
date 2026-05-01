// Pure-Dart smoke coverage for IOSNotificationManager — the class doesn't
// gate on Platform.isIOS, so every public method is reachable from a macOS
// host once the flutter_mcp method channel is mocked.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/notification/ios_notification.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart';
import 'package:flutter_mcp/src/config/notification_config.dart' as cfg;
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool failConfigure;
  late bool failShow;
  late bool failHide;
  late bool failPermission;

  setUp(() {
    calls = [];
    failConfigure = false;
    failShow = false;
    failHide = false;
    failPermission = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'configureNotifications':
          if (failConfigure) throw PlatformException(code: 'cfg');
          return true;
        case 'requestNotificationPermission':
          if (failPermission) throw PlatformException(code: 'perm');
          return true;
        case 'showNotification':
          if (failShow) throw PlatformException(code: 'show');
          return {'success': true};
        case 'cancelNotification':
          if (failHide) throw PlatformException(code: 'hide');
          return true;
        case 'cancelAllNotifications':
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

  group('IOSNotificationManager — initialize', () {
    test('initialize without config uses defaults', () async {
      final m = IOSNotificationManager();
      await m.initialize(null);
      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('configureNotifications'));
      // Permission is intentionally NOT requested during initialize so
      // host apps can defer the system dialog to a UI affordance.
      expect(methods, isNot(contains('requestNotificationPermission')));
      await m.dispose();
    });

    test('initialize with config overrides sound + priority', () async {
      final m = IOSNotificationManager();
      await m.initialize(cfg.NotificationConfig(
        channelId: 'c',
        channelName: 'n',
        enableSound: false,
        priority: cfg.NotificationPriority.high,
      ));
      final args = Map<String, dynamic>.from(calls
          .firstWhere((c) => c.method == 'configureNotifications')
          .arguments as Map);
      expect(args['enableSound'], isFalse);
      await m.dispose();
    });

    test('initialize wraps native errors as MCPException', () async {
      failConfigure = true;
      final m = IOSNotificationManager();
      await expectLater(
        m.initialize(null),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('IOSNotificationManager — show / hide / update', () {
    late IOSNotificationManager m;
    setUp(() async {
      m = IOSNotificationManager();
      await m.initialize(null);
      calls.clear();
    });
    tearDown(() async => m.dispose());

    test('showNotification populates payload + tracks active list', () async {
      await m.showNotification(
        title: 't',
        body: 'b',
        id: 'n1',
        data: {'k': 'v', 'subtitle': 'sub'},
        actions: [NotificationAction(id: 'a', title: 'A')],
        image: '/img.png',
      );
      final args = Map<String, dynamic>.from(
          calls.firstWhere((c) => c.method == 'showNotification').arguments
              as Map);
      expect(args['title'], 't');
      expect(args['body'], 'b');
      expect(args['id'], 'n1');
      expect(args['subtitle'], 'sub');
      expect(args['actions'], hasLength(1));
      expect(args['image'], '/img.png');
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

    test('hideNotification clears tracking', () async {
      await m.showNotification(title: 't', body: 'b', id: 'h1');
      expect(m.isNotificationActive('h1'), isTrue);
      await m.hideNotification('h1');
      expect(m.isNotificationActive('h1'), isFalse);
    });

    test('hideNotification wraps platform errors as MCPException', () async {
      await m.showNotification(title: 't', body: 'b', id: 'h2');
      failHide = true;
      await expectLater(
        m.hideNotification('h2'),
        throwsA(isA<MCPException>()),
      );
    });

    test('updateNotification only fires when id is tracked', () async {
      // Untracked id is a silent no-op.
      await m.updateNotification(id: 'absent', title: 't');
      expect(
        calls.where((c) => c.method == 'updateNotification'),
        isEmpty,
      );
      await m.showNotification(title: 't', body: 'b', id: 'u1');
      calls.clear();
      await m.updateNotification(
        id: 'u1',
        title: 't2',
        body: 'b2',
        progress: 50,
        data: {'k': 'v'},
      );
      expect(calls, hasLength(1));
      expect(calls.first.method, 'updateNotification');
    });

    test('updateNotification swallows native errors', () async {
      await m.showNotification(title: 't', body: 'b', id: 'u2');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateNotification') {
          throw PlatformException(code: 'u');
        }
        return true;
      });
      await m.updateNotification(id: 'u2', title: 'x'); // should not throw
    });

    test('cancelNotification delegates to hideNotification', () async {
      await m.showNotification(title: 't', body: 'b', id: 'c1');
      await m.cancelNotification('c1');
      expect(m.isNotificationActive('c1'), isFalse);
    });

    test('cancelAllNotifications clears tracking', () async {
      await m.showNotification(title: 't', body: 'b', id: 'a');
      await m.showNotification(title: 't', body: 'b', id: 'b');
      await m.cancelAllNotifications();
      expect(m.activeNotificationCount, 0);
    });

    test('clearAllNotifications wraps native errors', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancelAllNotifications') {
          throw PlatformException(code: 'all');
        }
        return true;
      });
      await expectLater(
        m.clearAllNotifications(),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestPermission returns true on success', () async {
      expect(await m.requestPermission(), isTrue);
    });

    test('requestPermission returns false on platform error', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestNotificationPermission') {
          throw PlatformException(code: 'perm');
        }
        return true;
      });
      expect(await m.requestPermission(), isFalse);
    });

    test('getActiveNotifications maps to NotificationInfo entries', () async {
      await m.showNotification(title: 't1', body: 'b1', id: 'a');
      await m.showNotification(title: 't2', body: 'b2', id: 'b');
      final list = m.getActiveNotifications();
      expect(list, hasLength(2));
      expect(list.map((n) => n.id), containsAll(['a', 'b']));
    });
  });

  group('IOSNotificationManager — click handlers', () {
    test('register/unregister are silent', () async {
      final m = IOSNotificationManager();
      await m.initialize(null);
      m.registerClickHandler('id1', (id, data) {});
      m.registerClickHandler('default', (id, data) {});
      m.unregisterClickHandler('id1');
      await m.dispose();
    });
  });
}
