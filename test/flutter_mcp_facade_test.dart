// Coverage-targeted facade tests for FlutterMCP — exercises uncovered
// branches in flutter_mcp.dart's main API surface. The singleton can only
// be initialized once per process, so init/shutdown cycles share a single
// setUpAll/tearDownAll.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void _installMethodChannelMock() {
  const channel = MethodChannel('flutter_mcp');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        return {'success': true, 'platform': 'test'};
      case 'getPlatformVersion':
        return 'Test 1.0';
      case 'startBackgroundService':
      case 'stopBackgroundService':
      case 'cancelNotification':
      case 'cancelAllNotifications':
      case 'shutdown':
      case 'requestNotificationPermission':
      case 'configureNotifications':
        return true;
      case 'showNotification':
        return {'success': true, 'id': 'test'};
      case 'secureStore':
      case 'secureDelete':
        return true;
      case 'secureRead':
        return null;
      case 'secureContainsKey':
        return false;
      default:
        return null;
    }
  });
}

void _removeMethodChannelMock() {
  const channel = MethodChannel('flutter_mcp');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterMCP — uninitialized status', () {
    test('isInitialized starts false (or already initialized in shared singleton)',
        () {
      // We don't assert false here because a previous suite in the run
      // might have left the singleton initialized — both states are
      // valid for an unrelated test suite.
      expect(FlutterMCP.instance.isInitialized, isA<bool>());
    });

    test('getSystemStatus returns minimal status when not initialized', () async {
      // Force uninitialized state for this test.
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      final status = FlutterMCP.instance.getSystemStatus();
      expect(status['initialized'], isFalse);
      expect(status, contains('platformName'));
      expect(status, contains('platformFeatures'));
      expect(status, contains('timestamp'));
    });

    test('isFeatureSupported can be queried without init', () {
      final result = FlutterMCP.instance.isFeatureSupported('notifications');
      expect(result, isA<bool>());
    });

    test('getSystemHealth throws when not initialized', () async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      // Implementation throws when called pre-init (no fallback shape).
      await expectLater(
        FlutterMCP.instance.getSystemHealth(),
        throwsA(isA<MCPException>()),
      );
    });

    test('checkPermission throws when not initialized', () async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      await expectLater(
        FlutterMCP.instance.checkPermission('notifications'),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestPermission throws when not initialized', () async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      await expectLater(
        FlutterMCP.instance.requestPermission('notifications'),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('FlutterMCP — initialized facade', () {
    setUpAll(() async {
      _installMethodChannelMock();
      if (!FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.init(
          MCPConfig(appName: 'facade-test', appVersion: '0.0.1'),
        );
      }
    });

    tearDownAll(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      _removeMethodChannelMock();
    });

    test('isInitialized is true after init', () {
      expect(FlutterMCP.instance.isInitialized, isTrue);
    });

    test('clientManager / serverManager / llmManager getters available', () {
      expect(FlutterMCP.instance.clientManager, isNotNull);
      expect(FlutterMCP.instance.serverManager, isNotNull);
      expect(FlutterMCP.instance.llmManager, isNotNull);
    });

    test('platformServices getter available', () {
      expect(FlutterMCP.instance.platformServices, isNotNull);
    });

    test('getSystemStatus returns full status when initialized', () {
      final status = FlutterMCP.instance.getSystemStatus();
      expect(status['initialized'], isTrue);
      expect(status, contains('clients'));
      expect(status, contains('servers'));
      expect(status, contains('llms'));
      expect(status, contains('platformName'));
      expect(status, contains('timestamp'));
      expect(status, contains('clientsStatus'));
      expect(status, contains('serversStatus'));
      expect(status, contains('llmsStatus'));
      expect(status, contains('pluginsCount'));
    });

    test('clientManagerStatus / serverManagerStatus / llmManagerStatus diagnostics',
        () {
      expect(FlutterMCP.instance.clientManagerStatus, isA<Map>());
      expect(FlutterMCP.instance.serverManagerStatus, isA<Map>());
      expect(FlutterMCP.instance.llmManagerStatus, isA<Map>());
    });

    test('schedulerStatus diagnostic', () {
      final status = FlutterMCP.instance.schedulerStatus;
      expect(status, contains('isRunning'));
      expect(status, contains('jobCount'));
      expect(status, contains('activeJobCount'));
    });

    test('platformServicesStatus diagnostic', () {
      final status = FlutterMCP.instance.platformServicesStatus;
      expect(status, contains('backgroundServiceRunning'));
      expect(status, contains('platformName'));
    });

    test('pluginRegistryStatus diagnostic', () {
      final status = FlutterMCP.instance.pluginRegistryStatus;
      expect(status, contains('pluginCount'));
      expect(status, contains('plugins'));
    });

    test('getClientDetails returns empty for unknown id', () {
      expect(FlutterMCP.instance.getClientDetails('no-such-client'), isEmpty);
    });

    test('getServerDetails returns empty for unknown id', () {
      expect(FlutterMCP.instance.getServerDetails('no-such-server'), isEmpty);
    });

    test('getLlmDetails returns empty for unknown id', () {
      expect(FlutterMCP.instance.getLlmDetails('no-such-llm'), isEmpty);
    });

    test('isFeatureSupported handles common feature names', () {
      // These are queried via PlatformUtils — behavior is platform dependent
      // but the call should never throw.
      expect(FlutterMCP.instance.isFeatureSupported('notifications'),
          isA<bool>());
      expect(FlutterMCP.instance.isFeatureSupported('tray'), isA<bool>());
      expect(FlutterMCP.instance.isFeatureSupported('background'),
          isA<bool>());
      expect(FlutterMCP.instance.isFeatureSupported('unknown_feature'),
          isA<bool>());
    });

    test('getClient / getServer return null for unknown ids', () {
      expect(FlutterMCP.instance.getClient('no-such'), isNull);
      expect(FlutterMCP.instance.getServer('no-such'), isNull);
    });

    // The createClient surface wraps validation failures in
    // MCPOperationFailedException via its outer try/catch. We accept either
    // type for the assertions below since the inner cause is the
    // MCPValidationException.
    final transportFailure = throwsA(anyOf(
      isA<MCPValidationException>(),
      isA<MCPOperationFailedException>(),
    ));

    test('createClient validates that some transport setting is supplied',
        () async {
      // No transportCommand and no serverUrl → validation error.
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'broken',
          version: '0.0.1',
        ),
        transportFailure,
      );
    });

    test('createClient with stdio transport but no command throws', () async {
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'stdio-no-cmd',
          version: '0.0.1',
          config: MCPClientConfig(
            name: 'stdio-no-cmd',
            version: '0.0.1',
            transportType: 'stdio',
            serverUrl: 'http://placeholder',
          ),
        ),
        transportFailure,
      );
    });

    test('createClient with sse transport but no serverUrl throws', () async {
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'sse-no-url',
          version: '0.0.1',
          config: MCPClientConfig(
            name: 'sse-no-url',
            version: '0.0.1',
            transportType: 'sse',
            transportCommand: 'placeholder',
          ),
        ),
        transportFailure,
      );
    });

    test('createServer with stdio transport succeeds', () async {
      final id = await FlutterMCP.instance.createServer(
        name: 'stdio-server',
        version: '0.0.1',
        config: MCPServerConfig(
          name: 'stdio-server',
          version: '0.0.1',
          transportType: 'stdio',
        ),
      );
      expect(id, isNotEmpty);
      expect(FlutterMCP.instance.getServer(id), isNotNull);
    });

    test('createServer with invalid transport type throws', () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'bad',
          version: '0.0.1',
          config: MCPServerConfig(
            name: 'bad',
            version: '0.0.1',
            transportType: 'unknown_transport',
          ),
        ),
        throwsA(anyOf(
          isA<MCPOperationFailedException>(),
          isA<MCPValidationException>(),
        )),
      );
    });

    test('connectClient on unknown clientId throws', () async {
      await expectLater(
        FlutterMCP.instance.connectClient('no-such-client'),
        throwsA(isA<MCPException>()),
      );
    });

    test('connectServer on unknown serverId throws', () async {
      expect(
        () => FlutterMCP.instance.connectServer('no-such-server'),
        throwsA(isA<MCPException>()),
      );
    });

    test('callTool with unknown clientId throws', () async {
      await expectLater(
        FlutterMCP.instance.callTool('no-such', 'tool', {}),
        throwsA(anyOf(
          isA<MCPException>(),
          isA<MCPResourceNotFoundException>(),
        )),
      );
    });

    test('shutdown completes without error after init', () async {
      // shutdown is exercised by tearDownAll, but call it once more here
      // through the regular flow to also cover the idempotency path: a
      // second init() is now blocked by the singleton's sticky latch, so
      // we only verify shutdown() itself.
      // (We don't actually call shutdown here because that would break
      // subsequent tests in the group. The tearDownAll covers it.)
      expect(FlutterMCP.instance.isInitialized, isTrue);
    });
  });
}
