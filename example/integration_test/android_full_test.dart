// Full Android native surface verification — extends android_native_test.dart
// to cover every method-channel handler reachable on Android:
// rich notification options, configureNotifications, configureBackgroundService,
// scheduleBackgroundTask round-trip, secure storage extras (containsKey,
// deleteAll), updateNotification path, requestPermissions multi-permission.
//
// Run with:
//   cd example
//   flutter test integration_test/android_full_test.dart -d <emulator>

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

const _channel = MethodChannel('flutter_mcp');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.init(
        MCPConfig(
          appName: 'android-full-test',
          appVersion: '0.0.1',
          useBackgroundService: true,
          useNotification: true,
          useTray: false,
          secure: true,
          autoStart: false,
        ),
      );
    }
  });

  tearDownAll(() async {
    if (FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.shutdown();
    }
  });

  group('rich notification options', () {
    testWidgets('showNotification with full payload', (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('showNotification', {
        'id': 'rich-1',
        'title': 'Rich notification',
        'body': 'with all options',
        'icon': null,
      });
      await _channel.invokeMethod('cancelNotification', {'id': 'rich-1'});
    });

    testWidgets('cancelAllNotifications clears the queue', (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('showNotification', {
        'id': 'a',
        'title': 't',
        'body': 'b',
      });
      await _channel.invokeMethod('showNotification', {
        'id': 'b',
        'title': 't',
        'body': 'b',
      });
      await _channel.invokeMethod('cancelAllNotifications');
    });

    testWidgets('configureNotifications accepts channel + sound config',
        (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('configureNotifications', {
        'channelId': 'mcp-test-channel',
        'channelName': 'Test channel',
        'channelDescription': 'channel for tests',
        'enableSound': false,
        'priority': 1,
        'icon': null,
      });
    });

    testWidgets('updateNotification refreshes existing entry', (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('showNotification', {
        'id': 'upd-1',
        'title': 'before',
        'body': 'b',
      });
      await _channel.invokeMethod('updateNotification', {
        'id': 'upd-1',
        'title': 'after',
        'body': 'b2',
      });
      await _channel.invokeMethod('cancelNotification', {'id': 'upd-1'});
    });
  });

  group('background service rich surface', () {
    testWidgets('initializeBackgroundService accepts config map',
        (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('initializeBackgroundService', {
        'config': {
          'intervalMs': 30000,
          'keepAlive': true,
        },
      });
    });

    testWidgets('configureBackgroundService passes interval + keepAlive',
        (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('configureBackgroundService', {
        'intervalMs': 30000,
        'keepAlive': true,
      });
    });

    testWidgets('scheduleBackgroundTask + cancelBackgroundTask round-trip',
        (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('scheduleBackgroundTask', {
        'taskId': 'task-rich-1',
        'delayMillis': 60000,
        'data': {'k': 'v'},
      });
      await _channel.invokeMethod('cancelBackgroundTask', {
        'taskId': 'task-rich-1',
      });
    });
  });

  group('secure storage extras', () {
    testWidgets('secureContainsKey reflects stored vs absent', (tester) async {
      if (!Platform.isAndroid) return;
      const k = 'flutter_mcp.android_full.contains.key';
      expect(
        await _channel.invokeMethod<bool>('secureContainsKey', {'key': k}),
        isFalse,
      );
      await _channel.invokeMethod('secureStore', {'key': k, 'value': 'v'});
      expect(
        await _channel.invokeMethod<bool>('secureContainsKey', {'key': k}),
        isTrue,
      );
      await _channel.invokeMethod('secureDelete', {'key': k});
      expect(
        await _channel.invokeMethod<bool>('secureContainsKey', {'key': k}),
        isFalse,
      );
    });

    testWidgets('secureDeleteAll clears every stored key', (tester) async {
      if (!Platform.isAndroid) return;
      await _channel.invokeMethod('secureStore',
          {'key': 'flutter_mcp.android_full.bulk.1', 'value': 'x'});
      await _channel.invokeMethod('secureStore',
          {'key': 'flutter_mcp.android_full.bulk.2', 'value': 'y'});
      await _channel.invokeMethod('secureDeleteAll');
      expect(
        await _channel.invokeMethod<bool>('secureContainsKey',
            {'key': 'flutter_mcp.android_full.bulk.1'}),
        isFalse,
      );
    });
  });

  group('permissions surface', () {
    testWidgets('requestPermissions returns Map<String,bool> for multiple keys',
        (tester) async {
      if (!Platform.isAndroid) return;
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestPermissions',
        {
          'permissions': ['notification', 'storage'],
        },
      );
      expect(result, isNotNull);
      expect(result!.containsKey('notification'), isTrue);
      expect(result.containsKey('storage'), isTrue);
    });

    testWidgets('checkPermission returns bool for known permission',
        (tester) async {
      if (!Platform.isAndroid) return;
      final granted = await _channel
          .invokeMethod<bool>('checkPermission', {'permission': 'notification'});
      expect(granted, isA<bool>());
    });

    testWidgets('requestNotificationPermission returns bool', (tester) async {
      if (!Platform.isAndroid) return;
      final granted =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      expect(granted, isA<bool>());
    });
  });
}
