import 'package:mcp_llm/mcp_llm.dart' as llm;

/// LLM information with support for multiple clients and servers
/// Enhanced with plugin system support
class LlmInfo {
  /// LLM ID
  final String id;

  /// MCP LLM instance
  final llm.MCPLlm mcpLlm;

  /// Map of LLM clients managed by this LLM (clientId -> LlmClient)
  final Map<String, llm.LlmClient> llmClients = {};

  /// Map of LLM servers managed by this LLM (serverId -> LlmServer)
  final Map<String, llm.LlmServer> llmServers = {};

  /// Connected client IDs (MCP client IDs -> LLM client IDs)
  final Map<String, Set<String>> mcpClientToLlmClientMap = {};

  /// Connected server IDs (MCP server IDs -> LLM server IDs)
  final Map<String, Set<String>> mcpServerToLlmServerMap = {};

  /// Default LLM client ID for this LLM
  String? defaultLlmClientId;

  /// Default LLM server ID for this LLM
  String? defaultLlmServerId;

  /// Plugin managers for LLM clients and servers
  final Map<String, llm.PluginManager> llmClientPluginManagers = {};
  final Map<String, llm.PluginManager> llmServerPluginManagers = {};

  /// Primary LLM client (if any)
  llm.LlmClient? get primaryClient => defaultLlmClientId != null
      ? llmClients[defaultLlmClientId]
      : llmClients.isNotEmpty
          ? llmClients.values.first
          : null;

  /// Primary LLM server (if any)
  llm.LlmServer? get primaryServer => defaultLlmServerId != null
      ? llmServers[defaultLlmServerId]
      : llmServers.isNotEmpty
          ? llmServers.values.first
          : null;

  /// Default LLM client
  llm.LlmClient? get defaultLlmClient =>
      defaultLlmClientId != null ? llmClients[defaultLlmClientId] : null;

  /// Default LLM server
  llm.LlmServer? get defaultLlmServer =>
      defaultLlmServerId != null ? llmServers[defaultLlmServerId] : null;

  LlmInfo({
    required this.id,
    required this.mcpLlm,
    llm.LlmClient? initialClient,
    llm.LlmServer? initialServer,
  }) {
    // Register the initial client if provided
    if (initialClient != null) {
      final clientId = 'primary_client_$id';
      llmClients[clientId] = initialClient;
      defaultLlmClientId = clientId;

      // Store the plugin manager if available
      llmClientPluginManagers[clientId] = initialClient.pluginManager;
    }

    // Register the initial server if provided
    if (initialServer != null) {
      final serverId = 'primary_server_$id';
      llmServers[serverId] = initialServer;
      defaultLlmServerId = serverId;

      // Store the plugin manager if available
      llmServerPluginManagers[serverId] = initialServer.pluginManager;
    }
  }

  /// Add an LLM client
  void addLlmClient(String clientId, llm.LlmClient client) {
    llmClients[clientId] = client;

    // Set as default if this is the first client or no default is set
    if (llmClients.length == 1 || defaultLlmClientId == null) {
      defaultLlmClientId = clientId;
    }

    // Store the plugin manager if available
    llmClientPluginManagers[clientId] = client.pluginManager;
  }

  /// Remove an LLM client
  llm.LlmClient? removeLlmClient(String clientId) {
    final client = llmClients.remove(clientId);

    // If we removed the default client, set a new default if available
    if (clientId == defaultLlmClientId && llmClients.isNotEmpty) {
      defaultLlmClientId = llmClients.keys.first;
    } else if (llmClients.isEmpty) {
      defaultLlmClientId = null;
    }

    // Remove the plugin manager
    llmClientPluginManagers.remove(clientId);

    return client;
  }

  /// Add an LLM server
  void addLlmServer(String serverId, llm.LlmServer server) {
    llmServers[serverId] = server;

    // Set as default if this is the first server or no default is set
    if (llmServers.length == 1 || defaultLlmServerId == null) {
      defaultLlmServerId = serverId;
    }

    // Store the plugin manager if available
    llmServerPluginManagers[serverId] = server.pluginManager;
  }

  /// Remove an LLM server
  llm.LlmServer? removeLlmServer(String serverId) {
    final server = llmServers.remove(serverId);

    // If we removed the default server, set a new default if available
    if (serverId == defaultLlmServerId && llmServers.isNotEmpty) {
      defaultLlmServerId = llmServers.keys.first;
    } else if (llmServers.isEmpty) {
      defaultLlmServerId = null;
    }

    // Remove the plugin manager
    llmServerPluginManagers.remove(serverId);

    return server;
  }

  /// Set default LLM client
  void setDefaultLlmClient(String clientId) {
    if (llmClients.containsKey(clientId)) {
      defaultLlmClientId = clientId;
    }
  }

  /// Set default LLM server
  void setDefaultLlmServer(String serverId) {
    if (llmServers.containsKey(serverId)) {
      defaultLlmServerId = serverId;
    }
  }

  /// Associate an MCP client with an LLM client
  void associateMcpClient(String mcpClientId, String llmClientId) {
    mcpClientToLlmClientMap.putIfAbsent(mcpClientId, () => {}).add(llmClientId);
  }

  /// Disassociate an MCP client from an LLM client
  void disassociateMcpClient(String mcpClientId, String llmClientId) {
    final llmClients = mcpClientToLlmClientMap[mcpClientId];
    if (llmClients != null) {
      llmClients.remove(llmClientId);
      if (llmClients.isEmpty) {
        mcpClientToLlmClientMap.remove(mcpClientId);
      }
    }
  }

  /// Associate an MCP server with an LLM server
  void associateMcpServer(String mcpServerId, String llmServerId) {
    mcpServerToLlmServerMap.putIfAbsent(mcpServerId, () => {}).add(llmServerId);
  }

  /// Disassociate an MCP server from an LLM server
  void disassociateMcpServer(String mcpServerId, String llmServerId) {
    final llmServers = mcpServerToLlmServerMap[mcpServerId];
    if (llmServers != null) {
      llmServers.remove(llmServerId);
      if (llmServers.isEmpty) {
        mcpServerToLlmServerMap.remove(mcpServerId);
      }
    }
  }

  /// Get all MCP client IDs
  Set<String> getAllMcpClientIds() {
    return mcpClientToLlmClientMap.keys.toSet();
  }

  /// Get all MCP server IDs
  Set<String> getAllMcpServerIds() {
    return mcpServerToLlmServerMap.keys.toSet();
  }

  /// Get all LLM client IDs
  Set<String> getAllLlmClientIds() {
    return llmClients.keys.toSet();
  }

  /// Get all LLM server IDs
  Set<String> getAllLlmServerIds() {
    return llmServers.keys.toSet();
  }

  /// Get the associated LLM client IDs for an MCP client
  Set<String> getLlmClientIdsForMcpClient(String mcpClientId) {
    return mcpClientToLlmClientMap[mcpClientId] ?? {};
  }

  /// Get the associated LLM server IDs for an MCP server
  Set<String> getLlmServerIdsForMcpServer(String mcpServerId) {
    return mcpServerToLlmServerMap[mcpServerId] ?? {};
  }

  /// Check if this LLM has any clients
  bool hasClients() {
    return llmClients.isNotEmpty;
  }

  /// Check if this LLM has any servers
  bool hasServers() {
    return llmServers.isNotEmpty;
  }

  /// Add a plugin manager for an LLM client
  void setLlmClientPluginManager(
      String llmClientId, llm.PluginManager pluginManager) {
    if (llmClients.containsKey(llmClientId)) {
      llmClientPluginManagers[llmClientId] = pluginManager;
    }
  }

  /// Add a plugin manager for an LLM server
  void setLlmServerPluginManager(
      String llmServerId, llm.PluginManager pluginManager) {
    if (llmServers.containsKey(llmServerId)) {
      llmServerPluginManagers[llmServerId] = pluginManager;
    }
  }

  /// Get a plugin manager for an LLM client
  llm.PluginManager? getLlmClientPluginManager(String llmClientId) {
    return llmClientPluginManagers[llmClientId];
  }

  /// Get a plugin manager for an LLM server
  llm.PluginManager? getLlmServerPluginManager(String llmServerId) {
    return llmServerPluginManagers[llmServerId];
  }

  /// Get all plugin managers across all LLM clients
  List<llm.PluginManager> getAllClientPluginManagers() {
    return llmClientPluginManagers.values.toList();
  }

  /// Get all plugin managers across all LLM servers
  List<llm.PluginManager> getAllServerPluginManagers() {
    return llmServerPluginManagers.values.toList();
  }

  /// Get all plugin managers (both client and server)
  List<llm.PluginManager> getAllPluginManagers() {
    return [
      ...llmClientPluginManagers.values,
      ...llmServerPluginManagers.values
    ];
  }
}
