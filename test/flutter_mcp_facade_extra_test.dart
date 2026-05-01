// Additional facade-level error-path tests for FlutterMCP — exercises
// guard branches on llm-client / llm-server / mcp-association methods.
//
// Combined into one initialized group because the singleton can only be
// initialized once per process.

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
        return 'Test Platform 1.0';
      case 'startBackgroundService':
      case 'stopBackgroundService':
      case 'requestNotificationPermission':
      case 'shutdown':
      case 'configureNotifications':
      case 'cancelNotification':
      case 'cancelAllNotifications':
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
      case 'requestPermission':
      case 'checkPermission':
        return true;
      case 'requestPermissions':
        return {'notif': true};
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

  group('FlutterMCP — uninitialized error paths (facade extras)', () {
    setUp(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
    });

    test('removeLlmClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeLlmClient('llm', 'llmc'),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeLlmServer throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeLlmServer('llm', 'llms'),
        throwsA(isA<MCPException>()),
      );
    });

    test('addMcpClientToLlmClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.addMcpClientToLlmClient(
          mcpClientId: 'mc',
          llmClientId: 'lc',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeMcpClientFromLlmClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeMcpClientFromLlmClient(
          mcpClientId: 'mc',
          llmClientId: 'lc',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('setDefaultMcpClientForLlmClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.setDefaultMcpClientForLlmClient(
          mcpClientId: 'mc',
          llmClientId: 'lc',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('addMcpServerToLlmServer throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.addMcpServerToLlmServer(
          mcpServerId: 'ms',
          llmServerId: 'ls',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeMcpServerFromLlmServer throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeMcpServerFromLlmServer(
          mcpServerId: 'ms',
          llmServerId: 'ls',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('setDefaultMcpServerForLlmServer throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.setDefaultMcpServerForLlmServer(
          mcpServerId: 'ms',
          llmServerId: 'ls',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('connectClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.connectClient('absent'),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('FlutterMCP — initialized: facade-extras error paths', () {
    setUpAll(() async {
      _installMethodChannelMock();
      if (!FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.init(
          MCPConfig(appName: 'facade-extras', appVersion: '0.0.1'),
        );
      }
    });

    tearDownAll(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      _removeMethodChannelMock();
    });

    test('setDefaultLlmClientId / setDefaultLlmServerId accept any string', () {
      // These are simple field setters with no side effects when no LLM
      // exists yet — verify they don't throw.
      FlutterMCP.instance.setDefaultLlmClientId('llm-client-1');
      FlutterMCP.instance.setDefaultLlmServerId('llm-server-1');
    });

    test('removeLlmClient throws MCPResourceNotFound for unknown llmId',
        () async {
      await expectLater(
        FlutterMCP.instance.removeLlmClient('absent', 'lc'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('removeLlmServer throws MCPResourceNotFound for unknown llmId',
        () async {
      await expectLater(
        FlutterMCP.instance.removeLlmServer('absent', 'ls'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('addMcpClientToLlmClient surfaces an MCPException for unknown ids',
        () async {
      await expectLater(
        FlutterMCP.instance.addMcpClientToLlmClient(
          mcpClientId: 'no-mc',
          llmClientId: 'no-lc',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeMcpClientFromLlmClient is a no-op or throws for unknown ids',
        () async {
      // Implementation either silently returns (no association to remove)
      // or surfaces an MCPException — either is acceptable.
      try {
        await FlutterMCP.instance.removeMcpClientFromLlmClient(
          mcpClientId: 'no-mc',
          llmClientId: 'no-lc',
        );
      } on MCPException {
        // expected alternative
      }
    });

    test('setDefaultMcpClientForLlmClient surfaces an MCPException for unknown ids',
        () async {
      await expectLater(
        FlutterMCP.instance.setDefaultMcpClientForLlmClient(
          mcpClientId: 'no-mc',
          llmClientId: 'no-lc',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('addMcpServerToLlmServer surfaces an MCPException for unknown ids',
        () async {
      await expectLater(
        FlutterMCP.instance.addMcpServerToLlmServer(
          mcpServerId: 'no-ms',
          llmServerId: 'no-ls',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeMcpServerFromLlmServer is a no-op or throws for unknown ids',
        () async {
      try {
        await FlutterMCP.instance.removeMcpServerFromLlmServer(
          mcpServerId: 'no-ms',
          llmServerId: 'no-ls',
        );
      } on MCPException {
        // expected alternative
      }
    });

    test('setDefaultMcpServerForLlmServer surfaces an MCPException for unknown ids',
        () async {
      await expectLater(
        FlutterMCP.instance.setDefaultMcpServerForLlmServer(
          mcpServerId: 'no-ms',
          llmServerId: 'no-ls',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('createClient with streamablehttp transport succeeds', () async {
      final id = await FlutterMCP.instance.createClient(
        name: 'http-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'http-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          endpoint: '/mcp',
          authToken: 'token',
          timeout: const Duration(seconds: 10),
          maxConcurrentRequests: 5,
          useHttp2: false,
        ),
      );
      expect(id, isNotEmpty);
    });

    test('createServer with sse transport succeeds', () async {
      final id = await FlutterMCP.instance.createServer(
        name: 'sse-server',
        version: '0.0.1',
        config: MCPServerConfig(
          name: 'sse-server',
          version: '0.0.1',
          transportType: 'sse',
          ssePort: 0, // 0 = auto-assign
          host: 'localhost',
          authToken: 'token',
        ),
      );
      expect(id, isNotEmpty);
    });

    test('createServer with sse but no ssePort throws', () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'sse-noport',
          version: '0.0.1',
          config: MCPServerConfig(
            name: 'sse-noport',
            version: '0.0.1',
            transportType: 'sse',
          ),
        ),
        throwsA(anyOf(
          isA<MCPValidationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('createServer with streamablehttp but no port throws', () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'http-noport',
          version: '0.0.1',
          config: MCPServerConfig(
            name: 'http-noport',
            version: '0.0.1',
            transportType: 'streamablehttp',
          ),
        ),
        throwsA(anyOf(
          isA<MCPValidationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });
  });
}
