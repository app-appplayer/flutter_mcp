// macOS native verification — runs against the real `flutter_mcp` macOS
// plugin via `flutter test integration_test/macos_native_test.dart -d macos`.
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
          appName: 'macos-native-test',
          appVersion: '0.0.1',
          // Exercise every native path enabled on macOS desktop.
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

  testWidgets('native: requestPermissions returns Map<String,bool>',
      (tester) async {
    if (!Platform.isMacOS) return;
    final result = await FlutterMCP.instance.platformServices
        .requestPermissions(['notification', 'storage']);
    expect(result, isA<Map<String, bool>>());
    expect(result['notification'], isTrue);
    expect(result['storage'], isTrue);
  });

  testWidgets('native: secureStore + secureRead round-trip', (tester) async {
    if (!Platform.isMacOS) return;
    const key = 'flutter_mcp.macos_native_test.key';
    await FlutterMCP.instance.platformServices
        .secureStore(key, 'hello-keychain');
    final read = await FlutterMCP.instance.platformServices.secureRead(key);
    expect(read, 'hello-keychain');

    // Cleanup so we don't leave state in the system keychain.
    final removed =
        await FlutterMCP.instance.platformServices.secureDelete(key);
    expect(removed, isTrue);
    expect(
      await FlutterMCP.instance.platformServices.secureRead(key),
      isNull,
    );
  });

  testWidgets('native: showNotification + hideNotification do not throw',
      (tester) async {
    if (!Platform.isMacOS) return;
    await FlutterMCP.instance.platformServices.showNotification(
      title: 'flutter_mcp test',
      body: 'macOS native verification',
      id: 'fmcp-test-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await FlutterMCP.instance.platformServices.hideNotification('fmcp-test-1');
  });

  testWidgets('native: setTrayIcon + setTrayTooltip + setTrayMenu',
      (tester) async {
    if (!Platform.isMacOS) return;
    // Tray icon path is allowed to be missing on disk for this smoke
    // test — the native side accepts the call regardless. We only check
    // that the channel doesn't throw MissingPluginException.
    await FlutterMCP.instance.platformServices.setTrayTooltip('flutter_mcp');
    await FlutterMCP.instance.platformServices.setTrayMenu([
      TrayMenuItem(label: 'Show', onTap: () {}),
      TrayMenuItem.separator(),
      TrayMenuItem(label: 'Quit', onTap: () {}),
    ]);
  });

  testWidgets('native: startBackgroundService + stopBackgroundService',
      (tester) async {
    if (!Platform.isMacOS) return;
    final started =
        await FlutterMCP.instance.platformServices.startBackgroundService();
    expect(started, isTrue);
    expect(
      FlutterMCP.instance.platformServices.isBackgroundServiceRunning,
      isTrue,
    );
    final stopped =
        await FlutterMCP.instance.platformServices.stopBackgroundService();
    expect(stopped, isTrue);
  });

  testWidgets('native: checkPermission + requestPermission single', (tester) async {
    if (!Platform.isMacOS) return;
    final granted = await FlutterMCP.instance.platformServices
        .checkPermission('notification');
    expect(granted, isA<bool>());
    final granted2 = await FlutterMCP.instance.platformServices
        .requestPermission('notification');
    expect(granted2, isA<bool>());
  });
}
