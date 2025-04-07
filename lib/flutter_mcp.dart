import 'dart:async';
import 'package:flutter_mcp/src/utils/error_recovery.dart';
import 'package:mcp_client/mcp_client.dart' as client hide LogLevel;
import 'package:mcp_server/mcp_server.dart' as server hide LogLevel;
import 'package:mcp_llm/mcp_llm.dart' as llm hide LogLevel;

import 'src/config/mcp_config.dart';
import 'src/config/job.dart';
import 'src/core/client_manager.dart';
import 'src/core/server_manager.dart';
import 'src/core/llm_manager.dart';
import 'src/core/scheduler.dart';
import 'src/platform/platform_services.dart';
import 'src/utils/logger.dart';
import 'src/utils/exceptions.dart';
import 'src/plugins/plugin_system.dart';
import 'src/utils/resource_manager.dart';
import 'src/utils/performance_monitor.dart';
import 'src/utils/event_system.dart';
import 'src/utils/memory_manager.dart';

// Re-export configuration classes
export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/job.dart';

// Re-export utility classes
export 'src/utils/exceptions.dart';
export 'src/utils/logger.dart';

// Re-export plugin interfaces
export 'src/plugins/plugin_system.dart' show MCPPlugin, MCPToolPlugin, MCPResourcePlugin,
MCPBackgroundPlugin, MCPNotificationPlugin, MCPClientPlugin, MCPServerPlugin;

// Re-export tray menu classes
export 'src/platform/tray/tray_manager.dart' show TrayMenuItem;

// Re-export model classes from original packages (with type aliases)
// This way apps using flutter_mcp don't need to import the original packages

// MCP Client exports
export 'package:mcp_client/mcp_client.dart'
    show ClientCapabilities, Client, ClientTransport;

// MCP Server exports
export 'package:mcp_server/mcp_server.dart'
    show ServerCapabilities, Server, ServerTransport,
    Content, TextContent, ImageContent, ResourceContent,
    Tool, Resource, Message, MessageRole, MCPContentType, CallToolResult;

// MCP LLM exports
export 'package:mcp_llm/mcp_llm.dart'
    show LlmConfiguration, LlmResponse, LlmToolCall, LlmResponseChunk,
    Document, StorageManager, RetrievalManager, ResultAggregator,
    ChatSession, Conversation, MemoryStorage;

/// Flutter MCP - Integrated MCP Management System
///
/// A package that integrates MCP components (mcp_client, mcp_server, mcp_llm)
/// and adds various platform features (background execution, notifications, system tray)
/// for Flutter environments.
class FlutterMCP {
  // Singleton instance
  static final FlutterMCP _instance = FlutterMCP._();

  /// Singleton instance accessor
  static FlutterMCP get instance => _instance;

  // Private constructor
  FlutterMCP._();

  // Core components
  final MCPClientManager _clientManager = MCPClientManager();
  final MCPServerManager _serverManager = MCPServerManager();
  final MCPLlmManager _llmManager = MCPLlmManager();

  // Multiple MCP LLM instances
  final Map<String, llm.MCPLlm> _mcpLlmInstances = {};

  // Platform services
  final PlatformServices _platformServices = PlatformServices();

  // Task scheduler
  final MCPScheduler _scheduler = MCPScheduler();

  // Plugin registry
  final MCPPluginRegistry _pluginRegistry = MCPPluginRegistry();

  // Resource manager for cleanup
  final ResourceManager _resourceManager = ResourceManager();

  // Event system for communication
  final EventSystem _eventSystem = EventSystem.instance;

  // Memory cache for LLM responses
  final Map<String, dynamic> _llmResponseCaches = {};

  // Plugin state
  bool _initialized = false;
  MCPConfig? _config;

  // Shutdown hook registered flag
  bool _shutdownHookRegistered = false;

  // Integrated logger
  static final MCPLogger _logger = MCPLogger('flutter_mcp');

  /// Initialize the plugin
  ///
  /// [config] specifies the configuration for necessary components.
  Future<void> init(MCPConfig config) async {
    if (_initialized) {
      _logger.warning('Flutter MCP is already initialized');
      return;
    }

    _config = config;

    // Initialize logging setup
    if (config.loggingLevel != null) {
      MCPLogger.setDefaultLevel(config.loggingLevel!);
    }

    _logger.info('Flutter MCP initialization started');

    // Start performance monitoring if enabled
    if (config.enablePerformanceMonitoring ?? false) {
      _initializePerformanceMonitoring();
    }

    try {
      // Register shutdown hook for proper cleanup
      _registerShutdownHook();

      // Initialize memory management if configured
      if (config.highMemoryThresholdMB != null) {
        _initializeMemoryManagement(config.highMemoryThresholdMB!);
      }

      // Create default MCP LLM instance
      final defaultLlm = llm.MCPLlm();
      _mcpLlmInstances['default'] = defaultLlm;

      // Register default LLM providers on the default instance
      _registerDefaultProviders(defaultLlm);

      // Initialize platform services
      await _platformServices.initialize(config);

      // Initialize resource manager with platform services
      _resourceManager.registerCallback('platform_services', () => _platformServices.shutdown());

      // Initialize managers
      await _initializeManagers();

      // Initialize scheduler
      if (config.schedule != null && config.schedule!.isNotEmpty) {
        _initializeScheduler(config.schedule!);
      }

      // Initialize plugin registry
      await _initializePluginRegistry();

      // Auto-start configuration
      if (config.autoStart) {
        _logger.info('Starting services based on auto-start configuration');
        await startServices();
      }

      _initialized = true;
      _logger.info('Flutter MCP initialization completed');
    } catch (e, stackTrace) {
      _logger.error('Flutter MCP initialization failed', e, stackTrace);

      // Clean up any resources that were initialized
      await _cleanup();

      throw MCPInitializationException('Flutter MCP initialization failed', e, stackTrace);
    }
  }

  /// Initialize memory management
  void _initializeMemoryManagement(int highMemoryThresholdMB) {
    _logger.debug('Initializing memory management with threshold: $highMemoryThresholdMB MB');

    MemoryManager.instance.initialize(
      startMonitoring: true,
      highMemoryThresholdMB: highMemoryThresholdMB,
      monitoringInterval: Duration(seconds: 30),
    );

    // Register memory manager for cleanup
    _resourceManager.registerCallback('memory_manager', () async {
      MemoryManager.instance.dispose();
    });

    // Add high memory callback
    MemoryManager.instance.addHighMemoryCallback(() async {
      _logger.warning('High memory usage detected, triggering cleanup');
      // Perform memory cleanup operations
      await _performMemoryCleanup();
    });
  }

  /// Perform memory cleanup when usage is high
  Future<void> _performMemoryCleanup() async {
    _logger.debug('Performing memory cleanup');

    try {
      // 1. Clear any non-essential caches
      final llmIds = _llmManager.getAllLlmIds();
      for (final llmId in llmIds) {
        // Here you would clear any caches specific to LLM instances
        // This is where you'd integrate with caching solutions used in your LLM wrapper
        _logger.debug('Clearing caches for LLM: $llmId');
      }

      // 2. Release any disposed but not yet garbage collected resources
      _logger.debug('Suggesting resource cleanup to garbage collector');

      // 3. Clear performance monitoring history to free memory
      if (_config?.enablePerformanceMonitoring ?? false) {
        _logger.debug('Clearing performance monitoring history');
        PerformanceMonitor.instance.reset();
      }

      // 4. Publish memory cleanup event for other components to respond
      _eventSystem.publish('memory.cleanup', {
        'timestamp': DateTime.now().toIso8601String(),
        'currentMemoryMB': MemoryManager.instance.currentMemoryUsageMB,
        'peakMemoryMB': MemoryManager.instance.peakMemoryUsageMB,
      });

      _logger.debug('Memory cleanup completed');
    } catch (e, stackTrace) {
      _logger.error('Error during memory cleanup', e, stackTrace);
    }
  }

  /// Initialize core managers
  Future<void> _initializeManagers() async {
    // Initialize in parallel for efficiency
    await Future.wait([
      _clientManager.initialize(),
      _serverManager.initialize(),
      _llmManager.initialize(),
    ]);

    // Register for cleanup
    _resourceManager.registerCallback('client_manager', () => _clientManager.closeAll());
    _resourceManager.registerCallback('server_manager', () => _serverManager.closeAll());
    _resourceManager.registerCallback('llm_manager', () => _llmManager.closeAll());
  }

  /// Initialize scheduler
  void _initializeScheduler(List<MCPJob> jobs) {
    _scheduler.initialize();

    for (final job in jobs) {
      _scheduler.addJob(job);
    }

    _scheduler.start();

    // Register for cleanup
    _resourceManager.registerCallback('scheduler', () async {
      _scheduler.stop();
      _scheduler.dispose();
    });
  }

  /// Initialize plugin registry
  Future<void> _initializePluginRegistry() async {
    // Connect the plugin registry with core managers
    for (final serverId in _serverManager.getAllServerIds()) {
      final server = _serverManager.getServer(serverId);
      if (server != null) {
        _pluginRegistry.registerServer(serverId, server);
      }
    }

    for (final clientId in _clientManager.getAllClientIds()) {
      final client = _clientManager.getClient(clientId);
      if (client != null) {
        _pluginRegistry.registerClient(clientId, client);
      }
    }

    // Register for cleanup
    _resourceManager.registerCallback('plugin_registry', () => _pluginRegistry.shutdownAll());
  }

  /// Initialize performance monitoring
  void _initializePerformanceMonitoring() {
    PerformanceMonitor.instance.initialize(
      enableLogging: true,
      enableMetricsExport: _config?.enableMetricsExport ?? false,
      exportPath: _config?.metricsExportPath,
    );

    // Enable caching for certain key events
    PerformanceMonitor.instance.enableCaching('llm.request');
    PerformanceMonitor.instance.enableCaching('llm.response');

    // Register for cleanup
    _resourceManager.registerCallback('performance_monitor', () async {
      await PerformanceMonitor.instance.exportMetrics();
      PerformanceMonitor.instance.dispose();
    });
  }

  /// Register shutdown hook to ensure proper cleanup
  void _registerShutdownHook() {
    if (_shutdownHookRegistered) return;

    // Use platform lifecycle events to register for app shutdown
    _platformServices.setLifecycleChangeListener((state) {
      // On app termination, ensure resources are cleaned up
      if (state.toString().contains('detached') || state.toString().contains('paused')) {
        _cleanup();
      }
    });

    _shutdownHookRegistered = true;
  }

  /// Register default LLM providers with improved error handling
  void _registerDefaultProviders(llm.MCPLlm mcpLlm) {
    _registerProviderSafely(mcpLlm, 'openai', llm.OpenAiProviderFactory());
    _registerProviderSafely(mcpLlm, 'claude', llm.ClaudeProviderFactory());
    _registerProviderSafely(mcpLlm, 'together', llm.TogetherProviderFactory());

    // Register other providers as needed
  }

  /// Safely register an LLM provider with error handling
  void _registerProviderSafely(llm.MCPLlm mcpLlm, String name, llm.LlmProviderFactory factory) {
    try {
      mcpLlm.registerProvider(name, factory);
      _logger.debug('Registered $name provider');
    } catch (e, stackTrace) {
      _logger.warning('Failed to register $name provider', e, stackTrace);

      // Track the failure in performance metrics
      PerformanceMonitor.instance.incrementCounter('provider.registration.failure.$name');
    }
  }

  /// Start services
  Future<void> startServices() async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Start background service
    if (_config!.useBackgroundService) {
      await _platformServices.startBackgroundService();
    }

    // Show notification
    if (_config!.useNotification) {
      await _platformServices.showNotification(
        title: '${_config!.appName} Running',
        body: 'MCP service is running',
      );
    }

    // Start configured components
    await _startConfiguredComponents();
  }

  /// Start configured components with improved error handling
  Future<void> _startConfiguredComponents() async {
    final config = _config!;
    final startErrors = <String, dynamic>{};

    // Start auto-start servers
    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (final serverConfig in config.autoStartServer!) {
        try {
          await _startServer(serverConfig);
        } catch (e, stackTrace) {
          _logger.error('Failed to start server: ${serverConfig.name}', e, stackTrace);
          startErrors['server.${serverConfig.name}'] = e;

          // Track failure
          PerformanceMonitor.instance.incrementCounter('server.start.failure');
        }
      }
    }

    // Start auto-start clients
    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (final clientConfig in config.autoStartClient!) {
        try {
          await _startClient(clientConfig);
        } catch (e, stackTrace) {
          _logger.error('Failed to start client: ${clientConfig.name}', e, stackTrace);
          startErrors['client.${clientConfig.name}'] = e;

          // Track failure
          PerformanceMonitor.instance.incrementCounter('client.start.failure');
        }
      }
    }

    // Report any errors that occurred during startup
    if (startErrors.isNotEmpty) {
      _logger.warning('Some components failed to start: ${startErrors.keys.join(", ")}');

      // Publish start errors event
      _eventSystem.publish('mcp.startup.errors', startErrors);
    }
  }

  /// Start a server from configuration
  Future<String> _startServer(MCPServerConfig serverConfig) async {
    final timer = PerformanceMonitor.instance.startTimer('server.start');

    try {
      final serverId = await createServer(
        name: serverConfig.name,
        version: serverConfig.version,
        capabilities: serverConfig.capabilities,
        useStdioTransport: serverConfig.useStdioTransport,
        ssePort: serverConfig.ssePort,
      );

      // Integrate with LLM if configured
      if (serverConfig.integrateLlm != null) {
        String llmId;

        if (serverConfig.integrateLlm!.existingLlmId != null) {
          llmId = serverConfig.integrateLlm!.existingLlmId!;
        } else {
          llmId = await createLlm(
            providerName: serverConfig.integrateLlm!.providerName!,
            config: serverConfig.integrateLlm!.config!,
          );
        }

        await integrateServerWithLlm(
          serverId: serverId,
          llmId: llmId,
        );
      }

      // Connect server
      connectServer(serverId);

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return serverId;
    } catch (e) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      rethrow;
    }
  }

  /// Start a client from configuration
  Future<String> _startClient(MCPClientConfig clientConfig) async {
    final timer = PerformanceMonitor.instance.startTimer('client.start');

    try {
      final clientId = await createClient(
        name: clientConfig.name,
        version: clientConfig.version,
        capabilities: clientConfig.capabilities,
        transportCommand: clientConfig.transportCommand,
        transportArgs: clientConfig.transportArgs,
        serverUrl: clientConfig.serverUrl,
      );

      // Integrate with LLM if configured
      if (clientConfig.integrateLlm != null) {
        String llmId;

        if (clientConfig.integrateLlm!.existingLlmId != null) {
          llmId = clientConfig.integrateLlm!.existingLlmId!;
        } else {
          llmId = await createLlm(
            providerName: clientConfig.integrateLlm!.providerName!,
            config: clientConfig.integrateLlm!.config!,
          );
        }

        await integrateClientWithLlm(
          clientId: clientId,
          llmId: llmId,
        );
      }

      // Connect client
      await connectClient(clientId);

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return clientId;
    } catch (e) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      rethrow;
    }
  }

  /// Create MCP client with improved error handling
  Future<String> createClient({
    required String name,
    required String version,
    client.ClientCapabilities? capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    String? serverUrl,
    String? authToken,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP client: $name');
    final timer = PerformanceMonitor.instance.startTimer('client.create');

    try {
      // Validate parameters
      if (transportCommand == null && serverUrl == null) {
        throw MCPValidationException(
            'Either transportCommand or serverUrl must be provided',
            {'transport': 'Missing transport configuration'}
        );
      }

      // Create client using McpClient factory
      final clientId = _clientManager.generateId();
      final mcpClient = client.McpClient.createClient(
        name: name,
        version: version,
        capabilities: capabilities ?? client.ClientCapabilities(),
      );

      // Create transport
      client.ClientTransport? transport;
      if (transportCommand != null) {
        transport = await client.McpClient.createStdioTransport(
          command: transportCommand,
          arguments: transportArgs ?? [],
        );
      } else if (serverUrl != null) {
        transport = await client.McpClient.createSseTransport(
          serverUrl: serverUrl,
          headers: authToken != null ? {'Authorization': 'Bearer $authToken'} : null,
        );
      }

      // Register client
      _clientManager.registerClient(clientId, mcpClient, transport);

      // Update plugin registry
      _pluginRegistry.registerClient(clientId, mcpClient);

      // Register for resource cleanup
      _resourceManager.register<client.Client>(
          'client_$clientId',
          mcpClient,
              (c) async => await _clientManager.closeClient(clientId)
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return clientId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to create MCP client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create MCP client: $name',
          e,
          stackTrace
      );
    }
  }

  /// Create MCP server with improved error handling
  Future<String> createServer({
    required String name,
    required String version,
    server.ServerCapabilities? capabilities,
    bool useStdioTransport = true,
    int? ssePort,
    List<int>? fallbackPorts,
    String? authToken,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP server: $name');
    final timer = PerformanceMonitor.instance.startTimer('server.create');

    try {
      // Validate SSE configuration
      if (!useStdioTransport && ssePort == null) {
        throw MCPValidationException(
            'SSE port must be provided when using SSE transport',
            {'transport': 'Missing SSE port configuration'}
        );
      }

      // Create server using McpServer factory
      final serverId = _serverManager.generateId();
      final mcpServer = server.McpServer.createServer(
        name: name,
        version: version,
        capabilities: capabilities ?? server.ServerCapabilities(),
      );

      // Create transport
      server.ServerTransport? transport;
      if (useStdioTransport) {
        transport = server.McpServer.createStdioTransport();
      } else if (ssePort != null) {
        transport = server.McpServer.createSseTransport(
          endpoint: '/sse',
          messagesEndpoint: '/messages',
          port: ssePort,
          fallbackPorts: fallbackPorts,
          authToken: authToken,
        );
      }

      // Register server
      _serverManager.registerServer(serverId, mcpServer, transport);

      // Update plugin registry
      _pluginRegistry.registerServer(serverId, mcpServer);

      // Register for resource cleanup
      _resourceManager.register<server.Server>(
          'server_$serverId',
          mcpServer,
              (s) async => await _serverManager.closeServer(serverId)
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return serverId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to create MCP server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create MCP server: $name',
          e,
          stackTrace
      );
    }
  }

  /// Create a new MCPLlm instance with custom ID
  ///
  /// [instanceId]: ID for the new instance
  /// [registerDefaultProviders]: Whether to register default providers
  ///
  /// Returns the newly created MCPLlm instance
  llm.MCPLlm createMcpLlmInstance(String instanceId, {bool registerDefaultProviders = true}) {
    if (_mcpLlmInstances.containsKey(instanceId)) {
      _logger.warning('MCPLlm instance with ID $instanceId already exists');
      return _mcpLlmInstances[instanceId]!;
    }

    final mcpLlm = llm.MCPLlm();
    _mcpLlmInstances[instanceId] = mcpLlm;

    if (registerDefaultProviders) {
      _registerDefaultProviders(mcpLlm);
    }

    // Register for resource cleanup
    _resourceManager.register<llm.MCPLlm>(
        'mcpllm_$instanceId',
        mcpLlm,
            (instance) async {
          // Cleanup logic for MCPLlm instance - it doesn't have a direct cleanup method
          // so we'll remove it from our instances
          _mcpLlmInstances.remove(instanceId);
        }
    );

    return mcpLlm;
  }

  /// Get an existing MCPLlm instance by ID
  ///
  /// [instanceId]: ID of the instance to get
  ///
  /// Returns the requested MCPLlm instance or null if not found
  llm.MCPLlm? getMcpLlmInstance(String instanceId) {
    return _mcpLlmInstances[instanceId];
  }

  /// Create MCP LLM with improved validation and error handling
  ///
  /// [providerName]: LLM provider name
  /// [config]: LLM configuration
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  /// [storageManager]: Optional storage manager for the LLM
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  ///
  /// Returns ID of the created LLM
  Future<String> createLlm({
    required String providerName,
    required llm.LlmConfiguration config,
    String mcpLlmInstanceId = 'default',
    llm.StorageManager? storageManager,
    llm.RetrievalManager? retrievalManager,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.create');

    try {
      // Validate the API key and other critical configuration
      _validateLlmConfiguration(providerName, config);

      // Get MCPLlm instance, create if doesn't exist
      llm.MCPLlm mcpLlm;
      if (!_mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
        _logger.debug('Creating new MCPLlm instance: $mcpLlmInstanceId');
        mcpLlm = createMcpLlmInstance(mcpLlmInstanceId);
      } else {
        mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!;
      }

      _logger.info('Creating MCP LLM: $providerName on instance $mcpLlmInstanceId');

      // Verify provider is registered
      if (!mcpLlm.getProviderCapabilities().containsKey(providerName)) {
        throw MCPConfigurationException('Provider $providerName is not registered with MCPLlm instance $mcpLlmInstanceId');
      }

      // Create LLM client using specified MCP LLM instance and its factory method
      final llmClient = await mcpLlm.createClient(
        providerName: providerName,
        config: config,
        storageManager: storageManager,
        retrievalManager: retrievalManager,
      );

      // Generate and register LLM ID
      final llmId = _llmManager.generateId();
      _llmManager.registerLlm(llmId, mcpLlm, llmClient);

      // Register for resource cleanup
      _resourceManager.register<llm.LlmClient>(
          'llm_$llmId',
          llmClient,
              (client) async => await _llmManager.closeLlm(llmId)
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return llmId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false, metadata: {'provider': providerName});
      _logger.error('Failed to create LLM client for provider: $providerName', e, stackTrace);

      // Categorize errors better for clearer debugging
      if (e.toString().contains('API key')) {
        throw MCPAuthenticationException('Invalid API key for provider $providerName', e, stackTrace);
      } else if (e.toString().contains('timeout') || e.toString().contains('connection')) {
        throw MCPNetworkException('Network error while creating LLM client for provider $providerName',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Failed to create LLM client for provider $providerName',
          e,
          stackTrace
      );
    }
  }

  /// Validate LLM configuration
  void _validateLlmConfiguration(String providerName, llm.LlmConfiguration config) {
    final validationErrors = <String, String>{};

    // Check API key
    if (config.apiKey == null || config.apiKey!.isEmpty || config.apiKey == 'placeholder-key') {
      validationErrors['apiKey'] = 'API key is missing or invalid';
    }

    // Check model
    if (config.model == null || config.model!.isEmpty) {
      validationErrors['model'] = 'Model name is required';
    }

    // Provider-specific validation
    switch (providerName.toLowerCase()) {
      case 'openai':
      // OpenAI specific validation
        if (config.baseUrl != null && !config.baseUrl!.contains('openai.com') &&
            !config.baseUrl!.contains('localhost') && !config.baseUrl!.contains('127.0.0.1')) {
          validationErrors['baseUrl'] = 'Custom base URL should be from OpenAI or a local proxy';
        }
        break;

      case 'claude':
      // Claude specific validation
        if (config.apiKey != null && !config.apiKey!.startsWith('sk-')) {
          validationErrors['apiKey'] = 'Claude API keys typically start with "sk-"';
        }
        break;

      case 'together':
      // Together.ai specific validation
        if (config.baseUrl == null || config.baseUrl!.isEmpty) {
          // For Together.ai, baseUrl might be required
          validationErrors['baseUrl'] = 'Base URL is required for Together.ai';
        }
        break;
    }

    // If timeout is very short, warn about it
    if (config.timeout.inSeconds < 5) {
      validationErrors['timeout'] = 'Timeout is very short (${config.timeout.inSeconds}s), may cause failures';
    }

    if (validationErrors.isNotEmpty) {
      throw MCPValidationException(
          'LLM configuration validation failed',
          validationErrors
      );
    }
  }

  /// Integrate server with LLM with improved error handling
  ///
  /// [serverId]: Server ID
  /// [llmId]: LLM ID
  /// [storageManager]: Optional storage manager
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  Future<void> integrateServerWithLlm({
    required String serverId,
    required String llmId,
    llm.StorageManager? storageManager,
    llm.RetrievalManager? retrievalManager,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating server with LLM: $serverId + $llmId');
    final timer = PerformanceMonitor.instance.startTimer('llm.integrate_server');

    try {
      final mcpServer = _serverManager.getServer(serverId);
      if (mcpServer == null) {
        throw MCPResourceNotFoundException(serverId, 'Server not found');
      }

      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get provider capabilities to find available providers
      final providers = llmInfo.mcpLlm.getProviderCapabilities();
      if (providers.isEmpty) {
        throw MCPException('No LLM providers available');
      }

      // Use the specific provider from the LLM client instead of first available
      final providerName = providers.keys.first; // Determine the actual provider from llmInfo

      // Create LLM server using MCPLlm's createServer method
      final llmServer = await llmInfo.mcpLlm.createServer(
        providerName: providerName,
        config: null, // Using null as the LLM client is already configured
        mcpServer: mcpServer,
        storageManager: storageManager,
        retrievalManager: retrievalManager,
      );

      // Register LLM server
      _serverManager.setLlmServer(serverId, llmServer);

      // Register server + LLM integration for cleanup
      _resourceManager.register<llm.LlmServer>(
          'llm_server_integration_$serverId',
          llmServer,
              (server) async => await server.close()
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to integrate server with LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate server with LLM',
          e,
          stackTrace
      );
    }
  }

  /// Integrate client with LLM with improved error handling
  ///
  /// [clientId]: Client ID
  /// [llmId]: LLM ID
  Future<void> integrateClientWithLlm({
    required String clientId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating client with LLM: $clientId + $llmId');
    final timer = PerformanceMonitor.instance.startTimer('llm.integrate_client');

    try {
      final mcpClient = _clientManager.getClient(clientId);
      if (mcpClient == null) {
        throw MCPResourceNotFoundException(clientId, 'Client not found');
      }

      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Register client with LLM
      await _llmManager.addClientToLlm(llmId, mcpClient);

      // No specific resource to register for cleanup as this is just a logical connection

      PerformanceMonitor.instance.stopTimer(timer, success: true);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to integrate client with LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate client with LLM',
          e,
          stackTrace
      );
    }
  }

  /// Connect client with retry and timeout
  ///
  /// [clientId]: Client ID
  Future<void> connectClient(String clientId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting client: $clientId');
    final timer = PerformanceMonitor.instance.startTimer('client.connect');

    try {
      final clientInfo = _clientManager.getClientInfo(clientId);
      if (clientInfo == null) {
        throw MCPResourceNotFoundException(clientId, 'Client not found');
      }

      if (clientInfo.transport == null) {
        throw MCPException('Client has no transport configured: $clientId');
      }

      // Try to connect with retry and timeout
      await _retryWithTimeout(
              () => clientInfo.client.connect(clientInfo.transport!),
          maxRetries: 3,
          timeout: Duration(seconds: 30),
          operationName: 'Connect client $clientId'
      );

      clientInfo.connected = true;
      PerformanceMonitor.instance.stopTimer(timer, success: true);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to connect client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect client: $clientId',
          e,
          stackTrace
      );
    }
  }

  /// Connect server
  ///
  /// [serverId]: Server ID
  void connectServer(String serverId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting server: $serverId');
    final timer = PerformanceMonitor.instance.startTimer('server.connect');

    try {
      final serverInfo = _serverManager.getServerInfo(serverId);
      if (serverInfo == null) {
        throw MCPResourceNotFoundException(serverId, 'Server not found');
      }

      if (serverInfo.transport == null) {
        throw MCPException('Server has no transport configured: $serverId');
      }

      serverInfo.server.connect(serverInfo.transport!);
      serverInfo.running = true;

      PerformanceMonitor.instance.stopTimer(timer, success: true);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to connect server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect server: $serverId',
          e,
          stackTrace
      );
    }
  }

  /// Call tool with client with improved error handling
  ///
  /// [clientId]: Client ID
  /// [toolName]: Tool name
  /// [arguments]: Tool arguments
  Future<client.CallToolResult> callTool(
      String clientId,
      String toolName,
      Map<String, dynamic> arguments,
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.debug('Calling tool $toolName on client $clientId');
    final timer = PerformanceMonitor.instance.startTimer('tool.call');

    try {
      final clientInfo = _clientManager.getClientInfo(clientId);
      if (clientInfo == null) {
        throw MCPResourceNotFoundException(clientId, 'Client not found');
      }

      if (!clientInfo.connected) {
        throw MCPException('Client is not connected: $clientId');
      }

      // Try to call the tool with timeout
      final result = await _retryWithTimeout(
              () => clientInfo.client.callTool(toolName, arguments),
          timeout: Duration(seconds: 60),
          maxRetries: 2,
          operationName: 'Call tool $toolName'
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false,
          metadata: {'tool': toolName, 'client': clientId});
      _logger.error('Error calling tool $toolName', e, stackTrace);
      throw MCPOperationFailedException(
          'Error calling tool $toolName on client $clientId',
          e,
          stackTrace
      );
    }
  }

  /// Chat with LLM with improved error handling and memory-aware caching
  ///
  /// [llmId]: LLM ID
  /// [message]: Message content
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [useCache]: Whether to use memory-aware caching
  Future<llm.LlmResponse> chat(
      String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        bool useCache = true,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.debug('Starting chat with LLM $llmId');
    final timer = PerformanceMonitor.instance.startTimer('llm.chat');

    // Track request for monitoring
    PerformanceMonitor.instance.recordResourceUsage('llm.requests', 1.0);

    // Check cache if enabled and no tools are needed
    if (useCache && !enableTools && _config?.highMemoryThresholdMB != null) {
      final cache = _getOrCreateResponseCache(llmId);
      final cachedResponse = cache.get(message);

      if (cachedResponse != null) {
        _logger.debug('Cache hit for LLM request: $llmId');
        PerformanceMonitor.instance.incrementCounter('llm.cache.hits');
        PerformanceMonitor.instance.stopTimer(timer, success: true, metadata: {'cached': true});

        // Convert cached map to LlmResponse
        return llm.LlmResponse(
          text: cachedResponse['text'] as String,
          metadata: cachedResponse['metadata'] as Map<String, dynamic>? ?? {},
          toolCalls: cachedResponse['toolCalls'] != null
              ? (cachedResponse['toolCalls'] as List)
              .map((tc) => llm.LlmToolCall(
            name: tc['name'] as String,
            arguments: tc['arguments'] as Map<String, dynamic>,
            id: tc['id'] as String?,
          ))
              .toList()
              : null,
        );
      }

      PerformanceMonitor.instance.incrementCounter('llm.cache.misses');
    }

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Try to call the LLM with timeout and retry for transient issues
      final response = await _retryWithTimeout(
              () => llmInfo.client.chat(
            message,
            enableTools: enableTools,
            parameters: parameters,
          ),
          timeout: parameters['timeout'] != null ?
          Duration(milliseconds: parameters['timeout']) :
          Duration(seconds: 60),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'LLM chat'
      );

      // Store in cache if enabled and no tools were used
      if (useCache && !enableTools && (response.toolCalls == null || response.toolCalls!.isEmpty) &&
          _config?.highMemoryThresholdMB != null) {
        final cache = _getOrCreateResponseCache(llmId);

        // Convert LlmResponse to map
        final responseMap = {
          'text': response.text,
          'metadata': response.metadata,
          if (response.toolCalls != null) 'toolCalls': response.toolCalls!.map((tc) => {
            'name': tc.name,
            'arguments': tc.arguments,
            if (tc.id != null) 'id': tc.id,
          }).toList(),
        };

        cache.put(message, responseMap);
      }

      PerformanceMonitor.instance.stopTimer(timer, success: true);

      // Publish event for the response
      _eventSystem.publish('llm.response', {
        'llmId': llmId,
        'messageLength': message.length,
        'responseLength': response.text.length,
        'toolsUsed': response.toolCalls?.length ?? 0
      });

      return response;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Error in LLM chat', e, stackTrace);

      // Better error categorization
      if (_isRateLimitError(e)) {
        throw MCPRateLimitException('Rate limit exceeded for LLM', e, stackTrace);
      } else if (_isAuthError(e)) {
        throw MCPAuthenticationException('Authentication error for LLM', e, stackTrace);
      } else if (_isNetworkError(e)) {
        throw MCPNetworkException('Network error communicating with LLM service',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Error in LLM chat',
          e,
          stackTrace
      );
    }
  }

  /// Get or create a memory-aware cache for LLM responses
  dynamic _getOrCreateResponseCache(String llmId) {
    if (!_llmResponseCaches.containsKey(llmId)) {
      _logger.debug('Creating response cache for LLM: $llmId');
      _llmResponseCaches[llmId] = MemoryAwareCache<String, Map<String, dynamic>>(
        maxSize: 50,
        entryTTL: Duration(minutes: 30),
      );
    }
    return _llmResponseCaches[llmId]!;
  }

  /// Stream chat with LLM with improved error handling
  ///
  /// [llmId]: LLM ID
  /// [message]: Message content
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  Stream<llm.LlmResponseChunk> streamChat(
      String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
      }) async* {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.debug('Starting streaming chat with LLM $llmId');
    final timer = PerformanceMonitor.instance.startTimer('llm.stream_chat');

    // Track request for monitoring
    PerformanceMonitor.instance.recordResourceUsage('llm.stream_requests', 1.0);

    // Track streaming stats
    int chunkCount = 0;
    int totalTokens = 0;
    bool success = false;

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Start the stream - we can't easily retry streaming, so no retry wrapper
      final stream = llmInfo.client.streamChat(
        message,
        enableTools: enableTools,
        parameters: parameters,
      );

      // Process each chunk with timeout for the first chunk
      bool firstChunk = true;
      final firstChunkTimer = Stopwatch()..start();
      final firstChunkTimeout = parameters['firstChunkTimeout'] != null ?
      Duration(milliseconds: parameters['firstChunkTimeout']) :
      Duration(seconds: 10);

      await for (final chunk in stream) {
        // Check timeout for first chunk
        if (firstChunk) {
          firstChunk = false;
          if (firstChunkTimer.elapsed > firstChunkTimeout) {
            throw TimeoutException('First chunk timeout exceeded');
          }
        }

        // Track chunk stats
        chunkCount++;

        // Calculate tokens (approximate by character count)
        if (chunk.textChunk.isNotEmpty) {
          totalTokens += chunk.textChunk.length ~/ 4;
        }

        yield chunk;
      }

      success = true;
    } catch (e, stackTrace) {
      _logger.error('Error in LLM stream chat', e, stackTrace);

      // Categorize errors for better handling
      if (_isRateLimitError(e)) {
        throw MCPRateLimitException('Rate limit exceeded for LLM streaming', e, stackTrace);
      } else if (_isAuthError(e)) {
        throw MCPAuthenticationException('Authentication error for LLM streaming', e, stackTrace);
      } else if (_isNetworkError(e)) {
        throw MCPNetworkException('Network error in LLM streaming',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Error in LLM stream chat',
          e,
          stackTrace
      );
    } finally {
      // Stop the timer and record metrics
      PerformanceMonitor.instance.stopTimer(timer, success: success,
          metadata: {'chunks': chunkCount, 'tokens': totalTokens});

      // Publish streaming stats event
      _eventSystem.publish('llm.stream.completed', {
        'llmId': llmId,
        'success': success,
        'chunks': chunkCount,
        'tokens': totalTokens,
        'duration': timer
      });
    }
  }

  /// Process documents in memory-efficient chunks
  Future<List<llm.Document>> processDocumentsInChunks(
      List<llm.Document> documents,
      Future<llm.Document> Function(llm.Document) processFunction, {
        int chunkSize = 10,
        Duration? pauseBetweenChunks,
      }) async {
    _logger.debug('Processing ${documents.length} documents in chunks of $chunkSize');

    return await MemoryManager.processInChunks<llm.Document, llm.Document>(
      items: documents,
      chunkSize: chunkSize,
      pauseBetweenChunks: pauseBetweenChunks ?? Duration(milliseconds: 100),
      processItem: processFunction,
    );
  }

  /// Utility for retrying operations with timeout
  Future<T> _retryWithTimeout<T>(
      Future<T> Function() operation, {
        Duration timeout = const Duration(seconds: 30),
        int maxRetries = 3,
        bool Function(Exception)? retryIf,
        required String operationName,
      }) async {
    // Implementation uses ErrorRecovery utility from utils/error_recovery.dart
    return await ErrorRecovery.tryWithTimeout(
            () => ErrorRecovery.tryWithRetry(
            operation,
            maxRetries: maxRetries,
            retryIf: retryIf,
            operationName: operationName
        ),
        timeout,
        operationName: operationName
    );
  }

  /// Check if an error is a transient error that can be retried
  bool _isTransientError(Exception e) {
    final message = e.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('temporarily') ||
        message.contains('retry') ||
        message.contains('unavailable');
  }

  /// Check if an error is a rate limit error
  bool _isRateLimitError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('429');
  }

  /// Check if an error is an authentication error
  bool _isAuthError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('auth') ||
        message.contains('api key') ||
        message.contains('unauthorized') ||
        message.contains('401');
  }

  /// Check if an error is a network error
  bool _isNetworkError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout') ||
        message.contains('socket');
  }

  /// Add document to LLM for retrieval
  ///
  /// [llmId]: LLM ID
  /// [document]: Document to add
  Future<String> addDocument(String llmId, llm.Document document) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.add_document');

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      final docId = await llmInfo.client.addDocument(document);

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'documentSize': document.content.length});
      return docId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to add document to LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to add document to LLM',
          e,
          stackTrace
      );
    }
  }

  /// Retrieve relevant documents for a query
  ///
  /// [llmId]: LLM ID
  /// [query]: Query text
  /// [topK]: Number of results to return
  Future<List<llm.Document>> retrieveRelevantDocuments(
      String llmId,
      String query, {
        int topK = 5,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.retrieve_documents');

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      final docs = await llmInfo.client.retrieveRelevantDocuments(
        query,
        topK: topK,
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'count': docs.length});
      return docs;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to retrieve relevant documents', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to retrieve relevant documents',
          e,
          stackTrace
      );
    }
  }

  /// Generate embeddings
  ///
  /// [llmId]: LLM ID
  /// [text]: Text to embed
  Future<List<double>> generateEmbeddings(String llmId, String text) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.generate_embeddings');

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      final embeddings = await llmInfo.client.generateEmbeddings(text);

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'textLength': text.length, 'embeddingDimensions': embeddings.length});
      return embeddings;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to generate embeddings', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to generate embeddings',
          e,
          stackTrace
      );
    }
  }

  /// Add scheduled job
  ///
  /// [job]: Job to add
  ///
  /// Returns ID of the created job
  String addScheduledJob(MCPJob job) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _scheduler.addJob(job);
  }

  /// Remove scheduled job
  ///
  /// [jobId]: Job ID to remove
  void removeScheduledJob(String jobId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _scheduler.removeJob(jobId);
  }

  /// Store value securely with improved error handling
  ///
  /// [key]: Key to store value under
  /// [value]: Value to store
  Future<void> secureStore(String key, String value) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('storage.store');

    try {
      await _platformServices.secureStore(key, value);
      PerformanceMonitor.instance.stopTimer(timer, success: true);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to securely store value', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to securely store value for key: $key',
          e,
          stackTrace
      );
    }
  }

  /// Read value from secure storage with improved error handling
  ///
  /// [key]: Key to read
  Future<String?> secureRead(String key) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('storage.read');

    try {
      final value = await _platformServices.secureRead(key);
      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return value;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to read secure value', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to read secure value for key: $key',
          e,
          stackTrace
      );
    }
  }

  /// Create chat session
  ///
  /// [llmId]: LLM ID
  /// [sessionId]: Optional session ID
  /// [title]: Optional session title
  /// [storageManager]: Optional storage manager for persisting chat history
  Future<llm.ChatSession> createChatSession(
      String llmId, {
        String? sessionId,
        String? title,
        llm.StorageManager? storageManager,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('chat.create_session');

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Create a new chat session with storage
      final storage = storageManager ?? llm.MemoryStorage();
      final session = llm.ChatSession(
        llmProvider: llmInfo.client.llmProvider,
        storageManager: storage,
        id: sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
        title: title ?? 'Chat Session',
      );

      // Register for resource cleanup
      _resourceManager.register<llm.ChatSession>(
          'chat_session_${session.id}',
          session,
              (s) async {
            // No explicit cleanup needed for ChatSession, but might want to
            // persist its state before cleanup
            if (storage is PersistentStorage) {
              await storage.persist();
            }
          }
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return session;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to create chat session', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create chat session for LLM: $llmId',
          e,
          stackTrace
      );
    }
  }

  /// Create a conversation with multiple sessions
  ///
  /// [llmId]: LLM ID
  /// [title]: Optional conversation title
  /// [topics]: Optional topics for the conversation
  /// [storageManager]: Optional storage manager for persisting conversation
  Future<llm.Conversation> createConversation(
      String llmId, {
        String? title,
        List<String>? topics,
        llm.StorageManager? storageManager,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('chat.create_conversation');

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Create a new conversation
      final storage = storageManager ?? llm.MemoryStorage();
      final conversation = llm.Conversation(
        id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
        title: title ?? 'Conversation',
        llmProvider: llmInfo.client.llmProvider,
        topics: topics ?? [],
        storageManager: storage,
      );

      // Register for resource cleanup
      _resourceManager.register<llm.Conversation>(
          'conversation_${conversation.id}',
          conversation,
              (c) async {
            // No explicit cleanup needed for Conversation, but might want to
            // persist its state before cleanup
            if (storage is PersistentStorage) {
              await storage.persist();
            }
          }
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return conversation;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to create conversation', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create conversation for LLM: $llmId',
          e,
          stackTrace
      );
    }
  }

  /// Select client for a query
  ///
  /// [query]: Query text
  /// [properties]: Properties to match
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  llm.LlmClient? selectClient(
      String query, {
        Map<String, dynamic>? properties,
        String mcpLlmInstanceId = 'default',
      }) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.select_client');

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
      final result = mcpLlm.selectClient(query, properties: properties);

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'selectedProvider': result?.runtimeType.toString()});
      return result;    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to select LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to select LLM client for query',
          e,
          stackTrace
      );
    }
  }

  /// Fan out query to multiple clients
  ///
  /// [query]: Query text
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  Future<Map<String, llm.LlmResponse>> fanOutQuery(
      String query, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        String mcpLlmInstanceId = 'default',
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.fanout_query');

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
      final results = await mcpLlm.fanOutQuery(
        query,
        enableTools: enableTools,
        parameters: parameters,
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'providerCount': results.length});
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to fan out query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to fan out query to multiple LLM providers',
          e,
          stackTrace
      );
    }
  }

  /// Execute parallel query across multiple providers
  ///
  /// [query]: Query text
  /// [providers]: List of provider names
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  Future<llm.LlmResponse> executeParallel(
      String query, {
        List<String>? providerNames,
        llm.ResultAggregator? aggregator,
        Map<String, dynamic> parameters = const {},
        llm.LlmConfiguration? config,
        String mcpLlmInstanceId = 'default',
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final timer = PerformanceMonitor.instance.startTimer('llm.execute_parallel');

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
      final result = await mcpLlm.executeParallel(
        query,
        providerNames: providerNames,
        aggregator: aggregator,
        parameters: parameters,
        config: config,
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true,
          metadata: {'providers': providerNames?.length ?? 0});
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.error('Failed to execute parallel query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to execute parallel query across providers',
          e,
          stackTrace
      );
    }
  }

  /// Helper method to get MCPLlm instance or throw if not found
  llm.MCPLlm _getMcpLlmInstanceOrThrow(String instanceId) {
    final mcpLlm = _mcpLlmInstances[instanceId];
    if (mcpLlm == null) {
      throw MCPResourceNotFoundException(instanceId, 'MCPLlm instance not found');
    }
    return mcpLlm;
  }

  /// Register LLM provider
  ///
  /// [name]: Provider name
  /// [factory]: Provider factory
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to register on (defaults to 'default')
  void registerLlmProvider(
      String name,
      llm.LlmProviderFactory factory, {
        String mcpLlmInstanceId = 'default',
      }) {
    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    mcpLlm.registerProvider(name, factory);
  }

  /// List all registered MCPLlm instances
  List<String> getAllMcpLlmInstanceIds() {
    return _mcpLlmInstances.keys.toList();
  }

  /// Register a plugin
  ///
  /// [plugin]: Plugin to register
  /// [config]: Optional plugin configuration
  Future<void> registerPlugin(MCPPlugin plugin, [Map<String, dynamic>? config]) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _pluginRegistry.registerPlugin(plugin, config);

    // Register for cleanup
    _resourceManager.register<MCPPlugin>(
        'plugin_${plugin.name}',
        plugin,
            (p) async => await p.shutdown()
    );
  }

  /// Unregister a plugin
  ///
  /// [pluginName]: Name of the plugin to unregister
  Future<void> unregisterPlugin(String pluginName) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _pluginRegistry.unregisterPlugin(pluginName);

    // Remove from resource manager
    await _resourceManager.dispose('plugin_$pluginName');
  }

  /// Execute a tool plugin
  ///
  /// [name]: Plugin name
  /// [arguments]: Tool arguments
  Future<Map<String, dynamic>> executeToolPlugin(String name, Map<String, dynamic> arguments) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return await _pluginRegistry.executeTool(name, arguments);
  }

  /// Get resource from a resource plugin
  ///
  /// [name]: Plugin name
  /// [resourceUri]: Resource URI
  /// [params]: Resource parameters
  Future<Map<String, dynamic>> getPluginResource(
      String name,
      String resourceUri,
      Map<String, dynamic> params
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return await _pluginRegistry.getResource(name, resourceUri, params);
  }

  /// Show notification using a notification plugin
  ///
  /// [name]: Plugin name
  /// [title]: Notification title
  /// [body]: Notification body
  /// [id]: Optional notification ID
  /// [icon]: Optional notification icon
  /// [additionalData]: Optional additional data
  Future<void> showPluginNotification(
      String name, {
        required String title,
        required String body,
        String? id,
        String? icon,
        Map<String, dynamic>? additionalData,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _pluginRegistry.showNotification(
      name,
      title: title,
      body: body,
      id: id,
      icon: icon,
      additionalData: additionalData,
    );
  }

  /// Clean up all resources
  Future<void> _cleanup() async {
    _logger.debug('Cleaning up resources');

    try {
      // Stop the scheduler
      _scheduler.stop();

      // Clean up all registered resources
      await _resourceManager.disposeAll();

      // Signal the event system
      _eventSystem.publish('mcp.shutdown', null);

      // Ensure logger flushes
      await MCPLogger.flush();
    } catch (e, stackTrace) {
      _logger.error('Error during cleanup', e, stackTrace);
    }
  }

  /// Shutdown all services
  Future<void> shutdown() async {
    if (!_initialized) return;

    _logger.info('Flutter MCP shutdown started');

    try {
      await _cleanup();

      _initialized = false;
      _logger.info('Flutter MCP shutdown completed');
    } catch (e, stackTrace) {
      _logger.error('Error during shutdown', e, stackTrace);
      // Still mark as not initialized even if there was an error
      _initialized = false;
    } finally {
      // Final cleanup of logger
      await MCPLogger.closeAll();
    }
  }

  /// ID access methods
  List<String> get allClientIds => _clientManager.getAllClientIds();
  List<String> get allServerIds => _serverManager.getAllServerIds();
  List<String> get allLlmIds => _llmManager.getAllLlmIds();

  /// Object access methods
  client.Client? getClient(String clientId) => _clientManager.getClient(clientId);
  server.Server? getServer(String serverId) => _serverManager.getServer(serverId);
  llm.LlmClient? getLlm(String llmId) => _llmManager.getLlm(llmId);

  /// Get system status with enhanced information
  Map<String, dynamic> getSystemStatus() {
    final status = {
      'initialized': _initialized,
      'clients': _clientManager.getAllClientIds().length,
      'servers': _serverManager.getAllServerIds().length,
      'llms': _llmManager.getAllLlmIds().length,
      'backgroundServiceRunning': _platformServices.isBackgroundServiceRunning,
      'schedulerRunning': _scheduler.isRunning,
      'clientsStatus': _clientManager.getStatus(),
      'serversStatus': _serverManager.getStatus(),
      'llmsStatus': _llmManager.getStatus(),
      'pluginsCount': _pluginRegistry.getAllPluginNames().length,
      'registeredResourcesCount': _resourceManager.count,
      'platformName': _platformServices.platformName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Add performance metrics if available
    if (_config?.enablePerformanceMonitoring ?? false) {
      status['performanceMetrics'] = PerformanceMonitor.instance.getMetricsSummary();
    }

    return status;
  }
}

/// Rate limit exception for LLM services
class MCPRateLimitException extends MCPException {
  final Duration? retryAfter;

  MCPRateLimitException(
      String message,
      [dynamic originalError, StackTrace? stackTrace, this.retryAfter]
      ) : super('Rate limit error: $message', originalError, stackTrace);
}

/// Interface for persistent storage
abstract class PersistentStorage implements llm.StorageManager {
  /// Persist storage to disk
  Future<void> persist();

  /// Load storage from disk
  Future<void> load();
}
