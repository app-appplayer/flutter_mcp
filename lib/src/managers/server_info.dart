import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Server information
class ServerInfo {
  /// Server ID
  final String id;

  /// MCP server
  final Server server;

  /// Server transport
  final ServerTransport? transport;

  /// LLM server
  LlmServer? llmServer;

  /// Running status
  bool running = false;

  ServerInfo({
    required this.id,
    required this.server,
    this.transport,
  });
}
