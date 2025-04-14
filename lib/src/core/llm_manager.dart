import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_server/mcp_server.dart';
import '../managers/llm_info.dart';
import '../utils/logger.dart';

/// MCP LLM Manager with improved multi-client and multi-server support
class MCPLlmManager {
  /// Registered LLMs (llmId -> LlmInfo)
  final Map<String, LlmInfo> _llms = {};

  /// Map of MCP client IDs to LLM IDs
  final Map<String, Set<String>> _mcpClientToLlmMap = {};

  /// Map of MCP server IDs to LLM IDs
  final Map<String, Set<String>> _mcpServerToLlmMap = {};

  /// LLM counter (for ID generation)
  int _counter = 0;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.llm_manager');

  /// Initialize
  Future<void> initialize() async {
    _logger.debug('LLM manager initialization');
  }

  /// Generate new LLM ID
  String generateId() {
    _counter++;
    return 'llm_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Generate new LLM client ID
  String generateLlmClientId(String llmId) {
    return 'llm_client_${llmId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate new LLM server ID
  String generateLlmServerId(String llmId) {
    return 'llm_server_${llmId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Register LLM with flexible initialization
  /// Allows creation with client, server, both, or neither
  void registerLlm(String id, MCPLlm mcpLlm, {LlmClient? initialClient, LlmServer? initialServer}) {
    _logger.debug('Registering LLM: $id${initialClient != null ? " with initial client" : ""}${initialServer != null ? " with initial server" : ""}');

    _llms[id] = LlmInfo(
      id: id,
      mcpLlm: mcpLlm,
      initialClient: initialClient,
      initialServer: initialServer,
    );
  }

  /// Add a new LLM client to an existing LLM
  Future<String> addLlmClient(String llmId, String llmClientId, LlmClient client) async {
    _logger.debug('Adding LLM client to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    llmInfo.addLlmClient(llmClientId, client);

    _logger.info('Added LLM client $llmClientId to LLM $llmId');
    return llmClientId;
  }

  /// Add a new LLM server to an existing LLM
  Future<String> addLlmServer(String llmId, String llmServerId, LlmServer server) async {
    _logger.debug('Adding LLM server to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    llmInfo.addLlmServer(llmServerId, server);

    _logger.info('Added LLM server $llmServerId to LLM $llmId');
    return llmServerId;
  }

  /// Find LLM info that contains the given LLM client ID
  (LlmInfo?, String?) _findLlmInfoByClientId(String llmClientId) {
    for (final entry in _llms.entries) {
      if (entry.value.llmClients.containsKey(llmClientId)) {
        return (entry.value, entry.key);
      }
    }
    return (null, null);
  }

  /// Find LLM info that contains the given LLM server ID
  (LlmInfo?, String?) _findLlmInfoByServerId(String llmServerId) {
    for (final entry in _llms.entries) {
      if (entry.value.llmServers.containsKey(llmServerId)) {
        return (entry.value, entry.key);
      }
    }
    return (null, null);
  }

  /// Add MCP client to LLM client by client ID
  Future<void> addMcpClientToLlmClient(
      String llmClientId,
      String mcpClientId,
      Client mcpClient
      ) async {
    _logger.debug('Adding MCP client $mcpClientId to LLM client $llmClientId');

    // Find the LLM containing this client
    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);

    if (llmInfo == null || llmId == null) {
      throw Exception('LLM client not found: $llmClientId');
    }

    // Get the LLM client
    final llmClient = llmInfo.llmClients[llmClientId];
    if (llmClient == null) {
      throw Exception('LLM client object not found: $llmClientId');
    }

    // Directly add MCP client to the LLM client
    try {
      llmInfo.mcpLlm.addMcpClientToLlmClient(llmClientId, mcpClientId, mcpClient);
      _logger.info('Added MCP client $mcpClientId directly to LLM client $llmClientId');
    } catch (e) {
      _logger.error('Failed to add MCP client directly: $e');
      throw Exception('Failed to add MCP client: $e');
    }

    // Track associations
    llmInfo.associateMcpClient(mcpClientId, llmClientId);
    _mcpClientToLlmMap.putIfAbsent(mcpClientId, () => {}).add(llmId);

    _logger.info('Associated MCP client $mcpClientId with LLM client $llmClientId');
  }

  /// Add MCP server to LLM server by server ID
  Future<void> addMcpServerToLlmServer(
      String llmServerId,
      String mcpServerId,
      Server mcpServer
      ) async {
    _logger.debug('Adding MCP server $mcpServerId to LLM server $llmServerId');

    // Find the LLM containing this server
    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);

    if (llmInfo == null || llmId == null) {
      throw Exception('LLM server not found: $llmServerId');
    }

    // Get the LLM server
    final llmServer = llmInfo.llmServers[llmServerId];
    if (llmServer == null) {
      throw Exception('LLM server object not found: $llmServerId');
    }

    // Directly add MCP server to the LLM server
    try {
      llmInfo.mcpLlm.addMcpServerToLlmServer(llmServerId, mcpServerId, mcpServer);
      _logger.info('Added MCP server $mcpServerId directly to LLM server $llmServerId');
    } catch (e) {
      _logger.error('Failed to add MCP server directly: $e');
      throw Exception('Failed to add MCP server: $e');
    }

    // Track associations
    llmInfo.associateMcpServer(mcpServerId, llmServerId);
    _mcpServerToLlmMap.putIfAbsent(mcpServerId, () => {}).add(llmId);

    _logger.info('Associated MCP server $mcpServerId with LLM server $llmServerId');
  }

  /// Find default LLM client ID for an LLM
  Future<String> getDefaultLlmClientId(String llmId) async {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    if (!llmInfo.hasClients()) {
      throw Exception('LLM has no clients available. Create a client for $llmId first.');
    }

    final defaultLlmClientId = llmInfo.defaultLlmClientId;
    if (defaultLlmClientId == null) {
      throw Exception('No default LLM client available for LLM: $llmId');
    }

    return defaultLlmClientId;
  }

  /// Add MCP client to default LLM client for an LLM
  Future<void> addMcpClientToDefaultLlmClient(String llmId, Client mcpClient) async {
    final defaultLlmClientId = await getDefaultLlmClientId(llmId);
    await addMcpClientToLlmClient(
        defaultLlmClientId,
        mcpClient.name,
        mcpClient
    );
  }

  /// Remove MCP client from LLM client
  Future<void> removeMcpClientFromLlmClient(
      String llmClientId,
      String mcpClientId
      ) async {
    _logger.debug('Removing MCP client $mcpClientId from LLM client $llmClientId');

    // Find the LLM containing this client
    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);

    if (llmInfo == null || llmId == null) {
      _logger.warning('LLM client not found when removing MCP client: $llmClientId');
      return;
    }

    // Get the LLM client
    final llmClient = llmInfo.llmClients[llmClientId];
    if (llmClient == null) {
      _logger.warning('LLM client object not found: $llmClientId');
      return;
    }

    // Remove the MCP client
    try {
      llmInfo.mcpLlm.removeMcpClientFromLlmClient(llmClientId, mcpClientId);
      _logger.info('Removed MCP client $mcpClientId from LLM client $llmClientId');
    } catch (e) {
      _logger.error('Failed to remove MCP client: $e');
    }

    // Update tracking
    llmInfo.disassociateMcpClient(mcpClientId, llmClientId);

    // Update global tracking
    final llmIds = _mcpClientToLlmMap[mcpClientId];
    if (llmIds != null) {
      llmIds.remove(llmId);
      if (llmIds.isEmpty) {
        _mcpClientToLlmMap.remove(mcpClientId);
      }
    }
  }

  /// Remove MCP server from LLM server
  Future<void> removeMcpServerFromLlmServer(
      String llmServerId,
      String mcpServerId
      ) async {
    _logger.debug('Removing MCP server $mcpServerId from LLM server $llmServerId');

    // Find the LLM containing this server
    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);

    if (llmInfo == null || llmId == null) {
      _logger.warning('LLM server not found when removing MCP server: $llmServerId');
      return;
    }

    // Get the LLM server
    final llmServer = llmInfo.llmServers[llmServerId];
    if (llmServer == null) {
      _logger.warning('LLM server object not found: $llmServerId');
      return;
    }

    // Remove the MCP server
    try {
      llmInfo.mcpLlm.removeMcpServerFromLlmServer(llmServerId, mcpServerId);
      _logger.info('Removed MCP server $mcpServerId from LLM server $llmServerId');
    } catch (e) {
      _logger.error('Failed to remove MCP server: $e');
    }

    // Update tracking
    llmInfo.disassociateMcpServer(mcpServerId, llmServerId);

    // Update global tracking
    final llmIds = _mcpServerToLlmMap[mcpServerId];
    if (llmIds != null) {
      llmIds.remove(llmId);
      if (llmIds.isEmpty) {
        _mcpServerToLlmMap.remove(mcpServerId);
      }
    }
  }

  /// Set default MCP client for a specific LLM client
  Future<void> setDefaultMcpClientForLlmClient(
      String llmClientId,
      String mcpClientId
      ) async {
    _logger.debug('Setting default MCP client $mcpClientId for LLM client $llmClientId');

    // Find the LLM containing this client
    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);

    if (llmInfo == null || llmId == null) {
      throw Exception('LLM client not found: $llmClientId');
    }

    // Verify the MCP client is associated with this LLM client
    final associatedLlmClientIds = llmInfo.getLlmClientIdsForMcpClient(mcpClientId);
    if (!associatedLlmClientIds.contains(llmClientId)) {
      throw Exception('MCP client $mcpClientId is not associated with LLM client $llmClientId');
    }

    // Get the LLM client
    final llmClient = llmInfo.llmClients[llmClientId];
    if (llmClient == null) {
      throw Exception('LLM client object not found: $llmClientId');
    }

    // Set as default (assuming this method exists on LlmClient)
    try {
      llmInfo.mcpLlm.setDefaultMcpClient(llmClientId, mcpClientId);
      _logger.info('Set default MCP client to $mcpClientId for LLM client $llmClientId');
    } catch (e) {
      _logger.error('Failed to set default MCP client: $e');
      throw Exception('Failed to set default MCP client: $e');
    }
  }

  /// Set default MCP server for a specific LLM server
  Future<void> setDefaultMcpServerForLlmServer(
      String llmServerId,
      String mcpServerId
      ) async {
    _logger.debug('Setting default MCP server $mcpServerId for LLM server $llmServerId');

    // Find the LLM containing this server
    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);

    if (llmInfo == null || llmId == null) {
      throw Exception('LLM server not found: $llmServerId');
    }

    // Verify the MCP server is associated with this LLM server
    final associatedLlmServerIds = llmInfo.getLlmServerIdsForMcpServer(mcpServerId);
    if (!associatedLlmServerIds.contains(llmServerId)) {
      throw Exception('MCP server $mcpServerId is not associated with LLM server $llmServerId');
    }

    // Get the LLM server
    final llmServer = llmInfo.llmServers[llmServerId];
    if (llmServer == null) {
      throw Exception('LLM server object not found: $llmServerId');
    }

    // Set as default (assuming this method exists on LlmServer)
    try {
      llmInfo.mcpLlm.setDefaultMcpServer(llmServerId, mcpServerId);
      _logger.info('Set default MCP server to $mcpServerId for LLM server $llmServerId');
    } catch (e) {
      _logger.error('Failed to set default MCP server: $e');
      throw Exception('Failed to set default MCP server: $e');
    }
  }

  /// Get LLM info
  LlmInfo? getLlmInfo(String id) {
    return _llms[id];
  }

  /// Get LLM client by ID directly
  LlmClient? getLlmClientById(String llmClientId) {
    final (llmInfo, _) = _findLlmInfoByClientId(llmClientId);
    return llmInfo?.llmClients[llmClientId];
  }

  /// Get LLM server by ID directly
  LlmServer? getLlmServerById(String llmServerId) {
    final (llmInfo, _) = _findLlmInfoByServerId(llmServerId);
    return llmInfo?.llmServers[llmServerId];
  }

  /// Get all LLM IDs
  List<String> getAllLlmIds() {
    return _llms.keys.toList();
  }

  /// Get all LLM client IDs across all LLMs
  List<String> getAllLlmClientIds() {
    final result = <String>[];
    for (final llmInfo in _llms.values) {
      result.addAll(llmInfo.llmClients.keys);
    }
    return result;
  }

  /// Get all LLM server IDs across all LLMs
  List<String> getAllLlmServerIds() {
    final result = <String>[];
    for (final llmInfo in _llms.values) {
      result.addAll(llmInfo.llmServers.keys);
    }
    return result;
  }

  /// Get all MCP client IDs associated with a specific LLM client
  Set<String> getMcpClientIdsForLlmClient(String llmClientId) {
    final (llmInfo, _) = _findLlmInfoByClientId(llmClientId);
    if (llmInfo == null) {
      return {};
    }

    final result = <String>{};
    for (final mcpClientId in llmInfo.getAllMcpClientIds()) {
      if (llmInfo.getLlmClientIdsForMcpClient(mcpClientId).contains(llmClientId)) {
        result.add(mcpClientId);
      }
    }
    return result;
  }

  /// Get all MCP server IDs associated with a specific LLM server
  Set<String> getMcpServerIdsForLlmServer(String llmServerId) {
    final (llmInfo, _) = _findLlmInfoByServerId(llmServerId);
    if (llmInfo == null) {
      return {};
    }

    final result = <String>{};
    for (final mcpServerId in llmInfo.getAllMcpServerIds()) {
      if (llmInfo.getLlmServerIdsForMcpServer(mcpServerId).contains(llmServerId)) {
        result.add(mcpServerId);
      }
    }
    return result;
  }

  /// Find LLM client IDs containing a specific MCP client
  List<String> findLlmClientIdsWithMcpClient(String mcpClientId) {
    final result = <String>[];
    for (final llmInfo in _llms.values) {
      result.addAll(llmInfo.getLlmClientIdsForMcpClient(mcpClientId));
    }
    return result;
  }

  /// Find LLM server IDs containing a specific MCP server
  List<String> findLlmServerIdsWithMcpServer(String mcpServerId) {
    final result = <String>[];
    for (final llmInfo in _llms.values) {
      result.addAll(llmInfo.getLlmServerIdsForMcpServer(mcpServerId));
    }
    return result;
  }

  /// Find LLMs associated with an MCP client
  List<String> findLlmsForMcpClient(String mcpClientId) {
    return _mcpClientToLlmMap[mcpClientId]?.toList() ?? [];
  }

  /// Find LLMs associated with an MCP server
  List<String> findLlmsForMcpServer(String mcpServerId) {
    return _mcpServerToLlmMap[mcpServerId]?.toList() ?? [];
  }

  /// Close all resources and connections for an LLM
  Future<void> closeLlm(String id) async {
    _logger.debug('Closing LLM: $id');
    final llmInfo = _llms[id];
    if (llmInfo == null) {
      return;
    }

    // Close all LLM clients
    for (final client in llmInfo.llmClients.values) {
      await client.close();
    }

    // Close all LLM servers
    for (final server in llmInfo.llmServers.values) {
      await server.close();
    }

    // Remove from tracking maps
    for (final mcpClientId in llmInfo.getAllMcpClientIds()) {
      final llmIds = _mcpClientToLlmMap[mcpClientId];
      if (llmIds != null) {
        llmIds.remove(id);
        if (llmIds.isEmpty) {
          _mcpClientToLlmMap.remove(mcpClientId);
        }
      }
    }

    for (final mcpServerId in llmInfo.getAllMcpServerIds()) {
      final llmIds = _mcpServerToLlmMap[mcpServerId];
      if (llmIds != null) {
        llmIds.remove(id);
        if (llmIds.isEmpty) {
          _mcpServerToLlmMap.remove(mcpServerId);
        }
      }
    }

    // Remove the LLM
    _llms.remove(id);
  }

  /// Close a specific LLM client
  Future<void> closeLlmClient(String llmClientId) async {
    _logger.debug('Closing LLM client: $llmClientId');

    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);
    if (llmInfo == null || llmId == null) {
      _logger.warning('LLM client not found for closure: $llmClientId');
      return;
    }

    // Close the client
    final client = llmInfo.llmClients[llmClientId];
    if (client != null) {
      await client.close();
    }

    // Remove MCP client associations
    final mcpClientIds = getMcpClientIdsForLlmClient(llmClientId).toList();
    for (final mcpClientId in mcpClientIds) {
      llmInfo.disassociateMcpClient(mcpClientId, llmClientId);
    }

    // Remove the client from LLM info
    llmInfo.removeLlmClient(llmClientId);
  }

  /// Close a specific LLM server
  Future<void> closeLlmServer(String llmServerId) async {
    _logger.debug('Closing LLM server: $llmServerId');

    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);
    if (llmInfo == null || llmId == null) {
      _logger.warning('LLM server not found for closure: $llmServerId');
      return;
    }

    // Close the server
    final server = llmInfo.llmServers[llmServerId];
    if (server != null) {
      await server.close();
    }

    // Remove MCP server associations
    final mcpServerIds = getMcpServerIdsForLlmServer(llmServerId).toList();
    for (final mcpServerId in mcpServerIds) {
      llmInfo.disassociateMcpServer(mcpServerId, llmServerId);
    }

    // Remove the server from LLM info
    llmInfo.removeLlmServer(llmServerId);
  }

  /// Close all LLMs
  Future<void> closeAll() async {
    _logger.debug('Closing all LLMs');
    for (final id in _llms.keys.toList()) {
      await closeLlm(id);
    }
  }

  /// Get status information
  Map<String, dynamic> getStatus() {
    return {
      'total': _llms.length,
      'llms': _llms.map((key, value) => MapEntry(key, {
        'clientCount': value.llmClients.length,
        'serverCount': value.llmServers.length,
        'mcpClientCount': value.getAllMcpClientIds().length,
        'mcpServerCount': value.getAllMcpServerIds().length,
        'defaultLlmClientId': value.defaultLlmClientId,
        'defaultLlmServerId': value.defaultLlmServerId,
      })),
    };
  }
}

/*import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_server/mcp_server.dart';
import '../managers/llm_info.dart';
import '../utils/logger.dart';

/// MCP LLM Manager with improved multi-client and multi-server support
class MCPLlmManager {
  /// Registered LLMs (llmId -> LlmInfo)
  final Map<String, LlmInfo> _llms = {};

  /// Map of MCP client IDs to LLM IDs
  final Map<String, Set<String>> _mcpClientToLlmMap = {};

  /// Map of MCP server IDs to LLM IDs
  final Map<String, Set<String>> _mcpServerToLlmMap = {};

  /// LLM counter (for ID generation)
  int _counter = 0;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.llm_manager');

  /// Initialize
  Future<void> initialize() async {
    _logger.debug('LLM manager initialization');
  }

  /// Generate new LLM ID
  String generateId() {
    _counter++;
    return 'llm_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Generate new LLM client ID
  String generateLlmClientId(String llmId) {
    return 'llm_client_${llmId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate new LLM server ID
  String generateLlmServerId(String llmId) {
    return 'llm_server_${llmId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Register LLM with flexible initialization
  /// Allows creation with client, server, both, or neither
  void registerLlm(String id, MCPLlm mcpLlm, {LlmClient? initialClient, LlmServer? initialServer}) {
    _logger.debug('Registering LLM: $id${initialClient != null ? " with initial client" : ""}${initialServer != null ? " with initial server" : ""}');

    _llms[id] = LlmInfo(
      id: id,
      mcpLlm: mcpLlm,
      initialClient: initialClient,
      initialServer: initialServer,
    );
  }

  /// Add a new LLM client to an existing LLM
  Future<String> addLlmClient(String llmId, String llmClientId, LlmClient client) async {
    _logger.debug('Adding LLM client to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    llmInfo.addLlmClient(llmClientId, client);

    _logger.info('Added LLM client $llmClientId to LLM $llmId');
    return llmClientId;
  }

  /// Add a new LLM server to an existing LLM
  Future<String> addLlmServer(String llmId, String llmServerId, LlmServer server) async {
    _logger.debug('Adding LLM server to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    llmInfo.addLlmServer(llmServerId, server);

    _logger.info('Added LLM server $llmServerId to LLM $llmId');
    return llmServerId;
  }

  /// Associate an MCP client with a specific LLM and LLM client
  Future<void> associateMcpClientWithLlmClient(
      String llmId,
      String llmClientId,
      String mcpClientId,
      Client mcpClient
      ) async {
    _logger.debug('Associating MCP client $mcpClientId with LLM client $llmClientId in LLM $llmId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    if (!llmInfo.llmClients.containsKey(llmClientId)) {
      throw Exception('LLM client not found: $llmClientId in LLM $llmId');
    }

    // Use MCPLlm to add the MCP client to the LLM client
    await llmInfo.mcpLlm.addMcpClientToLlmClient(
        llmClientId,
        mcpClientId,
        mcpClient
    );

    // Track associations
    llmInfo.associateMcpClient(mcpClientId, llmClientId);
    _mcpClientToLlmMap.putIfAbsent(mcpClientId, () => {}).add(llmId);

    _logger.info('Associated MCP client $mcpClientId with LLM client $llmClientId in LLM $llmId');
  }

  /// Associate an MCP server with a specific LLM and LLM server
  Future<void> associateMcpServerWithLlmServer(
      String llmId,
      String llmServerId,
      String mcpServerId,
      Server mcpServer
      ) async {
    _logger.debug('Associating MCP server $mcpServerId with LLM server $llmServerId in LLM $llmId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    if (!llmInfo.llmServers.containsKey(llmServerId)) {
      throw Exception('LLM server not found: $llmServerId in LLM $llmId');
    }

    // Use MCPLlm to add the MCP server to the LLM server
    await llmInfo.mcpLlm.addMcpServerToLlmServer(
        llmServerId,
        mcpServerId,
        mcpServer
    );

    // Track associations
    llmInfo.associateMcpServer(mcpServerId, llmServerId);
    _mcpServerToLlmMap.putIfAbsent(mcpServerId, () => {}).add(llmId);

    _logger.info('Associated MCP server $mcpServerId with LLM server $llmServerId in LLM $llmId');
  }

  /// Add MCP client to an LLM (using the default LLM client)
  Future<void> addClientToLlm(String llmId, Client mcpClient) async {
    _logger.debug('Adding client to LLM: $llmId, ${mcpClient.name}');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    // If no LLM clients exist, throw error - we need to create one first
    if (!llmInfo.hasClients()) {
      throw Exception('LLM has no clients available. Create a client for $llmId first.');
    }

    final defaultLlmClientId = llmInfo.defaultLlmClientId;
    if (defaultLlmClientId == null) {
      throw Exception('No default LLM client available for LLM: $llmId');
    }

    await associateMcpClientWithLlmClient(
        llmId,
        defaultLlmClientId,
        mcpClient.name,
        mcpClient
    );
  }

  /// Remove client from LLM
  Future<void> removeClientFromLlm(String llmId, String mcpClientId) async {
    _logger.debug('Removing client from LLM: $llmId, $mcpClientId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      _logger.warning('LLM not found when removing client: $llmId');
      return;
    }

    // Get all LLM client IDs associated with this MCP client
    final llmClientIds = llmInfo.getLlmClientIdsForMcpClient(mcpClientId);

    for (final llmClientId in llmClientIds) {
      // Remove the association from MCPLlm
      await llmInfo.mcpLlm.removeMcpClientFromLlmClient(
          llmClientId,
          mcpClientId
      );

      // Update our tracking
      llmInfo.disassociateMcpClient(mcpClientId, llmClientId);
    }

    // Remove from global tracking
    final llmIds = _mcpClientToLlmMap[mcpClientId];
    if (llmIds != null) {
      llmIds.remove(llmId);
      if (llmIds.isEmpty) {
        _mcpClientToLlmMap.remove(mcpClientId);
      }
    }

    _logger.info('Client $mcpClientId removed from LLM $llmId');
  }

  /// Add server to an LLM (using the default LLM server or creating one if none exists)
  Future<void> addServerToLlm(String llmId, Server mcpServer) async {
    _logger.debug('Adding server to LLM: $llmId, ${mcpServer.name}');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    if (!llmInfo.hasServers()) {
      // No LLM server exists yet - create one
      Exception('LLM has no clients available. Create a client for $llmId first.');
    }

    // Associate with the existing default LLM server
    final defaultLlmServerId = llmInfo.defaultLlmServerId;
    if (defaultLlmServerId == null) {
      throw Exception('No default LLM server available for LLM: $llmId');
    }

    await associateMcpServerWithLlmServer(
        llmId,
        defaultLlmServerId,
        mcpServer.name,
        mcpServer
    );
  }

  /// Remove server from LLM
  Future<void> removeServerFromLlm(String llmId, String mcpServerId) async {
    _logger.debug('Removing server from LLM: $llmId, $mcpServerId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      _logger.warning('LLM not found when removing server: $llmId');
      return;
    }

    // Get all LLM server IDs associated with this MCP server
    final llmServerIds = llmInfo.getLlmServerIdsForMcpServer(mcpServerId);

    for (final llmServerId in llmServerIds) {
      // Remove the association from MCPLlm
      await llmInfo.mcpLlm.removeMcpServerFromLlmServer(
          llmServerId,
          mcpServerId
      );

      // Update our tracking
      llmInfo.disassociateMcpServer(mcpServerId, llmServerId);
    }

    // Remove from global tracking
    final llmIds = _mcpServerToLlmMap[mcpServerId];
    if (llmIds != null) {
      llmIds.remove(llmId);
      if (llmIds.isEmpty) {
        _mcpServerToLlmMap.remove(mcpServerId);
      }
    }

    _logger.info('Server $mcpServerId removed from LLM $llmId');
  }

  /// Set default client for LLM
  Future<void> setDefaultClientForLlm(String llmId, String mcpClientId) async {
    _logger.debug('Setting default client for LLM: $llmId, $mcpClientId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    // Find an LLM client associated with this MCP client
    final llmClientIds = llmInfo.getLlmClientIdsForMcpClient(mcpClientId);
    if (llmClientIds.isEmpty) {
      throw Exception('No LLM client associated with MCP client $mcpClientId in LLM $llmId');
    }

    // Use the first associated LLM client
    final llmClientId = llmClientIds.first;

    // Set as default in MCPLlm
    await llmInfo.mcpLlm.setDefaultMcpClient(
        llmClientId,
        mcpClientId
    );

    _logger.info('Default client for LLM $llmId set to MCP client $mcpClientId via LLM client $llmClientId');
  }

  /// Set default server for LLM
  Future<void> setDefaultServerForLlm(String llmId, String mcpServerId) async {
    _logger.debug('Setting default server for LLM: $llmId, $mcpServerId');

    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw Exception('LLM not found: $llmId');
    }

    // Find an LLM server associated with this MCP server
    final llmServerIds = llmInfo.getLlmServerIdsForMcpServer(mcpServerId);
    if (llmServerIds.isEmpty) {
      throw Exception('No LLM server associated with MCP server $mcpServerId in LLM $llmId');
    }

    // Use the first associated LLM server
    final llmServerId = llmServerIds.first;

    // Set as default in MCPLlm
    await llmInfo.mcpLlm.setDefaultMcpServer(
        llmServerId,
        mcpServerId
    );

    _logger.info('Default server for LLM $llmId set to MCP server $mcpServerId via LLM server $llmServerId');
  }

  /// Get LLM info
  LlmInfo? getLlmInfo(String id) {
    return _llms[id];
  }

  /// Get LLM client (default client for the LLM)
  LlmClient? getLlmClient(String id) {
    final llmInfo = _llms[id];
    return llmInfo?.defaultLlmClient;
  }

  /// Get LLM server (default server for the LLM)
  LlmServer? getLlmServer(String id) {
    final llmInfo = _llms[id];
    return llmInfo?.defaultLlmServer;
  }

  /// Get LLM client by ID
  LlmClient? getLlmClientById(String llmId, String llmClientId) {
    final llmInfo = _llms[llmId];
    return llmInfo?.llmClients[llmClientId];
  }

  /// Get LLM server by ID
  LlmServer? getLlmServerById(String llmId, String llmServerId) {
    final llmInfo = _llms[llmId];
    return llmInfo?.llmServers[llmServerId];
  }

  /// Get all LLM IDs
  List<String> getAllLlmIds() {
    return _llms.keys.toList();
  }

  /// Get all MCP client IDs associated with an LLM
  Set<String> getMcpClientIds(String llmId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      return {};
    }
    return llmInfo.getAllMcpClientIds();
  }

  /// Get all MCP server IDs associated with an LLM
  Set<String> getMcpServerIds(String llmId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      return {};
    }
    return llmInfo.getAllMcpServerIds();
  }

  /// Get all LLM client IDs for an LLM
  Set<String> getLlmClientIds(String llmId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      return {};
    }
    return llmInfo.getAllLlmClientIds();
  }

  /// Get all LLM server IDs for an LLM
  Set<String> getLlmServerIds(String llmId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      return {};
    }
    return llmInfo.getAllLlmServerIds();
  }

  /// Find LLMs associated with an MCP client
  List<String> findLlmsForMcpClient(String mcpClientId) {
    return _mcpClientToLlmMap[mcpClientId]?.toList() ?? [];
  }

  /// Find LLMs associated with an MCP server
  List<String> findLlmsForMcpServer(String mcpServerId) {
    return _mcpServerToLlmMap[mcpServerId]?.toList() ?? [];
  }

  /// Close LLM
  Future<void> closeLlm(String id) async {
    _logger.debug('Closing LLM: $id');
    final llmInfo = _llms[id];
    if (llmInfo == null) {
      return;
    }

    // Close all LLM clients
    for (final client in llmInfo.llmClients.values) {
      await client.close();
    }

    // Close all LLM servers
    for (final server in llmInfo.llmServers.values) {
      await server.close();
    }

    // Remove from tracking maps
    for (final mcpClientId in llmInfo.getAllMcpClientIds()) {
      final llmIds = _mcpClientToLlmMap[mcpClientId];
      if (llmIds != null) {
        llmIds.remove(id);
        if (llmIds.isEmpty) {
          _mcpClientToLlmMap.remove(mcpClientId);
        }
      }
    }

    for (final mcpServerId in llmInfo.getAllMcpServerIds()) {
      final llmIds = _mcpServerToLlmMap[mcpServerId];
      if (llmIds != null) {
        llmIds.remove(id);
        if (llmIds.isEmpty) {
          _mcpServerToLlmMap.remove(mcpServerId);
        }
      }
    }

    // Remove the LLM
    _llms.remove(id);
  }

  /// Close all LLMs
  Future<void> closeAll() async {
    _logger.debug('Closing all LLMs');
    for (final id in _llms.keys.toList()) {
      await closeLlm(id);
    }
  }

  /// Get status information
  Map<String, dynamic> getStatus() {
    return {
      'total': _llms.length,
      'llms': _llms.map((key, value) => MapEntry(key, {
        'clientCount': value.llmClients.length,
        'serverCount': value.llmServers.length,
        'mcpClientCount': value.getAllMcpClientIds().length,
        'mcpServerCount': value.getAllMcpServerIds().length,
        'defaultLlmClientId': value.defaultLlmClientId,
        'defaultLlmServerId': value.defaultLlmServerId,
      })),
    };
  }
}*/