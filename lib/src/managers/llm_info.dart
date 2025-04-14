import 'package:mcp_llm/mcp_llm.dart';

/// LLM information with support for multiple clients and servers
class LlmInfo {
  /// LLM ID
  final String id;

  /// MCP LLM instance
  final MCPLlm mcpLlm;

  /// Map of LLM clients managed by this LLM (clientId -> LlmClient)
  final Map<String, LlmClient> llmClients = {};

  /// Map of LLM servers managed by this LLM (serverId -> LlmServer)
  final Map<String, LlmServer> llmServers = {};

  /// Connected client IDs (MCP client IDs -> LLM client IDs)
  final Map<String, Set<String>> mcpClientToLlmClientMap = {};

  /// Connected server IDs (MCP server IDs -> LLM server IDs)
  final Map<String, Set<String>> mcpServerToLlmServerMap = {};

  /// Default LLM client ID for this LLM
  String? defaultLlmClientId;

  /// Default LLM server ID for this LLM
  String? defaultLlmServerId;

  /// Primary LLM client (if any)
  LlmClient? get primaryClient =>
      defaultLlmClientId != null ? llmClients[defaultLlmClientId] :
      llmClients.isNotEmpty ? llmClients.values.first : null;

  /// Primary LLM server (if any)
  LlmServer? get primaryServer =>
      defaultLlmServerId != null ? llmServers[defaultLlmServerId] :
      llmServers.isNotEmpty ? llmServers.values.first : null;

  LlmInfo({
    required this.id,
    required this.mcpLlm,
    LlmClient? initialClient,
    LlmServer? initialServer,
  }) {
    // Register the initial client if provided
    if (initialClient != null) {
      final clientId = 'primary_client_$id';
      llmClients[clientId] = initialClient;
      defaultLlmClientId = clientId;
    }

    // Register the initial server if provided
    if (initialServer != null) {
      final serverId = 'primary_server_$id';
      llmServers[serverId] = initialServer;
      defaultLlmServerId = serverId;
    }
  }

  /// Add an LLM client
  void addLlmClient(String clientId, LlmClient client) {
    llmClients[clientId] = client;
    defaultLlmClientId ??= clientId;
  }

  /// Remove an LLM client
  LlmClient? removeLlmClient(String clientId) {
    final client = llmClients.remove(clientId);

    // If we removed the default client, set a new default if available
    if (clientId == defaultLlmClientId && llmClients.isNotEmpty) {
      defaultLlmClientId = llmClients.keys.first;
    } else if (llmClients.isEmpty) {
      defaultLlmClientId = null;
    }

    return client;
  }

  /// Add an LLM server
  void addLlmServer(String serverId, LlmServer server) {
    llmServers[serverId] = server;
    defaultLlmServerId ??= serverId;
  }

  /// Remove an LLM server
  LlmServer? removeLlmServer(String serverId) {
    final server = llmServers.remove(serverId);

    // If we removed the default server, set a new default if available
    if (serverId == defaultLlmServerId && llmServers.isNotEmpty) {
      defaultLlmServerId = llmServers.keys.first;
    } else if (llmServers.isEmpty) {
      defaultLlmServerId = null;
    }

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

  /// Get default LLM client
  LlmClient? get defaultLlmClient {
    return defaultLlmClientId != null ? llmClients[defaultLlmClientId] : null;
  }

  /// Get default LLM server
  LlmServer? get defaultLlmServer {
    return defaultLlmServerId != null ? llmServers[defaultLlmServerId] : null;
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
}