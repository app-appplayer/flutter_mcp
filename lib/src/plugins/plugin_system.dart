import '../utils/error_recovery.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_client/mcp_client.dart';
import 'dart:async';

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

  /// Register tool with an MCP server
  Future<void> registerWithServer(Server server);
}

/// MCP Resource plugin interface
abstract class MCPResourcePlugin extends MCPPlugin {
  /// Get resource content
  Future<Map<String, dynamic>> getResource(String resourceUri, Map<String, dynamic> params);

  /// Get resource metadata
  Map<String, dynamic> getResourceMetadata();

  /// Register resource with an MCP server
  Future<void> registerWithServer(Server server);
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

/// MCP Client plugin interface
abstract class MCPClientPlugin extends MCPPlugin {
  /// Initialize with a client
  Future<void> initializeWithClient(Client client);

  /// Handle connection state changes
  void handleConnectionStateChange(bool connected);

  /// Get client extensions
  Map<String, dynamic> getClientExtensions();
}

/// MCP Server plugin interface
abstract class MCPServerPlugin extends MCPPlugin {
  /// Initialize with a server
  Future<void> initializeWithServer(Server server);

  /// Handle connection state changes
  void handleConnectionStateChange(bool connected);

  /// Get server extensions
  Map<String, dynamic> getServerExtensions();
}

/// MCP Plugin registry
class MCPPluginRegistry {
  final MCPLogger _logger = MCPLogger('mcp.plugin_registry');

  /// Registered plugins by type and name
  final Map<Type, Map<String, MCPPlugin>> _plugins = {};

  /// Plugin configurations
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// Plugin dependencies
  final Map<String, List<String>> _dependencies = {};

  /// Plugin load order
  final List<String> _loadOrder = [];

  /// Registered servers for automatic plugin registration
  final Map<String, Server> _servers = {};

  /// Registered clients for automatic plugin registration
  final Map<String, Client> _clients = {};

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

      // Add to load order
      if (!_loadOrder.contains(pluginName)) {
        _loadOrder.add(pluginName);
      }

      // Auto-register with servers/clients if applicable
      await _autoRegisterPlugin(plugin);

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

      // Remove from load order
      _loadOrder.remove(pluginName);

      // Remove dependencies
      _dependencies.remove(pluginName);
      for (final deps in _dependencies.values) {
        deps.remove(pluginName);
      }

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

  /// Register a server for plugins to use
  void registerServer(String id, Server server) {
    _servers[id] = server;

    // Auto-register existing plugins with this server
    for (final typeMap in _plugins.values) {
      for (final plugin in typeMap.values) {
        if (plugin is MCPToolPlugin || plugin is MCPResourcePlugin ||
            plugin is MCPServerPlugin) {
          _autoRegisterPluginWithServer(plugin, server);
        }
      }
    }
  }

  /// Register a client for plugins to use
  void registerClient(String id, Client client) {
    _clients[id] = client;

    // Auto-register existing plugins with this client
    for (final typeMap in _plugins.values) {
      for (final plugin in typeMap.values) {
        if (plugin is MCPClientPlugin) {
          _autoRegisterPluginWithClient(plugin, client);
        }
      }
    }
  }

  /// Auto-register a plugin with servers/clients
  Future<void> _autoRegisterPlugin(MCPPlugin plugin) async {
    // Register with servers if applicable
    if (plugin is MCPToolPlugin || plugin is MCPResourcePlugin ||
        plugin is MCPServerPlugin) {
      for (final server in _servers.values) {
        await _autoRegisterPluginWithServer(plugin, server);
      }
    }

    // Register with clients if applicable
    if (plugin is MCPClientPlugin) {
      for (final client in _clients.values) {
        await _autoRegisterPluginWithClient(plugin, client);
      }
    }
  }

  /// Auto-register a plugin with a server
  Future<void> _autoRegisterPluginWithServer(MCPPlugin plugin, Server server) async {
    try {
      if (plugin is MCPToolPlugin) {
        await plugin.registerWithServer(server);
      } else if (plugin is MCPResourcePlugin) {
        await plugin.registerWithServer(server);
      } else if (plugin is MCPServerPlugin) {
        await plugin.initializeWithServer(server);
      }
    } catch (e) {
      _logger.error('Failed to auto-register plugin ${plugin.name} with server', e);
    }
  }

  /// Auto-register a plugin with a client
  Future<void> _autoRegisterPluginWithClient(MCPPlugin plugin, Client client) async {
    try {
      if (plugin is MCPClientPlugin) {
        await plugin.initializeWithClient(client);
      }
    } catch (e) {
      _logger.error('Failed to auto-register plugin ${plugin.name} with client', e);
    }
  }

  /// Execute a tool plugin
  Future<Map<String, dynamic>> executeTool(String name, Map<String, dynamic> arguments) async {
    final plugin = getPlugin<MCPToolPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Tool plugin not found');
    }

    try {
      return await ErrorRecovery.tryWithRetry(
            () => plugin.execute(arguments),
        operationName: 'Execute tool plugin $name',
        maxRetries: 2,
      );
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
      return await ErrorRecovery.tryWithRetry(
            () => plugin.getResource(resourceUri, params),
        operationName: 'Get resource from plugin $name',
        maxRetries: 2,
      );
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

  /// Check plugin dependencies
  bool hasDependency(String plugin, String dependency) {
    if (!_dependencies.containsKey(plugin)) {
      return false;
    }

    return _dependencies[plugin]!.contains(dependency);
  }

  /// Add plugin dependency
  void addDependency(String plugin, String dependency) {
    if (!_dependencies.containsKey(plugin)) {
      _dependencies[plugin] = [];
    }

    if (!_dependencies[plugin]!.contains(dependency)) {
      _dependencies[plugin]!.add(dependency);
    }
  }

  /// Get all plugin dependencies
  List<String> getDependencies(String plugin) {
    return _dependencies[plugin] ?? [];
  }

  /// Get all plugins that depend on a specific plugin
  List<String> getDependents(String plugin) {
    return _dependencies.entries
        .where((entry) => entry.value.contains(plugin))
        .map((entry) => entry.key)
        .toList();
  }

  /// Shutdown all plugins
  Future<void> shutdownAll() async {
    _logger.debug('Shutting down all plugins');

    final errors = <String, dynamic>{};

    // Shutdown plugins in reverse registration order to respect dependencies
    for (final pluginName in _loadOrder.reversed) {
      // Find the plugin
      MCPPlugin? plugin;
      for (final typeMap in _plugins.values) {
        if (typeMap.containsKey(pluginName)) {
          plugin = typeMap[pluginName];
          break;
        }
      }

      if (plugin != null) {
        try {
          await plugin.shutdown();
        } catch (e) {
          _logger.error('Error shutting down plugin $pluginName', e);
          errors[pluginName] = e;
        }
      }
    }

    // Clear registries
    _plugins.clear();
    _configurations.clear();
    _dependencies.clear();
    _loadOrder.clear();
    _servers.clear();
    _clients.clear();

    if (errors.isNotEmpty) {
      throw MCPException('Errors occurred while shutting down plugins: $errors');
    }
  }

  /// Get all registered plugins
  List<MCPPlugin> getAllPlugins() {
    final plugins = <MCPPlugin>[];

    for (final typeMap in _plugins.values) {
      plugins.addAll(typeMap.values);
    }

    return plugins;
  }

  /// Get all plugin names
  List<String> getAllPluginNames() {
    return _loadOrder;
  }

  /// Get plugin configuration
  Map<String, dynamic>? getPluginConfiguration(String pluginName) {
    return _configurations[pluginName];
  }

  /// Update plugin configuration
  Future<void> updatePluginConfiguration(String pluginName, Map<String, dynamic> config) async {
    // Find the plugin
    MCPPlugin? plugin;
    for (final typeMap in _plugins.values) {
      if (typeMap.containsKey(pluginName)) {
        plugin = typeMap[pluginName];
        break;
      }
    }

    if (plugin == null) {
      throw MCPException('Plugin not found: $pluginName');
    }

    // Update configuration
    _configurations[pluginName] = config;

    // Re-initialize the plugin
    try {
      await plugin.shutdown();
      await plugin.initialize(config);
      _logger.info('Plugin $pluginName configuration updated successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to update plugin configuration', e, stackTrace);
      throw MCPOperationFailedException(
        'Failed to update plugin configuration',
        e,
        stackTrace,
      );
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
    } else if (plugin is MCPClientPlugin) {
      return 'Client';
    } else if (plugin is MCPServerPlugin) {
      return 'Server';
    } else {
      return 'Basic';
    }
  }
}