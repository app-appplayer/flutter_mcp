# Health Monitoring Guide

Monitor the health and performance of your Flutter MCP application with comprehensive health checks and monitoring capabilities.

## Overview

Flutter MCP provides a robust health monitoring system that includes:
- Component-level health checks
- System-wide health status
- Real-time monitoring
- Resource usage tracking
- Automatic issue detection
- Health check endpoints

## Basic Health Checks

### System Health Check

```dart
// Get overall system health
final systemHealth = await FlutterMCP.instance.getSystemHealth();

print('Overall Status: ${systemHealth.overallStatus}');
print('Components: ${systemHealth.components.length}');

// Check specific components
systemHealth.components.forEach((componentId, health) {
  print('$componentId: ${health.status}');
  if (health.message != null) {
    print('  Message: ${health.message}');
  }
});

// Check for issues
if (systemHealth.issues.isNotEmpty) {
  print('Issues detected:');
  for (final issue in systemHealth.issues) {
    print('  - ${issue.severity}: ${issue.description}');
  }
}
```

### Component Health Check

```dart
// Check specific component health
final clientHealth = await FlutterMCP.instance.getComponentHealth('client_manager');

switch (clientHealth.status) {
  case HealthStatus.healthy:
    print('Client manager is healthy');
    break;
  case HealthStatus.degraded:
    print('Client manager is degraded: ${clientHealth.message}');
    break;
  case HealthStatus.unhealthy:
    print('Client manager is unhealthy: ${clientHealth.message}');
    // Take corrective action
    await _handleUnhealthyComponent(clientHealth);
    break;
  case HealthStatus.unknown:
    print('Client manager health is unknown');
    break;
}
```

## Health Monitor Setup

### Basic Health Monitor

```dart
class ApplicationHealthMonitor {
  final HealthMonitor _healthMonitor = HealthMonitor.instance;
  Timer? _healthCheckTimer;
  
  void startMonitoring() {
    // Configure health monitor
    _healthMonitor.configure(
      checkInterval: Duration(seconds: 30),
      componentTimeout: Duration(seconds: 5),
      enableAutoRecovery: true,
    );
    
    // Register custom health checks
    _registerHealthChecks();
    
    // Start periodic health checks
    _healthCheckTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      await _performHealthCheck();
    });
  }
  
  void _registerHealthChecks() {
    // Register database health check
    _healthMonitor.registerCheck(
      'database',
      () async {
        try {
          await Database.instance.ping();
          return HealthCheckResult(
            healthy: true,
            componentStatuses: {'database': HealthStatus.healthy},
          );
        } catch (e) {
          return HealthCheckResult(
            healthy: false,
            componentStatuses: {'database': HealthStatus.unhealthy},
            errors: ['Database connection failed: $e'],
          );
        }
      },
    );
    
    // Register API health check
    _healthMonitor.registerCheck(
      'external_api',
      () async {
        final response = await http.get(Uri.parse('https://api.example.com/health'));
        return HealthCheckResult(
          healthy: response.statusCode == 200,
          componentStatuses: {
            'external_api': response.statusCode == 200 
              ? HealthStatus.healthy 
              : HealthStatus.unhealthy,
          },
        );
      },
    );
  }
  
  Future<void> _performHealthCheck() async {
    final result = await FlutterMCP.instance.checkHealth(
      components: ['client_manager', 'server_manager', 'llm_manager'],
      detailed: true,
    );
    
    if (!result.healthy) {
      await _handleHealthIssues(result);
    }
  }
  
  Future<void> _handleHealthIssues(HealthCheckResult result) async {
    // Log issues
    for (final error in result.errors) {
      print('Health check error: $error');
    }
    
    // Send alerts
    if (result.componentStatuses.values.any((status) => status == HealthStatus.unhealthy)) {
      await _sendHealthAlert(result);
    }
  }
  
  Future<void> _sendHealthAlert(HealthCheckResult result) async {
    // Send notification or alert
    await FlutterMCP.instance.backgroundService.showNotification(
      title: 'Health Check Failed',
      body: 'One or more components are unhealthy',
      data: {
        'type': 'health_alert',
        'components': result.componentStatuses.entries
          .where((e) => e.value == HealthStatus.unhealthy)
          .map((e) => e.key)
          .toList(),
      },
    );
  }
  
  void stopMonitoring() {
    _healthCheckTimer?.cancel();
    _healthMonitor.dispose();
  }
}
```

## Resource Monitoring

### Memory Monitoring

```dart
class MemoryHealthMonitor {
  final _warningThreshold = 0.8; // 80% memory usage
  final _criticalThreshold = 0.9; // 90% memory usage
  
  Future<void> monitorMemoryHealth() async {
    // Get resource statistics
    final resourceStats = FlutterMCP.instance.getResourceStatistics();
    
    final memoryStats = resourceStats['memory'];
    if (memoryStats != null) {
      final usage = memoryStats.currentInUse / memoryStats.totalAllocated;
      
      if (usage > _criticalThreshold) {
        await _handleCriticalMemory(usage, memoryStats);
      } else if (usage > _warningThreshold) {
        await _handleHighMemory(usage, memoryStats);
      }
    }
    
    // Check for memory leaks
    final leaks = await FlutterMCP.instance.checkForResourceLeaks();
    if (leaks.isNotEmpty) {
      await _handleMemoryLeaks(leaks);
    }
  }
  
  Future<void> _handleCriticalMemory(double usage, ResourceStatistics stats) async {
    print('CRITICAL: Memory usage at ${(usage * 100).toStringAsFixed(1)}%');
    
    // Force garbage collection
    await MemoryManager.instance.performCleanup();
    
    // Reduce concurrent operations
    await FlutterMCP.instance.clientManager.setMaxConcurrentOperations(2);
    
    // Clear caches
    await _clearCaches();
  }
  
  Future<void> _handleHighMemory(double usage, ResourceStatistics stats) async {
    print('WARNING: Memory usage at ${(usage * 100).toStringAsFixed(1)}%');
    
    // Trigger cleanup
    await MemoryManager.instance.optimizeMemory();
  }
  
  Future<void> _handleMemoryLeaks(List<ResourceLeak> leaks) async {
    print('Detected ${leaks.length} potential memory leaks');
    
    for (final leak in leaks) {
      print('Leak: ${leak.resourceType} allocated at ${leak.allocatedAt}');
      if (leak.stackTrace != null) {
        print('Stack trace: ${leak.stackTrace}');
      }
      
      // Attempt to clean up leaked resource
      await _cleanupLeakedResource(leak);
    }
  }
  
  Future<void> _cleanupLeakedResource(ResourceLeak leak) async {
    switch (leak.resourceType) {
      case 'client':
        await FlutterMCP.instance.clientManager.closeClient(leak.resourceId);
        break;
      case 'server':
        await FlutterMCP.instance.serverManager.stopServer(leak.resourceId);
        break;
      default:
        print('Unknown resource type: ${leak.resourceType}');
    }
  }
  
  Future<void> _clearCaches() async {
    // Clear various caches
    await SemanticCache.instance.clear();
    await ResponseCache.instance.clear();
  }
}
```

### Connection Health

```dart
class ConnectionHealthMonitor {
  final Map<String, int> _connectionFailures = {};
  final int _maxFailures = 5;
  
  Future<void> monitorConnections() async {
    // Monitor all client connections
    final clients = FlutterMCP.instance.clientManager.getAllClients();
    
    for (final client in clients) {
      await _checkClientHealth(client);
    }
    
    // Monitor server connections
    final servers = FlutterMCP.instance.serverManager.getAllServers();
    
    for (final server in servers) {
      await _checkServerHealth(server);
    }
  }
  
  Future<void> _checkClientHealth(ClientInfo client) async {
    try {
      // Perform health check
      final healthy = await client.client.ping();
      
      if (healthy) {
        // Reset failure count on success
        _connectionFailures.remove(client.id);
      } else {
        _recordFailure(client.id, 'Client ping failed');
      }
    } catch (e) {
      _recordFailure(client.id, 'Client health check error: $e');
    }
  }
  
  Future<void> _checkServerHealth(ServerInfo server) async {
    if (server.status != ServerStatus.running) {
      return;
    }
    
    try {
      // Check server responsiveness
      final response = await server.server.callMethod('system.ping', {});
      
      if (response != null) {
        _connectionFailures.remove(server.id);
      } else {
        _recordFailure(server.id, 'Server not responding');
      }
    } catch (e) {
      _recordFailure(server.id, 'Server health check error: $e');
    }
  }
  
  void _recordFailure(String resourceId, String reason) {
    final failures = (_connectionFailures[resourceId] ?? 0) + 1;
    _connectionFailures[resourceId] = failures;
    
    print('Health check failure for $resourceId: $reason (failures: $failures)');
    
    if (failures >= _maxFailures) {
      _handleUnhealthyConnection(resourceId, failures);
    }
  }
  
  Future<void> _handleUnhealthyConnection(String resourceId, int failures) async {
    print('Connection $resourceId marked as unhealthy after $failures failures');
    
    // Update component health
    await _updateComponentHealth(resourceId, HealthStatus.unhealthy);
    
    // Attempt recovery
    await _attemptRecovery(resourceId);
  }
  
  Future<void> _updateComponentHealth(String resourceId, HealthStatus status) async {
    // Update health status in monitoring system
    HealthMonitor.instance.updateComponentStatus(resourceId, status);
  }
  
  Future<void> _attemptRecovery(String resourceId) async {
    // Attempt to recover unhealthy connection
    if (resourceId.startsWith('client_')) {
      await FlutterMCP.instance.clientManager.reconnectClient(resourceId);
    } else if (resourceId.startsWith('server_')) {
      await FlutterMCP.instance.serverManager.restartServer(resourceId);
    }
  }
}
```

## Health Check Endpoints

### HTTP Health Endpoint

```dart
class HealthEndpoint {
  static Future<shelf.Response> handleHealthRequest(shelf.Request request) async {
    final path = request.url.path;
    
    switch (path) {
      case 'health':
        return await _basicHealthCheck();
      case 'health/detailed':
        return await _detailedHealthCheck();
      case 'health/ready':
        return await _readinessCheck();
      case 'health/live':
        return await _livenessCheck();
      default:
        return shelf.Response.notFound('Not found');
    }
  }
  
  static Future<shelf.Response> _basicHealthCheck() async {
    final health = await FlutterMCP.instance.getSystemHealth();
    
    final status = health.overallStatus == HealthStatus.healthy ? 200 : 503;
    
    return shelf.Response(
      status,
      body: jsonEncode({
        'status': health.overallStatus.toString(),
        'timestamp': health.timestamp.toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  
  static Future<shelf.Response> _detailedHealthCheck() async {
    final health = await FlutterMCP.instance.getSystemHealth();
    
    final components = <String, dynamic>{};
    health.components.forEach((id, component) {
      components[id] = {
        'status': component.status.toString(),
        'message': component.message,
        'checkedAt': component.checkedAt.toIso8601String(),
        'details': component.details,
      };
    });
    
    final status = health.overallStatus == HealthStatus.healthy ? 200 : 503;
    
    return shelf.Response(
      status,
      body: jsonEncode({
        'status': health.overallStatus.toString(),
        'components': components,
        'issues': health.issues.map((issue) => {
          'severity': issue.severity.toString(),
          'description': issue.description,
        }).toList(),
        'timestamp': health.timestamp.toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  
  static Future<shelf.Response> _readinessCheck() async {
    // Check if app is ready to serve requests
    final ready = FlutterMCP.instance.isInitialized &&
                  await _checkDependencies();
    
    return shelf.Response(
      ready ? 200 : 503,
      body: jsonEncode({'ready': ready}),
      headers: {'content-type': 'application/json'},
    );
  }
  
  static Future<shelf.Response> _livenessCheck() async {
    // Simple liveness check
    return shelf.Response(
      200,
      body: jsonEncode({'alive': true}),
      headers: {'content-type': 'application/json'},
    );
  }
  
  static Future<bool> _checkDependencies() async {
    // Check critical dependencies
    try {
      // Check database
      await Database.instance.ping();
      
      // Check external services
      final response = await http.get(
        Uri.parse('https://api.example.com/health'),
      ).timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
```

## Dashboard Integration

### Health Metrics Dashboard

```dart
class HealthDashboard extends StatefulWidget {
  @override
  _HealthDashboardState createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  SystemHealth? _systemHealth;
  Map<String, ResourceStatistics>? _resourceStats;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    _loadHealthData();
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _loadHealthData();
    });
  }
  
  Future<void> _loadHealthData() async {
    final health = await FlutterMCP.instance.getSystemHealth();
    final stats = FlutterMCP.instance.getResourceStatistics();
    
    setState(() {
      _systemHealth = health;
      _resourceStats = stats;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_systemHealth == null) {
      return Center(child: CircularProgressIndicator());
    }
    
    return Column(
      children: [
        _buildOverallStatus(),
        _buildComponentGrid(),
        _buildResourceMetrics(),
        if (_systemHealth!.issues.isNotEmpty) _buildIssuesList(),
      ],
    );
  }
  
  Widget _buildOverallStatus() {
    final status = _systemHealth!.overallStatus;
    final color = _getStatusColor(status);
    
    return Card(
      color: color.withOpacity(0.1),
      child: ListTile(
        leading: Icon(
          _getStatusIcon(status),
          color: color,
          size: 32,
        ),
        title: Text(
          'System Health: ${status.toString().split('.').last.toUpperCase()}',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Last checked: ${_formatTime(_systemHealth!.timestamp)}'),
      ),
    );
  }
  
  Widget _buildComponentGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2,
      ),
      itemCount: _systemHealth!.components.length,
      itemBuilder: (context, index) {
        final entry = _systemHealth!.components.entries.elementAt(index);
        return _buildComponentCard(entry.key, entry.value);
      },
    );
  }
  
  Widget _buildComponentCard(String name, ComponentHealth health) {
    final color = _getStatusColor(health.status);
    
    return Card(
      child: InkWell(
        onTap: () => _showComponentDetails(name, health),
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, color: color, size: 16),
              SizedBox(height: 4),
              Text(
                name,
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              if (health.message != null)
                Text(
                  health.message!,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildResourceMetrics() {
    if (_resourceStats == null) return SizedBox.shrink();
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resource Usage',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ..._resourceStats!.entries.map((entry) {
              final stats = entry.value;
              final usage = stats.currentInUse / stats.totalAllocated;
              
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text('${(usage * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: usage,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation(
                      usage > 0.8 ? Colors.red : Colors.green,
                    ),
                  ),
                  SizedBox(height: 8),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildIssuesList() {
    return Card(
      color: Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Issues',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            ..._systemHealth!.issues.map((issue) {
              return ListTile(
                leading: Icon(
                  _getSeverityIcon(issue.severity),
                  color: _getSeverityColor(issue.severity),
                ),
                title: Text(issue.description),
                subtitle: Text('Since: ${_formatTime(issue.detectedAt)}'),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
  
  Color _getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.healthy:
        return Colors.green;
      case HealthStatus.degraded:
        return Colors.orange;
      case HealthStatus.unhealthy:
        return Colors.red;
      case HealthStatus.unknown:
        return Colors.grey;
    }
  }
  
  IconData _getStatusIcon(HealthStatus status) {
    switch (status) {
      case HealthStatus.healthy:
        return Icons.check_circle;
      case HealthStatus.degraded:
        return Icons.warning;
      case HealthStatus.unhealthy:
        return Icons.error;
      case HealthStatus.unknown:
        return Icons.help;
    }
  }
  
  IconData _getSeverityIcon(IssueSeverity severity) {
    switch (severity) {
      case IssueSeverity.low:
        return Icons.info;
      case IssueSeverity.medium:
        return Icons.warning;
      case IssueSeverity.high:
        return Icons.error;
      case IssueSeverity.critical:
        return Icons.dangerous;
    }
  }
  
  Color _getSeverityColor(IssueSeverity severity) {
    switch (severity) {
      case IssueSeverity.low:
        return Colors.blue;
      case IssueSeverity.medium:
        return Colors.orange;
      case IssueSeverity.high:
        return Colors.deepOrange;
      case IssueSeverity.critical:
        return Colors.red;
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }
  
  void _showComponentDetails(String name, ComponentHealth health) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${health.status}'),
            if (health.message != null) Text('Message: ${health.message}'),
            Text('Last checked: ${_formatTime(health.checkedAt)}'),
            if (health.details != null) ...[
              SizedBox(height: 16),
              Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(jsonEncode(health.details)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
```

## Alerting

### Health Alert Configuration

```dart
class HealthAlertManager {
  final Map<String, AlertConfig> _alertConfigs = {
    'memory_high': AlertConfig(
      condition: (health) => _checkMemoryUsage(health) > 0.8,
      severity: AlertSeverity.warning,
      message: 'Memory usage above 80%',
      actions: [AlertAction.notify, AlertAction.log],
    ),
    'memory_critical': AlertConfig(
      condition: (health) => _checkMemoryUsage(health) > 0.95,
      severity: AlertSeverity.critical,
      message: 'Memory usage critical - above 95%',
      actions: [AlertAction.notify, AlertAction.page, AlertAction.autoRecover],
    ),
    'component_down': AlertConfig(
      condition: (health) => _hasUnhealthyComponents(health),
      severity: AlertSeverity.high,
      message: 'One or more components are unhealthy',
      actions: [AlertAction.notify, AlertAction.log],
    ),
  };
  
  Future<void> checkAlerts(SystemHealth health) async {
    for (final entry in _alertConfigs.entries) {
      final config = entry.value;
      
      if (config.condition(health)) {
        await _triggerAlert(entry.key, config, health);
      }
    }
  }
  
  Future<void> _triggerAlert(
    String alertId,
    AlertConfig config,
    SystemHealth health,
  ) async {
    print('ALERT: ${config.message}');
    
    for (final action in config.actions) {
      switch (action) {
        case AlertAction.notify:
          await _sendNotification(config);
          break;
        case AlertAction.log:
          await _logAlert(alertId, config, health);
          break;
        case AlertAction.page:
          await _pageOnCall(config);
          break;
        case AlertAction.autoRecover:
          await _attemptAutoRecovery(alertId, health);
          break;
      }
    }
  }
  
  static double _checkMemoryUsage(SystemHealth health) {
    final stats = FlutterMCP.instance.getResourceStatistics();
    final memoryStats = stats['memory'];
    if (memoryStats != null) {
      return memoryStats.currentInUse / memoryStats.totalAllocated;
    }
    return 0.0;
  }
  
  static bool _hasUnhealthyComponents(SystemHealth health) {
    return health.components.values.any(
      (component) => component.status == HealthStatus.unhealthy,
    );
  }
  
  Future<void> _sendNotification(AlertConfig config) async {
    await FlutterMCP.instance.backgroundService.showNotification(
      title: 'Health Alert',
      body: config.message,
      priority: config.severity == AlertSeverity.critical
        ? NotificationPriority.urgent
        : NotificationPriority.high,
    );
  }
  
  Future<void> _logAlert(String alertId, AlertConfig config, SystemHealth health) async {
    // Log to monitoring system
    await Logger('HealthAlert').severe(
      'Alert triggered: $alertId - ${config.message}',
      health.toJson(),
    );
  }
  
  Future<void> _pageOnCall(AlertConfig config) async {
    // Integration with paging service
    // await PagerDuty.triggerIncident(config.message);
  }
  
  Future<void> _attemptAutoRecovery(String alertId, SystemHealth health) async {
    switch (alertId) {
      case 'memory_critical':
        // Force garbage collection and clear caches
        await MemoryManager.instance.emergencyCleanup();
        break;
      case 'component_down':
        // Restart unhealthy components
        for (final entry in health.components.entries) {
          if (entry.value.status == HealthStatus.unhealthy) {
            await _restartComponent(entry.key);
          }
        }
        break;
    }
  }
  
  Future<void> _restartComponent(String componentId) async {
    // Component-specific restart logic
    print('Attempting to restart component: $componentId');
  }
}

class AlertConfig {
  final bool Function(SystemHealth) condition;
  final AlertSeverity severity;
  final String message;
  final List<AlertAction> actions;
  
  AlertConfig({
    required this.condition,
    required this.severity,
    required this.message,
    required this.actions,
  });
}

enum AlertSeverity { low, medium, high, warning, critical }
enum AlertAction { notify, log, page, autoRecover }
```

## Best Practices

### 1. Regular Health Checks

```dart
// Configure appropriate intervals
const healthCheckIntervals = {
  'system': Duration(seconds: 30),
  'connections': Duration(minutes: 1),
  'resources': Duration(minutes: 5),
  'detailed': Duration(minutes: 15),
};
```

### 2. Graceful Degradation

```dart
class GracefulDegradation {
  Future<void> handleDegradedHealth(ComponentHealth health) async {
    switch (health.componentId) {
      case 'llm_manager':
        // Reduce LLM query concurrency
        await FlutterMCP.instance.llmManager.setMaxConcurrency(1);
        break;
      case 'client_manager':
        // Pause new connections
        await FlutterMCP.instance.clientManager.pauseNewConnections();
        break;
    }
  }
}
```

### 3. Health Check Caching

```dart
class CachedHealthCheck {
  final Duration _cacheExpiry = Duration(seconds: 10);
  SystemHealth? _cachedHealth;
  DateTime? _lastCheck;
  
  Future<SystemHealth> getHealth() async {
    if (_cachedHealth != null && 
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _cacheExpiry) {
      return _cachedHealth!;
    }
    
    _cachedHealth = await FlutterMCP.instance.getSystemHealth();
    _lastCheck = DateTime.now();
    
    return _cachedHealth!;
  }
}
```

## See Also

- [Performance Monitoring](../guides/performance-monitoring-guide.md)
- [Circuit Breaker Guide](circuit-breaker.md)
- [API Reference - Health Methods](../api/flutter-mcp-api.md#health--monitoring-methods)