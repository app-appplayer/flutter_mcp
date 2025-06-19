import 'package:mcp_client/mcp_client.dart' hide ClientInfo;
import '../managers/client_info.dart';
import 'base_manager.dart';
import '../types/health_types.dart';

/// MCP client manager
class MCPClientManager extends BaseManager {
  /// Registered clients
  final Map<String, ClientInfo> _clients = {};

  /// Client counter (for ID generation)
  int _counter = 0;

  MCPClientManager() : super('client_manager');

  @override
  Future<void> onInitialize() async {
    logger.fine('Initializing client manager');
  }

  /// Generate new client ID
  String generateId() {
    _counter++;
    return 'client_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }

  /// Register client
  void registerClient(String id, Client client, ClientTransport? transport) {
    logger.fine('Registering client: $id');
    _clients[id] = ClientInfo(
      id: id,
      client: client,
      transport: transport,
    );

    // Report health status
    reportHealthy('Client registered: $id');
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
    logger.fine('Closing client: $id');
    final clientInfo = _clients[id];
    if (clientInfo != null) {
      clientInfo.client.disconnect();
      _clients.remove(id);
    }
  }

  /// Close all clients
  Future<void> closeAll() async {
    logger.fine('Closing all clients');
    for (final id in _clients.keys.toList()) {
      await closeClient(id);
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
      'total': _clients.length,
      'connected': _clients.values.where((c) => c.client.isConnected).length,
      'disconnected':
          _clients.values.where((c) => !c.client.isConnected).length,
      'clients': _clients.map((key, value) => MapEntry(key, {
            'connected': value.client.isConnected,
            'name': value.client.name,
            'version': value.client.version,
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
    final connectedCount =
        _clients.values.where((c) => c.client.isConnected).length;
    final totalCount = _clients.length;

    if (totalCount == 0) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.healthy,
        message: 'No clients configured',
        details: getStatus(),
      );
    }

    final connectionRate = connectedCount / totalCount;

    if (connectionRate == 0) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'All clients disconnected',
        details: getStatus(),
      );
    } else if (connectionRate < 0.5) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.degraded,
        message: 'More than half of clients disconnected',
        details: getStatus(),
      );
    }

    return MCPHealthCheckResult(
      status: MCPHealthStatus.healthy,
      message: '$connectedCount/$totalCount clients connected',
      details: getStatus(),
    );
  }
}
