# Multiple Servers Example

This example demonstrates connecting to and managing multiple MCP servers simultaneously.

## Overview

This example shows how to:
- Connect to multiple servers
- Switch between servers
- Load balance requests
- Handle failover scenarios

## Code Example

### Configuration

```dart
// lib/config/mcp_config.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class AppConfig {
  static MCPConfig get mcpConfig => MCPConfig(
    servers: {
      'primary-server': ServerConfig(
        uri: 'ws://localhost:3000',
        auth: AuthConfig(
          type: 'token',
          token: 'primary-token',
        ),
        priority: 1,
      ),
      'secondary-server': ServerConfig(
        uri: 'ws://localhost:3001',
        auth: AuthConfig(
          type: 'token',
          token: 'secondary-token',
        ),
        priority: 2,
      ),
      'backup-server': ServerConfig(
        uri: 'ws://localhost:3002',
        auth: AuthConfig(
          type: 'token',
          token: 'backup-token',
        ),
        priority: 3,
      ),
    },
    loadBalancing: LoadBalancingStrategy.roundRobin,
    failoverEnabled: true,
  );
}
```

### Server Manager Service

```dart
// lib/services/server_manager.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class ServerManagerService {
  final Map<String, MCPServer> _servers = {};
  final Map<String, ServerStatus> _statuses = {};
  int _currentServerIndex = 0;
  
  List<String> get serverNames => AppConfig.mcpConfig.servers.keys.toList();
  
  Future<void> initialize() async {
    // Connect to all servers
    for (final serverName in serverNames) {
      try {
        await connectToServer(serverName);
      } catch (e) {
        print('Failed to connect to $serverName: $e');
      }
    }
  }
  
  Future<void> connectToServer(String serverName) async {
    try {
      final server = await FlutterMCP.connect(serverName);
      _servers[serverName] = server;
      _statuses[serverName] = ServerStatus.connected;
      
      // Monitor server health
      _monitorServerHealth(serverName);
    } catch (e) {
      _statuses[serverName] = ServerStatus.error;
      throw e;
    }
  }
  
  void _monitorServerHealth(String serverName) {
    Timer.periodic(Duration(seconds: 30), (timer) async {
      if (!_servers.containsKey(serverName)) {
        timer.cancel();
        return;
      }
      
      try {
        await _servers[serverName]!.execute('ping', {});
        _statuses[serverName] = ServerStatus.connected;
      } catch (e) {
        _statuses[serverName] = ServerStatus.error;
        // Attempt reconnection
        _attemptReconnection(serverName);
      }
    });
  }
  
  Future<void> _attemptReconnection(String serverName) async {
    await Future.delayed(Duration(seconds: 5));
    
    try {
      await connectToServer(serverName);
    } catch (e) {
      // Schedule next retry
      Future.delayed(Duration(seconds: 30), () {
        _attemptReconnection(serverName);
      });
    }
  }
  
  MCPServer getNextServer() {
    // Round-robin load balancing
    final availableServers = _servers.entries
        .where((e) => _statuses[e.key] == ServerStatus.connected)
        .toList();
    
    if (availableServers.isEmpty) {
      throw MCPException('No available servers');
    }
    
    final server = availableServers[_currentServerIndex % availableServers.length];
    _currentServerIndex++;
    
    return server.value;
  }
  
  Future<T> executeWithFailover<T>(String method, Map<String, dynamic> params) async {
    Exception? lastError;
    
    // Try each server in priority order
    final sortedServers = _servers.entries.toList()
      ..sort((a, b) {
        final priorityA = AppConfig.mcpConfig.servers[a.key]!.priority ?? 999;
        final priorityB = AppConfig.mcpConfig.servers[b.key]!.priority ?? 999;
        return priorityA.compareTo(priorityB);
      });
    
    for (final entry in sortedServers) {
      if (_statuses[entry.key] != ServerStatus.connected) {
        continue;
      }
      
      try {
        return await entry.value.execute(method, params);
      } catch (e) {
        lastError = e as Exception;
        _statuses[entry.key] = ServerStatus.error;
      }
    }
    
    throw lastError ?? MCPException('All servers failed');
  }
  
  ServerStatus getServerStatus(String serverName) {
    return _statuses[serverName] ?? ServerStatus.disconnected;
  }
  
  void dispose() {
    for (final server in _servers.values) {
      server.disconnect();
    }
    _servers.clear();
    _statuses.clear();
  }
}

enum ServerStatus {
  disconnected,
  connecting,
  connected,
  error,
}
```

### UI Implementation

```dart
// lib/screens/multi_server_screen.dart
import 'package:flutter/material.dart';
import '../services/server_manager.dart';

class MultiServerScreen extends StatefulWidget {
  @override
  _MultiServerScreenState createState() => _MultiServerScreenState();
}

class _MultiServerScreenState extends State<MultiServerScreen> {
  final ServerManagerService _serverManager = ServerManagerService();
  String _result = '';
  bool _loading = false;
  
  @override
  void initState() {
    super.initState();
    _initializeServers();
  }
  
  Future<void> _initializeServers() async {
    setState(() => _loading = true);
    
    try {
      await _serverManager.initialize();
    } catch (e) {
      _showError('Initialization failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
  
  Future<void> _executeOnNext() async {
    setState(() => _loading = true);
    
    try {
      final server = _serverManager.getNextServer();
      final result = await server.execute('getData', {});
      setState(() {
        _result = 'Result from ${server.name}: ${result.toString()}';
      });
    } catch (e) {
      _showError('Execution failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
  
  Future<void> _executeWithFailover() async {
    setState(() => _loading = true);
    
    try {
      final result = await _serverManager.executeWithFailover('getData', {});
      setState(() {
        _result = 'Failover result: ${result.toString()}';
      });
    } catch (e) {
      _showError('All servers failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multiple Servers Example'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Server Status',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            ..._serverManager.serverNames.map((serverName) {
              final status = _serverManager.getServerStatus(serverName);
              return Card(
                child: ListTile(
                  title: Text(serverName),
                  subtitle: Text(status.toString()),
                  leading: Icon(
                    status == ServerStatus.connected
                        ? Icons.check_circle
                        : status == ServerStatus.error
                            ? Icons.error
                            : Icons.circle,
                    color: status == ServerStatus.connected
                        ? Colors.green
                        : status == ServerStatus.error
                            ? Colors.red
                            : Colors.grey,
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: () async {
                      try {
                        await _serverManager.connectToServer(serverName);
                        setState(() {});
                      } catch (e) {
                        _showError('Failed to reconnect: $e');
                      }
                    },
                  ),
                ),
              );
            }).toList(),
            SizedBox(height: 32),
            Text(
              'Result',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 8),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(_result.isEmpty ? 'No result yet' : _result),
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _executeOnNext,
              child: Text('Execute on Next Server (Round Robin)'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _executeWithFailover,
              child: Text('Execute with Failover'),
            ),
            if (_loading)
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _serverManager.dispose();
    super.dispose();
  }
}
```

### Load Balancing Strategies

```dart
// lib/services/load_balancer.dart
abstract class LoadBalancer {
  MCPServer selectServer(List<MCPServer> servers);
}

class RoundRobinBalancer implements LoadBalancer {
  int _currentIndex = 0;
  
  @override
  MCPServer selectServer(List<MCPServer> servers) {
    if (servers.isEmpty) {
      throw MCPException('No servers available');
    }
    
    final server = servers[_currentIndex % servers.length];
    _currentIndex++;
    return server;
  }
}

class RandomBalancer implements LoadBalancer {
  final _random = Random();
  
  @override
  MCPServer selectServer(List<MCPServer> servers) {
    if (servers.isEmpty) {
      throw MCPException('No servers available');
    }
    
    return servers[_random.nextInt(servers.length)];
  }
}

class LeastConnectionsBalancer implements LoadBalancer {
  final Map<MCPServer, int> _connectionCounts = {};
  
  @override
  MCPServer selectServer(List<MCPServer> servers) {
    if (servers.isEmpty) {
      throw MCPException('No servers available');
    }
    
    // Initialize counts for new servers
    for (final server in servers) {
      _connectionCounts.putIfAbsent(server, () => 0);
    }
    
    // Find server with least connections
    MCPServer? selected;
    int minConnections = double.maxFinite.toInt();
    
    for (final server in servers) {
      final count = _connectionCounts[server]!;
      if (count < minConnections) {
        minConnections = count;
        selected = server;
      }
    }
    
    // Increment connection count
    _connectionCounts[selected!] = _connectionCounts[selected]! + 1;
    
    return selected;
  }
  
  void releaseConnection(MCPServer server) {
    if (_connectionCounts.containsKey(server)) {
      _connectionCounts[server] = max(0, _connectionCounts[server]! - 1);
    }
  }
}
```

## Testing

```dart
// test/server_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp_test/flutter_mcp_test.dart';

void main() {
  group('ServerManager', () {
    test('connects to multiple servers', () async {
      // Mock multiple servers
      MCPTestEnvironment.mockServer('primary-server', {
        'getData': () => {'source': 'primary'},
      });
      MCPTestEnvironment.mockServer('secondary-server', {
        'getData': () => {'source': 'secondary'},
      });
      
      final manager = ServerManagerService();
      await manager.initialize();
      
      expect(manager.getServerStatus('primary-server'), 
          equals(ServerStatus.connected));
      expect(manager.getServerStatus('secondary-server'), 
          equals(ServerStatus.connected));
    });
    
    test('performs failover on error', () async {
      // Primary server fails, secondary succeeds
      MCPTestEnvironment.mockServerError('primary-server', 
          'getData', MCPException('Primary failed'));
      MCPTestEnvironment.mockServer('secondary-server', {
        'getData': () => {'source': 'secondary'},
      });
      
      final manager = ServerManagerService();
      await manager.initialize();
      
      final result = await manager.executeWithFailover('getData', {});
      expect(result['source'], equals('secondary'));
    });
    
    test('round-robin load balancing', () async {
      // Mock three servers
      for (int i = 1; i <= 3; i++) {
        MCPTestEnvironment.mockServer('server-$i', {
          'getData': () => {'source': 'server-$i'},
        });
      }
      
      final manager = ServerManagerService();
      await manager.initialize();
      
      // Execute multiple times
      final results = [];
      for (int i = 0; i < 6; i++) {
        final server = manager.getNextServer();
        final result = await server.execute('getData', {});
        results.add(result['source']);
      }
      
      // Should cycle through servers
      expect(results, equals([
        'server-1', 'server-2', 'server-3',
        'server-1', 'server-2', 'server-3',
      ]));
    });
  });
}
```

## Key Concepts

### Load Balancing

The example demonstrates three load balancing strategies:

1. **Round Robin**: Distributes requests evenly
2. **Random**: Randomly selects servers
3. **Least Connections**: Routes to least busy server

### Failover

Automatic failover ensures high availability:

```dart
// Primary fails -> Try secondary -> Try backup
for (final server in prioritizedServers) {
  try {
    return await server.execute(method, params);
  } catch (e) {
    continue; // Try next server
  }
}
```

### Health Monitoring

Continuous health checks detect failed servers:

```dart
Timer.periodic(Duration(seconds: 30), (timer) async {
  try {
    await server.execute('ping', {});
    status = ServerStatus.connected;
  } catch (e) {
    status = ServerStatus.error;
    attemptReconnection();
  }
});
```

## Advanced Patterns

### Circuit Breaker

```dart
class ServerCircuitBreaker {
  int _failureCount = 0;
  DateTime? _lastFailure;
  CircuitState _state = CircuitState.closed;
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitState.open) {
      if (_shouldReset()) {
        _state = CircuitState.halfOpen;
      } else {
        throw CircuitOpenException('Circuit open');
      }
    }
    
    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }
}
```

### Request Routing

```dart
class RequestRouter {
  final Map<String, String> _methodToServer = {
    'userService.*': 'user-server',
    'orderService.*': 'order-server',
    'inventoryService.*': 'inventory-server',
  };
  
  String selectServer(String method) {
    for (final entry in _methodToServer.entries) {
      if (RegExp(entry.key).hasMatch(method)) {
        return entry.value;
      }
    }
    return 'default-server';
  }
}
```

## Next Steps

- Explore [Background Jobs](./background-jobs.md)
- Learn about [State Management](./state-management.md)
- Try [Real-time Updates](./realtime-updates.md)