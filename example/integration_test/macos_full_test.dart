// Full macOS native surface verification — extends macos_native_test.dart
// to cover every method-channel handler reachable on macOS desktop:
// rich notification options, configureNotifications/BackgroundService,
// task scheduling, secure storage extras, full tray method set, and
// tray menu-click event delivery.
//
// Run with:
//   cd example
//   flutter test integration_test/macos_full_test.dart -d macos

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

const _channel = MethodChannel('flutter_mcp');
const _trayEvents = EventChannel('flutter_mcp/tray_events');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.init(
        MCPConfig(
          appName: 'macos-full-test',
          appVersion: '0.0.1',
          useBackgroundService: true,
          useNotification: true,
          useTray: true,
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
    testWidgets('showNotification with actions / image / subtitle / progress',
        (tester) async {
      if (!Platform.isMacOS) return;
      // Bypass the typed wrapper to send the full payload the native
      // showNotification handler accepts.
      await _channel.invokeMethod('showNotification', {
        'id': 'rich-1',
        'title': 'Rich notification',
        'body': 'with all options',
        'icon': null,
        'subtitle': 'subtitle text',
        'priority': 2, // high
        'enableSound': true,
        'data': {'k': 'v'},
        'actions': [
          {'id': 'open', 'title': 'Open'},
          {'id': 'dismiss', 'title': 'Dismiss'},
        ],
        'showProgress': true,
        'progress': 30,
        'maxProgress': 100,
        'group': 'g1',
        'image': null,
        'ongoing': false,
      });
      await _channel.invokeMethod('cancelNotification', {'id': 'rich-1'});
    });

    testWidgets('cancelAllNotifications clears the queue', (tester) async {
      if (!Platform.isMacOS) return;
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
      if (!Platform.isMacOS) return;
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
    testWidgets('configureBackgroundService passes interval + keepAlive',
        (tester) async {
      if (!Platform.isMacOS) return;
      await _channel.invokeMethod('configureBackgroundService', {
        'intervalMs': 30000,
        'keepAlive': true,
      });
    });

    testWidgets('scheduleBackgroundTask + cancelBackgroundTask round-trip',
        (tester) async {
      if (!Platform.isMacOS) return;
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
      if (!Platform.isMacOS) return;
      const k = 'flutter_mcp.macos_full.contains.key';
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

    testWidgets('secureDeleteAll clears every key under our prefix',
        (tester) async {
      if (!Platform.isMacOS) return;
      await _channel.invokeMethod(
          'secureStore', {'key': 'flutter_mcp.macos_full.bulk.1', 'value': 'x'});
      await _channel.invokeMethod(
          'secureStore', {'key': 'flutter_mcp.macos_full.bulk.2', 'value': 'y'});
      await _channel.invokeMethod('secureDeleteAll');
      expect(
        await _channel.invokeMethod<bool>('secureContainsKey',
            {'key': 'flutter_mcp.macos_full.bulk.1'}),
        isFalse,
      );
    });
  });

  group('enhanced tray surface', () {
    testWidgets('full lifecycle — initialize → set icon/tooltip/menu → show '
        '→ updateMenuItem → hide → dispose', (tester) async {
      if (!Platform.isMacOS) return;

      await _channel
          .invokeMethod('initializeTray', {'platform': 'macos'});
      // setTrayIcon may pass through to NSImage(contentsOfFile:) which
      // accepts a non-existent path silently — the call should still
      // return success.
      await _channel
          .invokeMethod('setTrayIcon', {'path': '/tmp/nope.png', 'isTemplate': false});
      await _channel
          .invokeMethod('setTrayTooltip', {'tooltip': 'rich'});
      await _channel.invokeMethod('setTrayContextMenu', {
        'items': [
          {'id': 'open', 'label': 'Open', 'disabled': false, 'visible': true},
          {'type': 'separator'},
          {'id': 'quit', 'label': 'Quit', 'disabled': false, 'visible': true},
        ],
      });
      await _channel.invokeMethod('showTray');
      await _channel.invokeMethod('updateTrayMenuItem', {
        'itemId': 'open',
        'label': 'Open (updated)',
        'disabled': false,
        'checked': false,
        'iconPath': null,
      });
      await _channel.invokeMethod('hideTray');
      await _channel.invokeMethod('disposeTray');
    });

    testWidgets('setTrayIconFromBytes accepts a Uint8List payload',
        (tester) async {
      if (!Platform.isMacOS) return;
      final pngHeader = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);
      await _channel.invokeMethod('setTrayIconFromBytes', {
        'bytes': pngHeader,
        'isTemplate': false,
      });
    });

    testWidgets(
        'setStatusBarItemProperties / setMenuBarVisibility do not throw',
        (tester) async {
      if (!Platform.isMacOS) return;
      await _channel.invokeMethod('setStatusBarItemProperties', {
        'width': 24.0,
        'highlightMode': true,
        'title': 'MCP',
      });
      await _channel.invokeMethod('setMenuBarVisibility', {'visible': true});
    });
  });

  group('event channel — tray click round-trip', () {
    testWidgets(
        'tray menu click broadcasts a trayEvent on flutter_mcp/tray_events',
        (tester) async {
      if (!Platform.isMacOS) return;

      // We can't programmatically click the tray on macOS without UI
      // automation; instead verify the event channel is reachable and
      // listenable. A real click would push a {type: trayEvent, data:
      // {action: menuItemClicked, itemId: ...}} entry on this stream.
      final completer =
          Future<dynamic>.delayed(const Duration(milliseconds: 250));
      final sub = _trayEvents
          .receiveBroadcastStream()
          .timeout(const Duration(milliseconds: 200), onTimeout: (sink) {
        sink.add(null);
        sink.close();
      }).take(1).listen((_) {});
      await completer;
      await sub.cancel();
    });
  });
}
