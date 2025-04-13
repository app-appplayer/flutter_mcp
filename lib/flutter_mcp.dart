import 'dart:async';
import 'dart:math';
import 'package:flutter_mcp/src/utils/error_recovery.dart';
import 'package:mcp_client/mcp_client.dart' as client;
import 'package:mcp_server/mcp_server.dart' as server;
import 'package:mcp_llm/mcp_llm.dart' as llm;

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
import 'src/utils/object_pool.dart';
import 'src/utils/circuit_breaker.dart';
import 'src/utils/semantic_cache.dart';

// Re-exports remain the same
export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';
export 'src/utils/logger.dart';
export 'src/plugins/plugin_system.dart' show MCPPlugin, MCPToolPlugin, MCPResourcePlugin,
MCPBackgroundPlugin, MCPNotificationPlugin, MCPClientPlugin, MCPServerPlugin;
export 'src/platform/tray/tray_manager.dart' show TrayMenuItem;
export 'package:mcp_client/mcp_client.dart'
    show ClientCapabilities, Client, ClientTransport;
export 'package:mcp_server/mcp_server.dart'
    show ServerCapabilities, Server, ServerTransport,
    Content, TextContent, ImageContent, ResourceContent,
    Tool, Resource, Message, MessageRole, MCPContentType, CallToolResult;
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
  // Singleton instance with lazy initialization
  static FlutterMCP? _instance;

  /// Singleton instance accessor with lazy initialization
  static FlutterMCP get instance {
    _instance ??= FlutterMCP._();
    return _instance!;
  }

  // Private constructor
  FlutterMCP._();

  // Core components
  final MCPClientManager _clientManager = MCPClientManager();
  final MCPServerManager _serverManager = MCPServerManager();
  final MCPLlmManager _llmManager = MCPLlmManager();

  // Multiple MCP LLM instances with lazy initialization
  final Map<String, Lazy<llm.MCPLlm>> _mcpLlmInstances = {};

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

  // Optimized memory cache for LLM responses with semantic support
  final Map<String, SemanticCache> _llmResponseCaches = {};

  // Optimized object pools
  final ObjectPool<Stopwatch> _stopwatchPool = ObjectPool<Stopwatch>(
    create: () => Stopwatch(),
    reset: (stopwatch) => stopwatch..reset(),
    initialSize: 10,
    maxSize: 50,
  );

  // Circuit breakers for handling failures
  final Map<String, CircuitBreaker> _circuitBreakers = {};

  // Plugin state
  bool _initialized = false;
  MCPConfig? _config;

  // Shutdown hook registered flag
  bool _shutdownHookRegistered = false;

  // Integrated logger with conditional logging
  static final MCPLogger _logger = MCPLogger('mcp.flutter_mcp');

  // Initialization lock to prevent parallel initializations
  final Completer<void> _initializationLock = Completer<void>();
  bool _initializationStarted = false;

  /// Get client manager
  MCPClientManager get clientManager => _clientManager;

  /// Get server manager
  MCPServerManager get serverManager => _serverManager;

  /// Get LLM manager
  MCPLlmManager get llmManager => _llmManager;

  /// Get Platform Services
  PlatformServices get platformServices => _platformServices;

  /// Initialize the plugin with improved concurrency handling
  ///
  /// [config] specifies the configuration for necessary components.
  Future<void> init(MCPConfig config) async {
    llm.Logger.setAllLevels(llm.LogLevel.debug);
    MCPLogger.setAllLevels(LogLevel.debug);
    // Prevent multiple parallel initializations
    if (_initialized) {
      _logger.warning('Flutter MCP is already initialized');
      return;
    }

    if (_initializationStarted) {
      // Wait for ongoing initialization to complete
      return _initializationLock.future;
    }

    _initializationStarted = true;

    _config = config;

    _logger.info('Flutter MCP initialization started');

    // Start performance monitoring if enabled
    if (config.enablePerformanceMonitoring ?? false) {
      _initializePerformanceMonitoring();
    }

    try {
      // Initialize platform services
      await _platformServices.initialize(config);

      // Register shutdown hook for proper cleanup
      _registerShutdownHook();

      // Initialize memory management if configured
      if (config.highMemoryThresholdMB != null) {
        _initializeMemoryManagement(config.highMemoryThresholdMB!);
      }

      // Create default MCP LLM instance (lazy initialized)
      _mcpLlmInstances['default'] = Lazy<llm.MCPLlm>(() {
        final defaultLlm = llm.MCPLlm();
        _registerDefaultProviders(defaultLlm);
        return defaultLlm;
      });

      // Initialize resource manager with platform services
      _resourceManager.registerCallback(
          'platform_services',
              () => _platformServices.shutdown(),
          priority: ResourceManager.HIGH_PRIORITY
      );

      // Initialize managers in parallel
      await _initializeManagers();

      // Initialize circuit breakers
      _initializeCircuitBreakers();

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

      // Complete the initialization lock
      _initializationLock.complete();
    } catch (e, stackTrace) {
      _logger.error('Flutter MCP initialization failed', e, stackTrace);

      // Complete the initialization lock with error
      _initializationLock.completeError(e, stackTrace);

      // Clean up any resources that were initialized
      await _cleanup();

      throw MCPInitializationException('Flutter MCP initialization failed', e, stackTrace);
    }
  }

  /// Initialize circuit breakers for different operations
  void _initializeCircuitBreakers() {
    // LLM chat circuit breaker
    _circuitBreakers['llm.chat'] = CircuitBreaker(
      name: 'llm.chat',
      failureThreshold: 5,
      resetTimeout: Duration(seconds: 30),
      onOpen: () {
        _logger.warning('Circuit breaker opened for LLM chat operations');
        _eventSystem.publish('circuit_breaker.opened', {'operation': 'llm.chat'});
      },
      onClose: () {
        _logger.info('Circuit breaker closed for LLM chat operations');
        _eventSystem.publish('circuit_breaker.closed', {'operation': 'llm.chat'});
      },
    );

    // Tool execution circuit breaker
    _circuitBreakers['tool.call'] = CircuitBreaker(
      name: 'tool.call',
      failureThreshold: 3,
      resetTimeout: Duration(seconds: 20),
      onOpen: () {
        _logger.warning('Circuit breaker opened for tool call operations');
        _eventSystem.publish('circuit_breaker.opened', {'operation': 'tool.call'});
      },
      onClose: () {
        _logger.info('Circuit breaker closed for tool call operations');
        _eventSystem.publish('circuit_breaker.closed', {'operation': 'tool.call'});
      },
    );
  }

  /// Initialize memory management with improved cleanup logic
  void _initializeMemoryManagement(int highMemoryThresholdMB) {
    _logger.debug('Initializing memory management with threshold: $highMemoryThresholdMB MB');

    MemoryManager.instance.initialize(
      startMonitoring: true,
      highMemoryThresholdMB: highMemoryThresholdMB,
      monitoringInterval: Duration(seconds: 30),
    );

    // Register memory manager for cleanup
    _resourceManager.registerCallback(
        'memory_manager',
            () async {
          MemoryManager.instance.dispose();
        },
        priority: ResourceManager.MEDIUM_PRIORITY
    );

    // Add high memory callback with tiered cleanup
    MemoryManager.instance.addHighMemoryCallback(() async {
      _logger.warning('High memory usage detected, triggering cleanup');

      // Determine the severity level based on current memory usage
      final currentUsage = MemoryManager.instance.currentMemoryUsageMB;
      final threshold = highMemoryThresholdMB;
      final severityLevel = currentUsage > threshold * 1.5 ? 3 :
      currentUsage > threshold * 1.2 ? 2 : 1;

      await _performTieredMemoryCleanup(severityLevel);
    });
  }

  /// Perform tiered memory cleanup based on severity level
  Future<void> _performTieredMemoryCleanup(int severityLevel) async {
    _logger.debug('Performing tier $severityLevel memory cleanup');

    try {
      // Tier 1 (always): Clear expired cache entries
      await _clearExpiredCaches();

      // Tier 2 (medium severity): Reduce cache sizes
      if (severityLevel >= 2) {
        await _reduceCacheSizes();
      }

      // Tier 3 (high severity): Aggressive cleanup
      if (severityLevel >= 3) {
        await _performAggressiveCleanup();
      }

      // Signal GC
      if (severityLevel >= 2) {
        _logger.debug('Suggesting resource cleanup to garbage collector');
      }

      // Clear performance monitoring history for higher tiers
      if (severityLevel >= 2 && (_config?.enablePerformanceMonitoring ?? false)) {
        _logger.debug('Clearing performance monitoring history');
        PerformanceMonitor.instance.reset();
      }

      // Publish memory cleanup event
      _eventSystem.publish('memory.cleanup', {
        'timestamp': DateTime.now().toIso8601String(),
        'currentMemoryMB': MemoryManager.instance.currentMemoryUsageMB,
        'peakMemoryMB': MemoryManager.instance.peakMemoryUsageMB,
        'severityLevel': severityLevel,
      });

      _logger.debug('Memory cleanup completed');
    } catch (e, stackTrace) {
      _logger.error('Error during memory cleanup', e, stackTrace);
    }
  }

  /// Clear expired cache entries
  Future<void> _clearExpiredCaches() async {
    for (final cache in _llmResponseCaches.values) {
      await cache.removeExpiredEntries();
    }

    // Clear object pools if they're too large
    _stopwatchPool.trim();
  }

  /// Reduce cache sizes for medium severity cleanup
  Future<void> _reduceCacheSizes() async {
    for (final cache in _llmResponseCaches.values) {
      await cache.shrink(0.5); // Reduce to 50% of current size
    }
  }

  /// Aggressive cleanup for high severity situations
  Future<void> _performAggressiveCleanup() async {
    // Clear all caches except for essential items
    for (final cache in _llmResponseCaches.values) {
      await cache.clear();
    }

    // Reset circuit breakers
    for (final breaker in _circuitBreakers.values) {
      breaker.reset();
    }

    // Clear all object pools
    _stopwatchPool.clear();
  }

  /// Initialize core managers in parallel
  Future<void> _initializeManagers() async {
    // Initialize in parallel for efficiency
    await Future.wait([
      _clientManager.initialize(),
      _serverManager.initialize(),
      _llmManager.initialize(),
    ]);

    // Register for cleanup with appropriate priorities
    _resourceManager.registerCallback(
        'client_manager',
            () => _clientManager.closeAll(),
        priority: ResourceManager.LOW_PRIORITY
    );

    _resourceManager.registerCallback(
        'server_manager',
            () => _serverManager.closeAll(),
        priority: ResourceManager.MEDIUM_PRIORITY
    );

    _resourceManager.registerCallback(
        'llm_manager',
            () => _llmManager.closeAll(),
        priority: ResourceManager.HIGH_PRIORITY
    );
  }

  /// Initialize scheduler with improved monitoring
  void _initializeScheduler(List<MCPJob> jobs) {
    _scheduler.initialize();

    for (final job in jobs) {
      _scheduler.addJob(job);
    }

    // Add event listener for job execution
    _eventSystem.subscribe<Map<String, dynamic>>('scheduler.job.executed', (data) {
      final jobId = data['jobId'] as String?;
      final success = data['success'] as bool? ?? false;

      if (jobId != null) {
        PerformanceMonitor.instance.incrementCounter(
            success ? 'scheduler.job.success' : 'scheduler.job.failure'
        );
      }
    });

    _scheduler.start();

    // Register for cleanup
    _resourceManager.registerCallback(
        'scheduler',
            () async {
          _scheduler.stop();
          _scheduler.dispose();
        },
        priority: ResourceManager.MEDIUM_PRIORITY
    );
  }

  /// Initialize plugin registry with improved dependency tracking
  Future<void> _initializePluginRegistry() async {
    // Connect the plugin registry with core managers
    final List<Future<void>> registrationTasks = [];

    for (final serverId in _serverManager.getAllServerIds()) {
      final server = _serverManager.getServer(serverId);
      if (server != null) {
        registrationTasks.add(
            Future(() => _pluginRegistry.registerServer(serverId, server))
        );
      }
    }

    for (final clientId in _clientManager.getAllClientIds()) {
      final client = _clientManager.getClient(clientId);
      if (client != null) {
        registrationTasks.add(
            Future(() => _pluginRegistry.registerClient(clientId, client))
        );
      }
    }

    // Register in parallel
    await Future.wait(registrationTasks);

    // Register for cleanup
    _resourceManager.registerCallback(
        'plugin_registry',
            () => _pluginRegistry.shutdownAll(),
        priority: ResourceManager.MEDIUM_PRIORITY
    );
  }

  /// Initialize performance monitoring with enhanced metrics
  void _initializePerformanceMonitoring() {
    PerformanceMonitor.instance.initialize(
      enableLogging: true,
      enableMetricsExport: _config?.enableMetricsExport ?? false,
      exportPath: _config?.metricsExportPath,
      maxRecentOperations: 100,
      autoExportInterval: Duration(minutes: 15),
    );

    // Enable caching for certain key events
    final eventTypesToCache = [
      'llm.request',
      'llm.response',
      'tool.call',
      'tool.response',
      'client.connect',
      'server.connect'
    ];

    for (final eventType in eventTypesToCache) {
      PerformanceMonitor.instance.enableCaching(eventType);
    }

    // Register for cleanup
    _resourceManager.registerCallback(
        'performance_monitor',
            () async {
          if (_config?.enableMetricsExport ?? false) {
            await PerformanceMonitor.instance.exportMetrics();
          }
          PerformanceMonitor.instance.dispose();
        },
        priority: ResourceManager.LOW_PRIORITY
    );
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

  /// Register default LLM providers with improved error handling
  void _registerDefaultProviders(llm.MCPLlm mcpLlm) {
    _registerProviderSafely(mcpLlm, 'openai', llm.OpenAiProviderFactory());
    _registerProviderSafely(mcpLlm, 'claude', llm.ClaudeProviderFactory());
    _registerProviderSafely(mcpLlm, 'together', llm.TogetherProviderFactory());

    // Register other providers as needed
  }

  /// Start services with better error aggregation
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
    final startErrors = await _startConfiguredComponents();

    // Report if there were errors
    if (startErrors.isNotEmpty) {
      _logger.warning(
          'Some components failed to start (${startErrors.length} errors). ' +
              'First error: ${startErrors.values.first}'
      );
    }
  }

  /// Start configured components with improved error handling and parallelism
  Future<Map<String, dynamic>> _startConfiguredComponents() async {
    final config = _config!;
    final startErrors = <String, dynamic>{};
    final startTasks = <Future<void>>[];

    // Start auto-start servers
    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (final serverConfig in config.autoStartServer!) {
        startTasks.add(_startServerWithErrorHandling(serverConfig, startErrors));
      }
    }

    // Start auto-start clients
    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (final clientConfig in config.autoStartClient!) {
        startTasks.add(_startClientWithErrorHandling(clientConfig, startErrors));
      }
    }

    // Wait for all tasks to complete
    await Future.wait(startTasks);

    // Report any errors that occurred during startup
    if (startErrors.isNotEmpty) {
      // Publish start errors event
      _eventSystem.publish('mcp.startup.errors', startErrors);
    }

    return startErrors;
  }

  /// Start server with error handling without blocking other components
  Future<void> _startServerWithErrorHandling(
      MCPServerConfig serverConfig,
      Map<String, dynamic> startErrors
      ) async {
    try {
      await _startServer(serverConfig);
    } catch (e, stackTrace) {
      _logger.error('Failed to start server: ${serverConfig.name}', e, stackTrace);
      startErrors['server.${serverConfig.name}'] = e;

      // Track failure
      PerformanceMonitor.instance.incrementCounter('server.start.failure');
    }
  }

  /// Start client with error handling without blocking other components
  Future<void> _startClientWithErrorHandling(
      MCPClientConfig clientConfig,
      Map<String, dynamic> startErrors
      ) async {
    try {
      await _startClient(clientConfig);
    } catch (e, stackTrace) {
      _logger.error('Failed to start client: ${clientConfig.name}', e, stackTrace);
      startErrors['client.${clientConfig.name}'] = e;

      // Track failure
      PerformanceMonitor.instance.incrementCounter('client.start.failure');
    }
  }

  /// Start a client from configuration with improved error handling
  Future<String> _startClient(MCPClientConfig clientConfig) async {
    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'client.start.${clientConfig.name}';

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
          // Use existing LLM ID
          llmId = clientConfig.integrateLlm!.existingLlmId!;
        } else {
          // Create new LLM client and use its llmId
          final (newLlmId, _) = await createLlmClient(
            providerName: clientConfig.integrateLlm!.providerName!,
            config: clientConfig.integrateLlm!.config!,
          );
          llmId = newLlmId;
        }

        await integrateClientWithLlm(
          clientId: clientId,
          llmId: llmId,
        );
      }

      // Connect client
      await connectClient(clientId);

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true
      );

      _stopwatchPool.release(stopwatch);
      return clientId;
    } catch (e) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false
      );

      _stopwatchPool.release(stopwatch);
      rethrow;
    }
  }

  /// Start a server from configuration with improved error handling
  Future<String> _startServer(MCPServerConfig serverConfig) async {
    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'server.start.${serverConfig.name}';

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
          // Use existing LLM ID
          llmId = serverConfig.integrateLlm!.existingLlmId!;
        } else {
          // Create new LLM server and use its llmId
          final (newLlmId, _) = await createLlmServer(
            providerName: serverConfig.integrateLlm!.providerName!,
            config: serverConfig.integrateLlm!.config!,
          );
          llmId = newLlmId;
        }

        await integrateServerWithLlm(
          serverId: serverId,
          llmId: llmId,
        );
      }

      // Connect server
      connectServer(serverId);

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true
      );

      _stopwatchPool.release(stopwatch);
      return serverId;
    } catch (e) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false
      );

      _stopwatchPool.release(stopwatch);
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

  /// Create LLM client directly without needing to call createLlm first
  ///
  /// [providerName]: Provider name to use for client creation
  /// [config]: LLM configuration for the client
  /// [storageManager]: Optional storage manager
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  ///
  /// Returns a Map with llmId and llmClientId
  Future<(String llmId, String llmClientId)> createLlmClient({
    required String providerName,
    required llm.LlmConfiguration config,
    llm.StorageManager? storageManager,
    llm.RetrievalManager? retrievalManager,
    String mcpLlmInstanceId = 'default',
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'llm.create_with_client';

    try {
      // Get MCPLlm instance, create if doesn't exist (lazy initialization)
      if (!_mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
        _logger.debug('Creating new MCPLlm instance: $mcpLlmInstanceId');
        createMcpLlmInstance(mcpLlmInstanceId);
      }

      final mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!.value;

      _logger.info('Creating LLM instance with client for $providerName on MCPLlm instance $mcpLlmInstanceId');

      // Generate and register LLM ID
      final llmId = _llmManager.generateId();

      // Register with the LLM manager (no clients or servers yet)
      _llmManager.registerLlm(llmId, mcpLlm);

      // Register for resource cleanup
      _resourceManager.register<String>(
          'llm_$llmId',
          llmId,
              (id) async => await _llmManager.closeLlm(id),
          priority: ResourceManager.MEDIUM_PRIORITY
      );

      // Verify provider is registered
      if (!mcpLlm.getProviderCapabilities().containsKey(providerName)) {
        throw MCPConfigurationException('Provider $providerName is not registered with MCPLlm');
      }

      // Validate configuration
      _validateLlmConfiguration(providerName, config);

      // Create a new LLM client using mcpLlm
      final llmClient = await _retryWithTimeout(
              () => mcpLlm.createClient(
            providerName: providerName,
            config: config,
            storageManager: storageManager,
            retrievalManager: retrievalManager,
          ),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Create LLM client for $providerName'
      );

      // Add to LLM manager
      final llmClientId = await _llmManager.addLlmClient(llmId, llmClient);

      // Create semantic cache for this client
      _llmResponseCaches[llmId] = SemanticCache(
        maxSize: 100,
        ttl: Duration(hours: 1),
        embeddingFunction: (text) async => await llmClient.generateEmbeddings(text),
        similarityThreshold: 0.85,
      );

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'provider': providerName,
            'mcpLlmInstanceId': mcpLlmInstanceId
          }
      );

      _logger.info('Created LLM $llmId with client $llmClientId using provider $providerName');

      _stopwatchPool.release(stopwatch);
      return (llmId, llmClientId);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString(), 'provider': providerName}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to create LLM with client', e, stackTrace);

      // Categorize errors better for clearer debugging
      if (e.toString().contains('API key')) {
        throw MCPAuthenticationException('Invalid API key for provider', e, stackTrace);
      } else if (e.toString().contains('timeout') || e.toString().contains('connection')) {
        throw MCPNetworkException('Network error while creating LLM client',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Failed to create LLM with client for provider: $providerName',
          e,
          stackTrace
      );
    }
  }

  /// Create LLM server directly without needing to call createLlm first
  ///
  /// [providerName]: Provider name to use for server creation
  /// [config]: LLM configuration for the server
  /// [storageManager]: Optional storage manager
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  ///
  /// Returns a Map with llmId and llmServerId
  Future<(String llmId, String llmServerId)> createLlmServer({
    required String providerName,
    required llm.LlmConfiguration config,
    llm.StorageManager? storageManager,
    llm.RetrievalManager? retrievalManager,
    String mcpLlmInstanceId = 'default',
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'llm.create_with_server';

    try {
      // Get MCPLlm instance, create if doesn't exist (lazy initialization)
      if (!_mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
        _logger.debug('Creating new MCPLlm instance: $mcpLlmInstanceId');
        createMcpLlmInstance(mcpLlmInstanceId);
      }

      final mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!.value;

      _logger.info('Creating LLM instance with server for $providerName on MCPLlm instance $mcpLlmInstanceId');

      // Generate and register LLM ID
      final llmId = _llmManager.generateId();

      // Register with the LLM manager (no clients or servers yet)
      _llmManager.registerLlm(llmId, mcpLlm);

      // Register for resource cleanup
      _resourceManager.register<String>(
          'llm_$llmId',
          llmId,
              (id) async => await _llmManager.closeLlm(id),
          priority: ResourceManager.MEDIUM_PRIORITY
      );

      // Verify provider is registered
      if (!mcpLlm.getProviderCapabilities().containsKey(providerName)) {
        throw MCPConfigurationException('Provider $providerName is not registered with MCPLlm');
      }

      // Validate configuration
      _validateLlmConfiguration(providerName, config);

      // Create a new LLM server using mcpLlm
      final llmServer = await _retryWithTimeout(
              () => mcpLlm.createServer(
            providerName: providerName,
            config: config,
            storageManager: storageManager,
            retrievalManager: retrievalManager,
          ),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Create LLM server for $providerName'
      );

      // Add to LLM manager
      final llmServerId = await _llmManager.addLlmServer(llmId, llmServer);

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'provider': providerName,
            'mcpLlmInstanceId': mcpLlmInstanceId
          }
      );

      _logger.info('Created LLM $llmId with server $llmServerId using provider $providerName');

      _stopwatchPool.release(stopwatch);
      return (llmId, llmServerId);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString(), 'provider': providerName}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to create LLM with server', e, stackTrace);

      // Categorize errors better for clearer debugging
      if (e.toString().contains('API key')) {
        throw MCPAuthenticationException('Invalid API key for provider', e, stackTrace);
      } else if (e.toString().contains('timeout') || e.toString().contains('connection')) {
        throw MCPNetworkException('Network error while creating LLM server',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Failed to create LLM with server for provider: $providerName',
          e,
          stackTrace
      );
    }
  }

  /// Get LLM details with enhanced information about clients and servers
  ///
  /// [llmId]: LLM ID
  Map<String, dynamic> getLlmDetails(String llmId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPResourceNotFoundException(llmId, 'LLM not found');
    }

    // Build client details
    final clientDetails = <String, Map<String, dynamic>>{};
    for (final clientId in llmInfo.getAllLlmClientIds()) {
      final client = llmInfo.llmClients[clientId];
      if (client != null) {
        clientDetails[clientId] = {
          'isDefault': clientId == llmInfo.defaultLlmClientId,
          'provider': client.llmProvider.runtimeType.toString(),
          'associatedMcpClients': llmInfo.getAllMcpClientIds().where((mcpClientId) =>
              llmInfo.getLlmClientIdsForMcpClient(mcpClientId).contains(clientId)
          ).toList(),
        };
      }
    }

    // Build server details
    final serverDetails = <String, Map<String, dynamic>>{};
    for (final serverId in llmInfo.getAllLlmServerIds()) {
      final server = llmInfo.llmServers[serverId];
      if (server != null) {
        serverDetails[serverId] = {
          'isDefault': serverId == llmInfo.defaultLlmServerId,
          'provider': server.llmProvider.runtimeType.toString(),
          'associatedMcpServers': llmInfo.getAllMcpServerIds().where((mcpServerId) =>
              llmInfo.getLlmServerIdsForMcpServer(mcpServerId).contains(serverId)
          ).toList(),
        };
      }
    }

    return {
      'id': llmId,
      'hasClients': llmInfo.hasClients(),
      'hasServers': llmInfo.hasServers(),
      'clientCount': llmInfo.llmClients.length,
      'serverCount': llmInfo.llmServers.length,
      'defaultLlmClientId': llmInfo.defaultLlmClientId,
      'defaultLlmServerId': llmInfo.defaultLlmServerId,
      'clients': clientDetails,
      'servers': serverDetails,
      'associatedMcpClients': llmInfo.getAllMcpClientIds().toList(),
      'associatedMcpServers': llmInfo.getAllMcpServerIds().toList(),
    };
  }

  /// Get all LLM details with pagination support
  ///
  /// [offset]: Starting offset for pagination
  /// [limit]: Maximum number of items to return
  /// [includeDetails]: Whether to include full details for each LLM
  Map<String, dynamic> getAllLlmDetails({int offset = 0, int limit = 50, bool includeDetails = false}) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final allLlmIds = _llmManager.getAllLlmIds();
    final totalCount = allLlmIds.length;

    // Apply pagination
    final paginatedIds = allLlmIds.skip(offset).take(limit).toList();

    final llmDetails = <String, dynamic>{};
    for (final llmId in paginatedIds) {
      if (includeDetails) {
        // Full details
        try {
          llmDetails[llmId] = getLlmDetails(llmId);
        } catch (e) {
          // Skip errors
          _logger.warning('Error getting details for LLM $llmId: $e');
        }
      } else {
        // Basic information only
        final llmInfo = _llmManager.getLlmInfo(llmId);
        if (llmInfo != null) {
          llmDetails[llmId] = {
            'clientCount': llmInfo.llmClients.length,
            'serverCount': llmInfo.llmServers.length,
            'hasClients': llmInfo.hasClients(),
            'hasServers': llmInfo.hasServers(),
          };
        }
      }
    }

    return {
      'total': totalCount,
      'offset': offset,
      'limit': limit,
      'returned': llmDetails.length,
      'llms': llmDetails,
    };
  }

  /// Remove an LLM client from an LLM
  ///
  /// [llmId]: LLM ID
  /// [llmClientId]: LLM client ID to remove
  Future<void> removeLlmClient(String llmId, String llmClientId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'llm.remove_client';

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      if (!llmInfo.llmClients.containsKey(llmClientId)) {
        throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
      }

      // Get associated MCP clients
      final associatedMcpClientIds = <String>[];
      for (final mcpClientId in llmInfo.getAllMcpClientIds()) {
        if (llmInfo.getLlmClientIdsForMcpClient(mcpClientId).contains(llmClientId)) {
          associatedMcpClientIds.add(mcpClientId);
        }
      }

      // Remove MCP client associations first
      for (final mcpClientId in associatedMcpClientIds) {
        llmInfo.disassociateMcpClient(mcpClientId, llmClientId);
      }

      // Remove the LLM client
      final client = llmInfo.removeLlmClient(llmClientId);
      if (client != null) {
        await client.close();
      }

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'llmId': llmId, 'llmClientId': llmClientId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'llmId': llmId, 'llmClientId': llmClientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove LLM client',
          e,
          stackTrace
      );
    }
  }

  /// Remove an LLM server from an LLM
  ///
  /// [llmId]: LLM ID
  /// [llmServerId]: LLM server ID to remove
  Future<void> removeLlmServer(String llmId, String llmServerId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'llm.remove_server';

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      if (!llmInfo.llmServers.containsKey(llmServerId)) {
        throw MCPResourceNotFoundException(llmServerId, 'LLM server not found');
      }

      // Get associated MCP servers
      final associatedMcpServerIds = <String>[];
      for (final mcpServerId in llmInfo.getAllMcpServerIds()) {
        if (llmInfo.getLlmServerIdsForMcpServer(mcpServerId).contains(llmServerId)) {
          associatedMcpServerIds.add(mcpServerId);
        }
      }

      // Remove MCP server associations first
      for (final mcpServerId in associatedMcpServerIds) {
        llmInfo.disassociateMcpServer(mcpServerId, llmServerId);
      }

      // Remove the LLM server
      final server = llmInfo.removeLlmServer(llmServerId);
      if (server != null) {
        await server.close();
      }

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'llmId': llmId, 'llmServerId': llmServerId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'llmId': llmId, 'llmServerId': llmServerId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove LLM server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove LLM server',
          e,
          stackTrace
      );
    }
  }

  /// Create a new MCPLlm instance with lazy initialization and better resource management
  ///
  /// [instanceId]: ID for the new instance
  /// [registerDefaultProviders]: Whether to register default providers
  ///
  /// Returns the newly created MCPLlm instance
  llm.MCPLlm createMcpLlmInstance(String instanceId, {bool registerDefaultProviders = true}) {
    if (_mcpLlmInstances.containsKey(instanceId)) {
      _logger.warning('MCPLlm instance with ID $instanceId already exists');
      return _mcpLlmInstances[instanceId]!.value;
    }

    final lazy = Lazy<llm.MCPLlm>(() {
      final mcpLlm = llm.MCPLlm();
      if (registerDefaultProviders) {
        _registerDefaultProviders(mcpLlm);
      }

      // Register for resource cleanup
      _resourceManager.register<llm.MCPLlm>(
          'mcpllm_$instanceId',
          mcpLlm,
              (instance) async {
            // Cleanup logic for MCPLlm instance
            try {
              await mcpLlm.shutdown();
            } catch (e) {
              _logger.error('Error shutting down MCPLlm instance $instanceId', e);
            }
            _mcpLlmInstances.remove(instanceId);
          },
          priority: ResourceManager.HIGH_PRIORITY
      );

      return mcpLlm;
    });

    _mcpLlmInstances[instanceId] = lazy;
    return lazy.value;
  }

  /// Get an existing MCPLlm instance by ID with lazy initialization
  ///
  /// [instanceId]: ID of the instance to get
  ///
  /// Returns the requested MCPLlm instance or null if not found
  llm.MCPLlm? getMcpLlmInstance(String instanceId) {
    final lazy = _mcpLlmInstances[instanceId];
    return lazy?.value;
  }

  /// Validate LLM configuration with improved provider-specific checks
  void _validateLlmConfiguration(String providerName, llm.LlmConfiguration config) {
    final validationErrors = <String, String>{};

    // Check API key
    if (config.apiKey == null || config.apiKey!.isEmpty || config.apiKey == 'placeholder-key') {
      validationErrors['apiKey'] = 'API key is missing or invalid';
    }

    // Check model (with provider-specific validation)
    if (config.model == null || config.model!.isEmpty) {
      validationErrors['model'] = 'Model name is required';
    } else {
      // Provider-specific model validation
      switch (providerName.toLowerCase()) {
        case 'openai':
        // OpenAI model naming convention
          if (!config.model!.contains('gpt') &&
              !config.model!.contains('text-') &&
              !config.model!.contains('embedding')) {
            validationErrors['model'] = 'Unrecognized OpenAI model format: ${config.model}';
          }
          break;

        case 'claude':
        // Claude model naming convention
          if (!config.model!.contains('claude')) {
            validationErrors['model'] = 'Unrecognized Claude model format: ${config.model}';
          }
          break;

        case 'together':
        // Together.ai models often have specific prefixes
          if (!config.model!.contains('/')) {
            validationErrors['model'] = 'Together.ai models should include organization/model format';
          }
          break;
      }
    }

    // Provider-specific validation
    switch (providerName.toLowerCase()) {
      case 'openai':
      // OpenAI specific validation
        if (config.baseUrl != null &&
            !config.baseUrl!.contains('openai.com') &&
            !config.baseUrl!.contains('localhost') &&
            !config.baseUrl!.contains('127.0.0.1') &&
            !config.baseUrl!.contains('azure.com')) { // Added Azure support
          validationErrors['baseUrl'] = 'Custom base URL should be from OpenAI, Azure, or a local proxy';
        }
        break;

      case 'claude':
      // Claude specific validation
        if (config.apiKey != null &&
            !config.apiKey!.startsWith('sk-') &&
            !config.apiKey!.startsWith('sa-')) {
          validationErrors['apiKey'] = 'Claude API keys typically start with "sk-" or "sa-"';
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

  /// Integrate client with LLM with improved multi-client support
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpClient = _clientManager.getClient(clientId);
      if (mcpClient == null) {
        throw MCPResourceNotFoundException(clientId, 'Client not found');
      }

      // Add client to LLM with retry
      await _retryWithTimeout(
              () => _llmManager.addClientToLlm(llmId, mcpClient),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add client to LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'clientId': clientId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'clientId': clientId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to integrate client with LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate client with LLM',
          e,
          stackTrace
      );
    }
  }

  /// Remove client from LLM
  ///
  /// [clientId]: Client ID
  /// [llmId]: LLM ID
  Future<void> removeClientFromLlm({
    required String clientId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Removing client from LLM: $clientId from $llmId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove client from LLM with retry
      await _retryWithTimeout(
              () => _llmManager.removeClientFromLlm(llmId, clientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove client from LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'clientId': clientId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'clientId': clientId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove client from LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove client from LLM',
          e,
          stackTrace
      );
    }
  }

  /// Set default client for LLM
  ///
  /// [clientId]: Client ID to set as default
  /// [llmId]: LLM ID
  Future<void> setDefaultClientForLlm({
    required String clientId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Setting default client for LLM: $clientId as default for $llmId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default client for LLM with retry
      await _retryWithTimeout(
              () => _llmManager.setDefaultClientForLlm(llmId, clientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default client for LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'clientId': clientId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'clientId': clientId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to set default client for LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default client for LLM',
          e,
          stackTrace
      );
    }
  }

  /// Integrate server with LLM with improved multi-server support
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpServer = _serverManager.getServer(serverId);
      if (mcpServer == null) {
        throw MCPResourceNotFoundException(serverId, 'Server not found');
      }

      // Add server to LLM with retry
      await _retryWithTimeout(
              () => _llmManager.addServerToLlm(llmId, mcpServer),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add server to LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'serverId': serverId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'serverId': serverId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to integrate server with LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate server with LLM',
          e,
          stackTrace
      );
    }
  }

  /// Remove server from LLM
  ///
  /// [serverId]: Server ID
  /// [llmId]: LLM ID
  Future<void> removeServerFromLlm({
    required String serverId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Removing server from LLM: $serverId from $llmId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove server from LLM with retry
      await _retryWithTimeout(
              () => _llmManager.removeServerFromLlm(llmId, serverId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove server from LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'serverId': serverId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'serverId': serverId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove server from LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove server from LLM',
          e,
          stackTrace
      );
    }
  }

  /// Set default server for LLM
  ///
  /// [serverId]: Server ID to set as default
  /// [llmId]: LLM ID
  Future<void> setDefaultServerForLlm({
    required String serverId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Setting default server for LLM: $serverId as default for $llmId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default server for LLM with retry
      await _retryWithTimeout(
              () => _llmManager.setDefaultServerForLlm(llmId, serverId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default server for LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'serverId': serverId, 'llmId': llmId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'serverId': serverId, 'llmId': llmId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to set default server for LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default server for LLM',
          e,
          stackTrace
      );
    }
  }

  /// Connect client with adaptive retry and exponential backoff
  ///
  /// [clientId]: Client ID
  Future<void> connectClient(String clientId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting client: $clientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final clientInfo = _clientManager.getClientInfo(clientId);
      if (clientInfo == null) {
        throw MCPResourceNotFoundException(clientId, 'Client not found');
      }

      if (clientInfo.transport == null) {
        throw MCPException('Client has no transport configured: $clientId');
      }

      // Try to connect with adaptive retry and exponential backoff
      await _retryWithExponentialBackoff(
              () => clientInfo.client.connect(clientInfo.transport!),
          maxRetries: 4,
          initialDelay: Duration(milliseconds: 500),
          maxDelay: Duration(seconds: 8),
          timeout: Duration(seconds: 30),
          operationName: 'Connect client $clientId'
      );

      clientInfo.connected = true;

      PerformanceMonitor.instance.recordMetric(
          'client.connect',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'clientId': clientId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'client.connect',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'clientId': clientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to connect client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect client: $clientId',
          e,
          stackTrace
      );
    }
  }

  /// Connect server with improved error handling
  ///
  /// [serverId]: Server ID
  void connectServer(String serverId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting server: $serverId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

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

      PerformanceMonitor.instance.recordMetric(
          'server.connect',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'serverId': serverId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'server.connect',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'serverId': serverId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to connect server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect server: $serverId',
          e,
          stackTrace
      );
    }
  }

  /// Call tool with client with improved error handling and circuit breaker
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final circuitBreaker = _circuitBreakers['tool.call']!;

    try {
      // Use circuit breaker to prevent cascading failures
      return await circuitBreaker.execute(() async {
        final clientInfo = _clientManager.getClientInfo(clientId);
        if (clientInfo == null) {
          throw MCPResourceNotFoundException(clientId, 'Client not found');
        }

        if (!clientInfo.connected) {
          throw MCPException('Client is not connected: $clientId');
        }

        // Try to call the tool with timeout and adaptive retry
        final result = await _retryWithExponentialBackoff(
                () => clientInfo.client.callTool(toolName, arguments),
            initialDelay: Duration(milliseconds: 500),
            maxDelay: Duration(seconds: 4),
            maxRetries: 2,
            timeout: Duration(seconds: 60),
            operationName: 'Call tool $toolName'
        );

        PerformanceMonitor.instance.recordMetric(
            'tool.call',
            stopwatch.elapsedMilliseconds,
            success: true,
            metadata: {'tool': toolName, 'client': clientId}
        );

        _stopwatchPool.release(stopwatch);
        return result;
      });
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'tool.call',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'tool': toolName, 'client': clientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Error calling tool $toolName', e, stackTrace);

      // If it's a circuit breaker exception, wrap it
      if (e is CircuitBreakerOpenException) {
        throw MCPCircuitBreakerOpenException(
            'Circuit breaker open for tool calls, too many recent failures',
            e,
            stackTrace
        );
      }

      throw MCPOperationFailedException(
          'Error calling tool $toolName on client $clientId',
          e,
          stackTrace
      );
    }
  }

  /// Sends a message to the LLM and gets a response
  ///
  /// This function leverages the LlmClient's chat method to process user input
  /// and retrieve an LLM response.
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to use for processing the message (required)
  /// - [userInput] The message text from the user to process
  /// - [enableTools] Whether to enable tool usage in the response (default: true)
  /// - [enablePlugins] Whether to enable plugin usage in the response (default: true)
  /// - [parameters] Additional parameters to pass to the LLM provider (default: empty map)
  /// - [context] Optional context information for the LLM
  /// - [useRetrieval] Whether to use retrieval-augmented generation (default: false)
  /// - [enhanceSystemPrompt] Whether to enhance the system prompt with tool information (default: true)
  /// - [noHistory] Whether to clear conversation history before processing (default: false)
  ///
  /// Returns an [llm.LlmResponse] object containing the LLM's response
  Future<llm.LlmResponse> chat(
      String llmId,
      String userInput, {
        bool enableTools = true,
        bool enablePlugins = true,
        Map<String, dynamic> parameters = const {},
        llm.LlmContext? context,
        bool useRetrieval = false,
        bool enhanceSystemPrompt = true,
        bool noHistory = false,
      }) async {
    // Logger instance
    final logger = MCPLogger('mcp.llm_service');
    logger.debug('Processing chat request: $userInput');

    try {
      // Get LLM client from manager
      final llmClient = _llmManager.getLlmClient(llmId);
      if (llmClient == null) {
        logger.error('LLM client not found: $llmId');
        return llm.LlmResponse(
          text: 'Error: LLM client not found: $llmId',
          metadata: {'error': 'client_not_found'},
        );
      }

      // Call the underlying LlmClient chat method which already has performance monitoring
      final response = await llmClient.chat(
        userInput,
        enableTools: enableTools,
        enablePlugins: enablePlugins,
        parameters: parameters,
        context: context,
        useRetrieval: useRetrieval,
        enhanceSystemPrompt: enhanceSystemPrompt,
        noHistory: noHistory,
      );

      return response;
    } catch (e, stackTrace) {
      // Handle and log errors
      logger.error('Error in chat: $e', e, stackTrace);

      // Return error response
      return llm.LlmResponse(
        text: 'Error processing chat request: $e',
        metadata: {'error': e.toString()},
      );
    }
  }

  /// Streams a message to the LLM and gets responses in chunks
  ///
  /// This function leverages the LlmClient's streamChat method to process user input
  /// and retrieve LLM responses as a stream of chunks.
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to use for processing the message (required)
  /// - [userInput] The message text from the user to process
  /// - [enableTools] Whether to enable tool usage in the response (default: true)
  /// - [enablePlugins] Whether to enable plugin usage in the response (default: true)
  /// - [parameters] Additional parameters to pass to the LLM provider (default: empty map)
  /// - [context] Optional context information for the LLM
  /// - [useRetrieval] Whether to use retrieval-augmented generation (default: false)
  /// - [enhanceSystemPrompt] Whether to enhance the system prompt with tool information (default: true)
  /// - [noHistory] Whether to clear conversation history before processing (default: false)
  ///
  /// Returns a Stream of [llm.LlmResponseChunk] objects containing the LLM's response chunks
  Stream<llm.LlmResponseChunk> streamChat(
      String llmId,
      String userInput, {
        bool enableTools = true,
        bool enablePlugins = true,
        Map<String, dynamic> parameters = const {},
        llm.LlmContext? context,
        bool useRetrieval = false,
        bool enhanceSystemPrompt = true,
        bool noHistory = false,
      }) {
    // Logger instance
    final logger = MCPLogger('mcp.llm_service');
    logger.debug('Processing stream chat request: $userInput');

    try {
      // Get LLM client from manager
      final llmClient = _llmManager.getLlmClient(llmId);
      if (llmClient == null) {
        logger.error('LLM client not found: $llmId');

        return Stream.value(llm.LlmResponseChunk(
          textChunk: 'Error: LLM client not found: $llmId',
          isDone: true,
          metadata: {'error': 'client_not_found'},
        ));
      }

      // Stream the response from LlmClient's streamChat method
      // Note: LlmClient.streamChat already includes performance monitoring
      return llmClient.streamChat(
        userInput,
        enableTools: enableTools,
        enablePlugins: enablePlugins,
        parameters: parameters,
        context: context,
        useRetrieval: useRetrieval,
        enhanceSystemPrompt: enhanceSystemPrompt,
        noHistory: noHistory,
      );
    } catch (e, stackTrace) {
      // Handle and log errors
      logger.error('Error in stream chat: $e', e, stackTrace);

      // Return error response
    return Stream.value(llm.LlmResponseChunk(
        textChunk: 'Error processing stream chat request: $e',
        isDone: true,
        metadata: {'error': e.toString()},
      ));
    }
  }

  /// Process documents in memory-efficient chunks with improved parallelism options
  Future<List<llm.Document>> processDocumentsInChunks(
      List<llm.Document> documents,
      Future<llm.Document> Function(llm.Document) processFunction, {
        int chunkSize = 10,
        Duration? pauseBetweenChunks,
        bool parallel = false,
        int maxParallelism = 3,
      }) async {
    _logger.debug('Processing ${documents.length} documents in chunks of $chunkSize${parallel ? ' with parallelism $maxParallelism' : ' sequentially'}');

    if (parallel) {
      // Process with controlled parallelism
      return await MemoryManager.processInParallelChunks<llm.Document, llm.Document>(
        items: documents,
        maxConcurrent: maxParallelism,
        chunkSize: chunkSize,
        pauseBetweenChunks: pauseBetweenChunks ?? Duration(milliseconds: 100),
        processItem: processFunction,
      );
    } else {
      // Process sequentially
      return await MemoryManager.processInChunks<llm.Document, llm.Document>(
        items: documents,
        chunkSize: chunkSize,
        pauseBetweenChunks: pauseBetweenChunks ?? Duration(milliseconds: 100),
        processItem: processFunction,
      );
    }
  }

  /// Estimate appropriate timeout based on message length
  Duration _estimateTimeout(int messageLength) {
    // Base timeout of 30 seconds
    int baseTimeoutSeconds = 30;

    // Add 1 second for every 500 characters (roughly 100 tokens)
    int additionalSeconds = (messageLength / 500).ceil();

    // Cap at 120 seconds to avoid excessive timeouts
    return Duration(seconds: min(baseTimeoutSeconds + additionalSeconds, 120));
  }

  /// Utility for retrying operations with exponential backoff
  Future<T> _retryWithExponentialBackoff<T>(
      Future<T> Function() operation, {
        Duration initialDelay = const Duration(milliseconds: 200),
        Duration maxDelay = const Duration(seconds: 10),
        double backoffFactor = 2.0,
        int maxRetries = 3,
        Duration timeout = const Duration(seconds: 30),
        bool Function(Exception)? retryIf,
        required String operationName,
      }) async {
    return await ErrorRecovery.tryWithExponentialBackoff(
        operation,
        initialDelay: initialDelay,
        maxDelay: maxDelay,
        backoffFactor: backoffFactor,
        maxRetries: maxRetries,
        timeout: timeout,
        retryIf: retryIf,
        operationName: operationName,
        onRetry: (attempt, error, delay) {
          _logger.warning(
              'Retrying $operationName (attempt ${attempt + 1}/$maxRetries) ' +
                  'after $delay due to error: ${error.toString().substring(0, min(100, error.toString().length))}'
          );
          PerformanceMonitor.instance.incrementCounter('retry.$operationName');
        }
    );
  }

  /// Utility for retrying operations with timeout (simpler version)
  Future<T> _retryWithTimeout<T>(
      Future<T> Function() operation, {
        Duration timeout = const Duration(seconds: 30),
        int maxRetries = 3,
        bool Function(Exception)? retryIf,
        required String operationName,
      }) async {
    // Implementation uses ErrorRecovery utility
    return await ErrorRecovery.tryWithTimeout(
            () => ErrorRecovery.tryWithRetry(
            operation,
            maxRetries: maxRetries,
            retryIf: retryIf,
            operationName: operationName,
            onRetry: (attempt, error) {
              _logger.warning(
                  'Retrying $operationName (attempt ${attempt + 1}/$maxRetries) ' +
                      'due to error: ${error.toString().substring(0, min(100, error.toString().length))}'
              );
              PerformanceMonitor.instance.incrementCounter('retry.$operationName');
            }
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
        message.contains('unavailable') ||
        message.contains('503') ||
        message.contains('429') ||
        message.contains('too many requests');
  }
/*
  /// Check if an error is a rate limit error
  bool _isRateLimitError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('429') ||
        message.contains('quota') ||
        message.contains('exceed') && (
            message.contains('limit') ||
                message.contains('request') ||
                message.contains('rate')
        );
  }

  /// Check if an error is an authentication error
  bool _isAuthError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('auth') ||
        message.contains('api key') ||
        message.contains('unauthorized') ||
        message.contains('401') ||
        message.contains('403') ||
        message.contains('permission') ||
        message.contains('invalid key');
  }

  /// Check if an error is a network error
  bool _isNetworkError(dynamic e) {
    final message = e.toString().toLowerCase();
    return message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout') ||
        message.contains('socket') ||
        message.contains('unreachable') ||
        message.contains('dns') ||
        message.contains('refused');
  }
*/
  /// Adds a document to the LLM's document store for retrieval
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to add the document to (required)
  /// - [document] The document to add to the LLM's document store
  /// - [llmClientId] The specific LLM client ID to use (optional, uses default if not specified)
  ///
  /// Returns the document ID assigned by the LLM system
  Future<String> addDocument(
      String llmId,
      llm.Document document, {
        String? llmClientId,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get the specified client or fall back to default/primary
      llm.LlmClient? llmClient;
      if (llmClientId != null) {
        // Use the specified client ID
        llmClient = llmInfo.llmClients[llmClientId];
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmId, 'LLM has no client configured');
        }
      }

      // Add with retry for transient errors
      final docId = await _retryWithTimeout(
              () => llmClient!.addDocument(document),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Add document to LLM'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.add_document',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'documentSize': document.content.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'docId': docId
          }
      );

      _stopwatchPool.release(stopwatch);
      return docId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.add_document',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to add document to LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to add document to LLM',
          e,
          stackTrace
      );
    }
  }

  /// Retrieve relevant documents for a query with improved relevance handling
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to use for retrieval (required)
  /// - [query] The search query text
  /// - [llmClientId] The specific LLM client ID to use (optional, uses default if not specified)
  /// - [topK] Number of results to return (default: 5)
  /// - [minRelevanceScore] Minimum relevance score threshold, 0.0-1.0 (default: 0.0)
  ///
  /// Returns a list of documents relevant to the query
  Future<List<llm.Document>> retrieveRelevantDocuments(
      String llmId,
      String query, {
        String? llmClientId,
        int topK = 5,
        double minRelevanceScore = 0.0,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get the specified client or fall back to default/primary
      llm.LlmClient? llmClient;
      if (llmClientId != null) {
        // Use the specified client ID
        llmClient = llmInfo.llmClients[llmClientId];
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmId, 'LLM has no client configured');
        }
      }

      // Retry wrapper for resilience
      final docs = await _retryWithTimeout(
              () => llmClient!.retrieveRelevantDocuments(
            query,
            topK: topK,
            minimumScore: minRelevanceScore > 0 ? minRelevanceScore : null,
          ),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Retrieve documents'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.retrieve_documents',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'count': docs.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'queryLength': query.length
          }
      );

      _stopwatchPool.release(stopwatch);
      return docs;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.retrieve_documents',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to retrieve relevant documents', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to retrieve relevant documents',
          e,
          stackTrace
      );
    }
  }

  /// Generate embeddings with improved error handling and caching
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to use for embeddings (required)
  /// - [text] The text to embed
  /// - [llmClientId] The specific LLM client ID to use (optional, uses default if not specified)
  ///
  /// Returns a list of embedding values (vector) for the input text
  Future<List<double>> generateEmbeddings(
      String llmId,
      String text, {
        String? llmClientId,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get the specified client or fall back to default/primary
      llm.LlmClient? llmClient;
      if (llmClientId != null) {
        // Use the specified client ID
        llmClient = llmInfo.llmClients[llmClientId];
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmId, 'LLM has no client configured');
        }
      }

      // Retry wrapper for resilience
      final embeddings = await _retryWithTimeout(
              () => llmClient!.generateEmbeddings(text),
          timeout: Duration(seconds: 20),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Generate embeddings'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.generate_embeddings',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'textLength': text.length,
            'embeddingDimensions': embeddings.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default'
          }
      );

      _stopwatchPool.release(stopwatch);
      return embeddings;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.generate_embeddings',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to generate embeddings', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to generate embeddings',
          e,
          stackTrace
      );
    }
  }

  /// Add scheduled job with validation
  ///
  /// [job]: Job to add
  ///
  /// Returns ID of the created job
  String addScheduledJob(MCPJob job) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (job.interval.inMilliseconds <= 0) {
      throw MCPValidationException(
          'Job interval must be positive',
          {'interval': 'Interval must be greater than zero'}
      );
    }

    return _scheduler.addJob(job);
  }

  /// Remove scheduled job with validation
  ///
  /// [jobId]: Job ID to remove
  void removeScheduledJob(String jobId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (jobId.isEmpty) {
      throw MCPValidationException(
          'Job ID cannot be empty',
          {'jobId': 'Job ID is required'}
      );
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      await _platformServices.secureStore(key, value);

      PerformanceMonitor.instance.recordMetric(
          'storage.store',
          stopwatch.elapsedMilliseconds,
          success: true
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'storage.store',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final value = await _platformServices.secureRead(key);

      PerformanceMonitor.instance.recordMetric(
          'storage.read',
          stopwatch.elapsedMilliseconds,
          success: true
      );

      _stopwatchPool.release(stopwatch);
      return value;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'storage.read',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to read secure value', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to read secure value for key: $key',
          e,
          stackTrace
      );
    }
  }

  /// Create chat session with improved persistence handling
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to create the chat session with (required)
  /// - [llmClientId] The specific LLM client ID to use (optional, uses default if not specified)
  /// - [sessionId] Optional session ID
  /// - [title] Optional session title
  /// - [storageManager] Optional storage manager for persisting chat history
  /// - [systemPrompt] Optional system prompt to initialize the session
  ///
  /// Returns a new ChatSession object
  Future<llm.ChatSession> createChatSession(
      String llmId, {
        String? llmClientId,
        String? sessionId,
        String? title,
        llm.StorageManager? storageManager,
        String? systemPrompt,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get the specified client or fall back to default/primary
      llm.LlmClient? llmClient;
      if (llmClientId != null) {
        // Use the specified client ID
        llmClient = llmInfo.llmClients[llmClientId];
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmId, 'LLM has no client configured');
        }
      }

      // Create a new chat session with storage
      final storage = storageManager ?? llm.MemoryStorage();
      final generatedId = 'session_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
      final session = llm.ChatSession(
        llmProvider: llmClient.llmProvider,
        storageManager: storage,
        id: sessionId ?? generatedId,
        title: title ?? 'Chat Session',
      );

      // Add system prompt if provided
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        session.addSystemMessage(systemPrompt);
      }

      // Register for resource cleanup
      _resourceManager.register<llm.ChatSession>(
          'chat_session_${session.id}',
          session,
              (s) async {
            // Persist state before cleanup
            if (storage is PersistentStorage) {
              await storage.persist();
            }
          },
          priority: ResourceManager.LOW_PRIORITY
      );

      PerformanceMonitor.instance.recordMetric(
          'chat.create_session',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'sessionId': session.id
          }
      );

      _stopwatchPool.release(stopwatch);
      return session;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'chat.create_session',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to create chat session', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create chat session for LLM: $llmId',
          e,
          stackTrace
      );
    }
  }
  /// Create a conversation with multiple sessions and enhanced persistence
  ///
  /// Parameters:
  /// - [llmId] The ID of the LLM to create the conversation with (required)
  /// - [llmClientId] The specific LLM client ID to use (optional, uses default if not specified)
  /// - [title] Optional conversation title
  /// - [topics] Optional topics for the conversation
  /// - [storageManager] Optional storage manager for persisting conversation
  /// - [initialSystemPrompt] Optional system prompt for the first session
  ///
  /// Returns a new Conversation object
  Future<llm.Conversation> createConversation(
      String llmId, {
        String? llmClientId,
        String? title,
        List<String>? topics,
        llm.StorageManager? storageManager,
        String? initialSystemPrompt,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final llmInfo = _llmManager.getLlmInfo(llmId);
      if (llmInfo == null) {
        throw MCPResourceNotFoundException(llmId, 'LLM not found');
      }

      // Get the specified client or fall back to default/primary
      llm.LlmClient? llmClient;
      if (llmClientId != null) {
        // Use the specified client ID
        llmClient = llmInfo.llmClients[llmClientId];
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(llmId, 'LLM has no client configured');
        }
      }

      // Create a new conversation
      final storage = storageManager ?? llm.MemoryStorage();
      final generatedId = 'conv_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
      final conversation = llm.Conversation(
        id: generatedId,
        title: title ?? 'Conversation',
        llmProvider: llmClient.llmProvider,
        topics: topics ?? [],
        storageManager: storage,
      );

      // Create initial session with system prompt if provided
      if (initialSystemPrompt != null && initialSystemPrompt.isNotEmpty) {
        final session = conversation.createSession();
        session.addSystemMessage(initialSystemPrompt);
      }

      // Register for resource cleanup
      _resourceManager.register<llm.Conversation>(
          'conversation_${conversation.id}',
          conversation,
              (c) async {
            // Persist its state before cleanup
            if (storage is PersistentStorage) {
              await storage.persist();
            }
          },
          priority: ResourceManager.LOW_PRIORITY
      );

      PerformanceMonitor.instance.recordMetric(
          'chat.create_conversation',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'conversationId': conversation.id
          }
      );

      _stopwatchPool.release(stopwatch);
      return conversation;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'chat.create_conversation',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to create conversation', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create conversation for LLM: $llmId',
          e,
          stackTrace
      );
    }
  }

  /// Generate a random string of specified length
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
        Iterable.generate(
            length,
                (_) => chars.codeUnitAt(random.nextInt(chars.length))
        )
    );
  }

  /// Select client for a query with improved matching algorithm
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

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
      final result = mcpLlm.selectClient(query, properties: properties);

      PerformanceMonitor.instance.recordMetric(
          'llm.select_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'selectedProvider': result?.runtimeType.toString(),
            'queryLength': query.length
          }
      );

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.select_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to select LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to select LLM client for query',
          e,
          stackTrace
      );
    }
  }

  /// Execute parallel query across multiple providers with improved aggregation and error handling
  ///
  /// [query]: Query text
  /// [providerNames]: List of provider names
  /// [aggregator]: Result aggregator
  /// [parameters]: Additional parameters
  /// [config]: LLM configuration
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  /// [timeout]: Optional timeout for the operation
  Future<llm.LlmResponse> executeParallel(
      String query, {
        List<String>? providerNames,
        llm.ResultAggregator? aggregator,
        Map<String, dynamic> parameters = const {},
        llm.LlmConfiguration? config,
        String mcpLlmInstanceId = 'default',
        Duration? timeout,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);

      // Apply timeout if provided
      final effectiveTimeout = timeout ?? _estimateTimeout(query.length) * 2;

      // Execute with timeout
      final result = await _executeWithTimeout(
              () => mcpLlm.executeParallel(
            query,
            providerNames: providerNames,
            aggregator: aggregator,
            parameters: parameters,
            config: config,
          ),
          effectiveTimeout,
          'Execute parallel query'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.execute_parallel',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'providers': providerNames?.length ?? 0,
            'queryLength': query.length,
            'responseLength': result.text.length,
          }
      );

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.execute_parallel',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to execute parallel query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to execute parallel query across providers',
          e,
          stackTrace
      );
    }
  }

  /// Execute a parallel query across multiple LLMs
  ///
  /// [query]: The text query to process
  /// [llmIds]: List of LLM IDs to use for parallel processing
  /// [aggregator]: Optional custom result aggregator (uses default if not provided)
  /// [parameters]: Additional parameters for the query
  /// [timeout]: Optional timeout for the entire operation
  ///
  /// Returns aggregated response from all participating LLMs
  Future<llm.LlmResponse> executeParallelQuery(
      String query,
      List<String> llmIds, {
        llm.ResultAggregator? aggregator,
        Map<String, dynamic> parameters = const {},
        Duration? timeout,
      }
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (llmIds.isEmpty) {
      throw MCPValidationException('No LLM IDs provided for parallel execution', {});
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();
    final operationId = 'llm.parallel_query';

    try {
      // Collect all clients to use (one from each LLM)
      final providers = <llm.LlmInterface>[];
      final providerToLlmMap = <llm.LlmInterface, String>{};

      for (final llmId in llmIds) {
        final llmInfo = _llmManager.getLlmInfo(llmId);
        if (llmInfo == null) {
          _logger.warning('LLM not found for parallel execution: $llmId - skipping');
          continue;
        }

        // Find a client to use
        if (!llmInfo.hasClients()) {
          _logger.warning('LLM has no clients: $llmId - skipping');
          continue;
        }

        // Use the default client
        final client = llmInfo.defaultLlmClient;
        if (client == null) {
          _logger.warning('No default client for LLM: $llmId - skipping');
          continue;
        }

        // Add the provider
        providers.add(client.llmProvider);
        providerToLlmMap[client.llmProvider] = llmId;
      }

      if (providers.isEmpty) {
        throw MCPException('No valid LLM clients found for any of the provided LLM IDs');
      }

      // Setup executor with all providers
      final executor = llm.ParallelExecutor(
        providers: providers,
        aggregator: aggregator,
      );

      // Create request
      final request = llm.LlmRequest(
        prompt: query,
        parameters: parameters,
      );

      // Apply timeout if provided
      final effectiveTimeout = timeout ?? _estimateTimeout(query.length) * 2;

      // Execute in parallel with timeout
      final result = await _executeWithTimeout(
              () => executor.executeParallel(request),
          effectiveTimeout,
          'Execute parallel query across multiple LLMs'
      );

      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmCount': providers.length,
            'queryLength': query.length,
            'responseLength': result.text.length,
          }
      );

      _logger.info('Executed parallel query across ${providers.length} LLMs');

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId,
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to execute parallel query', e, stackTrace);

      throw MCPOperationFailedException(
          'Failed to execute parallel query across multiple LLMs',
          e,
          stackTrace
      );
    }
  }

  /// Fan out query to multiple clients with improved parallelism and error handling
  ///
  /// [query]: Query text
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  /// [timeout]: Optional timeout for the entire operation
  Future<Map<String, llm.LlmResponse>> fanOutQuery(
      String query, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        String mcpLlmInstanceId = 'default',
        Duration? timeout,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);

      // Apply timeout if provided
      final effectiveTimeout = timeout ?? _estimateTimeout(query.length) * 2;

      // Execute with timeout
      final results = await _executeWithTimeout(
              () => mcpLlm.fanOutQuery(
            query,
            enableTools: enableTools,
            parameters: parameters,
          ),
          effectiveTimeout,
          'Fan out query to multiple LLMs'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.fanout_query',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'providerCount': results.length,
            'queryLength': query.length
          }
      );

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.fanout_query',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to fan out query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to fan out query to multiple LLM providers',
          e,
          stackTrace
      );
    }
  }

  /// Execute with timeout helper
  Future<T> _executeWithTimeout<T>(
      Future<T> Function() operation,
      Duration timeout,
      String operationName
      ) async {
    try {
      return await operation().timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
              'Operation timed out after ${timeout.inSeconds} seconds: $operationName'
          )
      );
    } on TimeoutException catch (e) {
      _logger.error('Timeout in operation: $operationName', e);
      rethrow;
    }
  }

  /// Helper method to get MCPLlm instance or throw if not found
  llm.MCPLlm _getMcpLlmInstanceOrThrow(String instanceId) {
    final lazy = _mcpLlmInstances[instanceId];
    if (lazy == null) {
      throw MCPResourceNotFoundException(instanceId, 'MCPLlm instance not found');
    }
    return lazy.value;
  }

  /// Register LLM provider with validation
  ///
  /// [name]: Provider name
  /// [factory]: Provider factory
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to register on (defaults to 'default')
  void registerLlmProvider(
      String name,
      llm.LlmProviderFactory factory, {
        String mcpLlmInstanceId = 'default',
      }) {
    if (name.isEmpty) {
      throw MCPValidationException(
          'Provider name cannot be empty',
          {'name': 'Provider name is required'}
      );
    }

    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    _registerProviderSafely(mcpLlm, name, factory);
  }

  /// List all registered MCPLlm instances
  List<String> getAllMcpLlmInstanceIds() {
    return _mcpLlmInstances.keys.toList();
  }

  /// Register a plugin with improved validation and error handling
  ///
  /// [plugin]: Plugin to register
  /// [config]: Optional plugin configuration
  Future<void> registerPlugin(MCPPlugin plugin, [Map<String, dynamic>? config]) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (plugin.name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty',
          {'name': 'Plugin name is required'}
      );
    }

    await _pluginRegistry.registerPlugin(plugin, config);

    // Register for cleanup
    _resourceManager.register<MCPPlugin>(
        'plugin_${plugin.name}',
        plugin,
            (p) async => await p.shutdown(),
        priority: ResourceManager.MEDIUM_PRIORITY
    );

    // Log registration
    _logger.info('Registered plugin: ${plugin.name} (${plugin.runtimeType})');
  }

  /// Unregister a plugin with improved error handling
  ///
  /// [pluginName]: Name of the plugin to unregister
  Future<void> unregisterPlugin(String pluginName) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (pluginName.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty',
          {'name': 'Plugin name is required'}
      );
    }

    await _pluginRegistry.unregisterPlugin(pluginName);

    // Remove from resource manager
    await _resourceManager.dispose('plugin_$pluginName');

    // Log unregistration
    _logger.info('Unregistered plugin: $pluginName');
  }

  /// Execute a tool plugin with improved error handling and timeout
  ///
  /// [name]: Plugin name
  /// [arguments]: Tool arguments
  Future<Map<String, dynamic>> executeToolPlugin(
      String name,
      Map<String, dynamic> arguments,
      {Duration? timeout}
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty',
          {'name': 'Plugin name is required'}
      );
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final effectiveTimeout = timeout ?? Duration(seconds: 30);

      // Execute with timeout
      final result = await _executeWithTimeout(
              () => _pluginRegistry.executeTool(name, arguments),
          effectiveTimeout,
          'Execute plugin tool $name'
      );

      PerformanceMonitor.instance.recordMetric(
          'plugin.execute_tool',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'plugin': name}
      );

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.execute_tool',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'plugin': name, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to execute tool plugin: $name', e, stackTrace);
      throw MCPPluginException(name, 'Failed to execute tool plugin', e, stackTrace);
    }
  }

  /// Get resource from a resource plugin with improved error handling
  ///
  /// [name]: Plugin name
  /// [resourceUri]: Resource URI
  /// [params]: Resource parameters
  Future<Map<String, dynamic>> getPluginResource(
      String name,
      String resourceUri,
      Map<String, dynamic> params,
      {Duration? timeout}
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty',
          {'name': 'Plugin name is required'}
      );
    }

    if (resourceUri.isEmpty) {
      throw MCPValidationException(
          'Resource URI cannot be empty',
          {'resourceUri': 'Resource URI is required'}
      );
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final effectiveTimeout = timeout ?? Duration(seconds: 30);

      // Execute with timeout
      final result = await _executeWithTimeout(
              () => _pluginRegistry.getResource(name, resourceUri, params),
          effectiveTimeout,
          'Get plugin resource from $name: $resourceUri'
      );

      PerformanceMonitor.instance.recordMetric(
          'plugin.get_resource',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'plugin': name, 'uri': resourceUri}
      );

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.get_resource',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'plugin': name, 'uri': resourceUri, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to get resource from plugin: $name', e, stackTrace);
      throw MCPPluginException(name, 'Failed to get resource from plugin', e, stackTrace);
    }
  }

  /// Show notification using a notification plugin with improved error handling
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

    if (name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty',
          {'name': 'Plugin name is required'}
      );
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      await _pluginRegistry.showNotification(
        name,
        title: title,
        body: body,
        id: id,
        icon: icon,
        additionalData: additionalData,
      );

      PerformanceMonitor.instance.recordMetric(
          'plugin.show_notification',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'plugin': name}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.show_notification',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'plugin': name, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to show notification using plugin: $name', e, stackTrace);
      throw MCPPluginException(name, 'Failed to show notification using plugin', e, stackTrace);
    }
  }

  /// Clean up all resources with improved prioritization
  Future<void> _cleanup() async {
    _logger.debug('Cleaning up resources');

    try {
      // Stop the scheduler first
      _scheduler.stop();

      // Clean up all registered resources in priority order
      await _resourceManager.disposeAll();

      // Signal the event system
      _eventSystem.publish('mcp.shutdown', {'timestamp': DateTime.now().toIso8601String()});

      // Ensure logger flushes
      await MCPLogger.flush();
    } catch (e, stackTrace) {
      _logger.error('Error during cleanup', e, stackTrace);
    }
  }

  /// Shutdown all services with graceful handling
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
  llm.LlmClient? getLlmClient(String llmId) => _llmManager.getLlmClient(llmId);
  llm.LlmServer? getLlmServer(String llmId) => _llmManager.getLlmServer(llmId);

  /// Get system status with enhanced information and health metrics
  Map<String, dynamic> getSystemStatus() {
    // Basic stats
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

    // Add memory stats
    if (_config?.highMemoryThresholdMB != null) {
      status['memory'] = {
        'currentUsageMB': MemoryManager.instance.currentMemoryUsageMB,
        'peakUsageMB': MemoryManager.instance.peakMemoryUsageMB,
        'thresholdMB': _config?.highMemoryThresholdMB,
      };
    }

    // Add circuit breaker status
    status['circuitBreakers'] = _circuitBreakers.map((name, breaker) =>
        MapEntry(name, {'state': breaker.state.toString(), 'failureCount': breaker.failureCount})
    );

    // Add performance metrics if available
    if (_config?.enablePerformanceMonitoring ?? false) {
      status['performanceMetrics'] = PerformanceMonitor.instance.getMetricsSummary();
    }

    // Add scheduler status
    status['scheduler'] = {
      'running': _scheduler.isRunning,
      'jobCount': _scheduler.jobCount,
      'activeJobCount': _scheduler.activeJobCount,
    };

    // Add cache stats
    status['cacheStats'] = {
      'responseCount': _llmResponseCaches.length,
      'instances': _llmResponseCaches.map((id, cache) =>
          MapEntry(id, {'size': cache.size, 'hitRate': cache.hitRate})
      ),
    };

    return status;
  }
}

/// Rate limit exception for LLM services with automatic retry-after calculation
class MCPRateLimitException extends MCPException {
  final Duration? retryAfter;

  MCPRateLimitException(
      String message,
      [dynamic originalError, StackTrace? stackTrace, this.retryAfter]
      ) : super('Rate limit error: $message', originalError, stackTrace);
}

/// Circuit breaker open exception for when too many operations have failed
class MCPCircuitBreakerOpenException extends MCPException {
  MCPCircuitBreakerOpenException(
      String message,
      [dynamic originalError, StackTrace? stackTrace]
      ) : super('Circuit breaker open: $message', originalError, stackTrace);
}

/// Interface for persistent storage
abstract class PersistentStorage implements llm.StorageManager {
  /// Persist storage to disk
  Future<void> persist();

  /// Load storage from disk
  Future<void> load();

  /// Get storage statistics
  Map<String, dynamic> getStats();
}

/// Lazy loading wrapper to defer expensive initializations
class Lazy<T> {
  final T Function() _factory;
  T? _value;
  bool _initialized = false;

  Lazy(this._factory);

  T get value {
    if (!_initialized) {
      _value = _factory();
      _initialized = true;
    }
    return _value!;
  }

  bool get isInitialized => _initialized;
}

/// Utilities for min/max operations
int min(int a, int b) => a < b ? a : b;
int max(int a, int b) => a > b ? a : b;

/// Mark a Future as unawaited
void unawaited(Future<void> future) {
  // Explicitly handles the future in a way that the analyzer recognizes as not needing an await
  future.then((_) {}, onError: (e, st) {});
}