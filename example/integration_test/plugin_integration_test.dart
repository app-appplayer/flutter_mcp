// End-to-end smoke test: drives FlutterMCP through init → createClient
// (stdio + /usr/bin/true) → shutdown on the host platform. Run with:
//     flutter test integration_test/plugin_integration_test.dart -d macos
//
// On Linux the binary lives at /usr/bin/true as well. iOS / Android
// don't ship those binaries, so the createClient path skips on mobile.

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
          appName: 'flutter-mcp-integration',
          appVersion: '0.0.1',
          // Keep platform side-effects off so the smoke runs anywhere.
          useBackgroundService: false,
          useNotification: false,
          useTray: false,
          secure: false,
          autoStart: false,
          enablePerformanceMonitoring: false,
        ),
      );
    }
  });

  tearDownAll(() async {
    if (FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.shutdown();
    }
  });

  testWidgets('FlutterMCP reports initialized after init', (tester) async {
    expect(FlutterMCP.instance.isInitialized, isTrue);
    expect(FlutterMCP.instance.platformServices.platformName, isNotEmpty);
  });

  testWidgets('Diagnostic getters return populated maps', (tester) async {
    expect(FlutterMCP.instance.clientManagerStatus, isA<Map>());
    expect(FlutterMCP.instance.serverManagerStatus, isA<Map>());
    expect(FlutterMCP.instance.llmManagerStatus, isA<Map>());
    expect(FlutterMCP.instance.platformServicesStatus, isA<Map>());
    expect(FlutterMCP.instance.pluginRegistryStatus, isA<Map>());
  });

  testWidgets(
    'createClient(stdio, /usr/bin/true) registers a clientId',
    (tester) async {
      // Skip on mobile where /usr/bin/true isn't reachable.
      if (Platform.isAndroid || Platform.isIOS) return;
      final clientId = await FlutterMCP.instance.createClient(
        name: 'integration-stdio',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'integration-stdio',
          version: '1.0.0',
          transportType: 'stdio',
          transportCommand: '/usr/bin/true',
        ),
      );
      expect(clientId, startsWith('client_'));
      expect(
        FlutterMCP.instance.clientManager.getClientInfo(clientId),
        isNotNull,
      );
      // Cleanup so the spawned process is reaped.
      await FlutterMCP.instance.clientManager.closeClient(clientId);
    },
  );

  testWidgets('getSystemHealth returns an aggregated map', (tester) async {
    final h = await FlutterMCP.instance.getSystemHealth();
    expect(h, contains('overall'));
    expect(h, contains('components'));
  });
}
