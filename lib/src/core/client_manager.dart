import 'package:mcp_client/mcp_client.dart';
import '../managers/client_info.dart';
import '../utils/logger.dart';

/// MCP client manager
class MCPClientManager {
  /// Registered clients
  final Map<String, ClientInfo> _clients = {};

  /// Client counter (for ID generation)
  int _counter = 0;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.client_manager');

  /// Initialize
  Future<void> initialize() async {
    _logger.debug('Initializing client manager');
  }

  /// Generate new client ID
  String generateId() {
    _counter++;
    return 'client_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Register client
  void registerClient(String id, Client client, ClientTransport? transport) {
    _logger.debug('Registering client: $id');
    _clients[id] = ClientInfo(
      id: id,
      client: client,
      transport: transport,
    );
  }

  /// Get client info
  ClientInfo? getClientInfo(String id) {
    return _clients[id];
  }

  /// Get client
  Client? getClient(String id) {
    return _clients[id]?.client;
  }

  /// Get all client IDs
  List<String> getAllClientIds() {
    return _clients.keys.toList();
  }

  /// Close client
  Future<void> closeClient(String id) async {
    _logger.debug('Closing client: $id');
    final clientInfo = _clients[id];
    if (clientInfo != null) {
      clientInfo.client.disconnect();
      _clients.remove(id);
    }
  }

  /// Close all clients
  Future<void> closeAll() async {
    _logger.debug('Closing all clients');
    for (final id in _clients.keys.toList()) {
      await closeClient(id);
    }
  }

  /// Get status information
  Map<String, dynamic> getStatus() {
    return {
      'total': _clients.length,
      'clients': _clients.map((key, value) => MapEntry(key, {
        'connected': value.client.isConnected,
        'name': value.client.name,
        'version': value.client.version,
      })),
    };
  }
}
