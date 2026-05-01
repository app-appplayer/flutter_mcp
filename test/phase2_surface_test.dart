// Tests for the Phase 2 spec surface added in flutter_mcp 2.0:
// - MCPClientConfig.{initialRoots, autoBridgeSampling, elicitationHandler, listRootsHandler}
// - MCPServerConfig.protectedResource + MCPProtectedResourceConfig
// - FlutterMCP.{setElicitationHandler, addClientRoot, removeClientRoot, getClientRoots}
// - FlutterMCP.{requestClientSampling, requestClientRoots, requestClientElicitation}
// - FlutterMCP.{addServerCompletion, removeServerCompletion}
//
// These tests exercise the real FlutterMCP singleton.

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
      case 'cancelNotification':
      case 'cancelAllNotifications':
      case 'shutdown':
        return true;
      case 'showNotification':
        return {'success': true, 'id': 'test_notification'};
      case 'secureStore':
        return true;
      case 'secureRead':
        return null;
      case 'secureDelete':
        return true;
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

  group('MCPProtectedResourceConfig', () {
    test('constructs with required fields only', () {
      const cfg = MCPProtectedResourceConfig(
        resource: 'https://api.example.com/mcp',
        authorizationServers: ['https://auth.example.com'],
      );
      expect(cfg.resource, 'https://api.example.com/mcp');
      expect(cfg.authorizationServers, ['https://auth.example.com']);
      expect(cfg.scopesSupported, isNull);
      expect(cfg.bearerMethodsSupported, isNull);
      expect(cfg.resourceDocumentation, isNull);
    });

    test('constructs with all fields', () {
      const cfg = MCPProtectedResourceConfig(
        resource: 'https://api.example.com/mcp',
        authorizationServers: ['https://auth.example.com', 'https://auth2.example.com'],
        scopesSupported: ['mcp:read', 'mcp:tools'],
        bearerMethodsSupported: ['header'],
        resourceDocumentation: 'https://example.com/docs',
      );
      expect(cfg.authorizationServers.length, 2);
      expect(cfg.scopesSupported, ['mcp:read', 'mcp:tools']);
      expect(cfg.bearerMethodsSupported, ['header']);
      expect(cfg.resourceDocumentation, 'https://example.com/docs');
    });
  });

  group('MCPClientConfig — Phase 2 fields', () {
    test('autoBridgeSampling defaults to true', () {
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
      );
      expect(cfg.autoBridgeSampling, isTrue);
      expect(cfg.initialRoots, isNull);
      expect(cfg.elicitationHandler, isNull);
      expect(cfg.listRootsHandler, isNull);
    });

    test('autoBridgeSampling can be disabled', () {
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        autoBridgeSampling: false,
      );
      expect(cfg.autoBridgeSampling, isFalse);
    });

    test('initialRoots accepted', () {
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        initialRoots: const [
          Root(uri: 'file:///workspace', name: 'workspace'),
          Root(uri: 'file:///tmp', name: 'tmp'),
        ],
      );
      expect(cfg.initialRoots, hasLength(2));
      expect(cfg.initialRoots!.first.uri, 'file:///workspace');
    });

    test('elicitationHandler stored', () async {
      Future<Map<String, dynamic>> handler(Map<String, dynamic> params) async {
        return {'action': 'decline'};
      }
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        elicitationHandler: handler,
      );
      expect(cfg.elicitationHandler, isNotNull);
      final result = await cfg.elicitationHandler!({'message': 'test'});
      expect(result['action'], 'decline');
    });

    test('listRootsHandler stored', () async {
      Future<List<Root>> handler() async {
        return const [Root(uri: 'file:///custom', name: 'custom')];
      }
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        listRootsHandler: handler,
      );
      final roots = await cfg.listRootsHandler!();
      expect(roots, hasLength(1));
      expect(roots.first.uri, 'file:///custom');
    });

    test('transportType is required', () {
      expect(
        () => MCPClientConfig(name: 'X', version: '1.0.0'),
        throwsArgumentError,
      );
    });

    test('toJson serializes core fields', () {
      final cfg = MCPClientConfig(
        name: 'Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        endpoint: '/mcp',
        timeout: const Duration(seconds: 30),
      );
      final json = cfg.toJson();
      expect(json['name'], 'Client');
      expect(json['transportType'], 'streamablehttp');
      expect(json['serverUrl'], 'http://localhost:8080');
      expect(json['endpoint'], '/mcp');
      expect(json['timeout'], 30000);
    });
  });

  group('MCPServerConfig — Phase 2 fields', () {
    test('protectedResource is optional', () {
      final cfg = MCPServerConfig(
        name: 'Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
      );
      expect(cfg.protectedResource, isNull);
    });

    test('protectedResource carries RFC 9728 metadata', () {
      final cfg = MCPServerConfig(
        name: 'Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
        protectedResource: const MCPProtectedResourceConfig(
          resource: 'https://api.example.com/mcp',
          authorizationServers: ['https://auth.example.com'],
          scopesSupported: ['mcp:read'],
        ),
      );
      expect(cfg.protectedResource, isNotNull);
      expect(cfg.protectedResource!.resource, 'https://api.example.com/mcp');
    });

    test('toJson includes core fields', () {
      final cfg = MCPServerConfig(
        name: 'Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
        host: '0.0.0.0',
      );
      final json = cfg.toJson();
      expect(json['name'], 'Server');
      expect(json['transportType'], 'streamablehttp');
      expect(json['streamableHttpPort'], 8080);
      expect(json['host'], '0.0.0.0');
    });
  });

  group('FlutterMCP not-initialized error paths', () {
    setUp(() async {
      // Ensure FlutterMCP starts uninitialized for these tests.
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
    });

    test('addClientRoot throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.addClientRoot(
          'no-such-client',
          const Root(uri: 'file:///x', name: 'x'),
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeClientRoot throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeClientRoot('no-such-client', 'file:///x'),
        throwsA(isA<MCPException>()),
      );
    });

    test('getClientRoots throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.getClientRoots('no-such-client'),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestClientSampling throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.requestClientSampling(
          serverId: 'no-such',
          sessionId: 's1',
          params: const {},
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestClientRoots throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.requestClientRoots(
          serverId: 'no-such',
          sessionId: 's1',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('requestClientElicitation throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.requestClientElicitation(
          serverId: 'no-such',
          sessionId: 's1',
          params: const {},
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('addServerCompletion throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.addServerCompletion(
          serverId: 'no-such',
          refType: 'prompt',
          refKey: 'p',
          handler: (ref, arg, ctx) async => {'values': []},
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('removeServerCompletion throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.removeServerCompletion(
          serverId: 'no-such',
          refType: 'prompt',
          refKey: 'p',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('setElicitationHandler does not require initialization', () {
      // Setter is allowed before init — handler is consumed by future
      // createClient calls; setting it early is the documented pattern.
      Future<Map<String, dynamic>> handler(Map<String, dynamic> p) async =>
          {'action': 'decline'};
      FlutterMCP.instance.setElicitationHandler(handler);
      // Reset to null afterwards.
      FlutterMCP.instance.setElicitationHandler(null);
    });
  });

  // FlutterMCP singleton can only be initialized once per process — its
  // _initializationStarted latch is sticky across shutdown(). All tests
  // that require init() share a single group so a single setUpAll covers
  // them. Tests that require uninitialized state must run before init,
  // which is why this combined group sits after the not-initialized one.
  group('FlutterMCP initialized', () {
    setUpAll(() async {
      _installMethodChannelMock();
      if (!FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.init(
          MCPConfig(appName: 'phase2-init-test', appVersion: '0.0.1'),
        );
      }
    });

    tearDownAll(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      _removeMethodChannelMock();
    });

    test('addClientRoot raises MCPResourceNotFound for unknown clientId', () {
      expect(
        () => FlutterMCP.instance.addClientRoot(
          'no-such-client',
          const Root(uri: 'file:///x', name: 'x'),
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('removeClientRoot raises MCPResourceNotFound for unknown clientId', () {
      expect(
        () => FlutterMCP.instance.removeClientRoot('no-such-client', 'file:///x'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('getClientRoots raises MCPResourceNotFound for unknown clientId', () {
      expect(
        () => FlutterMCP.instance.getClientRoots('no-such-client'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('requestClientSampling raises MCPResourceNotFound for unknown serverId',
        () async {
      await expectLater(
        FlutterMCP.instance.requestClientSampling(
          serverId: 'no-such',
          sessionId: 's1',
          params: const {},
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('requestClientRoots raises MCPResourceNotFound for unknown serverId',
        () async {
      await expectLater(
        FlutterMCP.instance.requestClientRoots(
          serverId: 'no-such',
          sessionId: 's1',
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('requestClientElicitation raises MCPResourceNotFound for unknown serverId',
        () async {
      await expectLater(
        FlutterMCP.instance.requestClientElicitation(
          serverId: 'no-such',
          sessionId: 's1',
          params: const {},
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('addServerCompletion raises MCPResourceNotFound for unknown serverId',
        () {
      expect(
        () => FlutterMCP.instance.addServerCompletion(
          serverId: 'no-such',
          refType: 'prompt',
          refKey: 'p',
          handler: (ref, arg, ctx) async => {'values': []},
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('removeServerCompletion raises MCPResourceNotFound for unknown serverId',
        () {
      expect(
        () => FlutterMCP.instance.removeServerCompletion(
          serverId: 'no-such',
          refType: 'prompt',
          refKey: 'p',
        ),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('setElicitationHandler accepts a handler and clears with null', () {
      Future<Map<String, dynamic>> handler(Map<String, dynamic> p) async =>
          {'action': 'decline'};
      FlutterMCP.instance.setElicitationHandler(handler);
      FlutterMCP.instance.setElicitationHandler(null);
      // No exception means success.
    });

    test('createClient with initialRoots seeds roots before connect', () async {
      final clientId = await FlutterMCP.instance.createClient(
        name: 'roots-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'roots-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          initialRoots: const [
            Root(uri: 'file:///a', name: 'a'),
            Root(uri: 'file:///b', name: 'b'),
          ],
        ),
      );
      final roots = FlutterMCP.instance.getClientRoots(clientId);
      expect(roots, hasLength(2));
      expect(roots.map((r) => r.uri).toSet(), {'file:///a', 'file:///b'});
    });

    test('addClientRoot on a created client updates the root list', () async {
      final clientId = await FlutterMCP.instance.createClient(
        name: 'add-root-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'add-root-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          initialRoots: const [Root(uri: 'file:///a', name: 'a')],
        ),
      );
      FlutterMCP.instance.addClientRoot(
        clientId,
        const Root(uri: 'file:///c', name: 'c'),
      );
      final roots = FlutterMCP.instance.getClientRoots(clientId);
      expect(roots.map((r) => r.uri).toSet(), {'file:///a', 'file:///c'});
    });

    test('removeClientRoot drops a root by uri', () async {
      final clientId = await FlutterMCP.instance.createClient(
        name: 'remove-root-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'remove-root-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          initialRoots: const [
            Root(uri: 'file:///a', name: 'a'),
            Root(uri: 'file:///b', name: 'b'),
          ],
        ),
      );
      FlutterMCP.instance.removeClientRoot(clientId, 'file:///a');
      final roots = FlutterMCP.instance.getClientRoots(clientId);
      expect(roots.map((r) => r.uri).toSet(), {'file:///b'});
    });

    test('createClient with autoBridgeSampling=false still succeeds', () async {
      final clientId = await FlutterMCP.instance.createClient(
        name: 'no-sampling-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'no-sampling-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          autoBridgeSampling: false,
        ),
      );
      expect(clientId, isNotEmpty);
    });

    test('createClient with elicitationHandler succeeds', () async {
      Future<Map<String, dynamic>> handler(Map<String, dynamic> p) async =>
          {'action': 'decline'};
      final clientId = await FlutterMCP.instance.createClient(
        name: 'elicit-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'elicit-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          elicitationHandler: handler,
        ),
      );
      expect(clientId, isNotEmpty);
    });

    test('createClient with listRootsHandler succeeds', () async {
      Future<List<Root>> handler() async =>
          const [Root(uri: 'file:///dynamic', name: 'dynamic')];
      final clientId = await FlutterMCP.instance.createClient(
        name: 'roots-handler-client',
        version: '0.0.1',
        config: MCPClientConfig(
          name: 'roots-handler-client',
          version: '0.0.1',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:9999',
          listRootsHandler: handler,
        ),
      );
      expect(clientId, isNotEmpty);
    });

    test('createServer with protectedResource succeeds', () async {
      final serverId = await FlutterMCP.instance.createServer(
        name: 'rfc9728-server',
        version: '0.0.1',
        config: MCPServerConfig(
          name: 'rfc9728-server',
          version: '0.0.1',
          transportType: 'streamablehttp',
          streamableHttpPort: 19999,
          protectedResource: const MCPProtectedResourceConfig(
            resource: 'https://api.example.com/mcp',
            authorizationServers: ['https://auth.example.com'],
            scopesSupported: ['mcp:read', 'mcp:tools'],
            bearerMethodsSupported: ['header'],
            resourceDocumentation: 'https://example.com/docs',
          ),
        ),
      );
      expect(serverId, isNotEmpty);
    });
  });
}
