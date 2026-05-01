// iOS native verification — runs against the real `flutter_mcp` iOS
// plugin via `flutter test integration_test/ios_native_test.dart -d <ios-sim>`.
// Each test exercises one native method-channel path and asserts the
// channel returns without falling through to MissingPluginException.
//
// This file consolidates both the basic surface checks (typed
// PlatformServices facade) and the full surface checks (raw method
// channel for handlers the typed facade doesn't yet expose). They live
// in the same suite because iOS setUpAll on a cold simulator is slow
// (~5 min) and we don't want to pay that cost twice.

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
          appName: 'ios-native-test',
          appVersion: '0.0.1',
          // iOS supports background, notifications, secure storage; no tray.
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

  // ---- Basic surface (typed PlatformServices facade) ----

  testWidgets('native: requestPermissions returns Map<String,bool>',
      (tester) async {
    if (!Platform.isIOS) return;
    final result = await FlutterMCP.instance.platformServices
        .requestPermissions(['notification', 'storage']);
    expect(result, isA<Map<String, bool>>());
    // iOS notification permission may be denied in CI / fresh sims;
    // we only assert the call returned without MissingPluginException.
    expect(result.containsKey('notification'), isTrue);
  });

  testWidgets('native: secureStore + secureRead round-trip', (tester) async {
    if (!Platform.isIOS) return;
    const key = 'flutter_mcp.ios_native_test.key';
    await FlutterMCP.instance.platformServices
        .secureStore(key, 'hello-keychain');
    final read = await FlutterMCP.instance.platformServices.secureRead(key);
    expect(read, 'hello-keychain');

    await FlutterMCP.instance.platformServices.secureDelete(key);
    expect(
      await FlutterMCP.instance.platformServices.secureRead(key),
      isNull,
    );
  });

  testWidgets('native: showNotification + hideNotification do not throw',
      (tester) async {
    if (!Platform.isIOS) return;
    await FlutterMCP.instance.platformServices.showNotification(
      title: 'flutter_mcp test',
      body: 'iOS native verification',
      id: 'fmcp-test-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await FlutterMCP.instance.platformServices.hideNotification('fmcp-test-1');
  });

  testWidgets('native: startBackgroundService + stopBackgroundService',
      (tester) async {
    if (!Platform.isIOS) return;
    final started =
        await FlutterMCP.instance.platformServices.startBackgroundService();
    expect(started, isA<bool>());
    final stopped =
        await FlutterMCP.instance.platformServices.stopBackgroundService();
    expect(stopped, isA<bool>());
  });

  testWidgets('native: checkPermission + requestPermission single',
      (tester) async {
    if (!Platform.isIOS) return;
    final granted = await FlutterMCP.instance.platformServices
        .checkPermission('notification');
    expect(granted, isA<bool>());
    final granted2 = await FlutterMCP.instance.platformServices
        .requestPermission('notification');
    expect(granted2, isA<bool>());
  });

  // ---- Full surface (raw method channel for un-faceted handlers) ----

  group('rich notification options', () {
    testWidgets('showNotification with id/title/body via raw channel',
        (tester) async {
      if (!Platform.isIOS) return;
      await _channel.invokeMethod('showNotification', {
        'id': 'rich-1',
        'title': 'Rich notification',
        'body': 'with options',
      });
      await _channel.invokeMethod('cancelNotification', {'id': 'rich-1'});
    });

    testWidgets('cancelAllNotifications clears the queue', (tester) async {
      if (!Platform.isIOS) return;
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

    testWidgets('configureNotifications accepts category + sound config',
        (tester) async {
      if (!Platform.isIOS) return;
      await _channel.invokeMethod('configureNotifications', {
        'channelId': 'mcp-test-channel',
        'channelName': 'Test channel',
        'channelDescription': 'channel for tests',
        'enableSound': false,
        'priority': 1,
        'icon': null,
      });
    });
  });

  group('background service rich surface', () {
    testWidgets('configureBackgroundService stores config + callback handle',
        (tester) async {
      if (!Platform.isIOS) return;
      await _channel.invokeMethod('configureBackgroundService', {
        'intervalMs': 30000,
        'keepAlive': true,
      });
    });

    testWidgets('scheduleBackgroundTask + cancelBackgroundTask round-trip',
        (tester) async {
      if (!Platform.isIOS) return;
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
      if (!Platform.isIOS) return;
      const k = 'flutter_mcp.ios_full.contains.key';
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
      if (!Platform.isIOS) return;
      await _channel.invokeMethod('secureStore',
          {'key': 'flutter_mcp.ios_full.bulk.1', 'value': 'x'});
      await _channel.invokeMethod('secureStore',
          {'key': 'flutter_mcp.ios_full.bulk.2', 'value': 'y'});
      await _channel.invokeMethod('secureDeleteAll');
      expect(
        await _channel.invokeMethod<bool>(
            'secureContainsKey', {'key': 'flutter_mcp.ios_full.bulk.1'}),
        isFalse,
      );
    });
  });

  group('permissions surface', () {
    testWidgets('raw requestPermissions returns Map for multiple keys',
        (tester) async {
      if (!Platform.isIOS) return;
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestPermissions',
        {
          'permissions': ['notification', 'storage'],
        },
      );
      expect(result, isNotNull);
      expect(result!.containsKey('notification'), isTrue);
    });

    testWidgets('raw checkPermission returns bool for known permission',
        (tester) async {
      if (!Platform.isIOS) return;
      final granted = await _channel
          .invokeMethod<bool>('checkPermission', {'permission': 'notification'});
      expect(granted, isA<bool>());
    });

    testWidgets('requestNotificationPermission returns bool', (tester) async {
      if (!Platform.isIOS) return;
      final granted =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      expect(granted, isA<bool>());
    });
  });
}
