import 'dart:async';
import 'logger.dart';

/// Resource manager to track and properly dispose of resources
class ResourceManager {
  final MCPLogger _logger = MCPLogger('mcp.resource_manager');

  /// Resources to dispose
  final Map<String, _DisposableResource> _resources = {};

  /// Register a resource for cleanup
  ///
  /// [key] is a unique identifier for the resource
  /// [resource] is the resource object
  /// [disposeFunction] is the function to call to dispose the resource
  void register<T>(String key, T resource, Future<void> Function(T) disposeFunction) {
    _logger.debug('Registering resource: $key');

    // Dispose any existing resource with the same key
    if (_resources.containsKey(key)) {
      _logger.debug('Resource with key $key already exists, disposing previous resource');
      _resources[key]!.dispose().catchError((error) {
        _logger.error('Error disposing previous resource: $key', error);
      });
    }

    _resources[key] = _DisposableResource<T>(
      key: key,
      resource: resource,
      disposeFunction: disposeFunction,
    );
  }

  /// Register a stream subscription for cleanup
  void registerSubscription(String key, StreamSubscription subscription) {
    register<StreamSubscription>(key, subscription, (sub) => sub.cancel());
  }

  /// Register a callback to be executed during cleanup
  void registerCallback(String key, Future<void> Function() callback) {
    register<Future<void> Function()>(key, callback, (cb) => cb());
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

  /// Dispose a specific resource
  Future<void> dispose(String key) async {
    if (!_resources.containsKey(key)) {
      _logger.debug('No resource found with key: $key');
      return;
    }

    _logger.debug('Disposing resource: $key');
    try {
      await _resources[key]!.dispose();
      _resources.remove(key);
    } catch (e) {
      _logger.error('Error disposing resource: $key', e);
      rethrow;
    }
  }

  /// Dispose all resources
  Future<void> disposeAll() async {
    _logger.debug('Disposing all resources');

    final errors = <String, dynamic>{};

    // Make a copy of the keys to avoid concurrent modification
    final keys = _resources.keys.toList();

    // Dispose resources in reverse order (LIFO)
    for (final key in keys.reversed) {
      try {
        await _resources[key]!.dispose();
      } catch (e) {
        _logger.error('Error disposing resource: $key', e);
        errors[key] = e;
      }
    }

    _resources.clear();

    if (errors.isNotEmpty) {
      throw Exception('Errors disposing resources: $errors');
    }
  }

  /// Get all resource keys
  List<String> get allKeys => _resources.keys.toList();

  /// Resource count
  int get count => _resources.length;

  /// Group resources by tag
  ///
  /// Register resources with the same tag to group them
  void registerWithTag<T>(String key, T resource, Future<void> Function(T) disposeFunction, String tag) {
    register(key, resource, disposeFunction);
    _resources[key]!.tag = tag;
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
        await _resources[key]!.dispose();
        _resources.remove(key);
      } catch (e) {
        _logger.error('Error disposing resource: $key', e);
        errors[key] = e;
      }
    }

    if (errors.isNotEmpty) {
      throw Exception('Errors disposing resources with tag $tag: $errors');
    }
  }

  /// Get all resource keys with a specific tag
  List<String> getKeysByTag(String tag) {
    return _resources.entries
        .where((entry) => entry.value.tag == tag)
        .map((entry) => entry.key)
        .toList();
  }
}

/// Internal class to represent a disposable resource
class _DisposableResource<T> {
  final String key;
  final T resource;
  final Future<void> Function(T) disposeFunction;
  String? tag;
  bool _disposed = false;

  _DisposableResource({
    required this.key,
    required this.resource,
    required this.disposeFunction,
    this.tag,
  });

  Future<void> dispose() async {
    if (_disposed) return;

    await disposeFunction(resource);
    _disposed = true;
  }
}