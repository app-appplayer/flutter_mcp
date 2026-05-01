// Coverage tests for LlmInfo — exercises the data-class methods directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/managers/llm_info.dart';
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
llm.LlmServer _newServer() => llm.LlmServer(
      llmProvider: _FakeProvider(),
      pluginManager: llm.PluginManager(),
    );

void main() {
  group('LlmInfo — initial registration', () {
    test('without initialClient/Server: empty maps + null defaults', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      expect(info.id, 'L1');
      expect(info.llmClients, isEmpty);
      expect(info.llmServers, isEmpty);
      expect(info.defaultLlmClientId, isNull);
      expect(info.defaultLlmServerId, isNull);
      expect(info.primaryClient, isNull);
      expect(info.primaryServer, isNull);
      expect(info.defaultLlmClient, isNull);
      expect(info.defaultLlmServer, isNull);
      expect(info.hasClients(), isFalse);
      expect(info.hasServers(), isFalse);
    });

    test('with initialClient: registers as primary_client_<id>', () {
      final info = LlmInfo(
        id: 'L1',
        mcpLlm: llm.MCPLlm(),
        initialClient: _newClient(),
      );
      expect(info.llmClients.keys, ['primary_client_L1']);
      expect(info.defaultLlmClientId, 'primary_client_L1');
      expect(info.primaryClient, isNotNull);
      expect(info.defaultLlmClient, isNotNull);
      expect(info.hasClients(), isTrue);
      expect(info.llmClientPluginManagers, hasLength(1));
    });

    test('with initialServer: registers as primary_server_<id>', () {
      final info = LlmInfo(
        id: 'L1',
        mcpLlm: llm.MCPLlm(),
        initialServer: _newServer(),
      );
      expect(info.llmServers.keys, ['primary_server_L1']);
      expect(info.defaultLlmServerId, 'primary_server_L1');
      expect(info.primaryServer, isNotNull);
      expect(info.defaultLlmServer, isNotNull);
      expect(info.hasServers(), isTrue);
      expect(info.llmServerPluginManagers, hasLength(1));
    });
  });

  group('LlmInfo — addLlmClient + removeLlmClient', () {
    test('add multiple, first becomes default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.addLlmClient('c2', _newClient());
      expect(info.defaultLlmClientId, 'c1');
      expect(info.llmClients, hasLength(2));
    });

    test('remove default client picks next as new default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.addLlmClient('c2', _newClient());
      info.removeLlmClient('c1');
      expect(info.defaultLlmClientId, 'c2');
    });

    test('remove last client clears default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.removeLlmClient('c1');
      expect(info.defaultLlmClientId, isNull);
    });

    test('removeLlmClient on unknown returns null', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      expect(info.removeLlmClient('absent'), isNull);
    });
  });

  group('LlmInfo — addLlmServer + removeLlmServer', () {
    test('add multiple, first becomes default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmServer('s1', _newServer());
      info.addLlmServer('s2', _newServer());
      expect(info.defaultLlmServerId, 's1');
      expect(info.llmServers, hasLength(2));
    });

    test('remove default server picks next as new default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmServer('s1', _newServer());
      info.addLlmServer('s2', _newServer());
      info.removeLlmServer('s1');
      expect(info.defaultLlmServerId, 's2');
    });

    test('remove last server clears default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmServer('s1', _newServer());
      info.removeLlmServer('s1');
      expect(info.defaultLlmServerId, isNull);
    });
  });

  group('LlmInfo — setDefault*', () {
    test('setDefaultLlmClient on unknown is a no-op', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.setDefaultLlmClient('absent');
      expect(info.defaultLlmClientId, 'c1'); // unchanged
    });

    test('setDefaultLlmClient on known updates default', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.addLlmClient('c2', _newClient());
      info.setDefaultLlmClient('c2');
      expect(info.defaultLlmClientId, 'c2');
    });

    test('setDefaultLlmServer on unknown is a no-op', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmServer('s1', _newServer());
      info.setDefaultLlmServer('absent');
      expect(info.defaultLlmServerId, 's1');
    });
  });

  group('LlmInfo — associate / disassociate Mcp client', () {
    test('associate adds the link, getLlmClientIdsForMcpClient lists it', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.associateMcpClient('mcp1', 'c1');
      info.associateMcpClient('mcp1', 'c2');
      expect(info.getLlmClientIdsForMcpClient('mcp1'), {'c1', 'c2'});
      expect(info.getAllMcpClientIds(), {'mcp1'});
    });

    test('disassociate removes only the matching pair', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.associateMcpClient('mcp1', 'c1');
      info.associateMcpClient('mcp1', 'c2');
      info.disassociateMcpClient('mcp1', 'c1');
      expect(info.getLlmClientIdsForMcpClient('mcp1'), {'c2'});
    });

    test('disassociate of last LLM client clears the entry', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.associateMcpClient('mcp1', 'c1');
      info.disassociateMcpClient('mcp1', 'c1');
      expect(info.getAllMcpClientIds(), isEmpty);
    });

    test('disassociate of unknown is a no-op', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.disassociateMcpClient('absent', 'absent');
      expect(info.getAllMcpClientIds(), isEmpty);
    });

    test('getLlmClientIdsForMcpClient returns empty for unknown', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      expect(info.getLlmClientIdsForMcpClient('absent'), isEmpty);
    });
  });

  group('LlmInfo — associate / disassociate Mcp server', () {
    test('associate + getLlmServerIdsForMcpServer + getAllMcpServerIds', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.associateMcpServer('mcps1', 's1');
      info.associateMcpServer('mcps1', 's2');
      expect(info.getLlmServerIdsForMcpServer('mcps1'), {'s1', 's2'});
      expect(info.getAllMcpServerIds(), {'mcps1'});
    });

    test('disassociate removes one, then last clears entry', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.associateMcpServer('mcps1', 's1');
      info.associateMcpServer('mcps1', 's2');
      info.disassociateMcpServer('mcps1', 's2');
      expect(info.getLlmServerIdsForMcpServer('mcps1'), {'s1'});
      info.disassociateMcpServer('mcps1', 's1');
      expect(info.getAllMcpServerIds(), isEmpty);
    });

    test('getLlmServerIdsForMcpServer returns empty for unknown', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      expect(info.getLlmServerIdsForMcpServer('absent'), isEmpty);
    });
  });

  group('LlmInfo — getAllLlmClientIds / getAllLlmServerIds', () {
    test('lists registered keys', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.addLlmClient('c2', _newClient());
      info.addLlmServer('s1', _newServer());
      expect(info.getAllLlmClientIds(), {'c1', 'c2'});
      expect(info.getAllLlmServerIds(), {'s1'});
    });
  });

  group('LlmInfo — plugin manager helpers', () {
    test('setLlmClientPluginManager / getLlmClientPluginManager round-trip',
        () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      final pm = llm.PluginManager();
      info.setLlmClientPluginManager('c1', pm);
      expect(info.getLlmClientPluginManager('c1'), same(pm));
    });

    test('setLlmServerPluginManager / getLlmServerPluginManager round-trip',
        () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmServer('s1', _newServer());
      final pm = llm.PluginManager();
      info.setLlmServerPluginManager('s1', pm);
      expect(info.getLlmServerPluginManager('s1'), same(pm));
    });

    test('setLlmClientPluginManager on unknown is a silent no-op', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      final pm = llm.PluginManager();
      info.setLlmClientPluginManager('absent', pm);
      expect(info.getLlmClientPluginManager('absent'), isNull);
    });

    test('getAllClientPluginManagers / getAllServerPluginManagers / All', () {
      final info = LlmInfo(id: 'L1', mcpLlm: llm.MCPLlm());
      info.addLlmClient('c1', _newClient());
      info.addLlmServer('s1', _newServer());
      expect(info.getAllClientPluginManagers(), hasLength(1));
      expect(info.getAllServerPluginManagers(), hasLength(1));
      expect(info.getAllPluginManagers(), hasLength(2));
    });
  });
}
