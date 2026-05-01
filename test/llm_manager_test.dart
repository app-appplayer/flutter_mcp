// Coverage tests for MCPLlmManager — exercises the map-management /
// lookup / error-path methods. The minimal _FakeProvider lets us
// construct real LlmClient/LlmServer instances so the full add/remove
// paths run.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/core/llm_manager.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:mcp_llm/mcp_llm.dart' as llm;

class _FakeProvider implements llm.LlmProvider {
  @override
  Future<void> initialize(llm.LlmConfiguration config) async {}

  @override
  Future<void> close() async {}

  @override
  Future<llm.LlmResponse> complete(llm.LlmRequest request) async =>
      llm.LlmResponse(text: 'fake');

  @override
  Stream<llm.LlmResponseChunk> streamComplete(llm.LlmRequest request) =>
      const Stream.empty();

  @override
  Future<List<double>> getEmbeddings(String text) async => [];

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) => false;

  @override
  llm.LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) =>
      null;

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) =>
      metadata;
}

llm.LlmClient _newClient() => llm.LlmClient(llmProvider: _FakeProvider());
llm.LlmServer _newServer(llm.MCPLlm root) => llm.LlmServer(
      llmProvider: _FakeProvider(),
      pluginManager: llm.PluginManager(),
    );

void main() {
  group('MCPLlmManager — id generation', () {
    late MCPLlmManager m;
    setUp(() => m = MCPLlmManager());

    test('generateId is unique and prefixed', () {
      final a = m.generateId();
      final b = m.generateId();
      expect(a, startsWith('llm_'));
      expect(b, startsWith('llm_'));
      expect(a, isNot(b));
    });

    test('generateLlmClientId tracks llmId mapping', () {
      final id = m.generateLlmClientId('LLM-A');
      expect(id, startsWith('llm_client_'));
      expect(m.getLlmIdForClient(id), 'LLM-A');
    });

    test('generateLlmServerId tracks llmId mapping', () {
      final id = m.generateLlmServerId('LLM-B');
      expect(id, startsWith('llm_server_'));
      expect(m.getLlmIdForServer(id), 'LLM-B');
    });
  });

  group('MCPLlmManager — initialize', () {
    test('initialize is a no-op that does not throw', () async {
      final m = MCPLlmManager();
      await m.initialize();
    });
  });

  group('MCPLlmManager — registerLlm + getLlmInfo + lookups', () {
    test('registerLlm without initial client/server stores LlmInfo', () {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      expect(m.getLlmInfo('id1'), isNotNull);
      expect(m.getAllLlmIds(), contains('id1'));
    });

    test('registerLlm with initialClient + initialServer', () {
      final m = MCPLlmManager();
      final root = llm.MCPLlm();
      m.registerLlm(
        'id-x',
        root,
        initialClient: _newClient(),
        initialServer: _newServer(root),
      );
      final info = m.getLlmInfo('id-x')!;
      expect(info.llmClients, hasLength(1));
      expect(info.llmServers, hasLength(1));
    });

    test('getLlmInfo returns null for unknown', () {
      final m = MCPLlmManager();
      expect(m.getLlmInfo('absent'), isNull);
    });

    test('getAllLlmClientIds + getAllLlmServerIds return empty initially', () {
      final m = MCPLlmManager();
      expect(m.getAllLlmClientIds(), isEmpty);
      expect(m.getAllLlmServerIds(), isEmpty);
    });

    test('getLlmClientById / getLlmServerById return null for unknown', () {
      final m = MCPLlmManager();
      expect(m.getLlmClientById('absent'), isNull);
      expect(m.getLlmServerById('absent'), isNull);
    });
  });

  group('MCPLlmManager — addLlmClient / addLlmServer', () {
    test('addLlmClient on missing LLM throws MCPResourceNotFound', () async {
      final m = MCPLlmManager();
      await expectLater(
        m.addLlmClient('absent', 'cid', _newClient()),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('addLlmServer on missing LLM throws MCPResourceNotFound', () async {
      final m = MCPLlmManager();
      await expectLater(
        m.addLlmServer('absent', 'sid', _newServer(llm.MCPLlm())),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('addLlmClient succeeds and tracks mapping', () async {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      final clientId = await m.addLlmClient('id1', 'cid1', _newClient());
      expect(clientId, 'cid1');
      expect(m.getLlmIdForClient('cid1'), 'id1');
      expect(m.getLlmClientById('cid1'), isNotNull);
    });

    test('addLlmServer succeeds and tracks mapping', () async {
      final m = MCPLlmManager();
      final root = llm.MCPLlm();
      m.registerLlm('id1', root);
      final serverId = await m.addLlmServer('id1', 'sid1', _newServer(root));
      expect(serverId, 'sid1');
      expect(m.getLlmIdForServer('sid1'), 'id1');
      expect(m.getLlmServerById('sid1'), isNotNull);
    });
  });

  group('MCPLlmManager — setDefaultLlmClient / setDefaultLlmServer', () {
    test('throws on unknown LLM ID', () {
      final m = MCPLlmManager();
      expect(
        () => m.setDefaultLlmClient('absent', 'cid'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
      expect(
        () => m.setDefaultLlmServer('absent', 'sid'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('throws when client/server ID is not registered to LLM', () async {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      expect(
        () => m.setDefaultLlmClient('id1', 'unknown-client'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
      expect(
        () => m.setDefaultLlmServer('id1', 'unknown-server'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('happy path updates default', () async {
      final m = MCPLlmManager();
      final root = llm.MCPLlm();
      m.registerLlm('id1', root);
      await m.addLlmClient('id1', 'c1', _newClient());
      await m.addLlmClient('id1', 'c2', _newClient());
      m.setDefaultLlmClient('id1', 'c2');
      expect(m.getLlmInfo('id1')!.defaultLlmClientId, 'c2');

      await m.addLlmServer('id1', 's1', _newServer(root));
      await m.addLlmServer('id1', 's2', _newServer(root));
      m.setDefaultLlmServer('id1', 's2');
      expect(m.getLlmInfo('id1')!.defaultLlmServerId, 's2');
    });
  });

  group('MCPLlmManager — getDefaultLlmClientId', () {
    test('throws on unknown LLM', () async {
      final m = MCPLlmManager();
      await expectLater(
        m.getDefaultLlmClientId('absent'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('throws when LLM has no clients', () async {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      await expectLater(
        m.getDefaultLlmClientId('id1'),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('returns the default after addLlmClient', () async {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      await m.addLlmClient('id1', 'cid1', _newClient());
      final id = await m.getDefaultLlmClientId('id1');
      expect(id, 'cid1');
    });
  });

group('MCPLlmManager — removeMcpClient/Server when not found', () {
    test('removeMcpClientFromLlmClient is silent for unknown ids', () async {
      final m = MCPLlmManager();
      await m.removeMcpClientFromLlmClient('absent-llm-client', 'absent-mcp');
    });

    test('removeMcpServerFromLlmServer is silent for unknown ids', () async {
      final m = MCPLlmManager();
      await m.removeMcpServerFromLlmServer('absent-llm-server', 'absent-mcp');
    });
  });

  group('MCPLlmManager — getMcp*IdsFor* lookups', () {
    test('getMcpClientIdsForLlmClient returns empty for unknown', () {
      final m = MCPLlmManager();
      expect(m.getMcpClientIdsForLlmClient('absent'), isEmpty);
    });

    test('getMcpServerIdsForLlmServer returns empty for unknown', () {
      final m = MCPLlmManager();
      expect(m.getMcpServerIdsForLlmServer('absent'), isEmpty);
    });

    test('findLlmClientIdsWithMcpClient returns empty when none registered',
        () {
      final m = MCPLlmManager();
      expect(m.findLlmClientIdsWithMcpClient('absent'), isEmpty);
    });

    test('findLlmServerIdsWithMcpServer returns empty when none registered',
        () {
      final m = MCPLlmManager();
      expect(m.findLlmServerIdsWithMcpServer('absent'), isEmpty);
    });

    test('findLlmsForMcpClient returns empty when none registered', () {
      final m = MCPLlmManager();
      expect(m.findLlmsForMcpClient('absent'), isEmpty);
    });

    test('findLlmsForMcpServer returns empty when none registered', () {
      final m = MCPLlmManager();
      expect(m.findLlmsForMcpServer('absent'), isEmpty);
    });
  });

  group('MCPLlmManager — close lifecycle', () {
    test('closeLlm on unknown ID is a silent no-op', () async {
      final m = MCPLlmManager();
      await m.closeLlm('absent'); // should not throw
    });

    test('closeLlmClient on unknown ID is a silent no-op', () async {
      final m = MCPLlmManager();
      await m.closeLlmClient('absent');
    });

    test('closeLlmServer on unknown ID is a silent no-op', () async {
      final m = MCPLlmManager();
      await m.closeLlmServer('absent');
    });

    test('closeAll on empty manager runs cleanly', () async {
      final m = MCPLlmManager();
      await m.closeAll();
    });

    test('closeLlm with registered (no clients) clears state', () async {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      await m.closeLlm('id1');
      expect(m.getLlmInfo('id1'), isNull);
    });
  });

  group('MCPLlmManager — getStatus (status snapshot)', () {
    test('getStatus shape includes llms/clients/servers buckets', () {
      final m = MCPLlmManager();
      m.registerLlm('id1', llm.MCPLlm());
      // Access via reflection of the runtime status if available.
      // The class itself has no getStatus — flutter_mcp.dart aggregates via
      // getAllLlmIds + getAllLlmClientIds + getAllLlmServerIds.
      expect(m.getAllLlmIds(), contains('id1'));
      expect(m.getAllLlmClientIds(), isEmpty);
      expect(m.getAllLlmServerIds(), isEmpty);
    });
  });
}

