import '../utils/error_recovery.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../platform/tray/tray_manager.dart';
import 'package:mcp_llm/mcp_llm.dart' as mcp_llm;
import 'dart:async';
import 'dart:convert';

/// Base plugin interface for all MCP plugins
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

/// MCP Prompt plugin interface
abstract class MCPPromptPlugin extends MCPPlugin {
  /// Execute the prompt with arguments
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments);

  /// Get prompt metadata including arguments
  Map<String, dynamic> getPromptMetadata();
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

/// MCP Tray plugin interface
abstract class MCPTrayPlugin extends MCPPlugin {
  /// Set tray icon
  Future<void> setIcon(String iconPath);

  /// Set tray tooltip
  Future<void> setTooltip(String tooltip);

  /// Set tray menu items
  Future<void> setMenuItems(List<TrayMenuItem> items);

  /// Show the tray icon
  Future<void> show();

  /// Hide the tray icon
  Future<void> hide();

  /// Check if tray is supported on current platform
  bool get isSupported;
}

/// MCP Plugin registry
class MCPPluginRegistry {
  final Logger _logger = Logger('flutter_mcp.plugin_registry');

  /// Registered plugins by type and name
  final Map<Type, Map<String, MCPPlugin>> _plugins = {};

  /// Plugin configurations
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// Plugin dependencies
  final Map<String, List<String>> _dependencies = {};

  /// Plugin load order
  final List<String> _loadOrder = [];

  /// Register a plugin
  Future<void> registerPlugin(MCPPlugin plugin, [Map<String, dynamic>? config]) async {
    final pluginType = plugin.runtimeType;
    final typeName = _getPluginTypeName(plugin);
    final pluginName = plugin.name;

    _logger.fine('Registering $typeName plugin: $pluginName v${plugin.version}');

    // Initialize plugin type map if not exists
    _plugins.putIfAbsent(pluginType, () => {});

    // Check if plugin with same name already exists
    if (_plugins[pluginType]!.containsKey(pluginName)) {
      _logger.warning('Plugin $pluginName already registered');
      throw MCPPluginException(
        pluginName,
        'Plugin with name "$pluginName" is already registered',
      );
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

      _logger.info('Plugin $pluginName successfully initialized');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize plugin $pluginName', e, stackTrace);
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
    _logger.fine('Unregistering plugin: $pluginName');

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
    } catch (e, stackTrace) {
      _logger.severe('Failed to shutdown plugin $pluginName', e, stackTrace);
      // Continue with cleanup even if shutdown failed
    }
    
    // Always clean up resources regardless of shutdown result
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
      return await ErrorRecovery.tryWithRetry(
            () => plugin.execute(arguments),
        operationName: 'Execute tool plugin $name',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.severe('Error executing tool plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error executing tool plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Execute a prompt plugin
  Future<Map<String, dynamic>> executePrompt(String name, Map<String, dynamic> arguments) async {
    final plugin = getPlugin<MCPPromptPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Prompt plugin not found');
    }

    try {
      return await ErrorRecovery.tryWithRetry(
            () => plugin.execute(arguments),
        operationName: 'Execute prompt plugin $name',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.severe('Error executing prompt plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error executing prompt plugin: ${e.toString()}',
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
      _logger.severe('Error getting resource from plugin $name', e, stackTrace);
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
      _logger.severe('Error showing notification with plugin $name', e, stackTrace);
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
      _logger.severe('Error starting background plugin $name', e, stackTrace);
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
      _logger.severe('Error stopping background plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error stopping background plugin: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Update tray icon using a tray plugin
  Future<void> updateTrayIcon(String name, String iconPath) async {
    final plugin = getPlugin<MCPTrayPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Tray plugin not found');
    }

    try {
      await plugin.setIcon(iconPath);
    } catch (e, stackTrace) {
      _logger.severe('Error updating tray icon with plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error updating tray icon: ${e.toString()}',
        e,
        stackTrace,
      );
    }
  }

  /// Set tray menu items using a tray plugin
  Future<void> setTrayMenuItems(String name, List<TrayMenuItem> items) async {
    final plugin = getPlugin<MCPTrayPlugin>(name);

    if (plugin == null) {
      throw MCPPluginException(name, 'Tray plugin not found');
    }

    try {
      await plugin.setMenuItems(items);
    } catch (e, stackTrace) {
      _logger.severe('Error setting tray menu items with plugin $name', e, stackTrace);
      throw MCPPluginException(
        name,
        'Error setting tray menu items: ${e.toString()}',
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
    _logger.fine('Shutting down all plugins');

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
          _logger.severe('Error shutting down plugin $pluginName', e);
          errors[pluginName] = e;
        }
      }
    }

    // Clear registries
    _plugins.clear();
    _configurations.clear();
    _dependencies.clear();
    _loadOrder.clear();

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
      _logger.severe('Failed to update plugin configuration', e, stackTrace);
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
    } else if (plugin is MCPPromptPlugin) {
      return 'Prompt';
    } else if (plugin is MCPBackgroundPlugin) {
      return 'Background';
    } else if (plugin is MCPNotificationPlugin) {
      return 'Notification';
    } else if (plugin is MCPTrayPlugin) {
      return 'Tray';
    } else {
      return 'Basic';
    }
  }
}

/// Adapters for mcp_llm plugins to be used in flutter_mcp

/// Adapter for mcp_llm.ToolPlugin to MCPToolPlugin
class LlmToolPluginAdapter implements MCPToolPlugin {
  final mcp_llm.ToolPlugin _llmToolPlugin;

  LlmToolPluginAdapter(this._llmToolPlugin);

  @override
  String get name => _llmToolPlugin.name;

  @override
  String get version => _llmToolPlugin.version;

  @override
  String get description => _llmToolPlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) => _llmToolPlugin.initialize(config);

  @override
  Future<void> shutdown() => _llmToolPlugin.shutdown();

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    final result = await _llmToolPlugin.execute(arguments);
    return _convertToolResult(result);
  }

  @override
  Map<String, dynamic> getToolMetadata() {
    final toolDef = _llmToolPlugin.getToolDefinition();
    return {
      'name': toolDef.name,
      'description': toolDef.description,
      'inputSchema': toolDef.inputSchema,
    };
  }

  Map<String, dynamic> _convertToolResult(mcp_llm.LlmCallToolResult result) {
    if (result.content.isEmpty) return {};

    if (result.content.first is mcp_llm.LlmTextContent) {
      final textContent = result.content.first as mcp_llm.LlmTextContent;

      try {
        return jsonDecode(textContent.text);
      } catch (e) {
        // Text content is not valid JSON, return as plain text result
        Logger('flutter_mcp.plugin_system').finest('Tool result is not JSON, returning as text: $e');
        return {'result': textContent.text};
      }
    }

    return {'contents': result.content.map((c) => c.toJson()).toList()};
  }
}

/// Adapter for mcp_llm.ResourcePlugin to MCPResourcePlugin
class LlmResourcePluginAdapter implements MCPResourcePlugin {
  final mcp_llm.ResourcePlugin _llmResourcePlugin;

  LlmResourcePluginAdapter(this._llmResourcePlugin);

  @override
  String get name => _llmResourcePlugin.name;

  @override
  String get version => _llmResourcePlugin.version;

  @override
  String get description => _llmResourcePlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) => _llmResourcePlugin.initialize(config);

  @override
  Future<void> shutdown() => _llmResourcePlugin.shutdown();

  @override
  Future<Map<String, dynamic>> getResource(String resourceUri, Map<String, dynamic> params) async {
    final result = await _llmResourcePlugin.read(params);
    return {
      'content': result.content,
      'mimeType': result.mimeType,
      'contents': result.contents.map((c) => c.toJson()).toList(),
    };
  }

  @override
  Map<String, dynamic> getResourceMetadata() {
    final resourceDef = _llmResourcePlugin.getResourceDefinition();
    return {
      'name': resourceDef.name,
      'description': resourceDef.description,
      'uri': resourceDef.uri,
      'mimeType': resourceDef.mimeType,
    };
  }
}

/// Adapter for mcp_llm.PromptPlugin to MCPPromptPlugin
class LlmPromptPluginAdapter implements MCPPromptPlugin {
  final mcp_llm.PromptPlugin _llmPromptPlugin;

  LlmPromptPluginAdapter(this._llmPromptPlugin);

  @override
  String get name => _llmPromptPlugin.name;

  @override
  String get version => _llmPromptPlugin.version;

  @override
  String get description => _llmPromptPlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) => _llmPromptPlugin.initialize(config);

  @override
  Future<void> shutdown() => _llmPromptPlugin.shutdown();

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    final result = await _llmPromptPlugin.execute(arguments);
    return {
      'description': result.description,
      'messages': result.messages.map((m) => m.toJson()).toList(),
    };
  }

  @override
  Map<String, dynamic> getPromptMetadata() {
    final promptDef = _llmPromptPlugin.getPromptDefinition();
    return {
      'name': promptDef.name,
      'description': promptDef.description,
      'arguments': promptDef.arguments.map((arg) => {
        'name': arg.name,
        'description': arg.description,
        'required': arg.required,
        'default': arg.defaultValue,
      }).toList(),
    };
  }
}