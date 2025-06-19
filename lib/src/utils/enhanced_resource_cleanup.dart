import 'dart:async';
import 'package:meta/meta.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/enhanced_error_handler.dart';
import '../monitoring/health_monitor.dart';
import '../events/event_system.dart';
import '../types/health_types.dart';

/// Resource lifecycle states
enum ResourceState { registered, active, disposing, disposed, failed }

/// Enhanced resource allocation tracking
class EnhancedResourceAllocation {
  final String id;
  final String type;
  final int memorySizeMB;
  final DateTime allocatedAt;
  final StackTrace allocationStackTrace;
  final String? description;
  ResourceState state;
  DateTime? disposedAt;
  Duration? lifetime;

  EnhancedResourceAllocation({
    required this.id,
    required this.type,
    required this.memorySizeMB,
    required this.allocatedAt,
    required this.allocationStackTrace,
    this.description,
    this.state = ResourceState.registered,
  });

  /// Mark resource as active
  void markActive() {
    state = ResourceState.active;
  }

  /// Mark resource as disposed
  void markDisposed() {
    state = ResourceState.disposed;
    disposedAt = DateTime.now();
    lifetime = disposedAt!.difference(allocatedAt);
  }

  /// Mark resource as failed
  void markFailed() {
    state = ResourceState.failed;
  }

  /// Get resource age
  Duration get age => DateTime.now().difference(allocatedAt);

  /// Check if resource is leaked (active for too long)
  bool isLeaked(Duration threshold) {
    return state == ResourceState.active && age > threshold;
  }
}

/// Enhanced disposable resource wrapper with leak detection
class EnhancedDisposableResource<T> {
  final String key;
  final T resource;
  final Future<void> Function(T) disposeFunction;
  final int priority;
  final String? tag;
  final EnhancedResourceAllocation allocation;
  final List<String> dependencies;

  bool _disposed = false;
  Timer? _leakDetectionTimer;

  EnhancedDisposableResource({
    required this.key,
    required this.resource,
    required this.disposeFunction,
    required this.priority,
    required this.allocation,
    this.tag,
    this.dependencies = const [],
    Duration? leakDetectionTimeout,
  }) {
    // Set up leak detection
    if (leakDetectionTimeout != null) {
      _leakDetectionTimer = Timer(leakDetectionTimeout, () {
        if (!_disposed && allocation.state == ResourceState.active) {
          Logger('flutter_mcp.resource_cleanup').warning(
              'Potential resource leak detected: $key (type: ${allocation.type}, age: ${allocation.age.inSeconds}s)');
          allocation.markFailed();
        }
      });
    }
  }

  /// Dispose the resource
  Future<void> dispose() async {
    if (_disposed) return;

    _leakDetectionTimer?.cancel();
    allocation.state = ResourceState.disposing;

    try {
      await disposeFunction(resource);
      _disposed = true;
      allocation.markDisposed();
    } catch (e) {
      allocation.markFailed();
      rethrow;
    }
  }

  bool get isDisposed => _disposed;
}

/// Enhanced resource cleanup manager with leak detection
class EnhancedResourceCleanup {
  static EnhancedResourceCleanup? _instance;
  static EnhancedResourceCleanup get instance {
    _instance ??= EnhancedResourceCleanup._();
    return _instance!;
  }

  EnhancedResourceCleanup._();

  final Logger _logger = Logger('flutter_mcp.enhanced_resource_cleanup');
  final EventSystem _eventSystem = EventSystem.instance;

  /// Resources to dispose
  final Map<String, EnhancedDisposableResource> _resources = {};

  /// Resource dependency graph
  final Map<String, Set<String>> _dependencies = {};
  final Map<String, Set<String>> _dependents = {};

  /// Resource cleanup priority groups
  final Map<int, Set<String>> _priorityGroups = {};

  /// Weak references for leak detection
  final Map<String, WeakReference<Object>> _weakReferences = {};

  /// Resource statistics
  int _totalResourcesRegistered = 0;
  int _totalResourcesDisposed = 0;
  int _failedDisposals = 0;
  int _leaksDetected = 0;

  /// Leak detection configuration
  Duration _defaultLeakDetectionTimeout = Duration(minutes: 5);
  Timer? _periodicLeakChecker;

  /// Initialize the resource cleanup manager
  void initialize({
    Duration? defaultLeakDetectionTimeout,
    Duration periodicLeakCheckInterval = const Duration(minutes: 1),
  }) {
    if (defaultLeakDetectionTimeout != null) {
      _defaultLeakDetectionTimeout = defaultLeakDetectionTimeout;
    }

    // Start periodic leak checker
    _periodicLeakChecker?.cancel();
    _periodicLeakChecker = Timer.periodic(periodicLeakCheckInterval, (_) {
      checkForLeaks();
    });

    _logger.info('Enhanced resource cleanup initialized');
  }

  /// Register a resource with enhanced tracking
  void registerResource<T extends Object>({
    required String key,
    required T resource,
    required Future<void> Function(T) disposeFunction,
    required String type,
    int priority = 100,
    List<String>? dependencies,
    String? tag,
    String? description,
    int? estimatedMemoryMB,
    Duration? leakDetectionTimeout,
  }) {
    _logger.fine('Registering resource: $key (type: $type)');

    // Create allocation tracking
    final allocation = EnhancedResourceAllocation(
      id: key,
      type: type,
      memorySizeMB: estimatedMemoryMB ?? 0,
      allocatedAt: DateTime.now(),
      allocationStackTrace: StackTrace.current,
      description: description,
    );

    // Dispose any existing resource with the same key
    if (_resources.containsKey(key)) {
      _logger.warning(
          'Resource with key $key already exists, disposing previous resource');
      _disposeResourceAsync(key);
    }

    // Create disposable resource wrapper
    final disposableResource = EnhancedDisposableResource<T>(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      priority: priority,
      tag: tag,
      allocation: allocation,
      dependencies: dependencies ?? [],
      leakDetectionTimeout:
          leakDetectionTimeout ?? _defaultLeakDetectionTimeout,
    );

    _resources[key] = disposableResource;

    // Add weak reference for leak detection
    _weakReferences[key] = WeakReference(resource);

    // Add to priority group
    _priorityGroups.putIfAbsent(priority, () => {}).add(key);

    // Register dependencies
    if (dependencies != null && dependencies.isNotEmpty) {
      for (final dep in dependencies) {
        _addDependency(key, dep);
      }
    }

    _totalResourcesRegistered++;
    allocation.markActive();

    // Publish resource registration event
    _publishResourceEvent('registered', key, type);
  }

  /// Add a dependency between resources
  void _addDependency(String resource, String dependsOn) {
    if (_wouldCreateCircularDependency(resource, dependsOn)) {
      throw MCPException(
          'Circular dependency detected: $resource -> $dependsOn');
    }

    _dependencies.putIfAbsent(resource, () => {}).add(dependsOn);
    _dependents.putIfAbsent(dependsOn, () => {}).add(resource);
  }

  /// Check for circular dependencies
  bool _wouldCreateCircularDependency(String resource, String dependsOn) {
    return _isDependentOn(dependsOn, resource);
  }

  /// Check if resource1 depends on resource2
  bool _isDependentOn(String resource1, String resource2) {
    if (_dependencies.containsKey(resource1) &&
        _dependencies[resource1]!.contains(resource2)) {
      return true;
    }

    if (_dependencies.containsKey(resource1)) {
      for (final dep in _dependencies[resource1]!) {
        if (_isDependentOn(dep, resource2)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Dispose a specific resource
  Future<void> disposeResource(String key) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        if (!_resources.containsKey(key)) {
          _logger.warning('No resource found with key: $key');
          return;
        }

        final resource = _resources[key]!;
        _logger.fine(
            'Disposing resource: $key (type: ${resource.allocation.type})');

        // Check and dispose dependents first
        if (_dependents.containsKey(key) && _dependents[key]!.isNotEmpty) {
          _logger.fine(
              'Resource $key has dependents: ${_dependents[key]!.join(", ")}');

          for (final dependent in List<String>.from(_dependents[key]!)) {
            await disposeResource(dependent);
          }
        }

        // Dispose the resource
        await resource.dispose();

        // Clean up
        _cleanupResource(key);
        _totalResourcesDisposed++;

        // Publish disposal event
        _publishResourceEvent('disposed', key, resource.allocation.type);
      },
      context: 'resource_disposal',
      component: 'resource_cleanup',
      metadata: {'resourceKey': key},
    ).catchError((e, stackTrace) {
      _failedDisposals++;
      _logger.severe('Failed to dispose resource: $key', e, stackTrace);
      throw MCPOperationFailedException(
        'Failed to dispose resource: $key',
        e,
        stackTrace,
      );
    });
  }

  /// Async resource disposal (fire and forget)
  void _disposeResourceAsync(String key) {
    disposeResource(key).catchError((e) {
      _logger.severe('Async disposal failed for resource: $key', e);
    });
  }

  /// Clean up resource tracking
  void _cleanupResource(String key) {
    _resources.remove(key);
    _weakReferences.remove(key);
    _removeDependencies(key);
  }

  /// Remove all dependencies for a resource
  void _removeDependencies(String key) {
    // Remove as a dependency
    if (_dependencies.containsKey(key)) {
      for (final dep in _dependencies[key]!) {
        _dependents[dep]?.remove(key);
        if (_dependents[dep]?.isEmpty ?? false) {
          _dependents.remove(dep);
        }
      }
      _dependencies.remove(key);
    }

    // Remove as a dependent
    if (_dependents.containsKey(key)) {
      for (final dep in _dependents[key]!) {
        _dependencies[dep]?.remove(key);
        if (_dependencies[dep]?.isEmpty ?? false) {
          _dependencies.remove(dep);
        }
      }
      _dependents.remove(key);
    }

    // Remove from priority groups
    for (final group in _priorityGroups.values) {
      group.remove(key);
    }

    // Clean up empty priority groups
    _priorityGroups.removeWhere((_, resources) => resources.isEmpty);
  }

  /// Dispose all resources in priority order
  Future<void> disposeAll() async {
    _logger.info('Disposing all resources');

    final errors = <String, dynamic>{};

    try {
      // Cancel periodic leak checker
      _periodicLeakChecker?.cancel();

      // Sort priority groups (higher numbers disposed first)
      final priorities = _priorityGroups.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      // Dispose by priority groups
      for (final priority in priorities) {
        if (!_priorityGroups.containsKey(priority)) continue;

        final groupKeys = List<String>.from(_priorityGroups[priority]!);

        // Sort by dependencies within the group
        groupKeys.sort((a, b) {
          if (_isDependentOn(a, b)) return -1;
          if (_isDependentOn(b, a)) return 1;
          return 0;
        });

        // Dispose each resource
        for (final key in groupKeys) {
          if (!_resources.containsKey(key)) continue;

          try {
            await disposeResource(key);
          } catch (e) {
            errors[key] = e;
          }
        }
      }

      // Clear all tracking
      _resources.clear();
      _weakReferences.clear();
      _dependencies.clear();
      _dependents.clear();
      _priorityGroups.clear();
    } catch (e, stackTrace) {
      _logger.severe('Unexpected error during resource cleanup', e, stackTrace);
      errors['_general'] = e;
    }

    if (errors.isNotEmpty) {
      throw MCPException('Errors occurred while disposing resources: $errors');
    }

    _logger.info(
        'Resource cleanup complete. Disposed: $_totalResourcesDisposed, Failed: $_failedDisposals');
  }

  /// Check for resource leaks
  void checkForLeaks() {
    int leaksFound = 0;
    final leakedResources = <String>[];

    for (final entry in _resources.entries) {
      final key = entry.key;
      final resource = entry.value;

      // Check if resource is leaked
      if (resource.allocation.isLeaked(_defaultLeakDetectionTimeout)) {
        leaksFound++;
        leakedResources.add(key);
        _logger.warning(
            'Resource leak detected: $key (type: ${resource.allocation.type}, '
            'age: ${resource.allocation.age.inSeconds}s)');
      }

      // Check weak reference
      if (_weakReferences.containsKey(key)) {
        final weakRef = _weakReferences[key]!;
        if (weakRef.target == null && !resource.isDisposed) {
          _logger.warning(
              'Resource $key was garbage collected without being disposed');
          _disposeResourceAsync(key);
        }
      }
    }

    if (leaksFound > 0) {
      _leaksDetected += leaksFound;
      _publishLeakDetectionEvent(leakedResources);

      // Update health status
      HealthMonitor.instance.updateComponentHealth(
        'resource_cleanup',
        MCPHealthStatus.degraded,
        '$leaksFound resource leaks detected',
      );
    }
  }

  /// Publish resource event
  void _publishResourceEvent(
      String action, String resourceKey, String resourceType) {
    _eventSystem.publishTopic('resource.$action', {
      'key': resourceKey,
      'type': resourceType,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Publish leak detection event
  void _publishLeakDetectionEvent(List<String> leakedResources) {
    _eventSystem.publishTopic('resource.leak_detected', {
      'count': leakedResources.length,
      'resources': leakedResources,
      'totalLeaksDetected': _leaksDetected,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get resource statistics
  Map<String, dynamic> getStatistics() {
    final activeResources = _resources.values
        .where((r) => r.allocation.state == ResourceState.active)
        .length;

    final failedResources = _resources.values
        .where((r) => r.allocation.state == ResourceState.failed)
        .length;

    return {
      'totalRegistered': _totalResourcesRegistered,
      'totalDisposed': _totalResourcesDisposed,
      'currentActive': activeResources,
      'failedDisposals': _failedDisposals,
      'leaksDetected': _leaksDetected,
      'failedResources': failedResources,
      'resourcesByType': _getResourcesByType(),
      'resourcesByPriority': _getResourcesByPriority(),
    };
  }

  /// Get resources grouped by type
  Map<String, int> _getResourcesByType() {
    final typeCount = <String, int>{};
    for (final resource in _resources.values) {
      typeCount[resource.allocation.type] =
          (typeCount[resource.allocation.type] ?? 0) + 1;
    }
    return typeCount;
  }

  /// Get resources grouped by priority
  Map<int, int> _getResourcesByPriority() {
    final priorityCount = <int, int>{};
    for (final entry in _priorityGroups.entries) {
      priorityCount[entry.key] = entry.value.length;
    }
    return priorityCount;
  }

  /// Get detailed resource information
  List<Map<String, dynamic>> getResourceDetails() {
    return _resources.values
        .map((resource) => {
              'key': resource.key,
              'type': resource.allocation.type,
              'state': resource.allocation.state.name,
              'priority': resource.priority,
              'tag': resource.tag,
              'age': resource.allocation.age.inSeconds,
              'memorySizeMB': resource.allocation.memorySizeMB,
              'dependencies': resource.dependencies,
              'description': resource.allocation.description,
            })
        .toList();
  }
}

/// Mixin for classes that manage resources
mixin ResourceCleanupMixin {
  final List<String> _managedResources = [];

  /// Register a resource to be cleaned up when this object is disposed
  @protected
  void registerManagedResource<T extends Object>({
    required String key,
    required T resource,
    required Future<void> Function(T) disposeFunction,
    required String type,
    String? description,
    int? estimatedMemoryMB,
  }) {
    _managedResources.add(key);

    EnhancedResourceCleanup.instance.registerResource(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      type: type,
      description: description,
      estimatedMemoryMB: estimatedMemoryMB,
      dependencies: _managedResources.length > 1
          ? [_managedResources[_managedResources.length - 2]]
          : null,
    );
  }

  /// Dispose all managed resources
  @protected
  Future<void> disposeManagedResources() async {
    for (final resourceKey in _managedResources.reversed) {
      try {
        await EnhancedResourceCleanup.instance.disposeResource(resourceKey);
      } catch (e) {
        // Log but continue disposing other resources
        Logger(runtimeType.toString())
            .severe('Failed to dispose managed resource: $resourceKey', e);
      }
    }
    _managedResources.clear();
  }
}

/// Resource guard for automatic resource disposal
class ResourceGuard<T extends Object> {
  final String key;
  final T resource;
  final Future<void> Function(T) disposeFunction;
  bool _disposed = false;

  ResourceGuard({
    required this.key,
    required this.resource,
    required this.disposeFunction,
    required String type,
    String? description,
  }) {
    EnhancedResourceCleanup.instance.registerResource(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      type: type,
      description: description,
    );
  }

  /// Use the resource within a callback
  Future<R> use<R>(Future<R> Function(T) callback) async {
    if (_disposed) {
      throw MCPException('Resource $key has already been disposed');
    }

    try {
      return await callback(resource);
    } finally {
      // Optionally auto-dispose after use
    }
  }

  /// Dispose the resource
  Future<void> dispose() async {
    if (_disposed) return;

    await EnhancedResourceCleanup.instance.disposeResource(key);
    _disposed = true;
  }
}
