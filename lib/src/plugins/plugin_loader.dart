import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'plugin_system.dart';
import 'plugin_communication.dart';

/// Dynamic plugin loader with hot reload support
class DynamicPluginLoader {
  static final DynamicPluginLoader _instance = DynamicPluginLoader._internal();
  
  /// Get singleton instance
  static DynamicPluginLoader get instance => _instance;
  
  DynamicPluginLoader._internal();
  
  final Logger _logger = Logger('flutter_mcp.plugin_loader');
  
  // Loaded plugins
  final Map<String, LoadedPlugin> _loadedPlugins = {};
  
  // Plugin isolates for isolation
  final Map<String, Isolate> _pluginIsolates = {};
  
  // Plugin registry reference
  MCPPluginRegistry? _registry;
  
  /// Initialize with plugin registry
  void initialize(MCPPluginRegistry registry) {
    _registry = registry;
  }
  
  /// Load plugin from file path
  Future<void> loadPluginFromFile(String filePath, {Map<String, dynamic>? config}) async {
    if (kIsWeb) {
      throw MCPException('Dynamic plugin loading from files is not supported on web platform');
    }
    
    _logger.info('Loading plugin from file: $filePath');
    
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw MCPResourceNotFoundException(filePath, 'Plugin file not found');
      }
      
      // Read plugin code
      final code = await file.readAsString();
      
      // Load plugin
      await _loadPluginCode(filePath, code, config);
      
    } catch (e, stackTrace) {
      _logger.severe('Failed to load plugin from file', e, stackTrace);
      throw MCPPluginException(filePath, 'Failed to load plugin from file', e, stackTrace);
    }
  }
  
  /// Load plugin from asset
  Future<void> loadPluginFromAsset(String assetPath, {Map<String, dynamic>? config}) async {
    _logger.info('Loading plugin from asset: $assetPath');
    
    try {
      // Read plugin code from asset
      final code = await rootBundle.loadString(assetPath);
      
      // Load plugin
      await _loadPluginCode(assetPath, code, config);
      
    } catch (e, stackTrace) {
      _logger.severe('Failed to load plugin from asset', e, stackTrace);
      throw MCPPluginException(assetPath, 'Failed to load plugin from asset', e, stackTrace);
    }
  }
  
  /// Load plugin from code string
  Future<void> _loadPluginCode(String source, String code, Map<String, dynamic>? config) async {
    // For now, we'll use a simplified approach
    // In a real implementation, this would use dart:mirrors or code generation
    
    final pluginName = _extractPluginName(source);
    
    // Create loaded plugin info
    final loadedPlugin = LoadedPlugin(
      name: pluginName,
      source: source,
      code: code,
      config: config ?? {},
      loadTime: DateTime.now(),
    );
    
    _loadedPlugins[pluginName] = loadedPlugin;
    
    // In a real implementation, we would:
    // 1. Parse the code to extract the plugin class
    // 2. Create an instance of the plugin
    // 3. Register it with the plugin registry
    
    _logger.info('Plugin $pluginName loaded successfully');
  }
  
  /// Unload a plugin
  Future<void> unloadPlugin(String pluginName) async {
    _logger.info('Unloading plugin: $pluginName');
    
    // Get loaded plugin info
    final loadedPlugin = _loadedPlugins[pluginName];
    if (loadedPlugin == null) {
      throw MCPResourceNotFoundException(pluginName, 'Plugin not found');
    }
    
    // Unregister from registry
    if (_registry != null) {
      await _registry!.unregisterPlugin(pluginName);
    }
    
    // Terminate isolate if exists
    final isolate = _pluginIsolates[pluginName];
    if (isolate != null) {
      isolate.kill();
      _pluginIsolates.remove(pluginName);
    }
    
    // Remove from loaded plugins
    _loadedPlugins.remove(pluginName);
    
    _logger.info('Plugin $pluginName unloaded successfully');
  }
  
  /// Reload a plugin (hot reload)
  Future<void> reloadPlugin(String pluginName) async {
    _logger.info('Reloading plugin: $pluginName');
    
    // Get current plugin info
    final loadedPlugin = _loadedPlugins[pluginName];
    if (loadedPlugin == null) {
      throw MCPResourceNotFoundException(pluginName, 'Plugin not found');
    }
    
    // Unload current version
    await unloadPlugin(pluginName);
    
    // Reload from original source
    if (loadedPlugin.source.startsWith('assets/')) {
      await loadPluginFromAsset(loadedPlugin.source, config: loadedPlugin.config);
    } else {
      await loadPluginFromFile(loadedPlugin.source, config: loadedPlugin.config);
    }
    
    _logger.info('Plugin $pluginName reloaded successfully');
  }
  
  /// Get list of loaded plugins
  List<LoadedPluginInfo> getLoadedPlugins() {
    return _loadedPlugins.values.map((p) => LoadedPluginInfo(
      name: p.name,
      source: p.source,
      loadTime: p.loadTime,
      configKeys: p.config.keys.toList(),
    )).toList();
  }
  
  /// Check if plugin is loaded
  bool isPluginLoaded(String pluginName) {
    return _loadedPlugins.containsKey(pluginName);
  }
  
  /// Extract plugin name from source path
  String _extractPluginName(String source) {
    final parts = source.split('/');
    final filename = parts.last;
    return filename.replaceAll('.dart', '').replaceAll('_plugin', '');
  }
  
  /// Dispose all loaded plugins
  Future<void> dispose() async {
    for (final pluginName in _loadedPlugins.keys.toList()) {
      await unloadPlugin(pluginName);
    }
  }
}

/// Loaded plugin information
class LoadedPlugin {
  final String name;
  final String source;
  final String code;
  final Map<String, dynamic> config;
  final DateTime loadTime;
  
  LoadedPlugin({
    required this.name,
    required this.source,
    required this.code,
    required this.config,
    required this.loadTime,
  });
}

/// Loaded plugin info for external use
class LoadedPluginInfo {
  final String name;
  final String source;
  final DateTime loadTime;
  final List<String> configKeys;
  
  LoadedPluginInfo({
    required this.name,
    required this.source,
    required this.loadTime,
    required this.configKeys,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'source': source,
    'loadTime': loadTime.toIso8601String(),
    'configKeys': configKeys,
  };
}

/// Example of a dynamically loadable plugin template
abstract class DynamicMCPPlugin extends CommunicatingPlugin {
  /// Plugin metadata
  Map<String, dynamic> get metadata;
  
  @override
  Future<void> onInitialize(Map<String, dynamic> config) async {
    // Subscribe to plugin lifecycle channel
    subscribeToChannel('plugin.lifecycle', (message) {
      if (message.data['pluginName'] == name) {
        _handleLifecycleMessage(message);
      }
    });
  }
  
  void _handleLifecycleMessage(PluginMessage message) {
    final action = message.data['action'];
    
    switch (action) {
      case 'reload':
        // Handle reload request
        onReload();
        break;
      case 'suspend':
        // Handle suspend request
        onSuspend();
        break;
      case 'resume':
        // Handle resume request
        onResume();
        break;
    }
  }
  
  /// Called when plugin is reloaded
  void onReload() {
    // Override in subclasses
  }
  
  /// Called when plugin is suspended
  void onSuspend() {
    // Override in subclasses
  }
  
  /// Called when plugin is resumed
  void onResume() {
    // Override in subclasses
  }
}