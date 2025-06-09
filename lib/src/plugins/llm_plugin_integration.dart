// Enhanced Plugin Integration for flutter_mcp and mcp_llm
// This file includes improvements to bridge the gap between flutter_mcp plugin system
// and mcp_llm plugin system

import 'dart:async';
import 'package:mcp_llm/mcp_llm.dart' as llm;

import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'plugin_system.dart';
import 'dart:convert' show json;

/// Enhanced manager for integrating mcp_llm plugins with flutter_mcp
class LlmPluginIntegrator {
  final Logger _logger = Logger('flutter_mcp.llm_plugin_integrator');
  final MCPPluginRegistry _pluginRegistry;

  // Cache of registered LLM plugins
  final Map<String, llm.LlmPlugin> _llmPluginsCache = {};

  // Track mappings between mcp_llm plugins and flutter_mcp plugins
  final Map<String, String> _llmToMcpPluginMap = {};
  final Map<String, String> _mcpToLlmPluginMap = {};

  LlmPluginIntegrator(this._pluginRegistry);

  /// Register an mcp_llm plugin with flutter_mcp plugin system
  Future<bool> registerLlmPlugin(llm.LlmPlugin llmPlugin, [Map<String, dynamic>? config]) async {
    final String llmPluginName = llmPlugin.name;

    try {
      _logger.fine('Registering mcp_llm plugin as flutter_mcp plugin: $llmPluginName');

      // Create appropriate adapter based on plugin type
      MCPPlugin mcpPlugin;

      if (llmPlugin is llm.ToolPlugin) {
        mcpPlugin = LlmToolPluginAdapter(llmPlugin);
      } else if (llmPlugin is llm.ResourcePlugin) {
        mcpPlugin = LlmResourcePluginAdapter(llmPlugin);
      } else if (llmPlugin is llm.PromptPlugin) {
        mcpPlugin = LlmPromptPluginAdapter(llmPlugin);
      } else {
        throw MCPValidationException(
            'Unsupported LLM plugin type: ${llmPlugin.runtimeType}',
            {'plugin_type': llmPlugin.runtimeType.toString()}
        );
      }

      // Register the adapter with the plugin registry
      await _pluginRegistry.registerPlugin(mcpPlugin, config);

      // Cache the LLM plugin
      _llmPluginsCache[llmPluginName] = llmPlugin;

      // Track mappings
      _llmToMcpPluginMap[llmPluginName] = mcpPlugin.name;
      _mcpToLlmPluginMap[mcpPlugin.name] = llmPluginName;

      _logger.info('Successfully registered mcp_llm plugin $llmPluginName as flutter_mcp plugin ${mcpPlugin.name}');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to register mcp_llm plugin: $llmPluginName', e, stackTrace);
      return false;
    }
  }

  /// Register multiple mcp_llm plugins at once
  Future<Map<String, bool>> registerLlmPlugins(
      List<llm.LlmPlugin> llmPlugins,
      [Map<String, Map<String, dynamic>>? configs]
      ) async {
    final results = <String, bool>{};

    for (final plugin in llmPlugins) {
      final config = configs != null ? configs[plugin.name] : null;
      results[plugin.name] = await registerLlmPlugin(plugin, config);
    }

    return results;
  }

  /// Register mcp_llm plugins from an LLM client
  Future<Map<String, bool>> registerPluginsFromLlmClient(
      String llmClientId,
      llm.LlmClient llmClient
      ) async {
    try {
      final pluginManager = llmClient.pluginManager;

      // Get all tools from plugin manager
      final toolPlugins = pluginManager.getAllToolPlugins();

      // Get all prompt plugins
      final promptPlugins = pluginManager.getAllPromptPlugins();

      // Get all resource plugins
      final resourcePlugins = pluginManager.getAllResourcePlugins();

      // Combine all plugins
      final allPlugins = <llm.LlmPlugin>[
        ...toolPlugins,
        ...promptPlugins,
        ...resourcePlugins
      ];

      // Register all plugins
      final results = await registerLlmPlugins(allPlugins);

      _logger.info('Registered ${results.values.where((v) => v).length}/${allPlugins.length} plugins from LLM client $llmClientId');

      return results;
    } catch (e, stackTrace) {
      _logger.severe('Failed to register plugins from LLM client $llmClientId', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM client $llmClientId',
          e,
          stackTrace
      );
    }
  }

  /// Register mcp_llm plugins from an LLM server
  Future<Map<String, bool>> registerPluginsFromLlmServer(
      String llmServerId,
      llm.LlmServer llmServer
      ) async {
    try {
      final pluginManager = llmServer.pluginManager;

      // Get all tools from plugin manager
      final toolPlugins = pluginManager.getAllToolPlugins();

      // Get all prompt plugins
      final promptPlugins = pluginManager.getAllPromptPlugins();

      // Get all resource plugins
      final resourcePlugins = pluginManager.getAllResourcePlugins();

      // Combine all plugins
      final allPlugins = <llm.LlmPlugin>[
        ...toolPlugins,
        ...promptPlugins,
        ...resourcePlugins
      ];

      // Register all plugins
      final results = await registerLlmPlugins(allPlugins);

      _logger.info('Registered ${results.values.where((v) => v).length}/${allPlugins.length} plugins from LLM server $llmServerId');

      return results;
    } catch (e, stackTrace) {
      _logger.severe('Failed to register plugins from LLM server $llmServerId', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM server $llmServerId',
          e,
          stackTrace
      );
    }
  }

  /// Register mcp_llm core plugins with flutter_mcp
  Future<Map<String, bool>> registerCoreLlmPlugins(
      llm.LlmInterface llmProvider,
      llm.RetrievalManager? retrievalManager,
      {
        bool includeCompletionPlugin = true,
        bool includeStreamingPlugin = true,
        bool includeEmbeddingPlugin = true,
        bool includeRetrievalPlugins = true,
      }
      ) async {
    try {
      // Create performance monitor just for the plugin creation
      final performanceMonitor = llm.PerformanceMonitor();

      // Create core plugins
      final plugins = llm.CoreLlmPluginFactory.createCorePlugins(
        llmProvider: llmProvider,
        retrievalManager: retrievalManager,
        performanceMonitor: performanceMonitor,
        includeCompletionPlugin: includeCompletionPlugin,
        includeStreamingPlugin: includeStreamingPlugin,
        includeEmbeddingPlugin: includeEmbeddingPlugin,
        includeRetrievalPlugins: includeRetrievalPlugins && retrievalManager != null,
      );

      // Register all plugins
      final results = await registerLlmPlugins(plugins);

      _logger.info('Registered ${results.values.where((v) => v).length}/${plugins.length} core LLM plugins');

      return results;
    } catch (e, stackTrace) {
      _logger.severe('Failed to register core LLM plugins', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register core LLM plugins',
          e,
          stackTrace
      );
    }
  }

  /// Create mcp_llm plugin manager with flutter_mcp plugins
  llm.PluginManager createLlmPluginManagerWithMcpPlugins() {
    final llmPluginManager = llm.PluginManager();

    // Add plugin adapters to mcp_llm's plugin manager
    _registerMcpPluginsToLlmManager(llmPluginManager);

    return llmPluginManager;
  }

  /// Register flutter_mcp plugins to an mcp_llm plugin manager
  Future<void> _registerMcpPluginsToLlmManager(llm.PluginManager llmPluginManager) async {
    // Get all tool plugins from flutter_mcp
    final toolPlugins = _pluginRegistry.getPluginsByType<MCPToolPlugin>();

    // Create and register adapters for each tool plugin
    for (final toolPlugin in toolPlugins) {
      // Skip if it's already an adapter for an LLM plugin
      if (toolPlugin is LlmToolPluginAdapter) continue;

      // Create adapter
      final adapter = McpToolPluginAdapter(toolPlugin);

      // Register with mcp_llm plugin manager
      await llmPluginManager.registerPlugin(adapter);

      _logger.fine('Registered flutter_mcp tool plugin ${toolPlugin.name} with LLM plugin manager');
    }

    // Get all resource plugins from flutter_mcp
    final resourcePlugins = _pluginRegistry.getPluginsByType<MCPResourcePlugin>();

    // Create and register adapters for each resource plugin
    for (final resourcePlugin in resourcePlugins) {
      // Skip if it's already an adapter for an LLM plugin
      if (resourcePlugin is LlmResourcePluginAdapter) continue;

      // Create adapter
      final adapter = McpResourcePluginAdapter(resourcePlugin);

      // Register with mcp_llm plugin manager
      await llmPluginManager.registerPlugin(adapter);

      _logger.fine('Registered flutter_mcp resource plugin ${resourcePlugin.name} with LLM plugin manager');
    }

    // Get all prompt plugins from flutter_mcp
    final promptPlugins = _pluginRegistry.getPluginsByType<MCPPromptPlugin>();

    // Create and register adapters for each prompt plugin
    for (final promptPlugin in promptPlugins) {
      // Skip if it's already an adapter for an LLM plugin
      if (promptPlugin is LlmPromptPluginAdapter) continue;

      // Create adapter
      final adapter = McpPromptPluginAdapter(promptPlugin);

      // Register with mcp_llm plugin manager
      await llmPluginManager.registerPlugin(adapter);

      _logger.fine('Registered flutter_mcp prompt plugin ${promptPlugin.name} with LLM plugin manager');
    }
  }

  /// Get LLM plugin by name
  llm.LlmPlugin? getLlmPlugin(String name) {
    return _llmPluginsCache[name];
  }

  /// Get MCP plugin name for LLM plugin
  String? getMcpPluginNameForLlmPlugin(String llmPluginName) {
    return _llmToMcpPluginMap[llmPluginName];
  }

  /// Get LLM plugin name for MCP plugin
  String? getLlmPluginNameForMcpPlugin(String mcpPluginName) {
    return _mcpToLlmPluginMap[mcpPluginName];
  }

  /// Unregister an LLM plugin
  Future<bool> unregisterLlmPlugin(String llmPluginName) async {
    try {
      // Check if plugin exists
      if (!_llmPluginsCache.containsKey(llmPluginName)) {
        _logger.warning('LLM plugin not found: $llmPluginName');
        return false;
      }

      // Get MCP plugin name
      final mcpPluginName = _llmToMcpPluginMap[llmPluginName];
      if (mcpPluginName == null) {
        _logger.warning('No MCP plugin mapping found for LLM plugin: $llmPluginName');
        return false;
      }

      // Unregister from plugin registry
      await _pluginRegistry.unregisterPlugin(mcpPluginName);

      // Clean up caches
      _llmPluginsCache.remove(llmPluginName);
      _llmToMcpPluginMap.remove(llmPluginName);
      _mcpToLlmPluginMap.remove(mcpPluginName);

      _logger.info('Successfully unregistered LLM plugin: $llmPluginName');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to unregister LLM plugin: $llmPluginName', e, stackTrace);
      return false;
    }
  }

  /// List all registered LLM plugins
  List<String> getRegisteredLlmPluginNames() {
    return _llmPluginsCache.keys.toList();
  }

  /// Clean up resources
  Future<void> shutdown() async {
    _logger.fine('Shutting down LLM Plugin Integrator');

    // Clear caches
    _llmPluginsCache.clear();
    _llmToMcpPluginMap.clear();
    _mcpToLlmPluginMap.clear();
  }
}

/// Adapter from flutter_mcp MCPToolPlugin to mcp_llm ToolPlugin
class McpToolPluginAdapter implements llm.ToolPlugin {
  final MCPToolPlugin _mcpToolPlugin;
  final Logger _logger = Logger('flutter_mcp.adapter.mcp_tool_plugin');

  McpToolPluginAdapter(this._mcpToolPlugin);

  @override
  String get name => _mcpToolPlugin.name;

  @override
  String get version => _mcpToolPlugin.version;

  @override
  String get description => _mcpToolPlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Nothing to do - the MCP plugin is already initialized
  }

  @override
  Future<void> shutdown() async {
    // Nothing to do - handled by the MCPPluginRegistry
  }

  @override
  llm.LlmTool getToolDefinition() {
    final metadata = _mcpToolPlugin.getToolMetadata();

    return llm.LlmTool(
      name: metadata['name'] as String,
      description: metadata['description'] as String,
      inputSchema: metadata['inputSchema'] as Map<String, dynamic>,
    );
  }

  @override
  Future<llm.LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final result = await _mcpToolPlugin.execute(arguments);

      // Convert to LlmCallToolResult
      return _convertToLlmCallToolResult(result);
    } catch (e, stackTrace) {
      _logger.severe('Error executing MCP tool plugin ${_mcpToolPlugin.name}', e, stackTrace);
      return llm.LlmCallToolResult(
        [llm.LlmTextContent(text: 'Error: ${e.toString()}')],
        isError: true,
      );
    }
  }

  /// Convert from MCP result to LLM CallToolResult
  llm.LlmCallToolResult _convertToLlmCallToolResult(Map<String, dynamic> mcpResult) {
    // Extract result as text if possible
    String resultText = '';

    if (mcpResult.containsKey('result') && mcpResult['result'] is String) {
      resultText = mcpResult['result'] as String;
    } else {
      // Serialize to JSON
      resultText = jsonify(mcpResult);
    }

    // Create and return result
    return llm.LlmCallToolResult(
      [llm.LlmTextContent(text: resultText)],
    );
  }

  /// Convert complex object to JSON string
  String jsonify(Object object) {
    try {
      return json.encode(object);
    } catch (e) {
      return object.toString();
    }
  }
}

/// Adapter from flutter_mcp MCPResourcePlugin to mcp_llm ResourcePlugin
class McpResourcePluginAdapter implements llm.ResourcePlugin {
  final MCPResourcePlugin _mcpResourcePlugin;
  final Logger _logger = Logger('flutter_mcp.adapter.mcp_resource_plugin');

  McpResourcePluginAdapter(this._mcpResourcePlugin);

  @override
  String get name => _mcpResourcePlugin.name;

  @override
  String get version => _mcpResourcePlugin.version;

  @override
  String get description => _mcpResourcePlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Nothing to do - the MCP plugin is already initialized
  }

  @override
  Future<void> shutdown() async {
    // Nothing to do - handled by the MCPPluginRegistry
  }

  @override
  llm.LlmResource getResourceDefinition() {
    final metadata = _mcpResourcePlugin.getResourceMetadata();

    return llm.LlmResource(
      name: metadata['name'] as String,
      description: metadata['description'] as String,
      uri: metadata['uri'] as String,
      mimeType: metadata['mimeType'] as String?,
    );
  }

  @override
  Future<llm.LlmReadResourceResult> read(Map<String, dynamic> parameters) async {
    try {
      final result = await _mcpResourcePlugin.getResource(
        parameters['uri'] as String? ?? getResourceDefinition().uri,
        parameters,
      );

      // Convert to LlmReadResourceResult
      return _convertToLlmReadResourceResult(result);
    } catch (e, stackTrace) {
      _logger.severe('Error reading from MCP resource plugin ${_mcpResourcePlugin.name}', e, stackTrace);
      return llm.LlmReadResourceResult(
        content: 'Error: ${e.toString()}',
        mimeType: 'text/plain',
        contents: [llm.LlmTextContent(text: 'Error: ${e.toString()}')],
      );
    }
  }

  /// Convert from MCP result to LLM ReadResourceResult
  llm.LlmReadResourceResult _convertToLlmReadResourceResult(Map<String, dynamic> mcpResult) {
    // Extract content and mime type
    final content = mcpResult['content'] as String? ?? '';
    final mimeType = mcpResult['mimeType'] as String? ?? 'text/plain';

    // Create contents list
    final List<llm.LLmContent> contents = [];

    if (mcpResult.containsKey('contents') && mcpResult['contents'] is List) {
      // Use provided contents if available
      final contentsList = mcpResult['contents'] as List;
      for (final contentItem in contentsList) {
        if (contentItem is Map<String, dynamic>) {
          // Parse content item based on type
          if (contentItem['type'] == 'text') {
            contents.add(llm.LlmTextContent(text: contentItem['text'] as String));
          } else if (contentItem['type'] == 'image') {
            contents.add(llm.LlmImageContent(
              url: contentItem['url'] as String,
              mimeType: contentItem['mimeType'] as String,
            ));
          } else if (contentItem['type'] == 'resource') {
            contents.add(llm.LlmResourceContent(
              uri: contentItem['uri'] as String,
              text: contentItem['text'] as String?,
            ));
          }
        }
      }
    } else {
      // Create default text content
      contents.add(llm.LlmTextContent(text: content));
    }

    // Create and return result
    return llm.LlmReadResourceResult(
      content: content,
      mimeType: mimeType,
      contents: contents,
    );
  }
}

/// Adapter from flutter_mcp MCPPromptPlugin to mcp_llm PromptPlugin
class McpPromptPluginAdapter implements llm.PromptPlugin {
  final MCPPromptPlugin _mcpPromptPlugin;
  final Logger _logger = Logger('flutter_mcp.adapter.mcp_prompt_plugin');

  McpPromptPluginAdapter(this._mcpPromptPlugin);

  @override
  String get name => _mcpPromptPlugin.name;

  @override
  String get version => _mcpPromptPlugin.version;

  @override
  String get description => _mcpPromptPlugin.description;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Nothing to do - the MCP plugin is already initialized
  }

  @override
  Future<void> shutdown() async {
    // Nothing to do - handled by the MCPPluginRegistry
  }

  @override
  llm.LlmPrompt getPromptDefinition() {
    final metadata = _mcpPromptPlugin.getPromptMetadata();

    final arguments = <llm.LlmPromptArgument>[];
    final argsList = metadata['arguments'] as List<dynamic>;

    for (final arg in argsList) {
      if (arg is Map<String, dynamic>) {
        arguments.add(llm.LlmPromptArgument(
          name: arg['name'] as String,
          description: arg['description'] as String,
          required: arg['required'] as bool? ?? false,
          defaultValue: arg['default'] as String?,
        ));
      }
    }

    return llm.LlmPrompt(
      name: metadata['name'] as String,
      description: metadata['description'] as String,
      arguments: arguments,
    );
  }

  @override
  Future<llm.LlmGetPromptResult> execute(Map<String, dynamic> arguments) async {
    try {
      final result = await _mcpPromptPlugin.execute(arguments);

      // Convert to LlmGetPromptResult
      return _convertToLlmGetPromptResult(result);
    } catch (e, stackTrace) {
      _logger.severe('Error executing MCP prompt plugin ${_mcpPromptPlugin.name}', e, stackTrace);
      return llm.LlmGetPromptResult(
        description: 'Error: ${e.toString()}',
        messages: [llm.LlmMessage.system('Error: ${e.toString()}')],
      );
    }
  }

  /// Convert from MCP result to LLM GetPromptResult
  llm.LlmGetPromptResult _convertToLlmGetPromptResult(Map<String, dynamic> mcpResult) {
    // Extract description
    final description = mcpResult['description'] as String? ?? '';

    // Extract messages
    final List<llm.LlmMessage> messages = [];

    if (mcpResult.containsKey('messages') && mcpResult['messages'] is List) {
      final messagesList = mcpResult['messages'] as List;
      for (final messageItem in messagesList) {
        if (messageItem is Map<String, dynamic>) {
          // Create message based on role
          final role = messageItem['role'] as String? ?? 'user';
          final content = messageItem['content'] as String? ?? '';

          switch (role) {
            case 'system':
              messages.add(llm.LlmMessage.system(content));
              break;
            case 'user':
              messages.add(llm.LlmMessage.user(content));
              break;
            case 'assistant':
              messages.add(llm.LlmMessage.assistant(content));
              break;
            default:
              messages.add(llm.LlmMessage.user(content));
          }
        }
      }
    }

    // If no messages, add a default one
    if (messages.isEmpty) {
      messages.add(llm.LlmMessage.system(description));
    }

    // Create and return result
    return llm.LlmGetPromptResult(
      description: description,
      messages: messages,
    );
  }
}
