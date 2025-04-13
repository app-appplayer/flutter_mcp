import 'dart:async';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Resource manager to track and properly dispose of resources
class ResourceManager {
  final MCPLogger _logger = MCPLogger('mcp.resource_manager');

  /// Resources to dispose
  final Map<String, _DisposableResource> _resources = {};

  /// Resource dependency graph
  final Map<String, Set<String>> _dependencies = {};
  final Map<String, Set<String>> _dependents = {};

  /// Resource cleanup priority groups
  final Map<int, Set<String>> _priorityGroups = {};

  /// Default cleanup priority
  static const int HIGH_PRIORITY = 300;
  static const int MEDIUM_PRIORITY = 200;
  static const int DEFAULT_PRIORITY = 100;
  static const int LOW_PRIORITY = 50;

  /// Resource cleanup statistics
  int _totalResourcesRegistered = 0;
  int _totalResourcesDisposed = 0;
  int _failedDisposals = 0;

  /// Register a resource for cleanup
  ///
  /// [key] is a unique identifier for the resource
  /// [resource] is the resource object
  /// [disposeFunction] is the function to call to dispose the resource
  /// [priority] determines cleanup order (lower values are cleaned up later)
  /// [dependencies] is a list of keys for resources this resource depends on
  void register<T>(
      String key,
      T resource,
      Future<void> Function(T) disposeFunction, {
        int priority = DEFAULT_PRIORITY,
        List<String>? dependencies,
        String? tag,
      }) {
    _logger.debug('Registering resource: $key');

    // Dispose any existing resource with the same key
    if (_resources.containsKey(key)) {
      _logger.debug('Resource with key $key already exists, disposing previous resource');
      _resources[key]!.dispose().catchError((error) {
        _logger.error('Error disposing previous resource: $key', error);
      });

      // Remove from dependency/dependent mappings
      _removeDependencies(key);
    }

    _resources[key] = _DisposableResource<T>(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      priority: priority,
      tag: tag,
    );

    // Add to priority group
    _priorityGroups.putIfAbsent(priority, () => {}).add(key);

    // Register dependencies
    if (dependencies != null && dependencies.isNotEmpty) {
      for (final dep in dependencies) {
        addDependency(key, dep);
      }
    }

    _totalResourcesRegistered++;
  }

  /// Register a stream subscription for cleanup
  void registerSubscription(
      String key,
      StreamSubscription subscription, {
        int priority = DEFAULT_PRIORITY,
        List<String>? dependencies,
        String? tag,
      }) {
    register<StreamSubscription>(
      key,
      subscription,
          (sub) => sub.cancel(),
      priority: priority,
      dependencies: dependencies,
      tag: tag,
    );
  }

  /// Register a callback to be executed during cleanup
  void registerCallback(
      String key,
      Future<void> Function() callback, {
        int priority = DEFAULT_PRIORITY,
        List<String>? dependencies,
        String? tag,
      }) {
    register<Future<void> Function()>(
      key,
      callback,
          (cb) => cb(),
      priority: priority,
      dependencies: dependencies,
      tag: tag,
    );
  }

  /// Get a registered resource
  T? get<T>(String key) {
    if (!_resources.containsKey(key)) {
      return null;
    }

    final resource = _resources[key];
    if (resource != null && resource.resource is T) {
      return resource.resource as T;
    }

    return null;
  }

  /// Check if a resource exists
  bool hasResource(String key) {
    return _resources.containsKey(key);
  }

  /// Add a dependency between resources
  void addDependency(String resource, String dependsOn) {
    if (!_resources.containsKey(resource)) {
      _logger.warning('Cannot add dependency: Resource $resource not found');
      return;
    }

    if (!_resources.containsKey(dependsOn)) {
      _logger.warning('Cannot add dependency: Dependency $dependsOn not found');
      return;
    }

    // Check for circular dependencies
    if (_wouldCreateCircularDependency(resource, dependsOn)) {
      _logger.error('Cannot add dependency: Would create circular dependency between $resource and $dependsOn');
      return;
    }

    // Add to dependencies map
    _dependencies.putIfAbsent(resource, () => {}).add(dependsOn);

    // Add to dependents map
    _dependents.putIfAbsent(dependsOn, () => {}).add(resource);

    _logger.debug('Added dependency: $resource depends on $dependsOn');
  }

  /// Remove a dependency between resources
  void removeDependency(String resource, String dependsOn) {
    // Remove from dependencies map
    if (_dependencies.containsKey(resource)) {
      _dependencies[resource]!.remove(dependsOn);
      if (_dependencies[resource]!.isEmpty) {
        _dependencies.remove(resource);
      }
    }

    // Remove from dependents map
    if (_dependents.containsKey(dependsOn)) {
      _dependents[dependsOn]!.remove(resource);
      if (_dependents[dependsOn]!.isEmpty) {
        _dependents.remove(dependsOn);
      }
    }
  }

  /// Remove all dependencies for a resource
  void _removeDependencies(String key) {
    // Remove as a dependency
    if (_dependencies.containsKey(key)) {
      final dependencies = List<String>.from(_dependencies[key]!);
      for (final dep in dependencies) {
        if (_dependents.containsKey(dep)) {
          _dependents[dep]!.remove(key);
          if (_dependents[dep]!.isEmpty) {
            _dependents.remove(dep);
          }
        }
      }
      _dependencies.remove(key);
    }

    // Remove as a dependent
    if (_dependents.containsKey(key)) {
      final dependents = List<String>.from(_dependents[key]!);
      for (final dep in dependents) {
        if (_dependencies.containsKey(dep)) {
          _dependencies[dep]!.remove(key);
          if (_dependencies[dep]!.isEmpty) {
            _dependencies.remove(dep);
          }
        }
      }
      _dependents.remove(key);
    }

    // Remove from priority groups
    for (final group in _priorityGroups.values) {
      group.remove(key);
    }

    // Clean up empty priority groups
    _priorityGroups.removeWhere((priority, resources) => resources.isEmpty);
  }

  /// Check if adding a dependency would create a circular dependency
  bool _wouldCreateCircularDependency(String resource, String dependsOn) {
    // If dependsOn depends on resource, this would create a cycle
    return _isDependentOn(dependsOn, resource);
  }

  /// Check if resource1 is dependent on resource2 (directly or indirectly)
  bool _isDependentOn(String resource1, String resource2) {
    // Direct dependency check
    if (_dependencies.containsKey(resource1) &&
        _dependencies[resource1]!.contains(resource2)) {
      return true;
    }

    // Recursive check through dependencies
    if (_dependencies.containsKey(resource1)) {
      for (final dep in _dependencies[resource1]!) {
        if (_isDependentOn(dep, resource2)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Dispose a specific resource with dependency handling
  Future<void> dispose(String key) async {
    if (!_resources.containsKey(key)) {
      _logger.warning('No resource found with key: $key');
      return;
    }

    _logger.debug('Disposing resource: $key');

    try {
      // Check dependents first
      if (_dependents.containsKey(key) && _dependents[key]!.isNotEmpty) {
        _logger.debug('Resource $key has dependents: ${_dependents[key]!.join(", ")}');

        // Dispose dependents first
        for (final dependent in List<String>.from(_dependents[key]!)) {
          await dispose(dependent);
        }
      }

      // Now dispose the resource itself
      await _resources[key]!.dispose();

      // Clean up dependency tracking
      _removeDependencies(key);

      // Remove the resource
      _resources.remove(key);

      _totalResourcesDisposed++;
    } catch (e, stackTrace) {
      _logger.error('Error disposing resource: $key', e, stackTrace);
      _failedDisposals++;
      throw MCPOperationFailedException(
        'Failed to dispose resource: $key',
        e,
        stackTrace,
      );
    }
  }

  /// Dispose all resources in prioritized order
  Future<void> disposeAll() async {
    _logger.debug('Disposing all resources');

    final errors = <String, dynamic>{};

    try {
      // Sort priority groups (higher numbers disposed first)
      final priorities = _priorityGroups.keys.toList()..sort((a, b) => b.compareTo(a));

      // Dispose by priority groups
      for (final priority in priorities) {
        if (!_priorityGroups.containsKey(priority)) continue;

        // Get a copy of the keys in this priority group
        final groupKeys = List<String>.from(_priorityGroups[priority]!);

        // Sort by dependencies within the group
        groupKeys.sort((a, b) {
          // If a depends on b, b should be disposed later (comes after)
          if (_isDependentOn(a, b)) return -1;
          // If b depends on a, a should be disposed later (comes after)
          if (_isDependentOn(b, a)) return 1;
          // Otherwise keep original order
          return 0;
        });

        // Dispose each resource in the group
        for (final key in groupKeys) {
          if (!_resources.containsKey(key)) continue;

          try {
            await _resources[key]!.dispose();
            _totalResourcesDisposed++;
          } catch (e, stackTrace) {
            _logger.error('Error disposing resource: $key', e, stackTrace);
            errors[key] = e;
            _failedDisposals++;
          } finally {
            _resources.remove(key);

            // Clean up dependency tracking for this resource
            _removeDependencies(key);
          }
        }
      }

      // Clear all maps
      _resources.clear();
      _dependencies.clear();
      _dependents.clear();
      _priorityGroups.clear();
    } catch (e, stackTrace) {
      _logger.error('Unexpected error during resource cleanup', e, stackTrace);
      errors['_general'] = e;
    }

    if (errors.isNotEmpty) {
      throw MCPException('Errors occurred while disposing resources: $errors');
    }
  }

  /// Get all resource keys
  List<String> get allKeys => _resources.keys.toList();

  /// Resource count
  int get count => _resources.length;

  /// Group resources by tag
  ///
  /// Register resources with the same tag to group them
  void registerWithTag<T>(
      String key,
      T resource,
      Future<void> Function(T) disposeFunction,
      String tag, {
        int priority = DEFAULT_PRIORITY,
        List<String>? dependencies,
      }) {
    register(
      key,
      resource,
      disposeFunction,
      priority: priority,
      dependencies: dependencies,
      tag: tag,
    );
  }

  /// Dispose all resources with a specific tag
  Future<void> disposeByTag(String tag) async {
    _logger.debug('Disposing resources with tag: $tag');

    final keysToDispose = _resources.entries
        .where((entry) => entry.value.tag == tag)
        .map((entry) => entry.key)
        .toList();

    final errors = <String, dynamic>{};

    for (final key in keysToDispose) {
      try {
        await dispose(key);
      } catch (e, stackTrace) {
        _logger.error('Error disposing resource: $key', e, stackTrace);
        errors[key] = e;
        _failedDisposals++;
      }
    }

    if (errors.isNotEmpty) {
      throw MCPException('Errors occurred while disposing resources with tag $tag: $errors');
    }
  }

  /// Get all resource keys with a specific tag
  List<String> getKeysByTag(String tag) {
    return _resources.entries
        .where((entry) => entry.value.tag == tag)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get resource statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalRegistered': _totalResourcesRegistered,
      'totalDisposed': _totalResourcesDisposed,
      'currentCount': _resources.length,
      'failedDisposals': _failedDisposals,
      'priorityGroups': _priorityGroups.map((k, v) => MapEntry(k.toString(), v.length)),
      'resourcesByType': _getResourceCountByType(),
    };
  }

  /// Get resource count by type
  Map<String, int> _getResourceCountByType() {
    final countByType = <String, int>{};

    for (final resource in _resources.values) {
      final type = resource.resource.runtimeType.toString();
      countByType[type] = (countByType[type] ?? 0) + 1;
    }

    return countByType;
  }

  /// Clear all resources without disposing them
  void clear() {
    _logger.debug('Clearing all resources without disposing');
    _resources.clear();
    _dependencies.clear();
    _dependents.clear();
    _priorityGroups.clear();
  }
}

/// Internal class to represent a disposable resource
class _DisposableResource<T> {
  final String key;
  final T resource;
  final Future<void> Function(T) disposeFunction;
  String? tag;
  final int priority;
  bool _disposed = false;

  _DisposableResource({
    required this.key,
    required this.resource,
    required this.disposeFunction,
    this.tag,
    required this.priority,
  });

  Future<void> dispose() async {
    if (_disposed) return;

    await disposeFunction(resource);
    _disposed = true;
  }
}