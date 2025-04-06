import '../utils/error_recovery.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Base plugin interface
abstract class MCPPlugin {
  /// Plugin name
  String get name;

  /// Plugin version
  String get version;

  /// Plugin description
  String get description;

  /// Initialize the plugin
  Future<void> initialize(Map<String, dynamic> config);

  /// Shutdown the plugin
  Future<void> shutdown();
}

/// MCP Tool plugin interface
abstract class MCPToolPlugin extends MCPPlugin {
  /// Execute the tool with arguments
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments);

  /// Get tool metadata including input schema
  Map<String, dynamic> getToolMetadata();
}

/// MCP Resource plugin interface
abstract class MCPResourcePlugin extends MCPPlugin {
  /// Get resource content
  Future<Map<String, dynamic>> getResource(String resourceUri, Map<String, dynamic> params);

  /// Get resource metadata
  Map<String, dynamic> getResourceMetadata();
}

/// MCP Background plugin interface
abstract class MCPBackgroundPlugin extends MCPPlugin {
  /// Start the background task
  Future<bool> start();

  /// Stop the background task
  Future<bool> stop();

  /// Check if the background task is running
  bool get isRunning;

  /// Register a background task handler
  void registerTaskHandler(Future<void> Function() handler);
}

/// MCP Notification plugin interface
abstract class MCPNotificationPlugin extends MCPPlugin {
  /// Show a notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? id,
    String? icon,
    Map<String, dynamic>? additionalData,
  });

  /// Hide a notification
  Future<void> hideNotification(String id);

  /// Register a notification click handler
  void registerClickHandler(Function(String id, Map<String, dynamic>? data) handler);
}

/// MCP Plugin registry
class MCPPluginRegistry {
  final MCPLogger _logger = MCPLogger('mcp.plugin_registry');

  /// Registered plugins by type and name
  final Map<Type, Map<String, MCPPlugin>> _plugins = {};

  /// Plugin configurations
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// Register a plugin
  Future<void> registerPlugin(MCPPlugin plugin, [Map<String, dynamic>? config]) async {
    final pluginType = plugin.runtimeType;
    final typeName = _getPluginTypeName(plugin);
    final pluginName = plugin.name;

    _logger.debug('Registering $typeName plugin: $pluginName v${plugin.version}');

    // Initialize plugin type map if not exists
    _plugins.putIfAbsent(pluginType, () => {});

    // Check if plugin with same name already exists
    if (_plugins[pluginType]!.containsKey(pluginName)) {
      _logger.warning('Plugin $pluginName already registered, replacing existing plugin');
    }

    // Store configuration
    final pluginConfig = config ?? {};
    _configurations[pluginName] = pluginConfig;

    // Initialize the plugin
    try {
      await plugin.initialize(pluginConfig);
      _plugins[pluginType]![pluginName] = plugin;
      _logger.info('Plugin $pluginName successfully initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize plugin $pluginName', e, stackTrace);
      throw MCPPluginException(
        pluginName,
        'Failed to initialize plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Unregister a plugin
  Future<void> unregisterPlugin(String pluginName) async {
    _logger.debug('Unregistering plugin: $pluginName');

    MCPPlugin? foundPlugin;
    Type? foundType;

    // Find the plugin
    for (final entry in _plugins.entries) {
      if (entry.value.containsKey(pluginName)) {
        foundPlugin = entry.value[pluginName];
        foundType = entry.key;
        break;
      }
    }

    if (foundPlugin == null || foundType == null) {
      _logger.warning('Plugin $pluginName not found');
      return;
    }

    // Shutdown the plugin
    try {
      await foundPlugin.shutdown();
      _plugins[foundType]!.remove(pluginName);
      _configurations.remove(pluginName);
      _logger.info('Plugin $pluginName successfully unregistered');
    } catch (e, stackTrace) {
      _logger.error('Failed to shutdown plugin $pluginName', e, stackTrace);
      throw MCPPluginException(
        pluginName,
        'Failed to shutdown plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Get a plugin by name and type
  T? getPlugin<T extends MCPPlugin>(String name) {
    for (final entry in _plugins.entries) {
      if (entry.value.containsKey(name) && entry.value[name] is T) {
        return entry.value[name] as T;
      }
    }
    return null;
  }

  /// Get all plugins of a specific type
  List<T> getPluginsByType<T extends MCPPlugin>() {
    final result = <T>[];

    for (final entry in _plugins.entries) {
      for (final plugin in entry.value.values) {
        if (plugin is T) {
          result.add(plugin);
        }
      }
    }

    return result;
  }

  /// Execute a tool plugin
  Future<Map<String, dynamic>> executeTool(String name, Map<String, dynamic> arguments) async {
    final plugin = getPlugin<MCPToolPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Tool plugin not found');
    }

    try {
      return await plugin.execute(arguments);
    } catch (e, stackTrace) {
      _logger.error('Error executing tool plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error executing tool plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Get a resource from a resource plugin
  Future<Map<String, dynamic>> getResource(
      String name,
      String resourceUri,
      Map<String, dynamic> params
      ) async {
    final plugin = getPlugin<MCPResourcePlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Resource plugin not found');
    }

    try {
      return await plugin.getResource(resourceUri, params);
    } catch (e, stackTrace) {
      _logger.error('Error getting resource from plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error getting resource: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Show notification using a notification plugin
  Future<void> showNotification(
      String name, {
        required String title,
        required String body,
        String? id,
        String? icon,
        Map<String, dynamic>? additionalData,
      }) async {
    final plugin = getPlugin<MCPNotificationPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Notification plugin not found');
    }

    try {
      await plugin.showNotification(
        title: title,
        body: body,
        id: id,
        icon: icon,
        additionalData: additionalData,
      );
    } catch (e, stackTrace) {
      _logger.error('Error showing notification with plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error showing notification: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Start a background plugin
  Future<bool> startBackgroundPlugin(String name) async {
    final plugin = getPlugin<MCPBackgroundPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Background plugin not found');
    }

    try {
      return await plugin.start();
    } catch (e, stackTrace) {
      _logger.error('Error starting background plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error starting background plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Stop a background plugin
  Future<bool> stopBackgroundPlugin(String name) async {
    final plugin = getPlugin<MCPBackgroundPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Background plugin not found');
    }

    try {
      return await plugin.stop();
    } catch (e, stackTrace) {
      _logger.error('Error stopping background plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error stopping background plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Shutdown all plugins
  Future<void> shutdownAll() async {
    _logger.debug('Shutting down all plugins');

    final errors = <String, dynamic>{};

    // Shutdown plugins in reverse registration order
    for (final typeMap in _plugins.values) {
      for (final pluginName in typeMap.keys.toList()) {
        try {
          final plugin = typeMap[pluginName];
          if (plugin != null) {
            await plugin.shutdown();
          }
        } catch (e) {
          _logger.error('Error shutting down plugin $pluginName', e);
          errors[pluginName] = e;
        }
      }
    }

    // Clear registries
    _plugins.clear();
    _configurations.clear();

    if (errors.isNotEmpty) {
      throw Exception('Errors occurred while shutting down plugins: $errors');
    }
  }

  /// Get plugin type name
  String _getPluginTypeName(MCPPlugin plugin) {
    if (plugin is MCPToolPlugin) {
      return 'Tool';
    } else if (plugin is MCPResourcePlugin) {
      return 'Resource';
    } else if (plugin is MCPBackgroundPlugin) {
      return 'Background';
    } else if (plugin is MCPNotificationPlugin) {
      return 'Notification';
    } else {
      return 'Unknown';
    }
  }
}