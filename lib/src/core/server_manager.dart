import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';
import '../managers/server_info.dart';
import '../utils/logger.dart';

/// MCP Server Manager
class MCPServerManager {
  /// Registered servers
  final Map<String, ServerInfo> _servers = {};

  /// Server counter (for ID generation)
  int _counter = 0;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.server_manager');

  /// Initialization
  Future<void> initialize() async {
    _logger.debug('Server manager initialization');
  }

  /// Generate new server ID
  String generateId() {
    _counter++;
    return 'server_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Register server
  void registerServer(String id, Server server, ServerTransport? transport) {
    _logger.debug('Server registered: $id');
    _servers[id] = ServerInfo(
      id: id,
      server: server,
      transport: transport,
    );
  }

  /// Set LLM server
  void setLlmServer(String id, LlmServer llmServer) {
    _logger.debug('LLM server set: $id');
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
    _logger.debug('Closing server: $id');
    final serverInfo = _servers[id];
    if (serverInfo != null) {
      serverInfo.server.disconnect();
      if (serverInfo.llmServer != null) {
        await serverInfo.llmServer!.close();
      }
      _servers.remove(id);
    }
  }

  /// Close all servers
  Future<void> closeAll() async {
    _logger.debug('Closing all servers');
    for (final id in _servers.keys.toList()) {
      await closeServer(id);
    }
  }

  /// Get status information
  Map<String, dynamic> getStatus() {
    return {
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
}
