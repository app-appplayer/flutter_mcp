// Smoke coverage for AndroidNotificationManager — class is reachable on
// non-Android hosts because the only Platform.isAndroid gate is in
// requestPermission(); all other methods exercise the standard channel.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/notification/android_notification.dart';
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
        case 'requestNotificationPermission':
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
        case 'getAndroidSdkVersion':
          return 30; // pre-13 → no permission prompt
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('AndroidNotificationManager — initialize', () {
    test('initialize without config uses defaults', () async {
      final m = AndroidNotificationManager();
      await m.initialize(null);
      expect(calls.map((c) => c.method), contains('configureNotifications'));
      await m.dispose();
    });

    test('initialize with config applies channel + sound + vibration', () async {
      final m = AndroidNotificationManager();
      await m.initialize(cfg.NotificationConfig(
        channelId: 'cid',
        channelName: 'cn',
        channelDescription: 'cd',
        enableSound: false,
        enableVibration: false,
        priority: cfg.NotificationPriority.high,
        icon: '/i.png',
      ));
      final args = Map<String, dynamic>.from(calls
          .firstWhere((c) => c.method == 'configureNotifications')
          .arguments as Map);
      expect(args['channelId'], 'cid');
      expect(args['channelName'], 'cn');
      expect(args['channelDescription'], 'cd');
      expect(args['enableSound'], isFalse);
      expect(args['enableVibration'], isFalse);
      expect(args['icon'], '/i.png');
      await m.dispose();
    });

    test('initialize wraps native errors as MCPException', () async {
      failConfigure = true;
      final m = AndroidNotificationManager();
      await expectLater(
        m.initialize(null),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('AndroidNotificationManager — show / hide / update', () {
    late AndroidNotificationManager m;
    setUp(() async {
      m = AndroidNotificationManager();
      await m.initialize(null);
      calls.clear();
    });
    tearDown(() async => m.dispose());

    test('showNotification populates payload + tracks active', () async {
      await m.showNotification(
        title: 't',
        body: 'b',
        id: 'n1',
        data: {'k': 'v'},
        actions: [NotificationAction(id: 'a', title: 'A')],
        showProgress: true,
        progress: 30,
        maxProgress: 100,
        group: 'g',
        image: '/img.png',
        ongoing: true,
      );
      final args = Map<String, dynamic>.from(calls
          .firstWhere((c) => c.method == 'showNotification')
          .arguments as Map);
      expect(args['title'], 't');
      expect(args['id'], 'n1');
      expect(args['progress'], 30);
      expect(args['ongoing'], true);
      expect(m.isNotificationActive('n1'), isTrue);
      expect(m.activeNotificationCount, 1);
    });

    test('showNotification wraps native errors as MCPException', () async {
      failShow = true;
      await expectLater(
        m.showNotification(title: 't', body: 'b'),
        throwsA(isA<MCPException>()),
      );
    });

    test('hideNotification clears tracking', () async {
      await m.showNotification(title: 't', body: 'b', id: 'h1');
      await m.hideNotification('h1');
      expect(m.isNotificationActive('h1'), isFalse);
    });

    test('hideNotification wraps native errors', () async {
      await m.showNotification(title: 't', body: 'b', id: 'h2');
      failHide = true;
      await expectLater(
        m.hideNotification('h2'),
        throwsA(isA<MCPException>()),
      );
    });

    test('updateNotification only fires when id is tracked', () async {
      await m.updateNotification(id: 'absent', title: 'x');
      expect(calls.where((c) => c.method == 'updateNotification'), isEmpty);
      await m.showNotification(title: 't', body: 'b', id: 'u');
      calls.clear();
      await m.updateNotification(id: 'u', title: 't2', body: 'b2');
      expect(calls.first.method, 'updateNotification');
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

    test('cancelAllNotifications swallows platform errors', () async {
      failCancelAll = true;
      await m.cancelAllNotifications(); // does not throw
    });

    test('clearAllNotifications wraps native errors as MCPException', () async {
      failCancelAll = true;
      await expectLater(
        m.clearAllNotifications(),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestPermission returns true on non-Android host', () async {
      // We're on macOS — Platform.isAndroid is false → method returns true.
      expect(await m.requestPermission(), isTrue);
    });

    test('getActiveNotifications maps to NotificationInfo entries', () async {
      await m.showNotification(title: 't1', body: 'b1', id: 'x');
      await m.showNotification(title: 't2', body: 'b2', id: 'y');
      final list = m.getActiveNotifications();
      expect(list, hasLength(2));
      expect(list.map((n) => n.id), containsAll(['x', 'y']));
    });
  });

  group('AndroidNotificationManager — click handlers', () {
    test('register/unregister are silent', () async {
      final m = AndroidNotificationManager();
      await m.initialize(null);
      m.registerClickHandler('id1', (id, data) {});
      m.registerClickHandler('default', (id, data) {});
      m.unregisterClickHandler('id1');
      await m.dispose();
    });
  });
}
