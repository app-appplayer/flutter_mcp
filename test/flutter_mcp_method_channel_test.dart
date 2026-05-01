import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp_method_channel.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelFlutterMcp impl;
  final List<MethodCall> calls = [];
  Object? Function(MethodCall call)? handler;

  setUp(() {
    impl = MethodChannelFlutterMcp();
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(impl.methodChannel, (MethodCall call) async {
      calls.add(call);
      if (handler != null) return handler!(call);
      // Default sensible returns for void / typed methods.
      switch (call.method) {
        case 'getPlatformVersion':
          return 'TestPlatform 1.0';
        case 'startBackgroundService':
        case 'stopBackgroundService':
        case 'requestNotificationPermission':
        case 'secureContainsKey':
        case 'checkPermission':
        case 'requestPermission':
          return true;
        case 'secureRead':
          return null;
        case 'requestPermissions':
          return {'notif': true, 'cam': false};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(impl.methodChannel, null);
    impl.dispose();
  });

  group('platform interaction — happy path', () {
    test('getPlatformVersion forwards to channel', () async {
      final v = await impl.getPlatformVersion();
      expect(v, 'TestPlatform 1.0');
      expect(calls.single.method, 'getPlatformVersion');
    });

    test('initialize forwards config.toJson()', () async {
      await impl.initialize(MCPConfig(appName: 'app', appVersion: '0.0.1'));
      expect(calls.single.method, 'initialize');
      expect(calls.single.arguments, isA<Map>());
    });

    test('startBackgroundService updates internal state', () async {
      expect(impl.isBackgroundServiceRunning, isFalse);
      final r = await impl.startBackgroundService();
      expect(r, isTrue);
      expect(impl.isBackgroundServiceRunning, isTrue);
    });

    test('stopBackgroundService updates internal state', () async {
      await impl.startBackgroundService();
      expect(impl.isBackgroundServiceRunning, isTrue);
      final r = await impl.stopBackgroundService();
      expect(r, isTrue);
      expect(impl.isBackgroundServiceRunning, isFalse);
    });

    test('configureBackgroundService forwards config json', () async {
      await impl.configureBackgroundService(BackgroundConfig());
      expect(calls.single.method, 'configureBackgroundService');
    });

    test('scheduleBackgroundTask sends taskId, delay, data', () async {
      await impl.scheduleBackgroundTask(
        taskId: 't1',
        delay: const Duration(seconds: 5),
        data: {'k': 'v'},
      );
      expect(calls.single.method, 'scheduleBackgroundTask');
      expect(calls.single.arguments['taskId'], 't1');
      expect(calls.single.arguments['delayMillis'], 5000);
      expect(calls.single.arguments['data'], {'k': 'v'});
    });

    test('cancelBackgroundTask sends taskId', () async {
      await impl.cancelBackgroundTask('t2');
      expect(calls.single.arguments['taskId'], 't2');
    });

    test('showNotification forwards title/body/icon/id', () async {
      await impl.showNotification(
        title: 'T',
        body: 'B',
        icon: 'i',
        id: 'n1',
      );
      expect(calls.single.method, 'showNotification');
      expect(calls.single.arguments['title'], 'T');
      expect(calls.single.arguments['body'], 'B');
      expect(calls.single.arguments['icon'], 'i');
      expect(calls.single.arguments['id'], 'n1');
    });

    test('requestNotificationPermission returns mock value', () async {
      expect(await impl.requestNotificationPermission(), isTrue);
    });

    test('configureNotifications forwards json', () async {
      await impl.configureNotifications(NotificationConfig());
      expect(calls.single.method, 'configureNotifications');
    });

    test('cancelNotification sends id', () async {
      await impl.cancelNotification('n1');
      expect(calls.single.arguments, {'id': 'n1'});
    });

    test('cancelAllNotifications takes no arguments', () async {
      await impl.cancelAllNotifications();
      expect(calls.single.method, 'cancelAllNotifications');
    });

    test('secureStore / secureRead / secureDelete', () async {
      await impl.secureStore('k', 'v');
      expect(calls[0].arguments, {'key': 'k', 'value': 'v'});

      handler = (_) => 'mock_value';
      final r = await impl.secureRead('k');
      expect(r, 'mock_value');
      handler = null;

      await impl.secureDelete('k');
      expect(calls.last.method, 'secureDelete');
    });

    test('secureContainsKey returns mock value', () async {
      expect(await impl.secureContainsKey('k'), isTrue);
    });

    test('secureDeleteAll', () async {
      await impl.secureDeleteAll();
      expect(calls.single.method, 'secureDeleteAll');
    });

    test('tray methods forward args', () async {
      await impl.showTrayIcon(iconPath: '/i.png', tooltip: 'tip');
      expect(calls.last.arguments, {'iconPath': '/i.png', 'tooltip': 'tip'});

      await impl.hideTrayIcon();
      expect(calls.last.method, 'hideTrayIcon');

      await impl.setTrayMenu([{'label': 'A'}]);
      expect(calls.last.arguments['items'], [{'label': 'A'}]);

      await impl.updateTrayTooltip('new');
      expect(calls.last.arguments, {'tooltip': 'new'});

      await impl.configureTray(TrayConfig());
      expect(calls.last.method, 'configureTray');
    });

    test('checkPermission / requestPermission / requestPermissions', () async {
      expect(await impl.checkPermission('notif'), isTrue);
      expect(calls.last.arguments, {'permission': 'notif'});

      expect(await impl.requestPermission('notif'), isTrue);
      expect(calls.last.arguments, {'permission': 'notif'});

      final r = await impl.requestPermissions(['notif', 'cam']);
      expect(r, {'notif': true, 'cam': false});
    });

    test('shutdown stops background service, cancels notifications, hides tray',
        () async {
      await impl.startBackgroundService();
      await impl.shutdown();
      // shutdown should have invoked stopBackgroundService, cancelAll,
      // hideTrayIcon, then native 'shutdown'.
      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('startBackgroundService'));
      expect(methods, contains('stopBackgroundService'));
      expect(methods, contains('cancelAllNotifications'));
      expect(methods, contains('hideTrayIcon'));
      expect(methods, contains('shutdown'));
    });
  });

  group('platform interaction — error wrapping', () {
    test('getPlatformVersion wraps PlatformException', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'no');
      await expectLater(
        impl.getPlatformVersion(),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('initialize wraps PlatformException', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.initialize(MCPConfig(appName: 'a', appVersion: '0.0.1')),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('startBackgroundService wraps as MCPBackgroundExecutionException',
        () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'oops');
      await expectLater(
        impl.startBackgroundService(),
        throwsA(isA<MCPBackgroundExecutionException>()),
      );
    });

    test('stopBackgroundService wraps as MCPBackgroundExecutionException',
        () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'oops');
      await expectLater(
        impl.stopBackgroundService(),
        throwsA(isA<MCPBackgroundExecutionException>()),
      );
    });

    test('configureBackgroundService wraps as MCPBackgroundExecutionException',
        () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'oops');
      await expectLater(
        impl.configureBackgroundService(BackgroundConfig()),
        throwsA(isA<MCPBackgroundExecutionException>()),
      );
    });

    test('scheduleBackgroundTask wraps', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'oops');
      await expectLater(
        impl.scheduleBackgroundTask(taskId: 't', delay: Duration.zero),
        throwsA(isA<MCPBackgroundExecutionException>()),
      );
    });

    test('cancelBackgroundTask wraps', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'oops');
      await expectLater(
        impl.cancelBackgroundTask('t'),
        throwsA(isA<MCPBackgroundExecutionException>()),
      );
    });

    test('showNotification wraps as MCPPlatformException', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.showNotification(title: 'T', body: 'B'),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('requestNotificationPermission rethrows PERMISSION_DENIED specifically',
        () async {
      handler = (_) => throw PlatformException(code: 'PERMISSION_DENIED');
      await expectLater(
        impl.requestNotificationPermission(),
        throwsA(isA<MCPPermissionDeniedException>()),
      );
    });

    test('requestNotificationPermission wraps other PlatformExceptions',
        () async {
      handler = (_) => throw PlatformException(code: 'OTHER');
      await expectLater(
        impl.requestNotificationPermission(),
        throwsA(allOf(
          isA<MCPPlatformException>(),
          isNot(isA<MCPPermissionDeniedException>()),
        )),
      );
    });

    test('configureNotifications wraps', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.configureNotifications(NotificationConfig()),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('cancelNotification wraps', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.cancelNotification('id'),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('cancelAllNotifications wraps', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.cancelAllNotifications(),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('secureStore wraps as MCPSecureStorageException', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'no');
      await expectLater(
        impl.secureStore('k', 'v'),
        throwsA(isA<MCPSecureStorageException>()),
      );
    });

    test('secureRead returns null when KEY_NOT_FOUND', () async {
      handler = (_) => throw PlatformException(code: 'KEY_NOT_FOUND');
      expect(await impl.secureRead('absent'), isNull);
    });

    test('secureRead wraps other errors', () async {
      handler = (_) => throw PlatformException(code: 'OTHER', message: 'x');
      await expectLater(
        impl.secureRead('k'),
        throwsA(isA<MCPSecureStorageException>()),
      );
    });

    test('secureDelete wraps', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'x');
      await expectLater(
        impl.secureDelete('k'),
        throwsA(isA<MCPSecureStorageException>()),
      );
    });

    test('secureContainsKey wraps', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'x');
      await expectLater(
        impl.secureContainsKey('k'),
        throwsA(isA<MCPSecureStorageException>()),
      );
    });

    test('secureDeleteAll wraps', () async {
      handler = (_) => throw PlatformException(code: 'X', message: 'x');
      await expectLater(
        impl.secureDeleteAll(),
        throwsA(isA<MCPSecureStorageException>()),
      );
    });

    test('showTrayIcon / hideTrayIcon / setTrayMenu / updateTrayTooltip / configureTray wrap',
        () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(impl.showTrayIcon(iconPath: '/x'),
          throwsA(isA<MCPPlatformException>()));
      await expectLater(impl.hideTrayIcon(),
          throwsA(isA<MCPPlatformException>()));
      await expectLater(impl.setTrayMenu([]),
          throwsA(isA<MCPPlatformException>()));
      await expectLater(impl.updateTrayTooltip('t'),
          throwsA(isA<MCPPlatformException>()));
      await expectLater(impl.configureTray(TrayConfig()),
          throwsA(isA<MCPPlatformException>()));
    });

    test('shutdown wraps top-level PlatformException', () async {
      // Make the native 'shutdown' call throw — earlier helpers must succeed
      // first or the throw will route to a different branch.
      handler = (call) {
        if (call.method == 'shutdown') {
          throw PlatformException(code: 'X');
        }
        return null;
      };
      await expectLater(impl.shutdown(),
          throwsA(isA<MCPPlatformException>()));
    });

    test('checkPermission wraps', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.checkPermission('p'),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('requestPermission rethrows PERMISSION_DENIED specifically',
        () async {
      handler = (_) => throw PlatformException(code: 'PERMISSION_DENIED');
      await expectLater(
        impl.requestPermission('p'),
        throwsA(isA<MCPPermissionDeniedException>()),
      );
    });

    test('requestPermission wraps other PlatformExceptions', () async {
      handler = (_) => throw PlatformException(code: 'OTHER');
      await expectLater(
        impl.requestPermission('p'),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('requestPermissions returns empty when channel returns null',
        () async {
      handler = (_) => null;
      expect(await impl.requestPermissions(['a']), isEmpty);
    });

    test('requestPermissions wraps PlatformException', () async {
      handler = (_) => throw PlatformException(code: 'X');
      await expectLater(
        impl.requestPermissions(['a']),
        throwsA(isA<MCPPlatformException>()),
      );
    });
  });

  group('exception classes', () {
    test('MCPPlatformException toString', () {
      final e = MCPPlatformException('msg', 'CODE', 'detail');
      expect(e.toString(), contains('msg'));
      expect(e.toString(), contains('CODE'));
    });

    test('MCPPermissionDeniedException uses fixed code', () {
      final e = MCPPermissionDeniedException('camera');
      expect(e.code, 'PERMISSION_DENIED');
      expect(e.details, 'camera');
    });

    test('MCPBackgroundExecutionException uses fixed code', () {
      final e = MCPBackgroundExecutionException('msg', 'd');
      expect(e.code, 'BACKGROUND_EXECUTION_ERROR');
    });

    test('MCPSecureStorageException uses fixed code', () {
      final e = MCPSecureStorageException('msg');
      expect(e.code, 'SECURE_STORAGE_ERROR');
    });

    test('MCPException is the base type', () {
      expect(MCPPlatformException('m', 'c'), isA<MCPException>());
    });
  });
}
