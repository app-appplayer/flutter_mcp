import 'package:mcp_client/mcp_client.dart' as client;
import 'package:mcp_llm/mcp_llm.dart' as llm;
import 'package:mcp_server/mcp_server.dart' as server;

import '../managers/llm_info.dart';
import '../utils/logger.dart';
import '../plugins/plugin_system.dart';
import '../plugins/llm_plugin_integration.dart';
import '../utils/exceptions.dart';

/// MCP LLM Manager with improved multi-client and multi-server support
/// and enhanced plugin system integration
class MCPLlmManager {
  /// Registered LLMs (llmId -> LlmInfo)
  final Map<String, LlmInfo> _llms = {};

  /// Map of MCP client IDs to LLM IDs
  final Map<String, Set<String>> _mcpClientToLlmMap = {};

  /// Map of MCP server IDs to LLM IDs
  final Map<String, Set<String>> _mcpServerToLlmMap = {};

  /// Plugin integrator for connecting flutter_mcp and mcp_llm plugin systems
  late final LlmPluginIntegrator _pluginIntegrator;

  /// Registry of LLM client IDs
  final Map<String, String> _llmClientIdToLlmId = {};

  /// Registry of LLM server IDs
  final Map<String, String> _llmServerIdToLlmId = {};

  /// LLM counter (for ID generation)
  int _counter = 0;
  int _clientIdCounter = 0;
  int _serverIdCounter = 0;

  /// Logger
  final Logger _logger = Logger('flutter_mcp.llm_manager');

  /// Default plugin registry or provided one
  final MCPPluginRegistry _pluginRegistry;

  MCPLlmManager({MCPPluginRegistry? pluginRegistry})
      : _pluginRegistry = pluginRegistry ?? MCPPluginRegistry() {
    // Initialize plugin integrator with plugin registry
    _pluginIntegrator = LlmPluginIntegrator(_pluginRegistry);
  }

  /// Initialize
  Future<void> initialize() async {
    _logger.fine('LLM manager initialization');
    // No additional initialization needed yet
  }

  /// Generate new LLM ID
  String generateId() {
    _counter++;
    return 'llm_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Generate new LLM client ID
  String generateLlmClientId(String llmId) {
    final id = 'llm_client_${_clientIdCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    _llmClientIdToLlmId[id] = llmId;
    return id;
  }

  /// Generate new LLM server ID
  String generateLlmServerId(String llmId) {
    final id = 'llm_server_${_serverIdCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    _llmServerIdToLlmId[id] = llmId;
    return id;
  }

  /// Register LLM with flexible initialization
  /// Allows creation with client, server, both, or neither
  void registerLlm(String id, llm.MCPLlm mcpLlm, {llm.LlmClient? initialClient, llm.LlmServer? initialServer}) {
    _logger.fine('Registering LLM: $id${initialClient != null ? " with initial client" : ""}${initialServer != null ? " with initial server" : ""}');

    _llms[id] = LlmInfo(
      id: id,
      mcpLlm: mcpLlm,
      initialClient: initialClient,
      initialServer: initialServer,
    );
  }

  /// Add a new LLM client to an existing LLM
  Future<String> addLlmClient(String llmId, String llmClientId, llm.LlmClient client) async {
    _logger.fine('Adding LLM client to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Ensure the LLM is properly registered before adding clients to it.',
      );
    }

    llmInfo.addLlmClient(llmClientId, client);

    // Register the client ID mapping
    _llmClientIdToLlmId[llmClientId] = llmId;

    _logger.info('Added LLM client $llmClientId to LLM $llmId');

    // Check for plugin integration capability
    // Register plugins from the client
    await _pluginIntegrator.registerPluginsFromLlmClient(llmClientId, client);
    _logger.fine('Registered plugins from LLM client $llmClientId');

    return llmClientId;
  }

  /// Add a new LLM server to an existing LLM
  Future<String> addLlmServer(String llmId, String llmServerId, llm.LlmServer server) async {
    _logger.fine('Adding LLM server to LLM: $llmId');
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Ensure the LLM is properly registered before adding servers to it.',
      );
    }

    llmInfo.addLlmServer(llmServerId, server);

    // Register the server ID mapping
    _llmServerIdToLlmId[llmServerId] = llmId;

    _logger.info('Added LLM server $llmServerId to LLM $llmId');

    // Check for plugin integration capability
    // Register plugins from the server
    await _pluginIntegrator.registerPluginsFromLlmServer(llmServerId, server);
    _logger.fine('Registered plugins from LLM server $llmServerId');

    return llmServerId;
  }

  /// Find LLM info that contains the given LLM client ID
  (LlmInfo?, String?) _findLlmInfoByClientId(String llmClientId) {
    final llmId = _llmClientIdToLlmId[llmClientId];
    if (llmId != null) {
      final llmInfo = _llms[llmId];
      if (llmInfo != null) {
        return (llmInfo, llmId);
      }
    }

    // Legacy fallback search
    for (final entry in _llms.entries) {
      if (entry.value.llmClients.containsKey(llmClientId)) {
        return (entry.value, entry.key);
      }
    }
    return (null, null);
  }

  /// Find LLM info that contains the given LLM server ID
  (LlmInfo?, String?) _findLlmInfoByServerId(String llmServerId) {
    final llmId = _llmServerIdToLlmId[llmServerId];
    if (llmId != null) {
      final llmInfo = _llms[llmId];
      if (llmInfo != null) {
        return (llmInfo, llmId);
      }
    }

    // Legacy fallback search
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
      client.Client mcpClient
      ) async {
    _logger.fine('Adding MCP client $mcpClientId to LLM client $llmClientId');

    // Find the LLM containing this client
    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);

    if (llmInfo == null || llmId == null) {
      throw MCPResourceNotFoundException.withContext(
        llmClientId,
        resourceType: 'LlmClient',
        errorCode: 'LLM_CLIENT_NOT_FOUND',
        resolution: 'Verify that the LLM client ID is correct and the client has been properly registered.',
      );
    }

    // Get the LLM client
    final llmClient = llmInfo.llmClients[llmClientId];
    if (llmClient == null) {
      throw MCPResourceNotFoundException.withContext(
        llmClientId,
        resourceType: 'LlmClient',
        errorCode: 'LLM_CLIENT_OBJECT_NOT_FOUND',
        resolution: 'The LLM client ID exists but the object is missing. This may indicate an internal consistency issue.',
      );
    }

    // Directly add MCP client to the LLM client
    try {
      llmInfo.mcpLlm.addMcpClientToLlmClient(llmClientId, mcpClientId, mcpClient);
      _logger.info('Added MCP client $mcpClientId directly to LLM client $llmClientId');
    } catch (e) {
      _logger.severe('Failed to add MCP client directly: $e');
      throw MCPOperationFailedException.withContext(
        'Failed to add MCP client: $e',
        e,
        StackTrace.current,
        errorCode: 'LLM_CLIENT_ASSOCIATION_FAILED',
        context: {
          'llmClientId': llmClientId,
          'mcpClientId': mcpClientId,
        },
        recoverable: true,
        resolution: 'Check if the MCP client is valid and that the LLM client supports additional MCP clients.',
      );
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
      server.Server mcpServer
      ) async {
    _logger.fine('Adding MCP server $mcpServerId to LLM server $llmServerId');

    // Find the LLM containing this server
    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);

    if (llmInfo == null || llmId == null) {
      throw MCPResourceNotFoundException.withContext(
        llmServerId,
        resourceType: 'LlmServer',
        errorCode: 'LLM_SERVER_NOT_FOUND',
        resolution: 'Verify that the LLM server ID is correct and the server has been properly registered.',
      );
    }

    // Get the LLM server
    final llmServer = llmInfo.llmServers[llmServerId];
    if (llmServer == null) {
      throw MCPResourceNotFoundException.withContext(
        llmServerId,
        resourceType: 'LlmServer',
        errorCode: 'LLM_SERVER_OBJECT_NOT_FOUND',
        resolution: 'The LLM server ID exists but the object is missing. This may indicate an internal consistency issue.',
      );
    }

    // Directly add MCP server to the LLM server
    try {
      llmInfo.mcpLlm.addMcpServerToLlmServer(llmServerId, mcpServerId, mcpServer);
      _logger.info('Added MCP server $mcpServerId directly to LLM server $llmServerId');
    } catch (e) {
      _logger.severe('Failed to add MCP server directly: $e');
      throw MCPOperationFailedException.withContext(
        'Failed to add MCP server: $e',
        e,
        StackTrace.current,
        errorCode: 'LLM_SERVER_ASSOCIATION_FAILED',
        context: {
          'llmServerId': llmServerId,
          'mcpServerId': mcpServerId,
        },
        recoverable: true,
        resolution: 'Check if the MCP server is valid and that the LLM server supports additional MCP servers.',
      );
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
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Verify that the LLM ID is correct and the LLM has been registered.',
      );
    }

    if (!llmInfo.hasClients()) {
      throw MCPOperationFailedException.withContext(
        'LLM has no clients available. Create a client for $llmId first.',
        null,
        StackTrace.current,
        errorCode: 'NO_LLM_CLIENTS',
        context: {'llmId': llmId},
        recoverable: true,
        resolution: 'Create at least one LLM client for this LLM before trying to get the default client.',
      );
    }

    final defaultLlmClientId = llmInfo.defaultLlmClientId;
    if (defaultLlmClientId == null) {
      throw MCPOperationFailedException.withContext(
        'No default LLM client available for LLM: $llmId',
        null,
        StackTrace.current,
        errorCode: 'NO_DEFAULT_LLM_CLIENT',
        context: {'llmId': llmId},
        recoverable: true,
        resolution: 'Set a default LLM client for this LLM using setDefaultLlmClient() method.',
      );
    }

    return defaultLlmClientId;
  }

  /// Add MCP client to default LLM client for an LLM
  Future<void> addMcpClientToDefaultLlmClient(String llmId, client.Client mcpClient) async {
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
    _logger.fine('Removing MCP client $mcpClientId from LLM client $llmClientId');

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
      _logger.severe('Failed to remove MCP client: $e');
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
    _logger.fine('Removing MCP server $mcpServerId from LLM server $llmServerId');

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
      _logger.severe('Failed to remove MCP server: $e');
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
    _logger.fine('Setting default MCP client $mcpClientId for LLM client $llmClientId');

    // Find the LLM containing this client
    final (llmInfo, llmId) = _findLlmInfoByClientId(llmClientId);

    if (llmInfo == null || llmId == null) {
      throw MCPResourceNotFoundException.withContext(
        llmClientId,
        resourceType: 'LlmClient',
        errorCode: 'LLM_CLIENT_NOT_FOUND',
        resolution: 'Verify that the LLM client ID is correct and the client has been properly registered.',
      );
    }

    // Verify the MCP client is associated with this LLM client
    final associatedLlmClientIds = llmInfo.getLlmClientIdsForMcpClient(mcpClientId);
    if (!associatedLlmClientIds.contains(llmClientId)) {
      throw MCPValidationException(
        'MCP client $mcpClientId is not associated with LLM client $llmClientId',
        {'mcpClientId': mcpClientId, 'llmClientId': llmClientId},
        errorCode: 'INVALID_ASSOCIATION',
        resolution: 'Associate the MCP client with the LLM client first using addMcpClientToLlmClient().',
      );
    }

    // Get the LLM client
    final llmClient = llmInfo.llmClients[llmClientId];
    if (llmClient == null) {
      throw MCPResourceNotFoundException.withContext(
        llmClientId,
        resourceType: 'LlmClient',
        errorCode: 'LLM_CLIENT_OBJECT_NOT_FOUND',
        resolution: 'The LLM client ID exists but the object is missing. This may indicate an internal consistency issue.',
      );
    }

    // Set as default (assuming this method exists on LlmClient)
    try {
      llmInfo.mcpLlm.setDefaultMcpClient(llmClientId, mcpClientId);
      _logger.info('Set default MCP client to $mcpClientId for LLM client $llmClientId');
    } catch (e) {
      _logger.severe('Failed to set default MCP client: $e');
      throw MCPOperationFailedException.withContext(
        'Failed to set default MCP client: $e',
        e,
        StackTrace.current,
        errorCode: 'DEFAULT_MCP_CLIENT_SET_FAILED',
        context: {
          'llmClientId': llmClientId,
          'mcpClientId': mcpClientId,
        },
        recoverable: true,
        resolution: 'Check if the MCP client is valid and that the LLM client supports setting a default MCP client.',
      );
    }
  }

  /// Set default MCP server for a specific LLM server
  Future<void> setDefaultMcpServerForLlmServer(
      String llmServerId,
      String mcpServerId
      ) async {
    _logger.fine('Setting default MCP server $mcpServerId for LLM server $llmServerId');

    // Find the LLM containing this server
    final (llmInfo, llmId) = _findLlmInfoByServerId(llmServerId);

    if (llmInfo == null || llmId == null) {
      throw MCPResourceNotFoundException.withContext(
        llmServerId,
        resourceType: 'LlmServer',
        errorCode: 'LLM_SERVER_NOT_FOUND',
        resolution: 'Verify that the LLM server ID is correct and the server has been properly registered.',
      );
    }

    // Verify the MCP server is associated with this LLM server
    final associatedLlmServerIds = llmInfo.getLlmServerIdsForMcpServer(mcpServerId);
    if (!associatedLlmServerIds.contains(llmServerId)) {
      throw MCPValidationException(
        'MCP server $mcpServerId is not associated with LLM server $llmServerId',
        {'mcpServerId': mcpServerId, 'llmServerId': llmServerId},
        errorCode: 'INVALID_ASSOCIATION',
        resolution: 'Associate the MCP server with the LLM server first using addMcpServerToLlmServer().',
      );
    }

    // Get the LLM server
    final llmServer = llmInfo.llmServers[llmServerId];
    if (llmServer == null) {
      throw MCPResourceNotFoundException.withContext(
        llmServerId,
        resourceType: 'LlmServer',
        errorCode: 'LLM_SERVER_OBJECT_NOT_FOUND',
        resolution: 'The LLM server ID exists but the object is missing. This may indicate an internal consistency issue.',
      );
    }

    // Set as default (assuming this method exists on LlmServer)
    try {
      llmInfo.mcpLlm.setDefaultMcpServer(llmServerId, mcpServerId);
      _logger.info('Set default MCP server to $mcpServerId for LLM server $llmServerId');
    } catch (e) {
      _logger.severe('Failed to set default MCP server: $e');
      throw MCPOperationFailedException.withContext(
        'Failed to set default MCP server: $e',
        e,
        StackTrace.current,
        errorCode: 'DEFAULT_MCP_SERVER_SET_FAILED',
        context: {
          'llmServerId': llmServerId,
          'mcpServerId': mcpServerId,
        },
        recoverable: true,
        resolution: 'Check if the MCP server is valid and that the LLM server supports setting a default MCP server.',
      );
    }
  }

  /// Set the default LLM client for an LLM
  void setDefaultLlmClient(String llmId, String llmClientId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Verify that the LLM ID is correct and the LLM has been registered.',
      );
    }

    if (!llmInfo.llmClients.containsKey(llmClientId)) {
      throw MCPResourceNotFoundException.withContext(
        llmClientId,
        resourceType: 'LlmClient',
        errorCode: 'LLM_CLIENT_NOT_FOUND_IN_LLM',
        context: {'llmId': llmId},
        resolution: 'Verify that the LLM client ID is correct and has been added to this LLM.',
      );
    }

    llmInfo.setDefaultLlmClient(llmClientId);
    _logger.info('Set default LLM client $llmClientId for LLM $llmId');
  }

  /// Set the default LLM server for an LLM
  void setDefaultLlmServer(String llmId, String llmServerId) {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Verify that the LLM ID is correct and the LLM has been registered.',
      );
    }

    if (!llmInfo.llmServers.containsKey(llmServerId)) {
      throw MCPResourceNotFoundException.withContext(
        llmServerId,
        resourceType: 'LlmServer',
        errorCode: 'LLM_SERVER_NOT_FOUND_IN_LLM',
        context: {'llmId': llmId},
        resolution: 'Verify that the LLM server ID is correct and has been added to this LLM.',
      );
    }

    llmInfo.setDefaultLlmServer(llmServerId);
    _logger.info('Set default LLM server $llmServerId for LLM $llmId');
  }

  /// Get LLM info
  LlmInfo? getLlmInfo(String id) {
    return _llms[id];
  }

  /// Get LLM client by ID directly
  llm.LlmClient? getLlmClientById(String llmClientId) {
    final (llmInfo, _) = _findLlmInfoByClientId(llmClientId);
    return llmInfo?.llmClients[llmClientId];
  }

  /// Get LLM server by ID directly
  llm.LlmServer? getLlmServerById(String llmServerId) {
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

  /// Get the LLM ID for a client
  String? getLlmIdForClient(String llmClientId) {
    return _llmClientIdToLlmId[llmClientId];
  }

  /// Get the LLM ID for a server
  String? getLlmIdForServer(String llmServerId) {
    return _llmServerIdToLlmId[llmServerId];
  }

  /// Close all resources and connections for an LLM
  Future<void> closeLlm(String id) async {
    _logger.fine('Closing LLM: $id');
    final llmInfo = _llms[id];
    if (llmInfo == null) {
      return;
    }

    // Close all LLM clients
    for (final clientId in llmInfo.llmClients.keys.toList()) {
      await closeLlmClient(clientId);
    }

    // Close all LLM servers
    for (final serverId in llmInfo.llmServers.keys.toList()) {
      await closeLlmServer(serverId);
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
    _logger.fine('Closing LLM client: $llmClientId');

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

    // Remove from ID mapping
    _llmClientIdToLlmId.remove(llmClientId);

    // Remove the client from LLM info
    llmInfo.removeLlmClient(llmClientId);
  }

  /// Close a specific LLM server
  Future<void> closeLlmServer(String llmServerId) async {
    _logger.fine('Closing LLM server: $llmServerId');

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

    // Remove from ID mapping
    _llmServerIdToLlmId.remove(llmServerId);

    // Remove the server from LLM info
    llmInfo.removeLlmServer(llmServerId);
  }

  /// Close all LLMs
  Future<void> closeAll() async {
    _logger.fine('Closing all LLMs');
    final errors = <String, dynamic>{};

    // Close all LLM instances
    for (final id in _llms.keys.toList()) {
      try {
        await closeLlm(id);
      } catch (e) {
        errors[id] = e;
        _logger.severe('Error closing LLM $id: $e');
      }
    }

    // Shutdown plugin integrator
    await _pluginIntegrator.shutdown();

    // Clear all registries
    _llmClientIdToLlmId.clear();
    _llmServerIdToLlmId.clear();

    _logger.info('All LLM instances and resources closed');

    if (errors.isNotEmpty) {
      throw MCPOperationFailedException.withContext(
        'Errors occurred while closing LLMs',
        errors,
        StackTrace.current,
        errorCode: 'LLM_CLOSE_ERRORS',
        context: {'errors': errors},
        recoverable: false,
        resolution: 'Check the error details to identify which LLMs failed to close properly.',
      );
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
      'registeredPlugins': _pluginIntegrator.getRegisteredLlmPluginNames(),
    };
  }

  /// Register core LLM plugins with improved registration process
  Future<Map<String, bool>> registerCoreLlmPlugins(
      String llmId,
      {
        String? llmClientId,
        String? llmServerId,
        bool includeCompletionPlugin = true,
        bool includeStreamingPlugin = true,
        bool includeEmbeddingPlugin = true,
        bool includeRetrievalPlugins = false,
      }
      ) async {
    final llmInfo = _llms[llmId];
    if (llmInfo == null) {
      throw MCPResourceNotFoundException.withContext(
        llmId,
        resourceType: 'LLM',
        errorCode: 'LLM_NOT_FOUND',
        resolution: 'Verify that the LLM ID is correct and the LLM has been registered.',
      );
    }

    llm.LlmInterface? llmProvider;
    llm.RetrievalManager? retrievalManager;

    if (llmClientId != null) {
      final llmClient = llmInfo.llmClients[llmClientId];
      if (llmClient == null) {
        throw MCPResourceNotFoundException.withContext(
          llmClientId,
          resourceType: 'LlmClient',
          errorCode: 'LLM_CLIENT_NOT_FOUND_IN_LLM',
          context: {'llmId': llmId},
          resolution: 'Verify that the LLM client ID is correct and has been added to this LLM.',
        );
      }

      llmProvider = llmClient.llmProvider;
      retrievalManager = llmClient.retrievalManager;
    } else if (llmServerId != null) {
      final llmServer = llmInfo.llmServers[llmServerId];
      if (llmServer == null) {
        throw MCPResourceNotFoundException.withContext(
          llmServerId,
          resourceType: 'LlmServer',
          errorCode: 'LLM_SERVER_NOT_FOUND_IN_LLM',
          context: {'llmId': llmId},
          resolution: 'Verify that the LLM server ID is correct and has been added to this LLM.',
        );
      }

      llmProvider = llmServer.llmProvider;
      retrievalManager = llmServer.retrievalManager;
    } else {
      throw MCPValidationException(
        'Either llmClientId or llmServerId must be provided',
        {'llmId': llmId},
        errorCode: 'MISSING_REQUIRED_PARAMETER',
        resolution: 'Provide either llmClientId or llmServerId parameter to specify the LLM component to use for plugin registration.',
      );
    }

    // Register core plugins
    return await _pluginIntegrator.registerCoreLlmPlugins(
      llmProvider,
      retrievalManager,
      includeCompletionPlugin: includeCompletionPlugin,
      includeStreamingPlugin: includeStreamingPlugin,
      includeEmbeddingPlugin: includeEmbeddingPlugin,
      includeRetrievalPlugins: includeRetrievalPlugins,
    );
  }

  /// Get the plugin integrator for LLM plugins
  LlmPluginIntegrator getPluginIntegrator() {
    return _pluginIntegrator;
  }
}