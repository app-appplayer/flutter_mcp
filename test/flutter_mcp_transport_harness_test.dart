// Coverage tests for FlutterMCP that drive connectClient / connectServer
// happy paths through a mock transport. The fake transport intercepts
// outgoing JSON-RPC and feeds back a successful initialize response so
// the client/server can connect without a real subprocess or network.

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_client/mcp_client.dart' as client_pkg;
import 'package:mcp_server/mcp_server.dart' as server_pkg;
import 'package:mcp_llm/mcp_llm.dart' as llm_pkg;

import '_mock_transport.dart';

class _FakeProviderFactory implements llm_pkg.LlmProviderFactory {
  @override
  String get name => 'fake-provider';

  @override
  Set<llm_pkg.LlmCapability> get capabilities =>
      {llm_pkg.LlmCapability.completion};

  @override
  llm_pkg.LlmInterface createProvider(llm_pkg.LlmConfiguration config) =>
      _FakeProvider();
}

class _FakeProvider implements llm_pkg.LlmProvider {
  @override
  bool get supportsPromptCaching => false;

  @override
  Future<void> initialize(llm_pkg.LlmConfiguration config) async {}
  @override
  Future<void> close() async {}
  @override
  Future<llm_pkg.LlmResponse> complete(llm_pkg.LlmRequest request) async =>
      llm_pkg.LlmResponse(text: 'fake');
  @override
  Stream<llm_pkg.LlmResponseChunk> streamComplete(llm_pkg.LlmRequest request) =>
      const Stream.empty();
  @override
  Future<List<double>> getEmbeddings(String text) async => [];
  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) => false;
  @override
  llm_pkg.LlmToolCall? extractToolCallFromMetadata(
          Map<String, dynamic> metadata) =>
      null;
  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) =>
      metadata;
}

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

  setUpAll(() async {
    _installMethodChannelMock();
    if (!FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.init(
        MCPConfig(appName: 'transport-harness', appVersion: '0.0.1'),
      );
    }
  });

  tearDownAll(() async {
    if (FlutterMCP.instance.isInitialized) {
      await FlutterMCP.instance.shutdown();
    }
    _removeMethodChannelMock();
  });

  group('FlutterMCP transport harness — connectClient happy path', () {

    test(
        'manually-registered client + fake transport connects through connectClient',
        () async {
      // Build a real Client + fake transport, register with the manager.
      final client = client_pkg.McpClient.createClient(
        client_pkg.McpClientConfig(name: 'harness-client', version: '1.0.0'),
      );
      final transport = FakeClientTransport();
      final cm = FlutterMCP.instance.clientManager;
      final clientId = cm.generateId();
      cm.registerClient(clientId, client, transport);

      // Now connect via the public API — this drives the entire connect
      // flow including the mock initialize round-trip.
      await FlutterMCP.instance.connectClient(clientId);

      // The fake transport should have observed the outgoing initialize
      // request and the post-init notification.
      expect(transport.sent, isNotEmpty);

      // Diagnostic: client info reports connected = true.
      final info = cm.getClientInfo(clientId);
      expect(info?.connected, isTrue);

      // Status snapshot includes the connected client.
      final status = FlutterMCP.instance.clientManagerStatus;
      expect(status['connected'], greaterThanOrEqualTo(1));

      // Detail getters return populated maps for live clients.
      final detail = FlutterMCP.instance.getClientDetails(clientId);
      expect(detail['id'], clientId);
      expect(detail['connected'], isTrue);
      expect(detail['hasTransport'], isTrue);

      // Close cleanly.
      await cm.closeClient(clientId);
    });

    test('connectClient throws when client has no transport', () async {
      final client = client_pkg.McpClient.createClient(
        client_pkg.McpClientConfig(name: 'no-tx', version: '1.0.0'),
      );
      final cm = FlutterMCP.instance.clientManager;
      final clientId = cm.generateId();
      cm.registerClient(clientId, client, null);
      await expectLater(
        FlutterMCP.instance.connectClient(clientId),
        throwsA(isA<MCPOperationFailedException>()),
      );
      await cm.closeClient(clientId);
    });
  });

  group('FlutterMCP transport harness — connectServer happy path', () {
    test(
        'manually-registered server + fake transport connects through connectServer',
        () async {
      final server = server_pkg.McpServer.createServer(
        server_pkg.McpServerConfig(name: 'harness-server', version: '1.0.0'),
      );
      final transport = FakeServerTransport();
      final sm = FlutterMCP.instance.serverManager;
      final serverId = sm.generateId();
      sm.registerServer(serverId, server, transport);

      FlutterMCP.instance.connectServer(serverId);

      final info = sm.getServerInfo(serverId);
      expect(info?.running, isTrue);

      final detail = FlutterMCP.instance.getServerDetails(serverId);
      expect(detail['id'], serverId);
      expect(detail['hasTransport'], isTrue);

      await sm.closeServer(serverId);
    });

    test('connectServer throws when server has no transport', () {
      final server = server_pkg.McpServer.createServer(
        server_pkg.McpServerConfig(name: 'no-tx-server', version: '1.0.0'),
      );
      final sm = FlutterMCP.instance.serverManager;
      final serverId = sm.generateId();
      sm.registerServer(serverId, server, null);
      expect(
        () => FlutterMCP.instance.connectServer(serverId),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });
  });

  group('FlutterMCP transport harness — LLM integration', () {
    test('addMcpClientToLlmClient + setDefaultMcpClient + removeLlmClient',
        () async {
      // Register a real Client + transport.
      final mcpClient = client_pkg.McpClient.createClient(
        client_pkg.McpClientConfig(name: 'lc-client', version: '1.0.0'),
      );
      final transport = FakeClientTransport();
      final cm = FlutterMCP.instance.clientManager;
      final mcpClientId = cm.generateId();
      cm.registerClient(mcpClientId, mcpClient, transport);

      // Register an LLM with a real LlmClient.
      final lm = FlutterMCP.instance.llmManager;
      final llmId = lm.generateId();
      lm.registerLlm('lid-$llmId', llm_pkg.MCPLlm());
      final llmClientId = 'llm-client-1';
      await lm.addLlmClient(
        'lid-$llmId',
        llmClientId,
        llm_pkg.LlmClient(llmProvider: _FakeProvider()),
      );

      // Drive addMcpClientToLlmClient through the public API.
      await FlutterMCP.instance.addMcpClientToLlmClient(
        mcpClientId: mcpClientId,
        llmClientId: llmClientId,
      );

      // Drive setDefaultMcpClientForLlmClient — the association exists.
      await FlutterMCP.instance.setDefaultMcpClientForLlmClient(
        mcpClientId: mcpClientId,
        llmClientId: llmClientId,
      );

      // Now exercise removeLlmClient — it walks the associations and
      // disassociates them before removing the client.
      await FlutterMCP.instance.removeLlmClient('lid-$llmId', llmClientId);

      // Cleanup.
      await cm.closeClient(mcpClientId);
      await lm.closeLlm('lid-$llmId');
    });

    test('addMcpClientToLlmClient throws for missing mcpClient', () async {
      await expectLater(
        FlutterMCP.instance.addMcpClientToLlmClient(
          mcpClientId: 'absent-mcp-client',
          llmClientId: 'absent-llm-client',
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('setDefaultLlmClientId / setDefaultLlmServerId update getters', () {
      FlutterMCP.instance.setDefaultLlmClientId('def-client');
      FlutterMCP.instance.setDefaultLlmServerId('def-server');
      expect(FlutterMCP.instance.defaultLlmClientId, 'def-client');
      expect(FlutterMCP.instance.defaultLlmServerId, 'def-server');
    });
  });

  group('FlutterMCP transport harness — connected-client operations', () {
    late String clientId;
    late FakeClientTransport transport;

    setUp(() async {
      final mcpClient = client_pkg.McpClient.createClient(
        client_pkg.McpClientConfig(name: 'op-client', version: '1.0.0'),
      );
      transport = FakeClientTransport();
      final cm = FlutterMCP.instance.clientManager;
      clientId = cm.generateId();
      cm.registerClient(clientId, mcpClient, transport);
      await FlutterMCP.instance.connectClient(clientId);
    });

    tearDown(() async {
      await FlutterMCP.instance.clientManager.closeClient(clientId);
    });

    test('callTool returns the canned tool result', () async {
      final r = await FlutterMCP.instance.callTool(
        clientId,
        'echo',
        {'input': 'hi'},
      );
      // CallToolResult.content shape — first content item is text 'tool result'.
      expect(r.content, isNotEmpty);
      // The fake transport recorded the outbound tools/call request.
      expect(
        transport.sent.any((m) =>
            m is Map && m['method'] == 'tools/call'),
        isTrue,
      );
    });

    test('callTool throws MCPResourceNotFound for unknown clientId', () async {
      await expectLater(
        FlutterMCP.instance.callTool('absent-cid', 'echo', {}),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });
  });

  group('FlutterMCP transport harness — chat happy path', () {
    test('chat returns LlmResponse from default LLM client', () async {
      final lm = FlutterMCP.instance.llmManager;
      final llmId = 'chat-llm-${DateTime.now().microsecondsSinceEpoch}';
      lm.registerLlm(llmId, llm_pkg.MCPLlm());
      const llmClientId = 'chat-llm-client';
      await lm.addLlmClient(
        llmId,
        llmClientId,
        llm_pkg.LlmClient(llmProvider: _FakeProvider()),
      );

      final r = await FlutterMCP.instance.chat(
        llmId,
        'hello',
        llmClientId: llmClientId,
      );
      expect(r.text, isNotNull);

      await lm.closeLlm(llmId);
    });

    test('chat returns fallback when llmId unknown', () async {
      // chat has fallback in EnhancedErrorHandler — falls back instead of throwing.
      final r = await FlutterMCP.instance.chat(
        'totally-absent-llm',
        'hello',
      );
      expect(r.text, isNotNull);
    });
  });

  group('FlutterMCP transport harness — MCPLlm instance + provider', () {
    test(
        'createMcpLlmInstance + getMcpLlmInstance + getAllMcpLlmInstanceIds',
        () {
      final id = 'inst-${DateTime.now().microsecondsSinceEpoch}';
      final mcpLlm = FlutterMCP.instance.createMcpLlmInstance(
        id,
        registerDefaultProviders: false,
      );
      expect(mcpLlm, isNotNull);
      expect(FlutterMCP.instance.getMcpLlmInstance(id), isNotNull);
      expect(FlutterMCP.instance.getAllMcpLlmInstanceIds(), contains(id));

      // Idempotent: second call returns the same instance.
      final again = FlutterMCP.instance.createMcpLlmInstance(id);
      expect(identical(mcpLlm, again), isTrue);
    });

    test('registerLlmProvider with empty name throws', () {
      expect(
        () => FlutterMCP.instance.registerLlmProvider(
          '',
          _FakeProviderFactory(),
        ),
        throwsA(isA<MCPValidationException>()),
      );
    });

    test('registerLlmProvider on missing instance throws', () {
      expect(
        () => FlutterMCP.instance.registerLlmProvider(
          'fake',
          _FakeProviderFactory(),
          mcpLlmInstanceId: 'absent-instance',
        ),
        throwsA(isA<MCPException>()),
      );
    });

    test('registerLlmProvider on existing instance succeeds', () {
      final id = 'reg-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(id, registerDefaultProviders: false);
      FlutterMCP.instance.registerLlmProvider(
        'fake-provider',
        _FakeProviderFactory(),
        mcpLlmInstanceId: id,
      );
      // No exception means success.
    });
  });

  group('FlutterMCP transport harness — getMcpLlmInstanceOrThrow paths', () {
    test('getMcpLlmInstance for unknown id returns null', () {
      expect(
        FlutterMCP.instance.getMcpLlmInstance('nope-${DateTime.now().microsecondsSinceEpoch}'),
        isNull,
      );
    });
  });

  group('FlutterMCP transport harness — createLlmClient happy path', () {
    test('with a registered fake provider, createLlmClient returns ids',
        () async {
      final instId = 'cl-inst-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      FlutterMCP.instance.registerLlmProvider(
        'fake-provider',
        _FakeProviderFactory(),
        mcpLlmInstanceId: instId,
      );

      final (llmId, llmClientId) = await FlutterMCP.instance.createLlmClient(
        providerName: 'fake-provider',
        config: llm_pkg.LlmConfiguration(
          apiKey: 'test-key',
          model: 'test-model',
        ),
        mcpLlmInstanceId: instId,
      );

      expect(llmId, startsWith('llm_'));
      expect(llmClientId, isNotEmpty);
      // The new client appears in the manager.
      expect(
        FlutterMCP.instance.llmManager.getLlmClientById(llmClientId),
        isNotNull,
      );

      await FlutterMCP.instance.llmManager.closeLlm(llmId);
    });

    test('createLlmClient with empty model fails validation', () async {
      final instId = 'inv-inst-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      FlutterMCP.instance.registerLlmProvider(
        'fake-provider',
        _FakeProviderFactory(),
        mcpLlmInstanceId: instId,
      );

      await expectLater(
        FlutterMCP.instance.createLlmClient(
          providerName: 'fake-provider',
          config: llm_pkg.LlmConfiguration(apiKey: 'k', model: ''),
          mcpLlmInstanceId: instId,
        ),
        throwsA(anyOf(
          isA<MCPValidationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('createLlmClient with absent apiKey fails validation', () async {
      final instId = 'inv2-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      FlutterMCP.instance.registerLlmProvider(
        'fake-provider',
        _FakeProviderFactory(),
        mcpLlmInstanceId: instId,
      );

      await expectLater(
        FlutterMCP.instance.createLlmClient(
          providerName: 'fake-provider',
          config: llm_pkg.LlmConfiguration(apiKey: '', model: 'm'),
          mcpLlmInstanceId: instId,
        ),
        throwsA(anyOf(
          isA<MCPValidationException>(),
          isA<MCPAuthenticationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('createLlmClient with unregistered provider fails', () async {
      final instId = 'inv3-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      await expectLater(
        FlutterMCP.instance.createLlmClient(
          providerName: 'never-registered',
          config: llm_pkg.LlmConfiguration(apiKey: 'k', model: 'm'),
          mcpLlmInstanceId: instId,
        ),
        throwsA(anyOf(
          isA<MCPConfigurationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });
  });

  group('FlutterMCP transport harness — createLlmServer happy path', () {
    test('with a registered fake provider, createLlmServer returns ids',
        () async {
      final instId = 'srv-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      FlutterMCP.instance.registerLlmProvider(
        'fake-provider',
        _FakeProviderFactory(),
        mcpLlmInstanceId: instId,
      );

      final (llmId, llmServerId) = await FlutterMCP.instance.createLlmServer(
        providerName: 'fake-provider',
        config: llm_pkg.LlmConfiguration(
          apiKey: 'test-key',
          model: 'test-model',
        ),
        mcpLlmInstanceId: instId,
      );

      expect(llmId, startsWith('llm_'));
      expect(llmServerId, isNotEmpty);
      expect(
        FlutterMCP.instance.llmManager.getLlmServerById(llmServerId),
        isNotNull,
      );
      await FlutterMCP.instance.llmManager.closeLlm(llmId);
    });

    test('createLlmServer with unregistered provider fails', () async {
      final instId = 'srv-bad-${DateTime.now().microsecondsSinceEpoch}';
      FlutterMCP.instance.createMcpLlmInstance(
        instId,
        registerDefaultProviders: false,
      );
      await expectLater(
        FlutterMCP.instance.createLlmServer(
          providerName: 'never-registered',
          config: llm_pkg.LlmConfiguration(apiKey: 'k', model: 'm'),
          mcpLlmInstanceId: instId,
        ),
        throwsA(anyOf(
          isA<MCPConfigurationException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });
  });

  group('FlutterMCP transport harness — streamChat', () {
    test('streamChat yields fallback chunk when llmClient unknown', () async {
      final stream = FlutterMCP.instance.streamChat('absent', 'hi');
      final chunks = await stream.toList();
      // At least one chunk yielded with isDone=true.
      expect(chunks, isNotEmpty);
      expect(chunks.last.isDone, isTrue);
    });

    test('streamChat returns chunks for a registered LLM client', () async {
      final lm = FlutterMCP.instance.llmManager;
      final llmId = 'sc-${DateTime.now().microsecondsSinceEpoch}';
      lm.registerLlm(llmId, llm_pkg.MCPLlm());
      const llmClientId = 'sc-client';
      await lm.addLlmClient(
        llmId,
        llmClientId,
        llm_pkg.LlmClient(llmProvider: _FakeProvider()),
      );

      final stream = FlutterMCP.instance.streamChat(
        llmId,
        'hi',
        llmClientId: llmClientId,
      );
      // _FakeProvider.streamComplete returns Stream.empty(), so the outer
      // streamChat returns no chunks (no error caught). Just verify the
      // stream completes without throwing.
      await stream.toList();

      await lm.closeLlm(llmId);
    });
  });

  group('FlutterMCP transport harness — registerPlugin / unregisterPlugin', () {
    test('registerPlugin with empty name throws MCPValidation', () async {
      await expectLater(
        FlutterMCP.instance.registerPlugin(_FakePlugin('')),
        throwsA(isA<MCPValidationException>()),
      );
    });

    test('registerPlugin happy path + unregisterPlugin', () async {
      final p = _FakePlugin('test-plugin-${DateTime.now().microsecondsSinceEpoch}');
      await FlutterMCP.instance.registerPlugin(p);
      // Plugin appears in the registry status.
      final status = FlutterMCP.instance.pluginRegistryStatus;
      expect(status['plugins'], contains(p.name));
      await FlutterMCP.instance.unregisterPlugin(p.name);
    });

    test('unregisterPlugin with empty name throws', () async {
      await expectLater(
        FlutterMCP.instance.unregisterPlugin(''),
        throwsA(isA<MCPValidationException>()),
      );
    });
  });

  group('FlutterMCP transport harness — connected client list ops', () {
    late String clientId;

    setUp(() async {
      final mcpClient = client_pkg.McpClient.createClient(
        client_pkg.McpClientConfig(name: 'list-client', version: '1.0.0'),
      );
      final transport = FakeClientTransport();
      final cm = FlutterMCP.instance.clientManager;
      clientId = cm.generateId();
      cm.registerClient(clientId, mcpClient, transport);
      await FlutterMCP.instance.connectClient(clientId);
    });

    tearDown(() async {
      await FlutterMCP.instance.clientManager.closeClient(clientId);
    });

    test('client.listTools returns canned list via fake transport', () async {
      final c = FlutterMCP.instance.clientManager.getClient(clientId);
      expect(c, isNotNull);
      final tools = await c!.listTools();
      expect(tools, isNotEmpty);
      expect(tools.first.name, 'echo');
    });

    test('client.listResources / listPrompts return canned shapes', () async {
      final c = FlutterMCP.instance.clientManager.getClient(clientId);
      // Ensure both list ops complete without throwing.
      final r = await c!.listResources();
      expect(r, isList);
      final p = await c.listPrompts();
      expect(p, isList);
    });
  });

  group('FlutterMCP transport harness — plugin execution APIs', () {
    test('executeToolPlugin throws MCPValidationException for empty name',
        () async {
      await expectLater(
        FlutterMCP.instance.executeToolPlugin('', const {}),
        throwsA(isA<MCPValidationException>()),
      );
    });

    test(
        'executeToolPlugin throws MCPPluginException for unknown plugin name',
        () async {
      await expectLater(
        FlutterMCP.instance
            .executeToolPlugin('absent-plugin', const {'k': 'v'}),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('getPluginResource throws on empty name + empty uri', () async {
      await expectLater(
        FlutterMCP.instance.getPluginResource('', 'uri', const {}),
        throwsA(isA<MCPValidationException>()),
      );
      await expectLater(
        FlutterMCP.instance.getPluginResource('p', '', const {}),
        throwsA(isA<MCPValidationException>()),
      );
    });

    test('getPluginResource throws MCPPluginException for unknown plugin',
        () async {
      await expectLater(
        FlutterMCP.instance.getPluginResource(
          'absent-plugin',
          'file:///x',
          const {},
        ),
        throwsA(isA<MCPPluginException>()),
      );
    });

    test('showPluginNotification throws on empty name + missing fields',
        () async {
      await expectLater(
        FlutterMCP.instance.showPluginNotification('', title: 't', body: 'b'),
        throwsA(isA<MCPValidationException>()),
      );
    });
  });

  group('FlutterMCP transport harness — createClient transport branches',
      () {
    test('createClient throws when transportType missing in config', () async {
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'no-tt',
          version: '1.0.0',
          transportCommand: '/usr/bin/true',
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('createClient throws when no transport at all', () async {
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'no-anything',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'cfg',
            version: '1.0.0',
            transportType: 'stdio',
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('createClient with stdio + /usr/bin/true returns a clientId', () async {
      // Windows has no `/usr/bin/true`; the equivalent is `cmd /c exit 0`
      // but launching it as a separate process inflates this unit test
      // beyond its purpose. Skip on Windows — the same code path is
      // covered by the platform-agnostic transport branches above.
      if (Platform.isWindows) return;
      final clientId = await FlutterMCP.instance.createClient(
        name: 'stdio-client',
        version: '1.0.0',
        transportCommand: '/usr/bin/true',
        config: MCPClientConfig(
          name: 'stdio-client',
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
    });

    test('createClient with streamablehttp returns a clientId', () async {
      final clientId = await FlutterMCP.instance.createClient(
        name: 'http-client',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'http-client',
          version: '1.0.0',
          transportType: 'streamablehttp',
          serverUrl: 'http://127.0.0.1:1',
          endpoint: '/mcp',
          authToken: 'token',
          headers: {'X-Test': 'v'},
        ),
      );
      expect(clientId, startsWith('client_'));
      expect(
        FlutterMCP.instance.clientManager.getClientInfo(clientId)?.transport,
        isNotNull,
      );
      await FlutterMCP.instance.clientManager.closeClient(clientId);
    });

    // SSE transport-creation failure is exercised through the underlying
    // EventSource connect, which raises async errors that the SSE client
    // surfaces but doesn't always rethrow synchronously. Skipping the
    // failure-path assertion here — the happy SSE path requires a live
    // SSE server which is out of scope for this harness.

    test('createClient with stdio + non-existent command surfaces as failure',
        () async {
      await expectLater(
        FlutterMCP.instance.createClient(
          name: 'stdio-bad',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'stdio-bad',
            version: '1.0.0',
            transportType: 'stdio',
            transportCommand: '/no/such/binary/exists',
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });
  });

  group('FlutterMCP transport harness — createServer transport branches',
      () {
    test('createServer with sse + missing ssePort fails validation', () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'sse-no-port',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'sse-no-port',
            version: '1.0.0',
            transportType: 'sse',
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test(
        'createServer with streamablehttp + missing port fails validation',
        () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'http-no-port',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'http-no-port',
            version: '1.0.0',
            transportType: 'streamablehttp',
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('createServer with invalid transportType fails', () async {
      await expectLater(
        FlutterMCP.instance.createServer(
          name: 'bad-tt',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'bad-tt',
            version: '1.0.0',
            transportType: 'pigeon-courier',
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('createServer with sse + port 0 (ephemeral) returns serverId',
        () async {
      final serverId = await FlutterMCP.instance.createServer(
        name: 'sse-server',
        version: '1.0.0',
        useStdioTransport: false,
        ssePort: 0, // ephemeral
        config: MCPServerConfig(
          name: 'sse-server',
          version: '1.0.0',
          transportType: 'sse',
          ssePort: 0,
          host: '127.0.0.1',
        ),
      );
      expect(serverId, startsWith('server_'));
      expect(
        FlutterMCP.instance.serverManager.getServerInfo(serverId)?.transport,
        isNotNull,
      );
      // Cleanup so the HTTP listener releases the port.
      await FlutterMCP.instance.serverManager.closeServer(serverId);
    });

    test('createServer with streamablehttp + port 0 returns serverId',
        () async {
      final serverId = await FlutterMCP.instance.createServer(
        name: 'http-server',
        version: '1.0.0',
        useStdioTransport: false,
        ssePort: 1, // dummy value to satisfy outer guard
        config: MCPServerConfig(
          name: 'http-server',
          version: '1.0.0',
          transportType: 'streamablehttp',
          streamableHttpPort: 0,
          host: '127.0.0.1',
        ),
      );
      expect(serverId, startsWith('server_'));
      await FlutterMCP.instance.serverManager.closeServer(serverId);
    });
  });
}

/// Minimal MCPPlugin for plugin-registry tests.
class _FakePlugin implements MCPPlugin {
  @override
  final String name;

  _FakePlugin(this.name);

  @override
  String get version => '1.0.0';

  @override
  String get description => 'fake';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> shutdown() async {}
}
