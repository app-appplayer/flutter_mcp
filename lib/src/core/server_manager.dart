import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart' hide ServerInfo;
import '../managers/server_info.dart';
import 'base_manager.dart';
import '../types/health_types.dart';

/// MCP Server Manager
class MCPServerManager extends BaseManager {
  /// Registered servers
  final Map<String, ServerInfo> _servers = {};

  /// Server counter (for ID generation)
  int _counter = 0;

  MCPServerManager() : super('server_manager');

  @override
  Future<void> onInitialize() async {
    logger.fine('Server manager initialization');
  }

  /// Generate new server ID
  String generateId() {
    _counter++;
    return 'server_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Register server
  void registerServer(String id, Server server, ServerTransport? transport) {
    logger.fine('Server registered: $id');
    _servers[id] = ServerInfo(
      id: id,
      server: server,
      transport: transport,
    );

    // Report health status
    reportHealthy('Server registered: $id');
  }

  /// Set LLM server
  void setLlmServer(String id, LlmServer llmServer) {
    logger.fine('LLM server set: $id');
    final serverInfo = _servers[id];
    if (serverInfo != null) {
      serverInfo.llmServer = llmServer;
    }
  }

  /// Get server information
  ServerInfo? getServerInfo(String id) {
    return _servers[id];
  }

  /// Get server
  Server? getServer(String id) {
    return _servers[id]?.server;
  }

  /// Get all server IDs
  List<String> getAllServerIds() {
    return _servers.keys.toList();
  }

  /// Close server
  Future<void> closeServer(String id) async {
    logger.fine('Closing server: $id');
    final serverInfo = _servers[id];
    if (serverInfo != null) {
      serverInfo.server.disconnect();
      if (serverInfo.llmServer != null) {
        await serverInfo.llmServer!.close();
      }
      _servers.remove(id);

      // Report health status
      reportHealthy('Server closed: $id');
    }
  }

  /// Close all servers
  Future<void> closeAll() async {
    logger.fine('Closing all servers');
    for (final id in _servers.keys.toList()) {
      await closeServer(id);
    }
  }

  @override
  Future<void> onDispose() async {
    await closeAll();
  }

  /// Get status information
  @override
  Map<String, dynamic> getStatus() {
    final baseStatus = super.getStatus();
    return {
      ...baseStatus,
      'total': _servers.length,
      'servers': _servers.map((key, value) => MapEntry(key, {
            'name': value.server.name,
            'version': value.server.version,
            'tools': value.server.getTools().length,
            'resources': value.server.getResources().length,
            'prompts': value.server.getPrompts().length,
            'hasLlmServer': value.llmServer != null,
          })),
    };
  }

  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    final baseHealth = await super.performHealthCheck();
    if (baseHealth.status == MCPHealthStatus.unhealthy) {
      return baseHealth;
    }

    // Check specific health metrics
    final totalCount = _servers.length;

    if (totalCount == 0) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.healthy,
        message: 'No servers configured',
        details: getStatus(),
      );
    }

    // Check if any server has issues
    int serversWithIssues = 0;
    for (final serverInfo in _servers.values) {
      // Basic health check - could be enhanced with actual server status checks
      if (serverInfo.server.getTools().isEmpty &&
          serverInfo.server.getResources().isEmpty &&
          serverInfo.server.getPrompts().isEmpty) {
        serversWithIssues++;
      }
    }

    if (serversWithIssues == totalCount) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.degraded,
        message: 'All servers have no capabilities registered',
        details: getStatus(),
      );
    } else if (serversWithIssues > 0) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.degraded,
        message: '$serversWithIssues/$totalCount servers have no capabilities',
        details: getStatus(),
      );
    }

    return MCPHealthCheckResult(
      status: MCPHealthStatus.healthy,
      message: '$totalCount servers configured and operational',
      details: getStatus(),
    );
  }
}
