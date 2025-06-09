import 'dart:async';
import '../utils/logger.dart';
import '../utils/event_system.dart';
import '../utils/exceptions.dart';
import 'plugin_system.dart';

/// Plugin lifecycle states
enum PluginState {
  uninitialized,
  initializing,
  initialized,
  starting,
  started,
  stopping,
  stopped,
  suspended,
  error,
}

/// Plugin lifecycle manager
class PluginLifecycleManager {
  static final PluginLifecycleManager _instance = PluginLifecycleManager._internal();
  
  /// Get singleton instance
  static PluginLifecycleManager get instance => _instance;
  
  PluginLifecycleManager._internal();
  
  final Logger _logger = Logger('flutter_mcp.plugin_lifecycle');
  
  // Plugin states
  final Map<String, PluginState> _pluginStates = {};
  
  // Plugin metadata
  final Map<String, PluginMetadata> _pluginMetadata = {};
  
  // State change listeners
  final Map<String, List<PluginStateListener>> _stateListeners = {};
  
  // Plugin dependencies
  final Map<String, Set<String>> _pluginDependencies = {};
  
  // Plugin start order
  final List<String> _startOrder = [];
  
  /// Register a plugin
  void registerPlugin(String pluginName, {Set<String>? dependencies}) {
    _logger.fine('Registering plugin: $pluginName');
    
    _pluginStates[pluginName] = PluginState.uninitialized;
    _pluginDependencies[pluginName] = dependencies ?? {};
    
    _pluginMetadata[pluginName] = PluginMetadata(
      name: pluginName,
      registrationTime: DateTime.now(),
    );
  }
  
  /// Unregister a plugin
  void unregisterPlugin(String pluginName) {
    _logger.fine('Unregistering plugin: $pluginName');
    
    _pluginStates.remove(pluginName);
    _pluginMetadata.remove(pluginName);
    _pluginDependencies.remove(pluginName);
    _stateListeners.remove(pluginName);
    _startOrder.remove(pluginName);
  }
  
  /// Get plugin state
  PluginState? getPluginState(String pluginName) {
    return _pluginStates[pluginName];
  }
  
  /// Update plugin state
  Future<void> updatePluginState(String pluginName, PluginState newState) async {
    final currentState = _pluginStates[pluginName];
    if (currentState == null) {
      throw MCPResourceNotFoundException(pluginName, 'Plugin not registered');
    }
    
    // Validate state transition
    if (!_isValidStateTransition(currentState, newState)) {
      throw MCPPluginException(
        pluginName,
        'Invalid state transition: $currentState -> $newState',
      );
    }
    
    _logger.info('Plugin $pluginName state: $currentState -> $newState');
    
    // Update state
    _pluginStates[pluginName] = newState;
    
    // Update metadata
    final metadata = _pluginMetadata[pluginName]!;
    switch (newState) {
      case PluginState.initialized:
        metadata.initializeTime = DateTime.now();
        break;
      case PluginState.started:
        metadata.startTime = DateTime.now();
        break;
      case PluginState.stopped:
        metadata.stopTime = DateTime.now();
        break;
      default:
        break;
    }
    
    // Notify listeners
    await _notifyStateListeners(pluginName, currentState, newState);
    
    // Publish state change event
    EventSystem.instance.publish('plugin.state.changed', {
      'pluginName': pluginName,
      'previousState': currentState.toString(),
      'newState': newState.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Add state change listener
  void addStateListener(String pluginName, PluginStateListener listener) {
    _stateListeners.putIfAbsent(pluginName, () => []).add(listener);
  }
  
  /// Remove state change listener
  void removeStateListener(String pluginName, PluginStateListener listener) {
    _stateListeners[pluginName]?.remove(listener);
  }
  
  /// Initialize plugin
  Future<void> initializePlugin(String pluginName, MCPPlugin plugin, Map<String, dynamic> config) async {
    await updatePluginState(pluginName, PluginState.initializing);
    
    try {
      await plugin.initialize(config);
      await updatePluginState(pluginName, PluginState.initialized);
    } catch (e) {
      await updatePluginState(pluginName, PluginState.error);
      throw e;
    }
  }
  
  /// Start plugin
  Future<void> startPlugin(String pluginName) async {
    final state = _pluginStates[pluginName];
    if (state != PluginState.initialized && state != PluginState.stopped) {
      throw MCPPluginException(pluginName, 'Plugin must be initialized or stopped before starting');
    }
    
    // Check dependencies
    final dependencies = _pluginDependencies[pluginName]!;
    for (final dep in dependencies) {
      final depState = _pluginStates[dep];
      if (depState != PluginState.started) {
        throw MCPPluginException(
          pluginName,
          'Dependency $dep is not started',
        );
      }
    }
    
    await updatePluginState(pluginName, PluginState.starting);
    
    try {
      // Plugin-specific start logic would go here
      await updatePluginState(pluginName, PluginState.started);
      
      // Add to start order
      if (!_startOrder.contains(pluginName)) {
        _startOrder.add(pluginName);
      }
    } catch (e) {
      await updatePluginState(pluginName, PluginState.error);
      throw e;
    }
  }
  
  /// Stop plugin
  Future<void> stopPlugin(String pluginName) async {
    final state = _pluginStates[pluginName];
    if (state != PluginState.started) {
      throw MCPPluginException(pluginName, 'Plugin must be started before stopping');
    }
    
    // Check if any plugins depend on this one
    final dependents = _findDependents(pluginName);
    for (final dependent in dependents) {
      final depState = _pluginStates[dependent];
      if (depState == PluginState.started) {
        throw MCPPluginException(
          pluginName,
          'Cannot stop plugin while $dependent depends on it',
        );
      }
    }
    
    await updatePluginState(pluginName, PluginState.stopping);
    
    try {
      // Plugin-specific stop logic would go here
      await updatePluginState(pluginName, PluginState.stopped);
      
      // Remove from start order
      _startOrder.remove(pluginName);
    } catch (e) {
      await updatePluginState(pluginName, PluginState.error);
      throw e;
    }
  }
  
  /// Suspend plugin
  Future<void> suspendPlugin(String pluginName) async {
    final state = _pluginStates[pluginName];
    if (state != PluginState.started) {
      throw MCPPluginException(pluginName, 'Plugin must be started before suspending');
    }
    
    await updatePluginState(pluginName, PluginState.suspended);
  }
  
  /// Resume plugin
  Future<void> resumePlugin(String pluginName) async {
    final state = _pluginStates[pluginName];
    if (state != PluginState.suspended) {
      throw MCPPluginException(pluginName, 'Plugin must be suspended before resuming');
    }
    
    await updatePluginState(pluginName, PluginState.started);
  }
  
  /// Get plugin start order
  List<String> getStartOrder() {
    return List.from(_startOrder);
  }
  
  /// Get plugin metadata
  PluginMetadata? getPluginMetadata(String pluginName) {
    return _pluginMetadata[pluginName];
  }
  
  /// Get all plugin states
  Map<String, PluginState> getAllPluginStates() {
    return Map.from(_pluginStates);
  }
  
  /// Validate state transition
  bool _isValidStateTransition(PluginState from, PluginState to) {
    final validTransitions = {
      PluginState.uninitialized: {PluginState.initializing},
      PluginState.initializing: {PluginState.initialized, PluginState.error},
      PluginState.initialized: {PluginState.starting, PluginState.error},
      PluginState.starting: {PluginState.started, PluginState.error},
      PluginState.started: {PluginState.stopping, PluginState.suspended, PluginState.error},
      PluginState.stopping: {PluginState.stopped, PluginState.error},
      PluginState.stopped: {PluginState.starting, PluginState.error},
      PluginState.suspended: {PluginState.started, PluginState.error},
      PluginState.error: {PluginState.initializing, PluginState.stopped},
    };
    
    return validTransitions[from]?.contains(to) ?? false;
  }
  
  /// Notify state listeners
  Future<void> _notifyStateListeners(String pluginName, PluginState from, PluginState to) async {
    final listeners = _stateListeners[pluginName];
    if (listeners == null) return;
    
    for (final listener in listeners) {
      try {
        await listener(pluginName, from, to);
      } catch (e) {
        _logger.severe('Error in state listener', e);
      }
    }
  }
  
  /// Find plugins that depend on a given plugin
  Set<String> _findDependents(String pluginName) {
    final dependents = <String>{};
    
    for (final entry in _pluginDependencies.entries) {
      if (entry.value.contains(pluginName)) {
        dependents.add(entry.key);
      }
    }
    
    return dependents;
  }
}

/// Plugin metadata
class PluginMetadata {
  final String name;
  final DateTime registrationTime;
  DateTime? initializeTime;
  DateTime? startTime;
  DateTime? stopTime;
  
  PluginMetadata({
    required this.name,
    required this.registrationTime,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'registrationTime': registrationTime.toIso8601String(),
    'initializeTime': initializeTime?.toIso8601String(),
    'startTime': startTime?.toIso8601String(),
    'stopTime': stopTime?.toIso8601String(),
  };
}

/// Plugin state listener
typedef PluginStateListener = Future<void> Function(
  String pluginName,
  PluginState fromState,
  PluginState toState,
);

/// Enhanced plugin registry with lifecycle support
extension LifecyclePluginRegistry on MCPPluginRegistry {
  /// Register plugin with lifecycle management
  Future<void> registerPluginWithLifecycle(
    MCPPlugin plugin,
    Map<String, dynamic> config, {
    Set<String>? dependencies,
  }) async {
    // Register with lifecycle manager
    PluginLifecycleManager.instance.registerPlugin(
      plugin.name,
      dependencies: dependencies,
    );
    
    // Initialize plugin
    await PluginLifecycleManager.instance.initializePlugin(
      plugin.name,
      plugin,
      config,
    );
    
    // Register with plugin registry
    await registerPlugin(plugin, config);
  }
  
  /// Unregister plugin with lifecycle cleanup
  Future<void> unregisterPluginWithLifecycle(String pluginName) async {
    // Get plugin state
    final state = PluginLifecycleManager.instance.getPluginState(pluginName);
    
    // Stop if running
    if (state == PluginState.started) {
      await PluginLifecycleManager.instance.stopPlugin(pluginName);
    }
    
    // Unregister from plugin registry
    await unregisterPlugin(pluginName);
    
    // Unregister from lifecycle manager
    PluginLifecycleManager.instance.unregisterPlugin(pluginName);
  }
}