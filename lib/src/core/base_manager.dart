/// Base manager class for consistent initialization and disposal patterns
library;

import 'dart:async';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/operation_wrapper.dart';
import '../events/event_models.dart';
import '../utils/event_system.dart';
import '../monitoring/health_monitor.dart';
import '../types/health_types.dart';

/// Base class for all managers with common lifecycle patterns
abstract class BaseManager with OperationWrapperMixin, HealthCheckMixin {
  final String managerName;
  
  @override
  final Logger logger;
  
  bool _initialized = false;
  bool _disposed = false;
  final DateTime _createdAt = DateTime.now();
  
  BaseManager(this.managerName) 
    : logger = Logger('flutter_mcp.$managerName');
  
  @override
  String get componentId => 'manager_$managerName';
  
  /// Whether the manager is initialized
  bool get isInitialized => _initialized;
  
  /// Whether the manager is disposed
  bool get isDisposed => _disposed;
  
  /// How long the manager has been alive
  Duration get uptime => DateTime.now().difference(_createdAt);
  
  /// Initialize the manager
  Future<void> initialize() async {
    if (_disposed) {
      throw MCPException('Cannot initialize disposed manager: $managerName');
    }
    
    if (_initialized) {
      logger.fine('$managerName already initialized');
      return;
    }
    
    await executeAsyncOperation<void>(
      operationName: 'initialize_$managerName',
      operation: () async {
        await onInitialize();
        _initialized = true;
        _publishLifecycleEvent('initialized');
        
        // Register health check after initialization
        registerHealthCheck();
        reportHealthy('Manager initialized successfully');
      },
      config: OperationConfig.criticalOperation,
    );
  }
  
  /// Dispose the manager
  Future<void> dispose() async {
    if (_disposed) {
      logger.fine('$managerName already disposed');
      return;
    }
    
    await executeAsyncOperation<void>(
      operationName: 'dispose_$managerName',
      operation: () async {
        _publishLifecycleEvent('disposing');
        
        // Unregister health check before disposal
        unregisterHealthCheck();
        
        await onDispose();
        _disposed = true;
        _initialized = false;
        _publishLifecycleEvent('disposed');
      },
      config: OperationConfig(
        timeout: Duration(seconds: 30),
        recordMetrics: true,
        throwOnError: false, // Don't throw on disposal errors
      ),
    );
  }
  
  /// Restart the manager (dispose then initialize)
  Future<void> restart() async {
    await executeAsyncOperation<void>(
      operationName: 'restart_$managerName',
      operation: () async {
        if (_initialized && !_disposed) {
          await dispose();
        }
        await initialize();
      },
      config: OperationConfig.criticalOperation,
    );
  }
  
  /// Get manager status
  Map<String, dynamic> getStatus() {
    return {
      'managerName': managerName,
      'initialized': _initialized,
      'disposed': _disposed,
      'createdAt': _createdAt.toIso8601String(),
      'uptime': uptime.inMilliseconds,
      'health': HealthMonitor.instance.currentHealth['components']?[componentId] ?? 'unknown',
    };
  }
  
  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    // Default health check implementation
    if (!_initialized) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'Manager not initialized',
      );
    }
    
    if (_disposed) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'Manager is disposed',
      );
    }
    
    // Subclasses can override for specific health checks
    return MCPHealthCheckResult(
      status: MCPHealthStatus.healthy,
      message: 'Manager is operational',
      details: getStatus(),
    );
  }
  
  /// Template method for initialization - override in subclasses
  Future<void> onInitialize();
  
  /// Template method for disposal - override in subclasses
  Future<void> onDispose() async {
    // Default implementation does nothing
  }
  
  /// Publish lifecycle event
  void _publishLifecycleEvent(String state) {
    final event = ManagerLifecycleEvent(
      managerName: managerName,
      state: state,
      metadata: getStatus(),
    );
    
    EventSystem.instance.publishTyped<ManagerLifecycleEvent>(event);
  }
  
  /// Ensure manager is initialized before operations
  void ensureInitialized() {
    if (!_initialized || _disposed) {
      throw MCPException('Manager $managerName is not initialized');
    }
  }
}

/// Manager lifecycle event
class ManagerLifecycleEvent extends McpEvent {
  @override
  final DateTime timestamp;
  final String managerName;
  final String state;
  final Map<String, dynamic> metadata;
  
  ManagerLifecycleEvent({
    required this.managerName,
    required this.state,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  @override
  String get eventType => 'manager.lifecycle';
  
  @override
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'managerName': managerName,
      'state': state,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Configuration-based manager for managers that load configuration
abstract class ConfigBasedManager<T> extends BaseManager {
  T? _config;
  
  ConfigBasedManager(String managerName) : super(managerName);
  
  /// Get current configuration
  T? get config => _config;
  
  /// Whether configuration is loaded
  bool get isConfigured => _config != null;
  
  @override
  Future<void> onInitialize() async {
    // Load configuration first
    _config = await loadConfiguration();
    
    // Validate configuration
    final loadedConfig = _config;
    if (loadedConfig != null) {
      validateConfiguration(loadedConfig);
      
      // Initialize with configuration
      await initializeWithConfig(loadedConfig);
    } else {
      throw MCPConfigurationException('Failed to load configuration for $managerName');
    }
  }
  
  /// Load configuration from source
  Future<T> loadConfiguration();
  
  /// Validate loaded configuration
  void validateConfiguration(T config) {
    // Default implementation does nothing
  }
  
  /// Initialize with validated configuration
  Future<void> initializeWithConfig(T config);
  
  @override
  Map<String, dynamic> getStatus() {
    final status = super.getStatus();
    status['configured'] = isConfigured;
    return status;
  }
}

/// Platform-specific manager for managers that handle platform differences
abstract class PlatformSpecificManager extends BaseManager {
  final String platformName;
  
  PlatformSpecificManager(String managerName, this.platformName) 
    : super('${managerName}_$platformName');
  
  @override
  Future<void> onInitialize() async {
    // Check platform support
    if (!isPlatformSupported()) {
      throw MCPPlatformNotSupportedException(
        '$managerName on $platformName',
        errorCode: 'PLATFORM_UNSUPPORTED_$managerName',
        resolution: 'Use a different platform or check platform-specific requirements',
      );
    }
    
    await initializeForPlatform();
  }
  
  /// Check if current platform is supported
  bool isPlatformSupported();
  
  /// Initialize for the specific platform
  Future<void> initializeForPlatform();
  
  @override
  Map<String, dynamic> getStatus() {
    final status = super.getStatus();
    status['platformName'] = platformName;
    status['platformSupported'] = isPlatformSupported();
    return status;
  }
}

/// Resource-managing manager for managers that handle disposable resources
abstract class ResourceManagingManager extends BaseManager {
  final List<String> _managedResourceKeys = [];
  
  ResourceManagingManager(String managerName) : super(managerName);
  
  /// Register a resource to be managed by this manager
  void registerManagedResource(String resourceKey) {
    _managedResourceKeys.add(resourceKey);
    logger.fine('Registered managed resource: $resourceKey');
  }
  
  /// Unregister a managed resource
  void unregisterManagedResource(String resourceKey) {
    _managedResourceKeys.remove(resourceKey);
    logger.fine('Unregistered managed resource: $resourceKey');
  }
  
  /// Get all managed resource keys
  List<String> get managedResources => List.unmodifiable(_managedResourceKeys);
  
  @override
  Future<void> onDispose() async {
    // Dispose all managed resources
    if (_managedResourceKeys.isNotEmpty) {
      logger.fine('Disposing ${_managedResourceKeys.length} managed resources');
      
      for (final resourceKey in _managedResourceKeys.reversed) {
        try {
          await disposeResource(resourceKey);
        } catch (e) {
          logger.warning('Failed to dispose resource $resourceKey: $e');
        }
      }
      
      _managedResourceKeys.clear();
    }
    
    await super.onDispose();
  }
  
  /// Dispose a specific resource - override in subclasses
  Future<void> disposeResource(String resourceKey) async {
    // Default implementation does nothing
  }
  
  @override
  Map<String, dynamic> getStatus() {
    final status = super.getStatus();
    status['managedResourceCount'] = _managedResourceKeys.length;
    status['managedResources'] = _managedResourceKeys;
    return status;
  }
}

/// Singleton manager mixin for managers that should be singletons
mixin SingletonManager<T extends BaseManager> on BaseManager {
  static final Map<Type, BaseManager> _instances = {};
  
  /// Get singleton instance
  static T getInstance<T extends BaseManager>(T Function() factory) {
    return _instances.putIfAbsent(T, factory) as T;
  }
  
  /// Clear singleton instance
  static void clearInstance<T extends BaseManager>() {
    final instance = _instances.remove(T);
    if (instance != null && !instance.isDisposed) {
      instance.dispose();
    }
  }
  
  /// Clear all singleton instances
  static Future<void> clearAllInstances() async {
    final instances = List.from(_instances.values);
    _instances.clear();
    
    for (final instance in instances) {
      if (!instance.isDisposed) {
        await instance.dispose();
      }
    }
  }
}