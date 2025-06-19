/// Enhanced resource management with lifecycle tracking and dependency resolution
library;

import 'dart:async';
import 'dart:collection';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/event_models.dart';
import '../events/event_system.dart';
import '../metrics/typed_metrics.dart';
import '../utils/performance_monitor.dart';

/// Resource lifecycle states
enum ResourceLifecycle {
  registered,
  initializing,
  initialized,
  disposing,
  disposed,
  error,
}

/// Resource type categories
enum ResourceType {
  stream,
  subscription,
  timer,
  isolate,
  webSocket,
  httpClient,
  fileHandle,
  database,
  cache,
  plugin,
  service,
  custom,
}

/// Resource priority levels for disposal ordering
class ResourcePriority {
  static const int critical = 1000;
  static const int high = 900;
  static const int normal = 500;
  static const int low = 100;
  static const int cleanup = 50;
}

/// Enhanced resource registration information
class ResourceRegistration<T> {
  final String key;
  final T resource;
  final Future<void> Function(dynamic)? disposeFunction;
  final Future<void> Function(dynamic)? initializeFunction;
  final ResourceType type;
  final int priority;
  final List<String> dependencies;
  final List<String> tags;
  final ResourceLifecycle lifecycle;
  final DateTime registeredAt;
  final DateTime? initializedAt;
  final DateTime? disposedAt;
  final String? group;
  final Map<String, dynamic> metadata;
  final Duration? maxLifetime;
  final bool autoDispose;

  ResourceRegistration({
    required this.key,
    required this.resource,
    this.disposeFunction,
    this.initializeFunction,
    this.type = ResourceType.custom,
    this.priority = ResourcePriority.normal,
    this.dependencies = const [],
    this.tags = const [],
    this.lifecycle = ResourceLifecycle.registered,
    required this.registeredAt,
    this.initializedAt,
    this.disposedAt,
    this.group,
    this.metadata = const {},
    this.maxLifetime,
    this.autoDispose = true,
  });

  ResourceRegistration<T> copyWith({
    ResourceLifecycle? lifecycle,
    DateTime? initializedAt,
    DateTime? disposedAt,
  }) {
    return ResourceRegistration<T>(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      initializeFunction: initializeFunction,
      type: type,
      priority: priority,
      dependencies: dependencies,
      tags: tags,
      lifecycle: lifecycle ?? this.lifecycle,
      registeredAt: registeredAt,
      initializedAt: initializedAt ?? this.initializedAt,
      disposedAt: disposedAt ?? this.disposedAt,
      group: group,
      metadata: metadata,
      maxLifetime: maxLifetime,
      autoDispose: autoDispose,
    );
  }

  bool get isExpired {
    if (maxLifetime == null || initializedAt == null) return false;
    return DateTime.now().difference(initializedAt!).compareTo(maxLifetime!) >
        0;
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'type': type.name,
      'priority': priority,
      'dependencies': dependencies,
      'tags': tags,
      'lifecycle': lifecycle.name,
      'registeredAt': registeredAt.toIso8601String(),
      'initializedAt': initializedAt?.toIso8601String(),
      'disposedAt': disposedAt?.toIso8601String(),
      'group': group,
      'metadata': metadata,
      'maxLifetime': maxLifetime?.inMilliseconds,
      'autoDispose': autoDispose,
      'isExpired': isExpired,
    };
  }
}

/// Resource dependency graph for optimized disposal order
class ResourceDependencyGraph {
  final Map<String, Set<String>> _dependencies = {};
  final Map<String, Set<String>> _dependents = {};

  void addDependency(String resource, String dependency) {
    _dependencies.putIfAbsent(resource, () => {}).add(dependency);
    _dependents.putIfAbsent(dependency, () => {}).add(resource);
  }

  void removeDependency(String resource, String dependency) {
    _dependencies[resource]?.remove(dependency);
    _dependents[dependency]?.remove(resource);

    if (_dependencies[resource]?.isEmpty ?? false) {
      _dependencies.remove(resource);
    }
    if (_dependents[dependency]?.isEmpty ?? false) {
      _dependents.remove(dependency);
    }
  }

  void removeResource(String resource) {
    // Remove all dependencies
    final deps = _dependencies[resource];
    if (deps != null) {
      for (final dep in deps) {
        _dependents[dep]?.remove(resource);
        if (_dependents[dep]?.isEmpty ?? false) {
          _dependents.remove(dep);
        }
      }
      _dependencies.remove(resource);
    }

    // Remove all dependents
    final dependents = _dependents[resource];
    if (dependents != null) {
      for (final dependent in dependents) {
        _dependencies[dependent]?.remove(resource);
        if (_dependencies[dependent]?.isEmpty ?? false) {
          _dependencies.remove(dependent);
        }
      }
      _dependents.remove(resource);
    }
  }

  List<String> getDisposalOrder(Iterable<String> resources) {
    final visited = <String>{};
    final visiting = <String>{};
    final order = <String>[];
    final cycles = <String>[];

    void visit(String resource) {
      if (visiting.contains(resource)) {
        cycles.add(resource);
        return;
      }

      if (visited.contains(resource)) {
        return;
      }

      visiting.add(resource);

      // Visit dependents first (they should be disposed before their dependencies)
      final dependents = _dependents[resource] ?? <String>{};
      for (final dependent in dependents) {
        if (resources.contains(dependent)) {
          visit(dependent);
        }
      }

      visiting.remove(resource);
      visited.add(resource);
      order.add(resource);
    }

    for (final resource in resources) {
      if (!visited.contains(resource)) {
        visit(resource);
      }
    }

    return order;
  }

  bool hasCircularDependency(String resource, String dependency) {
    if (resource == dependency) return true;

    final visited = <String>{};
    final queue = Queue<String>();
    queue.add(dependency);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current == resource) return true;

      if (visited.contains(current)) continue;
      visited.add(current);

      final deps = _dependencies[current] ?? <String>{};
      queue.addAll(deps);
    }

    return false;
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalNodes': _dependencies.length,
      'totalEdges':
          _dependencies.values.fold(0, (sum, deps) => sum + deps.length),
      'maxDependencies': _dependencies.values.isEmpty
          ? 0
          : _dependencies.values
              .map((d) => d.length)
              .reduce((a, b) => a > b ? a : b),
      'maxDependents': _dependents.values.isEmpty
          ? 0
          : _dependents.values
              .map((d) => d.length)
              .reduce((a, b) => a > b ? a : b),
    };
  }
}

/// Resource lifecycle event
class ResourceLifecycleEvent extends McpEvent {
  final String resourceKey;
  final ResourceLifecycle oldState;
  final ResourceLifecycle newState;
  final ResourceType resourceType;
  final String? error;

  ResourceLifecycleEvent({
    required this.resourceKey,
    required this.oldState,
    required this.newState,
    required this.resourceType,
    this.error,
    super.timestamp,
    Map<String, dynamic>? metadata,
  }) : super(metadata: metadata ?? {});

  @override
  String get eventType => 'resource.lifecycle';

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'resourceKey': resourceKey,
      'oldState': oldState.name,
      'newState': newState.name,
      'resourceType': resourceType.name,
      'error': error,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Enhanced resource manager with comprehensive lifecycle management
class EnhancedResourceManager {
  final Logger _logger = Logger('flutter_mcp.enhanced_resource_manager');

  // Resource registrations
  final Map<String, ResourceRegistration> _resources = {};

  // Dependency graph
  final ResourceDependencyGraph _dependencyGraph = ResourceDependencyGraph();

  // Resource groups
  final Map<String, Set<String>> _groups = {};

  // Resource tags
  final Map<String, Set<String>> _tags = {};

  // Lifecycle tracking
  final Set<String> _initializing = {};
  final Set<String> _disposing = {};

  // Event system
  final EventSystem _eventSystem = EventSystem.instance;

  // Performance monitor
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor.instance;

  // Statistics
  int _totalRegistered = 0;
  int _totalInitialized = 0;
  int _totalDisposed = 0;
  int _failedInitializations = 0;
  int _failedDisposals = 0;

  // Auto-cleanup timer
  Timer? _cleanupTimer;

  // Singleton instance
  static final EnhancedResourceManager _instance =
      EnhancedResourceManager._internal();

  /// Get singleton instance
  static EnhancedResourceManager get instance => _instance;

  EnhancedResourceManager._internal() {
    _startAutoCleanup();
  }

  /// Register a resource with comprehensive configuration
  void register<T>({
    required String key,
    required T resource,
    Future<void> Function(dynamic)? disposeFunction,
    Future<void> Function(dynamic)? initializeFunction,
    ResourceType type = ResourceType.custom,
    int priority = ResourcePriority.normal,
    List<String> dependencies = const [],
    List<String> tags = const [],
    String? group,
    Map<String, dynamic> metadata = const {},
    Duration? maxLifetime,
    bool autoDispose = true,
    bool autoInitialize = false,
  }) {
    _logger.fine('Registering resource: $key');

    // Dispose existing resource with same key
    if (_resources.containsKey(key)) {
      _logger.fine('Resource $key already exists, disposing previous');
      dispose(key).catchError(
          (e) => _logger.severe('Error disposing previous resource: $key', e));
    }

    // Validate dependencies
    for (final dep in dependencies) {
      if (_dependencyGraph.hasCircularDependency(key, dep)) {
        throw MCPException('Circular dependency detected: $key -> $dep');
      }
    }

    final registration = ResourceRegistration<T>(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
      initializeFunction: initializeFunction,
      type: type,
      priority: priority,
      dependencies: dependencies,
      tags: tags,
      group: group,
      metadata: metadata,
      maxLifetime: maxLifetime,
      autoDispose: autoDispose,
      registeredAt: DateTime.now(),
    );

    _resources[key] = registration;
    _totalRegistered++;

    // Update dependency graph
    for (final dep in dependencies) {
      _dependencyGraph.addDependency(key, dep);
    }

    // Update group mapping
    if (group != null) {
      _groups.putIfAbsent(group, () => {}).add(key);
    }

    // Update tag mappings
    for (final tag in tags) {
      _tags.putIfAbsent(tag, () => {}).add(key);
    }

    // Publish lifecycle event
    _publishLifecycleEvent(
      key,
      ResourceLifecycle.registered,
      ResourceLifecycle.registered,
      type,
    );

    // Auto-initialize if requested
    if (autoInitialize) {
      initialize(key).catchError(
          (e) => _logger.severe('Auto-initialization failed for $key', e));
    }
  }

  /// Register a stream subscription
  void registerStream<T>(
    String key,
    Stream<T> stream,
    void Function(T) onData, {
    Function? onError,
    void Function()? onDone,
    bool cancelOnError = false,
    int priority = ResourcePriority.normal,
    List<String> dependencies = const [],
    List<String> tags = const [],
    String? group,
  }) {
    // Create subscription first
    final subscription = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );

    // Register with the actual subscription
    register<StreamSubscription<T>>(
      key: key,
      resource: subscription,
      disposeFunction: (sub) => sub.cancel(),
      type: ResourceType.subscription,
      priority: priority,
      dependencies: dependencies,
      tags: tags,
      group: group,
      autoInitialize: false, // Already created
    );
  }

  /// Register a timer
  void registerTimer(
    String key,
    Duration duration,
    void Function() callback, {
    bool periodic = false,
    int priority = ResourcePriority.normal,
    List<String> dependencies = const [],
    List<String> tags = const [],
    String? group,
  }) {
    // Create timer first
    final Timer timer;
    if (periodic) {
      timer = Timer.periodic(duration, (_) => callback());
    } else {
      timer = Timer(duration, callback);
    }

    // Register with the actual timer
    register<Timer>(
      key: key,
      resource: timer,
      disposeFunction: (t) async => t.cancel(),
      type: ResourceType.timer,
      priority: priority,
      dependencies: dependencies,
      tags: tags,
      group: group,
      autoInitialize: false, // Already created
    );
  }

  /// Initialize a resource and its dependencies
  Future<void> initialize(String key) async {
    final registration = _resources[key];
    if (registration == null) {
      throw MCPException('Resource not found: $key');
    }

    if (registration.lifecycle == ResourceLifecycle.initialized) {
      return; // Already initialized
    }

    if (_initializing.contains(key)) {
      throw MCPException('Circular initialization detected: $key');
    }

    _initializing.add(key);

    try {
      _logger.fine('Initializing resource: $key');

      // Update lifecycle
      _resources[key] =
          registration.copyWith(lifecycle: ResourceLifecycle.initializing);
      _publishLifecycleEvent(
        key,
        ResourceLifecycle.registered,
        ResourceLifecycle.initializing,
        registration.type,
      );

      // Initialize dependencies first
      await _initializeDependencies(registration);

      // Initialize the resource
      final stopwatch = Stopwatch()..start();

      if (registration.initializeFunction != null) {
        await registration.initializeFunction!(registration.resource);
      }

      stopwatch.stop();

      // Update lifecycle
      _resources[key] = registration.copyWith(
        lifecycle: ResourceLifecycle.initialized,
        initializedAt: DateTime.now(),
      );

      _totalInitialized++;

      _publishLifecycleEvent(
        key,
        ResourceLifecycle.initializing,
        ResourceLifecycle.initialized,
        registration.type,
      );

      // Record performance metric
      _recordInitializationMetric(
          key, registration.type, stopwatch.elapsed, true);

      _logger.fine('Resource initialized successfully: $key');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize resource: $key', e, stackTrace);

      _failedInitializations++;

      // Update lifecycle to error
      _resources[key] =
          registration.copyWith(lifecycle: ResourceLifecycle.error);
      _publishLifecycleEvent(
        key,
        ResourceLifecycle.initializing,
        ResourceLifecycle.error,
        registration.type,
        error: e.toString(),
      );

      rethrow;
    } finally {
      _initializing.remove(key);
    }
  }

  /// Initialize dependencies
  Future<void> _initializeDependencies(
      ResourceRegistration registration) async {
    for (final dep in registration.dependencies) {
      final depRegistration = _resources[dep];
      if (depRegistration != null &&
          depRegistration.lifecycle != ResourceLifecycle.initialized) {
        await initialize(dep);
      }
    }
  }

  /// Dispose a resource and handle dependents
  Future<void> dispose(String key) async {
    final registration = _resources[key];
    if (registration == null) {
      _logger.warning('Resource not found for disposal: $key');
      return;
    }

    if (registration.lifecycle == ResourceLifecycle.disposed) {
      return; // Already disposed
    }

    if (_disposing.contains(key)) {
      _logger.warning('Resource already being disposed: $key');
      return;
    }

    _disposing.add(key);

    try {
      _logger.fine('Disposing resource: $key');

      // Update lifecycle
      _resources[key] =
          registration.copyWith(lifecycle: ResourceLifecycle.disposing);
      _publishLifecycleEvent(
        key,
        registration.lifecycle,
        ResourceLifecycle.disposing,
        registration.type,
      );

      // Dispose dependents first
      await _disposeDependents(key);

      // Dispose the resource
      final stopwatch = Stopwatch()..start();

      if (registration.disposeFunction != null) {
        await registration.disposeFunction!(registration.resource);
      }

      stopwatch.stop();

      // Update lifecycle
      _resources[key] = registration.copyWith(
        lifecycle: ResourceLifecycle.disposed,
        disposedAt: DateTime.now(),
      );

      _totalDisposed++;

      _publishLifecycleEvent(
        key,
        ResourceLifecycle.disposing,
        ResourceLifecycle.disposed,
        registration.type,
      );

      // Record performance metric
      _recordDisposalMetric(key, registration.type, stopwatch.elapsed, true);

      // Clean up mappings
      _cleanupMappings(key);

      // Remove the resource from the main registry
      _resources.remove(key);

      _logger.fine('Resource disposed successfully: $key');
    } catch (e, stackTrace) {
      _logger.severe('Failed to dispose resource: $key', e, stackTrace);

      _failedDisposals++;

      // Update lifecycle to error
      _resources[key] =
          registration.copyWith(lifecycle: ResourceLifecycle.error);
      _publishLifecycleEvent(
        key,
        ResourceLifecycle.disposing,
        ResourceLifecycle.error,
        registration.type,
        error: e.toString(),
      );

      rethrow;
    } finally {
      _disposing.remove(key);
    }
  }

  /// Dispose dependents of a resource
  Future<void> _disposeDependents(String key) async {
    // Find all resources that depend on this one
    final dependents = <String>[];
    for (final entry in _resources.entries) {
      if (entry.value.dependencies.contains(key)) {
        dependents.add(entry.key);
      }
    }

    // Dispose dependents first
    for (final dependent in dependents) {
      if (_resources[dependent]?.lifecycle != ResourceLifecycle.disposed) {
        await dispose(dependent);
      }
    }
  }

  /// Dispose all resources in optimal order
  Future<void> disposeAll() async {
    _logger.info('Disposing all resources');

    final keys = _resources.keys
        .where(
            (key) => _resources[key]?.lifecycle != ResourceLifecycle.disposed)
        .toList();

    if (keys.isEmpty) {
      return;
    }

    // Get optimal disposal order
    final order = _dependencyGraph.getDisposalOrder(keys);

    // Group by priority
    final priorityGroups = <int, List<String>>{};
    for (final key in order) {
      final priority = _resources[key]?.priority ?? ResourcePriority.normal;
      priorityGroups.putIfAbsent(priority, () => []).add(key);
    }

    // Sort priorities (higher priority disposed first)
    final sortedPriorities = priorityGroups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final errors = <String, dynamic>{};

    for (final priority in sortedPriorities) {
      final keysInPriority = priorityGroups[priority]!;

      // Dispose resources in this priority group
      for (final key in keysInPriority) {
        try {
          await dispose(key);
        } catch (e) {
          errors[key] = e;
        }
      }
    }

    // Remove disposed resources
    _resources
        .removeWhere((key, reg) => reg.lifecycle == ResourceLifecycle.disposed);

    if (errors.isNotEmpty) {
      throw MCPException('Errors occurred during resource disposal: $errors');
    }

    _logger.info('All resources disposed successfully');
  }

  /// Clean up mappings for a disposed resource
  void _cleanupMappings(String key) {
    final registration = _resources[key];
    if (registration == null) return;

    // Remove from dependency graph
    _dependencyGraph.removeResource(key);

    // Remove from group
    if (registration.group != null) {
      _groups[registration.group]?.remove(key);
      if (_groups[registration.group]?.isEmpty ?? false) {
        _groups.remove(registration.group);
      }
    }

    // Remove from tags
    for (final tag in registration.tags) {
      _tags[tag]?.remove(key);
      if (_tags[tag]?.isEmpty ?? false) {
        _tags.remove(tag);
      }
    }
  }

  /// Get a resource
  T? get<T>(String key) {
    final registration = _resources[key];
    if (registration?.resource is T) {
      return registration!.resource as T;
    }
    return null;
  }

  /// Check if resource exists
  bool has(String key) => _resources.containsKey(key);

  /// Get resource registration
  ResourceRegistration? getRegistration(String key) => _resources[key];

  /// Get all resources by type
  List<String> getByType(ResourceType type) {
    return _resources.entries
        .where((entry) => entry.value.type == type)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get all resources by group
  List<String> getByGroup(String group) {
    return _groups[group]?.toList() ?? [];
  }

  /// Get all resources by tag
  List<String> getByTag(String tag) {
    return _tags[tag]?.toList() ?? [];
  }

  /// Dispose resources by group
  Future<void> disposeGroup(String group) async {
    final keys = getByGroup(group);
    final errors = <String, dynamic>{};

    for (final key in keys) {
      try {
        await dispose(key);
      } catch (e) {
        errors[key] = e;
      }
    }

    if (errors.isNotEmpty) {
      throw MCPException('Errors disposing group $group: $errors');
    }
  }

  /// Dispose resources by tag
  Future<void> disposeTag(String tag) async {
    final keys = getByTag(tag);
    final errors = <String, dynamic>{};

    for (final key in keys) {
      try {
        await dispose(key);
      } catch (e) {
        errors[key] = e;
      }
    }

    if (errors.isNotEmpty) {
      throw MCPException('Errors disposing tag $tag: $errors');
    }
  }

  /// Start automatic cleanup of expired resources
  void _startAutoCleanup() {
    _cleanupTimer =
        Timer.periodic(Duration(minutes: 5), (_) => _performAutoCleanup());
  }

  /// Perform automatic cleanup
  Future<void> _performAutoCleanup() async {
    final expiredKeys = <String>[];

    for (final entry in _resources.entries) {
      final registration = entry.value;
      if (registration.autoDispose && registration.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    if (expiredKeys.isNotEmpty) {
      _logger.fine('Auto-disposing ${expiredKeys.length} expired resources');

      for (final key in expiredKeys) {
        try {
          await dispose(key);
        } catch (e) {
          _logger.warning('Failed to auto-dispose expired resource: $key', e);
        }
      }
    }
  }

  /// Get comprehensive statistics
  Map<String, dynamic> getStatistics() {
    final lifecycleStats = <String, int>{};
    final typeStats = <String, int>{};
    final priorityStats = <String, int>{};

    for (final registration in _resources.values) {
      final lifecycle = registration.lifecycle.name;
      lifecycleStats[lifecycle] = (lifecycleStats[lifecycle] ?? 0) + 1;

      final type = registration.type.name;
      typeStats[type] = (typeStats[type] ?? 0) + 1;

      final priority = registration.priority.toString();
      priorityStats[priority] = (priorityStats[priority] ?? 0) + 1;
    }

    return {
      'totalRegistered': _totalRegistered,
      'totalInitialized': _totalInitialized,
      'totalDisposed': _totalDisposed,
      'failedInitializations': _failedInitializations,
      'failedDisposals': _failedDisposals,
      'currentCount': _resources.length,
      'lifecycleStats': lifecycleStats,
      'typeStats': typeStats,
      'priorityStats': priorityStats,
      'groupCount': _groups.length,
      'tagCount': _tags.length,
      'dependencyGraph': _dependencyGraph.getStatistics(),
    };
  }

  /// Publish lifecycle event
  void _publishLifecycleEvent(
    String key,
    ResourceLifecycle oldState,
    ResourceLifecycle newState,
    ResourceType type, {
    String? error,
  }) {
    final event = ResourceLifecycleEvent(
      resourceKey: key,
      oldState: oldState,
      newState: newState,
      resourceType: type,
      error: error,
    );

    _eventSystem.publishTyped<ResourceLifecycleEvent>(event);
  }

  /// Record initialization performance metric
  void _recordInitializationMetric(
      String key, ResourceType type, Duration duration, bool success) {
    final metric = TimerMetric(
      name: 'resource.initialization',
      duration: duration,
      operation: 'initialize_${type.name}',
      success: success,
    );

    _performanceMonitor.recordTypedMetric(metric);
  }

  /// Record disposal performance metric
  void _recordDisposalMetric(
      String key, ResourceType type, Duration duration, bool success) {
    final metric = TimerMetric(
      name: 'resource.disposal',
      duration: duration,
      operation: 'dispose_${type.name}',
      success: success,
    );

    _performanceMonitor.recordTypedMetric(metric);
  }

  /// Dispose and clean up the manager itself
  Future<void> shutdown() async {
    _cleanupTimer?.cancel();
    await disposeAll();
    _resources.clear();
    _groups.clear();
    _tags.clear();

    // Reset statistics
    _totalRegistered = 0;
    _totalInitialized = 0;
    _totalDisposed = 0;
    _failedInitializations = 0;
    _failedDisposals = 0;
  }
}
