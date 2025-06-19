/// Enhanced dependency injection with lifecycle management and dependency resolution
library;

import 'dart:async';
import 'package:meta/meta.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/event_models.dart';
import '../events/event_system.dart';

/// Service lifecycle states
enum ServiceLifecycle {
  uninitialized,
  initializing,
  initialized,
  disposing,
  disposed,
  error,
}

/// Service registration information
class ServiceRegistration<T> {
  final Type type;
  final String? name;
  final T Function()? factory;
  final T? instance;
  final bool isSingleton;
  final List<Type> dependencies;
  final ServiceLifecycle lifecycle;
  final Future<void> Function(dynamic)? onInitialize;
  final Future<void> Function(dynamic)? onDispose;
  final DateTime registeredAt;
  final int priority;

  ServiceRegistration({
    required this.type,
    this.name,
    this.factory,
    this.instance,
    required this.isSingleton,
    this.dependencies = const [],
    this.lifecycle = ServiceLifecycle.uninitialized,
    this.onInitialize,
    this.onDispose,
    required this.registeredAt,
    this.priority = 0,
  });

  ServiceRegistration<T> copyWith({
    ServiceLifecycle? lifecycle,
    T? instance,
  }) {
    return ServiceRegistration<T>(
      type: type,
      name: name,
      factory: factory,
      instance: instance ?? this.instance,
      isSingleton: isSingleton,
      dependencies: dependencies,
      lifecycle: lifecycle ?? this.lifecycle,
      onInitialize: onInitialize,
      onDispose: onDispose,
      registeredAt: registeredAt,
      priority: priority,
    );
  }

  String get key => name != null ? '${type.toString()}:$name' : type.toString();

  Map<String, dynamic> toMap() {
    return {
      'type': type.toString(),
      'name': name,
      'isSingleton': isSingleton,
      'dependencies': dependencies.map((d) => d.toString()).toList(),
      'lifecycle': lifecycle.name,
      'registeredAt': registeredAt.toIso8601String(),
      'priority': priority,
      'hasInstance': instance != null,
      'hasFactory': factory != null,
    };
  }
}

/// Service dependency graph node
class DependencyNode {
  final String serviceKey;
  final Set<String> dependencies = {};
  final Set<String> dependents = {};
  int level = 0;
  bool visited = false;
  bool inStack = false;

  DependencyNode(this.serviceKey);

  void addDependency(String dependency) {
    dependencies.add(dependency);
  }

  void addDependent(String dependent) {
    dependents.add(dependent);
  }

  @override
  String toString() =>
      'DependencyNode($serviceKey, level: $level, deps: ${dependencies.length})';
}

/// Dependency resolution result
class DependencyResolutionResult {
  final List<String> initializationOrder;
  final List<String> disposalOrder;
  final List<String> circularDependencies;
  final Map<String, int> dependencyLevels;

  DependencyResolutionResult({
    required this.initializationOrder,
    required this.disposalOrder,
    required this.circularDependencies,
    required this.dependencyLevels,
  });

  bool get hasCircularDependencies => circularDependencies.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'initializationOrder': initializationOrder,
      'disposalOrder': disposalOrder,
      'circularDependencies': circularDependencies,
      'dependencyLevels': dependencyLevels,
      'hasCircularDependencies': hasCircularDependencies,
    };
  }
}

/// Service lifecycle event
class ServiceLifecycleEvent extends McpEvent {
  final String serviceKey;
  final ServiceLifecycle oldState;
  final ServiceLifecycle newState;
  final String? error;

  ServiceLifecycleEvent({
    required this.serviceKey,
    required this.oldState,
    required this.newState,
    this.error,
    super.timestamp,
    Map<String, dynamic>? metadata,
  }) : super(metadata: metadata ?? {});

  @override
  String get eventType => 'service.lifecycle';

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'serviceKey': serviceKey,
      'oldState': oldState.name,
      'newState': newState.name,
      'error': error,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Enhanced dependency injection container
class EnhancedDIContainer {
  final Logger _logger = Logger('flutter_mcp.enhanced_di');

  // Service registrations
  final Map<String, ServiceRegistration> _registrations = {};

  // Singleton instances
  final Map<String, dynamic> _instances = {};

  // Dependency graph
  final Map<String, DependencyNode> _dependencyGraph = {};

  // Initialization tracking
  final Set<String> _initializing = {};
  final Set<String> _initialized = {};
  final Set<String> _disposing = {};

  // Resolution cache
  DependencyResolutionResult? _cachedResolution;

  // Event system for lifecycle events
  final EventSystem _eventSystem = EventSystem.instance;

  // Singleton instance
  static final EnhancedDIContainer _instance = EnhancedDIContainer._internal();

  /// Get singleton instance
  static EnhancedDIContainer get instance => _instance;

  EnhancedDIContainer._internal();

  /// Register a service with lifecycle management
  void register<T>({
    required T Function() factory,
    String? name,
    bool isSingleton = false,
    List<Type> dependencies = const [],
    Future<void> Function(T)? onInitialize,
    Future<void> Function(T)? onDispose,
    int priority = 0,
  }) {
    final registration = ServiceRegistration<T>(
      type: T,
      name: name,
      factory: factory,
      isSingleton: isSingleton,
      dependencies: dependencies,
      onInitialize: onInitialize != null
          ? (dynamic instance) => onInitialize(instance as T)
          : null,
      onDispose: onDispose != null
          ? (dynamic instance) => onDispose(instance as T)
          : null,
      registeredAt: DateTime.now(),
      priority: priority,
    );

    _registerService(registration);
  }

  /// Register an existing instance
  void registerInstance<T>(
    T instance, {
    String? name,
    List<Type> dependencies = const [],
    Future<void> Function(T)? onDispose,
    int priority = 0,
  }) {
    final registration = ServiceRegistration<T>(
      type: T,
      name: name,
      instance: instance,
      isSingleton: true,
      dependencies: dependencies,
      lifecycle: ServiceLifecycle.initialized,
      onDispose: onDispose != null
          ? (dynamic instance) => onDispose(instance as T)
          : null,
      registeredAt: DateTime.now(),
      priority: priority,
    );

    _registerService(registration);
    _instances[registration.key] = instance;
    _initialized.add(registration.key);
  }

  /// Get a service with dependency resolution
  Future<T> get<T>({String? name}) async {
    final key = _getServiceKey<T>(name);
    _logger.fine('Getting service: $key');
    final registration = _registrations[key];

    if (registration == null) {
      throw MCPException('Service not registered: $key');
    }

    // Check if already initialized
    if (_instances.containsKey(key)) {
      _logger.fine('Service already initialized: $key');
      return _instances[key] as T;
    }

    // Initialize service and its dependencies
    _logger.fine('About to initialize service: $key');
    await _initializeService(registration);

    return _instances[key] as T;
  }

  /// Initialize all services in dependency order
  Future<void> initializeAll() async {
    _logger.info('Initializing all services in dependency order');

    final resolution = _resolveDependencies();

    if (resolution.hasCircularDependencies) {
      throw MCPException(
          'Circular dependencies detected: ${resolution.circularDependencies.join(', ')}');
    }

    for (final serviceKey in resolution.initializationOrder) {
      final registration = _registrations[serviceKey];
      if (registration != null && !_initialized.contains(serviceKey)) {
        await _initializeService(registration);
      }
    }

    _logger.info('All services initialized successfully');
  }

  /// Dispose all services in reverse dependency order
  Future<void> disposeAll() async {
    _logger.info('Disposing all services in reverse dependency order');

    final resolution = _resolveDependencies();

    for (final serviceKey in resolution.disposalOrder) {
      final registration = _registrations[serviceKey];
      if (registration != null && _initialized.contains(serviceKey)) {
        await _disposeService(registration);
      }
    }

    // Clear all state
    _instances.clear();
    _initialized.clear();
    _initializing.clear();
    _disposing.clear();

    _logger.info('All services disposed successfully');
  }

  /// Get service registration information
  ServiceRegistration? getRegistration<T>({String? name}) {
    final key = _getServiceKey<T>(name);
    return _registrations[key];
  }

  /// Get all registrations
  List<ServiceRegistration> getAllRegistrations() {
    return _registrations.values.toList();
  }

  /// Get dependency resolution information
  DependencyResolutionResult getDependencyResolution() {
    return _resolveDependencies();
  }

  /// Check if service is registered
  bool isRegistered<T>({String? name}) {
    final key = _getServiceKey<T>(name);
    return _registrations.containsKey(key);
  }

  /// Check if service is initialized
  bool isInitialized<T>({String? name}) {
    final key = _getServiceKey<T>(name);
    return _initialized.contains(key);
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    final registeredCount = _registrations.length;
    final initializedCount = _initialized.length;
    final singletonCount =
        _registrations.values.where((r) => r.isSingleton).length;

    final lifecycleStats = <String, int>{};
    for (final registration in _registrations.values) {
      final state = registration.lifecycle.name;
      lifecycleStats[state] = (lifecycleStats[state] ?? 0) + 1;
    }

    return {
      'registeredServices': registeredCount,
      'initializedServices': initializedCount,
      'singletonServices': singletonCount,
      'lifecycleStats': lifecycleStats,
      'dependencyGraphSize': _dependencyGraph.length,
      'circularDependencies':
          _resolveDependencies().circularDependencies.length,
    };
  }

  /// Clear all registrations and instances
  Future<void> clear() async {
    await disposeAll();
    _registrations.clear();
    _dependencyGraph.clear();
    _cachedResolution = null;
  }

  /// Register a service internally
  void _registerService<T>(ServiceRegistration<T> registration) {
    final key = registration.key;

    _logger.fine('Registering service: $key');

    // Store registration
    _registrations[key] = registration;

    // Build dependency graph
    _buildDependencyGraph(registration);

    // Invalidate cached resolution
    _cachedResolution = null;

    // Publish lifecycle event
    _publishLifecycleEvent(
      key,
      ServiceLifecycle.uninitialized,
      ServiceLifecycle.uninitialized,
    );
  }

  /// Initialize a service and its dependencies
  Future<void> _initializeService(ServiceRegistration registration) async {
    final key = registration.key;
    _logger.fine('_initializeService called for: $key');

    // Check if already initialized
    if (_initialized.contains(key)) {
      _logger.fine('Service already in initialized set: $key');
      return;
    }

    // Check if currently initializing (circular dependency)
    if (_initializing.contains(key)) {
      throw MCPException(
          'Circular dependency detected while initializing: $key');
    }

    _initializing.add(key);
    _logger.fine('Added to initializing set: $key');

    try {
      _logger.fine('Initializing service: $key');

      // Update lifecycle state
      final updatedRegistration = registration.copyWith(
        lifecycle: ServiceLifecycle.initializing,
      );
      _registrations[key] = updatedRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.uninitialized,
        ServiceLifecycle.initializing,
      );

      // Initialize dependencies first
      await _initializeDependencies(registration);

      // Create instance if needed
      dynamic instance = registration.instance;
      if (instance == null && registration.factory != null) {
        instance = registration.factory!();
      }

      if (instance == null) {
        throw MCPException('No instance or factory for service: $key');
      }

      // Call initialization callback
      if (registration.onInitialize != null) {
        await registration.onInitialize!(instance);
      }

      // Store instance
      _instances[key] = instance;
      _initialized.add(key);

      // Update lifecycle state
      final finalRegistration = updatedRegistration.copyWith(
        lifecycle: ServiceLifecycle.initialized,
        instance: instance,
      );
      _registrations[key] = finalRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.initializing,
        ServiceLifecycle.initialized,
      );

      _logger.fine('Service initialized successfully: $key');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize service: $key', e, stackTrace);

      // Update lifecycle state to error
      final errorRegistration = registration.copyWith(
        lifecycle: ServiceLifecycle.error,
      );
      _registrations[key] = errorRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.initializing,
        ServiceLifecycle.error,
        error: e.toString(),
      );

      rethrow;
    } finally {
      _initializing.remove(key);
    }
  }

  /// Initialize service dependencies
  Future<void> _initializeDependencies(ServiceRegistration registration) async {
    for (final dependencyType in registration.dependencies) {
      final dependencyKey = dependencyType.toString();
      final dependencyRegistration = _registrations[dependencyKey];

      if (dependencyRegistration != null &&
          !_initialized.contains(dependencyKey)) {
        await _initializeService(dependencyRegistration);
      }
    }
  }

  /// Dispose a service
  Future<void> _disposeService(ServiceRegistration registration) async {
    final key = registration.key;

    if (_disposing.contains(key)) {
      return; // Already disposing
    }

    _disposing.add(key);

    try {
      _logger.fine('Disposing service: $key');

      // Update lifecycle state
      final updatedRegistration = registration.copyWith(
        lifecycle: ServiceLifecycle.disposing,
      );
      _registrations[key] = updatedRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.initialized,
        ServiceLifecycle.disposing,
      );

      final instance = _instances[key];
      if (instance != null && registration.onDispose != null) {
        await registration.onDispose!(instance);
      }

      // Remove instance
      _instances.remove(key);
      _initialized.remove(key);

      // Update lifecycle state
      final finalRegistration = updatedRegistration.copyWith(
        lifecycle: ServiceLifecycle.disposed,
      );
      _registrations[key] = finalRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.disposing,
        ServiceLifecycle.disposed,
      );

      _logger.fine('Service disposed successfully: $key');
    } catch (e, stackTrace) {
      _logger.severe('Failed to dispose service: $key', e, stackTrace);

      // Update lifecycle state to error
      final errorRegistration = registration.copyWith(
        lifecycle: ServiceLifecycle.error,
      );
      _registrations[key] = errorRegistration;

      _publishLifecycleEvent(
        key,
        ServiceLifecycle.disposing,
        ServiceLifecycle.error,
        error: e.toString(),
      );

      rethrow;
    } finally {
      _disposing.remove(key);
    }
  }

  /// Build dependency graph for a service
  void _buildDependencyGraph(ServiceRegistration registration) {
    final serviceKey = registration.key;

    // Create node for this service
    final node = _dependencyGraph.putIfAbsent(
        serviceKey, () => DependencyNode(serviceKey));

    // Add dependencies
    for (final dependencyType in registration.dependencies) {
      final dependencyKey = dependencyType.toString();

      // Check for immediate circular dependency (A depends on B, B depends on A)
      final existingDepNode = _dependencyGraph[dependencyKey];
      if (existingDepNode != null &&
          existingDepNode.dependencies.contains(serviceKey)) {
        throw MCPException(
            'Circular dependency detected: $serviceKey <-> $dependencyKey');
      }

      // Create dependency node if it doesn't exist
      final depNode = _dependencyGraph.putIfAbsent(
          dependencyKey, () => DependencyNode(dependencyKey));

      // Add bidirectional relationship
      node.addDependency(dependencyKey);
      depNode.addDependent(serviceKey);
    }

    // Check for longer circular dependency chains
    _checkForCircularDependencies(serviceKey);
  }

  /// Check for circular dependencies starting from a service
  void _checkForCircularDependencies(String serviceKey) {
    final visited = <String>{};
    final inStack = <String>{};

    void dfs(String currentKey) {
      if (inStack.contains(currentKey)) {
        throw MCPException(
            'Circular dependency detected involving: $currentKey');
      }

      if (visited.contains(currentKey)) {
        return;
      }

      visited.add(currentKey);
      inStack.add(currentKey);

      final node = _dependencyGraph[currentKey];
      if (node != null) {
        for (final dependency in node.dependencies) {
          dfs(dependency);
        }
      }

      inStack.remove(currentKey);
    }

    dfs(serviceKey);
  }

  /// Resolve dependency order
  DependencyResolutionResult _resolveDependencies() {
    if (_cachedResolution != null) {
      return _cachedResolution!;
    }

    final initOrder = <String>[];
    final disposalOrder = <String>[];
    final circularDeps = <String>[];
    final levels = <String, int>{};

    // Reset visit state
    for (final node in _dependencyGraph.values) {
      node.visited = false;
      node.inStack = false;
      node.level = 0;
    }

    // Topological sort with cycle detection
    for (final serviceKey in _dependencyGraph.keys) {
      if (!_dependencyGraph[serviceKey]!.visited) {
        _dfsTopologicalSort(serviceKey, initOrder, circularDeps);
      }
    }

    // Calculate dependency levels
    _calculateDependencyLevels(levels);

    // Disposal order is reverse of initialization order
    disposalOrder.addAll(initOrder.reversed);

    _cachedResolution = DependencyResolutionResult(
      initializationOrder: initOrder,
      disposalOrder: disposalOrder,
      circularDependencies: circularDeps,
      dependencyLevels: levels,
    );

    return _cachedResolution!;
  }

  /// DFS topological sort with cycle detection
  void _dfsTopologicalSort(
      String serviceKey, List<String> order, List<String> circularDeps) {
    final node = _dependencyGraph[serviceKey];
    if (node == null) return;

    node.inStack = true;

    for (final dependency in node.dependencies) {
      final depNode = _dependencyGraph[dependency];
      if (depNode == null) continue;

      if (depNode.inStack) {
        // Circular dependency detected
        circularDeps.add('$serviceKey -> $dependency');
      } else if (!depNode.visited) {
        _dfsTopologicalSort(dependency, order, circularDeps);
      }
    }

    node.visited = true;
    node.inStack = false;
    order.add(serviceKey);
  }

  /// Calculate dependency levels for each service
  void _calculateDependencyLevels(Map<String, int> levels) {
    for (final serviceKey in _dependencyGraph.keys) {
      _calculateServiceLevel(serviceKey, levels, <String>{});
    }
  }

  /// Calculate level for a specific service
  int _calculateServiceLevel(
      String serviceKey, Map<String, int> levels, Set<String> visiting) {
    if (levels.containsKey(serviceKey)) {
      return levels[serviceKey]!;
    }

    if (visiting.contains(serviceKey)) {
      // Circular dependency detected - set level to 0 and don't recurse further
      levels[serviceKey] = 0;
      return 0;
    }

    visiting.add(serviceKey);

    final node = _dependencyGraph[serviceKey];
    if (node == null || node.dependencies.isEmpty) {
      levels[serviceKey] = 0;
      visiting.remove(serviceKey);
      return 0;
    }

    int maxDepLevel = -1;
    for (final dependency in node.dependencies) {
      final depLevel = _calculateServiceLevel(dependency, levels, visiting);
      maxDepLevel = maxDepLevel > depLevel ? maxDepLevel : depLevel;
    }

    final level = maxDepLevel + 1;
    levels[serviceKey] = level;
    node.level = level;

    visiting.remove(serviceKey);
    return level;
  }

  /// Get service key
  String _getServiceKey<T>(String? name) {
    return name != null ? '${T.toString()}:$name' : T.toString();
  }

  /// Publish lifecycle event
  void _publishLifecycleEvent(
    String serviceKey,
    ServiceLifecycle oldState,
    ServiceLifecycle newState, {
    String? error,
  }) {
    final event = ServiceLifecycleEvent(
      serviceKey: serviceKey,
      oldState: oldState,
      newState: newState,
      error: error,
    );

    _logger
        .fine('Publishing lifecycle event: $serviceKey $oldState -> $newState');
    _eventSystem.publishTyped<ServiceLifecycleEvent>(event);
  }
}

/// Enhanced service locator with lifecycle management
class EnhancedServiceLocator {
  static final EnhancedDIContainer _container = EnhancedDIContainer.instance;

  /// Register a service
  static void register<T>({
    required T Function() factory,
    String? name,
    bool isSingleton = false,
    List<Type> dependencies = const [],
    Future<void> Function(T)? onInitialize,
    Future<void> Function(T)? onDispose,
    int priority = 0,
  }) {
    _container.register<T>(
      factory: factory,
      name: name,
      isSingleton: isSingleton,
      dependencies: dependencies,
      onInitialize: onInitialize,
      onDispose: onDispose,
      priority: priority,
    );
  }

  /// Register an instance
  static void registerInstance<T>(
    T instance, {
    String? name,
    List<Type> dependencies = const [],
    Future<void> Function(T)? onDispose,
    int priority = 0,
  }) {
    _container.registerInstance<T>(
      instance,
      name: name,
      dependencies: dependencies,
      onDispose: onDispose,
      priority: priority,
    );
  }

  /// Get a service
  static Future<T> get<T>({String? name}) {
    return _container.get<T>(name: name);
  }

  /// Initialize all services
  static Future<void> initializeAll() {
    return _container.initializeAll();
  }

  /// Dispose all services
  static Future<void> disposeAll() {
    return _container.disposeAll();
  }

  /// Check if registered
  static bool isRegistered<T>({String? name}) {
    return _container.isRegistered<T>(name: name);
  }

  /// Check if initialized
  static bool isInitialized<T>({String? name}) {
    return _container.isInitialized<T>(name: name);
  }

  /// Get statistics
  static Map<String, dynamic> getStatistics() {
    return _container.getStatistics();
  }

  /// Get dependency resolution
  static DependencyResolutionResult getDependencyResolution() {
    return _container.getDependencyResolution();
  }
}

/// Mixin for enhanced dependency injection
mixin EnhancedDIAware {
  @protected
  Future<T> inject<T>({String? name}) =>
      EnhancedServiceLocator.get<T>(name: name);

  @protected
  bool canInject<T>({String? name}) =>
      EnhancedServiceLocator.isRegistered<T>(name: name);

  @protected
  bool isInjected<T>({String? name}) =>
      EnhancedServiceLocator.isInitialized<T>(name: name);
}
