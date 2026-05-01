// Android native verification — runs against the real `flutter_mcp`
// Android plugin via:
//     flutter test integration_test/android_native_test.dart -d <emulator>
// Each test exercises one native method-channel path and asserts the
// channel returns without falling through to MissingPluginException.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.init(
        MCPConfig(
          appName: 'android-native-test',
          appVersion: '0.0.1',
          // Android supports background, notifications, secure storage; no tray.
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

  testWidgets('native: requestPermissions returns Map<String,bool>',
      (tester) async {
    if (!Platform.isAndroid) return;
    final result = await FlutterMCP.instance.platformServices
        .requestPermissions(['notification', 'storage']);
    expect(result, isA<Map<String, bool>>());
    expect(result.containsKey('notification'), isTrue);
  });

  testWidgets('native: secureStore + secureRead round-trip', (tester) async {
    if (!Platform.isAndroid) return;
    const key = 'flutter_mcp.android_native_test.key';
    await FlutterMCP.instance.platformServices
        .secureStore(key, 'hello-encrypted-prefs');
    final read = await FlutterMCP.instance.platformServices.secureRead(key);
    expect(read, 'hello-encrypted-prefs');

    await FlutterMCP.instance.platformServices.secureDelete(key);
    expect(
      await FlutterMCP.instance.platformServices.secureRead(key),
      isNull,
    );
  });

  testWidgets('native: showNotification + hideNotification do not throw',
      (tester) async {
    if (!Platform.isAndroid) return;
    await FlutterMCP.instance.platformServices.showNotification(
      title: 'flutter_mcp test',
      body: 'Android native verification',
      id: 'fmcp-test-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await FlutterMCP.instance.platformServices.hideNotification('fmcp-test-1');
  });

  testWidgets('native: startBackgroundService + stopBackgroundService',
      (tester) async {
    if (!Platform.isAndroid) return;
    final started =
        await FlutterMCP.instance.platformServices.startBackgroundService();
    expect(started, isA<bool>());
    final stopped =
        await FlutterMCP.instance.platformServices.stopBackgroundService();
    expect(stopped, isA<bool>());
  });

  testWidgets('native: checkPermission + requestPermission single',
      (tester) async {
    if (!Platform.isAndroid) return;
    final granted = await FlutterMCP.instance.platformServices
        .checkPermission('notification');
    expect(granted, isA<bool>());
    final granted2 = await FlutterMCP.instance.platformServices
        .requestPermission('notification');
    expect(granted2, isA<bool>());
  });
}
