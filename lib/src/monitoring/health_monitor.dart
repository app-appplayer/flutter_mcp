import 'dart:async';
import '../events/event_system.dart';
import '../utils/logger.dart';
import '../types/health_types.dart';

/// Represents the health of a single component
class ComponentHealth {
  final String componentId;
  final MCPHealthStatus status;
  final String? message;
  final DateTime lastCheck;
  final Map<String, dynamic>? metadata;

  ComponentHealth({
    required this.componentId,
    required this.status,
    this.message,
    required this.lastCheck,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'componentId': componentId,
      'status': status.name,
      'message': message,
      'lastCheck': lastCheck.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Enhanced health monitoring system with real-time updates
class HealthMonitor {
  static HealthMonitor? _instance;
  static HealthMonitor get instance {
    _instance ??= HealthMonitor._();
    return _instance!;
  }

  HealthMonitor._();

  final Logger _logger = Logger('flutter_mcp.health_monitor');
  StreamController<MCPHealthCheckResult>? _healthStreamController;
  final Map<String, ComponentHealth> _componentHealths = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final EventSystem _eventSystem = EventSystem.instance;

  Timer? _aggregateHealthTimer;
  bool _isActive = false;

  // Configuration
  Duration _checkInterval = const Duration(seconds: 10);
  Duration _componentTimeout = const Duration(seconds: 5);

  /// Stream of health check results
  Stream<MCPHealthCheckResult> get healthStream {
    _healthStreamController ??=
        StreamController<MCPHealthCheckResult>.broadcast();
    return _healthStreamController!.stream;
  }

  /// Get current health snapshot
  Map<String, dynamic> get currentHealth {
    final overallStatus = _calculateOverallHealth();
    return {
      'status': overallStatus.name,
      'timestamp': DateTime.now().toIso8601String(),
      'components': _componentHealths.map((k, v) => MapEntry(k, v.toMap())),
      'summary': _generateHealthSummary(),
    };
  }

  /// Initialize the health monitor
  void initialize({
    Duration? checkInterval,
    Duration? componentTimeout,
  }) {
    if (_isActive) {
      _logger.warning('Health monitor already initialized');
      return;
    }

    _checkInterval = checkInterval ?? _checkInterval;
    _componentTimeout = componentTimeout ?? _componentTimeout;

    // Initialize stream controller if needed
    _healthStreamController ??=
        StreamController<MCPHealthCheckResult>.broadcast();

    _isActive = true;
    _startAggregateHealthCheck();
    _subscribeToEvents();

    _logger.info(
        'Health monitor initialized with check interval: $_checkInterval');
  }

  /// Register a component for health monitoring
  void registerComponent(
    String componentId, {
    Duration? customCheckInterval,
    Future<MCPHealthCheckResult> Function()? healthCheck,
  }) {
    if (_componentHealths.containsKey(componentId)) {
      _logger.warning('Component already registered: $componentId');
      return;
    }

    // Initial health status
    _componentHealths[componentId] = ComponentHealth(
      componentId: componentId,
      status: MCPHealthStatus.healthy,
      message: 'Component registered',
      lastCheck: DateTime.now(),
    );

    // Set up periodic health check if provided
    if (healthCheck != null) {
      final interval = customCheckInterval ?? _checkInterval;
      _healthCheckTimers[componentId] = Timer.periodic(interval, (_) async {
        await _performHealthCheck(componentId, healthCheck);
      });
    }

    _logger.fine('Registered component for health monitoring: $componentId');
    _emitHealthUpdate();
  }

  /// Unregister a component from health monitoring
  void unregisterComponent(String componentId) {
    _componentHealths.remove(componentId);
    _healthCheckTimers[componentId]?.cancel();
    _healthCheckTimers.remove(componentId);

    _logger.fine('Unregistered component from health monitoring: $componentId');
    _emitHealthUpdate();
  }

  /// Update component health status
  void updateComponentHealth(
    String componentId,
    MCPHealthStatus status,
    String? message, {
    Map<String, dynamic>? metadata,
  }) {
    final previousHealth = _componentHealths[componentId];

    _componentHealths[componentId] = ComponentHealth(
      componentId: componentId,
      status: status,
      message: message,
      lastCheck: DateTime.now(),
      metadata: metadata,
    );

    // Log status changes
    if (previousHealth?.status != status) {
      _logger.info(
          'Component $componentId health changed: ${previousHealth?.status.name} -> ${status.name}');

      // Publish health change event
      _eventSystem.publishTopic('health.component.changed', {
        'componentId': componentId,
        'previousStatus': previousHealth?.status.name,
        'newStatus': status.name,
        'message': message,
      });
    }

    _emitHealthUpdate();
  }

  /// Perform a health check for all components
  Future<Map<String, dynamic>> performFullHealthCheck() async {
    final futures = <String, Future<ComponentHealth>>{};

    for (final componentId in _componentHealths.keys) {
      futures[componentId] = _checkComponentHealth(componentId);
    }

    await Future.wait(futures.values);

    return currentHealth;
  }

  /// Check if system is healthy
  bool isHealthy() {
    final overallStatus = _calculateOverallHealth();
    return overallStatus == MCPHealthStatus.healthy;
  }

  /// Get health history for a component
  List<ComponentHealth> getComponentHistory(String componentId,
      {int limit = 100}) {
    // In a real implementation, this would query from a time-series database
    // For now, return current status only
    final current = _componentHealths[componentId];
    return current != null ? [current] : [];
  }

  /// Dispose the health monitor
  void dispose() {
    _isActive = false;
    _aggregateHealthTimer?.cancel();

    for (final timer in _healthCheckTimers.values) {
      timer.cancel();
    }
    _healthCheckTimers.clear();

    _componentHealths.clear(); // Clear component health data

    _healthStreamController?.close();
    _healthStreamController = null; // Allow reinitialization
    _logger.info('Health monitor disposed');
  }

  // Private methods

  void _startAggregateHealthCheck() {
    _aggregateHealthTimer = Timer.periodic(_checkInterval, (_) {
      _checkStaleComponents();
      _emitHealthUpdate();
    });
  }

  void _subscribeToEvents() {
    // Subscribe to system events that affect health
    _eventSystem.subscribeTopic('error.occurred', (data) {
      final componentId = data['componentId'] as String?;
      if (componentId != null) {
        updateComponentHealth(
          componentId,
          MCPHealthStatus.unhealthy,
          'Error: ${data['error']}',
          metadata: data,
        );
      }
    });

    _eventSystem.subscribeTopic('component.recovered', (data) {
      final componentId = data['componentId'] as String?;
      if (componentId != null) {
        updateComponentHealth(
          componentId,
          MCPHealthStatus.healthy,
          'Component recovered',
          metadata: data,
        );
      }
    });
  }

  Future<void> _performHealthCheck(
    String componentId,
    Future<MCPHealthCheckResult> Function() healthCheck,
  ) async {
    try {
      final result = await healthCheck().timeout(_componentTimeout);
      updateComponentHealth(
        componentId,
        result.status,
        result.message,
        metadata: result.details,
      );
    } catch (e) {
      updateComponentHealth(
        componentId,
        MCPHealthStatus.unhealthy,
        'Health check failed: $e',
        metadata: {'error': e.toString()},
      );
    }
  }

  Future<ComponentHealth> _checkComponentHealth(String componentId) async {
    // Default implementation - can be overridden by registered health checks
    return _componentHealths[componentId] ??
        ComponentHealth(
          componentId: componentId,
          status: MCPHealthStatus.unhealthy,
          message: 'Component not found',
          lastCheck: DateTime.now(),
        );
  }

  void _checkStaleComponents() {
    final now = DateTime.now();
    final staleThreshold = _checkInterval * 3;

    for (final component in _componentHealths.values) {
      final timeSinceLastCheck = now.difference(component.lastCheck);
      if (timeSinceLastCheck > staleThreshold &&
          component.status != MCPHealthStatus.unhealthy) {
        updateComponentHealth(
          component.componentId,
          MCPHealthStatus.degraded,
          'No health update for ${timeSinceLastCheck.inSeconds} seconds',
        );
      }
    }
  }

  MCPHealthStatus _calculateOverallHealth() {
    if (_componentHealths.isEmpty) {
      return MCPHealthStatus.healthy;
    }

    int unhealthyCount = 0;
    int degradedCount = 0;

    for (final health in _componentHealths.values) {
      switch (health.status) {
        case MCPHealthStatus.unhealthy:
          unhealthyCount++;
          break;
        case MCPHealthStatus.degraded:
          degradedCount++;
          break;
        case MCPHealthStatus.healthy:
          break;
      }
    }

    // Overall health rules
    if (unhealthyCount > 0) {
      return MCPHealthStatus.unhealthy;
    } else if (degradedCount > _componentHealths.length ~/ 2) {
      // If more than half are degraded, overall is degraded
      return MCPHealthStatus.degraded;
    } else if (degradedCount > 0) {
      // Some degraded but system can function
      return MCPHealthStatus.degraded;
    }

    return MCPHealthStatus.healthy;
  }

  Map<String, dynamic> _generateHealthSummary() {
    final statusCounts = <MCPHealthStatus, int>{};

    for (final health in _componentHealths.values) {
      statusCounts[health.status] = (statusCounts[health.status] ?? 0) + 1;
    }

    return {
      'totalComponents': _componentHealths.length,
      'healthy': statusCounts[MCPHealthStatus.healthy] ?? 0,
      'degraded': statusCounts[MCPHealthStatus.degraded] ?? 0,
      'unhealthy': statusCounts[MCPHealthStatus.unhealthy] ?? 0,
    };
  }

  void _emitHealthUpdate() {
    if (!_isActive) return;

    final overallStatus = _calculateOverallHealth();
    final result = MCPHealthCheckResult(
      status: overallStatus,
      message: 'System health check',
      details: currentHealth,
    );

    _healthStreamController?.add(result);

    // Publish overall health event
    _eventSystem.publishTopic('health.overall.updated', {
      'status': overallStatus.name,
      'timestamp': DateTime.now().toIso8601String(),
      'summary': _generateHealthSummary(),
    });
  }
}

/// Health check provider interface
abstract class HealthCheckProvider {
  String get componentId;
  Future<MCPHealthCheckResult> performHealthCheck();
}

/// Mixin for classes that want to provide health checks
mixin HealthCheckMixin implements HealthCheckProvider {
  void registerHealthCheck() {
    HealthMonitor.instance.registerComponent(
      componentId,
      healthCheck: performHealthCheck,
    );
  }

  void unregisterHealthCheck() {
    HealthMonitor.instance.unregisterComponent(componentId);
  }

  void reportHealthy([String? message]) {
    HealthMonitor.instance.updateComponentHealth(
      componentId,
      MCPHealthStatus.healthy,
      message,
    );
  }

  void reportDegraded(String message) {
    HealthMonitor.instance.updateComponentHealth(
      componentId,
      MCPHealthStatus.degraded,
      message,
    );
  }

  void reportUnhealthy(String message) {
    HealthMonitor.instance.updateComponentHealth(
      componentId,
      MCPHealthStatus.unhealthy,
      message,
    );
  }
}
