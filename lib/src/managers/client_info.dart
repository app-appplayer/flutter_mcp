import 'package:mcp_client/mcp_client.dart';

/// Client information
class ClientInfo {
  /// Client ID
  final String id;

  /// MCP client
  final Client client;

  /// Client transport
  final ClientTransport? transport;

  /// Connection status
  bool connected = false;

  ClientInfo({
    required this.id,
    required this.client,
    this.transport,
  });
}