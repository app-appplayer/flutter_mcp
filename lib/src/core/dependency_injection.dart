import 'package:meta/meta.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Key for named type registrations
class _NamedTypeKey {
  final Type type;
  final String name;
  
  const _NamedTypeKey(this.type, this.name);
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NamedTypeKey &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          name == other.name;
  
  @override
  int get hashCode => type.hashCode ^ name.hashCode;
  
  @override
  String toString() => '$type:$name';
}

/// Dependency injection container for Flutter MCP
/// Provides a lightweight DI solution to reduce singleton usage
class DIContainer {
  static final DIContainer _instance = DIContainer._internal();
  
  /// Get singleton instance
  static DIContainer get instance => _instance;
  
  DIContainer._internal();
  
  // Registered factories
  final Map<Object, _ServiceFactory> _factories = {};
  
  // Registered singletons
  final Map<Object, dynamic> _singletons = {};
  
  // Logger
  final Logger _logger = Logger('flutter_mcp.di_container');
  
  /// Register a factory function
  void registerFactory<T>(T Function() factory, {String? name}) {
    final key = _getKey<T>(name);
    _logger.fine('Registering factory for $key');
    _factories[key] = _ServiceFactory(factory: factory, isSingleton: false);
  }
  
  /// Register a singleton factory
  void registerSingleton<T>(T Function() factory, {String? name}) {
    final key = _getKey<T>(name);
    _logger.fine('Registering singleton for $key');
    _factories[key] = _ServiceFactory(factory: factory, isSingleton: true);
  }
  
  /// Register an existing instance as singleton
  void registerInstance<T>(T instance, {String? name}) {
    final key = _getKey<T>(name);
    _logger.fine('Registering instance for $key');
    _singletons[key] = instance;
  }
  
  /// Get a service instance
  T get<T>({String? name}) {
    final key = _getKey<T>(name);
    
    // Check if we have a singleton instance
    if (_singletons.containsKey(key)) {
      return _singletons[key] as T;
    }
    
    // Check if we have a factory
    final factory = _factories[key];
    if (factory != null) {
      if (factory.isSingleton) {
        // Create and cache singleton
        final instance = factory.factory() as T;
        _singletons[key] = instance;
        return instance;
      } else {
        // Create new instance
        return factory.factory() as T;
      }
    }
    
    throw MCPException('No registration found for type $T${name != null ? ' with name $name' : ''}');
  }
  
  /// Check if a type is registered
  bool isRegistered<T>({String? name}) {
    final key = _getKey<T>(name);
    return _factories.containsKey(key) || _singletons.containsKey(key);
  }
  
  /// Remove a registration
  void unregister<T>({String? name}) {
    final key = _getKey<T>(name);
    _factories.remove(key);
    _singletons.remove(key);
  }
  
  /// Clear all registrations
  void clear() {
    _factories.clear();
    _singletons.clear();
  }
  
  /// Get the key for a type with optional name
  Object _getKey<T>(String? name) {
    if (name != null) {
      return _NamedTypeKey(T, name);
    }
    return T;
  }
}

/// Service factory wrapper
class _ServiceFactory {
  final Function factory;
  final bool isSingleton;
  
  _ServiceFactory({
    required this.factory,
    required this.isSingleton,
  });
}

/// Service locator pattern for easy access
class ServiceLocator {
  static final DIContainer _container = DIContainer.instance;
  
  /// Register a factory
  static void registerFactory<T>(T Function() factory) {
    _container.registerFactory<T>(factory);
  }
  
  /// Register a singleton
  static void registerSingleton<T>(T Function() factory) {
    _container.registerSingleton<T>(factory);
  }
  
  /// Register an instance
  static void registerInstance<T>(T instance) {
    _container.registerInstance<T>(instance);
  }
  
  /// Get a service
  static T get<T>() {
    return _container.get<T>();
  }
  
  /// Check if registered
  static bool isRegistered<T>() {
    return _container.isRegistered<T>();
  }
}

/// Mixin for dependency injection
mixin DIAware {
  @protected
  T inject<T>() => ServiceLocator.get<T>();
  
  @protected
  bool canInject<T>() => ServiceLocator.isRegistered<T>();
}