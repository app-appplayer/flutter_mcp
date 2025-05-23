import 'dart:async';
import 'dart:math';
import 'package:flutter_mcp/src/config/plugin_config.dart';
import 'package:flutter_mcp/src/plugins/llm_plugin_integration.dart';
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
import 'src/utils/diagnostic_utils.dart';
import 'src/utils/platform_utils.dart';

// Re-exports
export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/plugin_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';
export 'src/utils/logger.dart';
export 'src/plugins/plugin_system.dart' show MCPPlugin, MCPToolPlugin, MCPResourcePlugin,
MCPBackgroundPlugin, MCPNotificationPlugin, MCPPromptPlugin;
export 'src/platform/tray/tray_manager.dart' show TrayMenuItem;
export 'package:mcp_client/mcp_client.dart'
    show ClientCapabilities, Client, ClientTransport;
export 'package:mcp_server/mcp_server.dart'
    show ServerCapabilities, Server, ServerTransport,
    Content, TextContent, ImageContent, ResourceContent,
    Tool, Resource, Message, MessageRole, MCPContentType, CallToolResult;
export 'package:mcp_llm/mcp_llm.dart';

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

  String? _defaultLlmClientId;
  String? _defaultLlmServerId;

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

  String? get defaultLlmClientId => _defaultLlmClientId;
  String? get defaultLlmServerId => _defaultLlmServerId;

  /// Initialize the plugin with improved concurrency handling and plugin integration
  ///
  /// [config] specifies the configuration for necessary components.
  Future<void> init(MCPConfig config) async {
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
      if (config.pluginConfigurations != null) {
        await _initializePluginRegistry(config.pluginConfigurations!);
      }

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
  Future<void> _initializePluginRegistry(List<PluginConfig> config) async {
    // Setup plugin integration system based on config
    for (final entry in config) {
      final plugin = entry.plugin;
      final config = entry.config;

      await registerPlugin(plugin, config);
    }

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

  void setDefaultLlmClientId(String llmClientId) {
    _defaultLlmClientId = llmClientId;
    _logger.info('Default LLM client ID set to: $llmClientId');
  }

  void setDefaultLlmServerId(String llmServerId) {
    _defaultLlmServerId = llmServerId;
    _logger.info('Default LLM server ID set to: $llmServerId');
  }

  /// Start a client from configuration with improved error handling
  Future<String> _startClient(MCPClientConfig clientConfig) async {
    final clientId = await createClient(
      name: clientConfig.name,
      version: clientConfig.version,
      capabilities: clientConfig.capabilities,
      transportCommand: clientConfig.transportCommand,
      transportArgs: clientConfig.transportArgs,
      serverUrl: clientConfig.serverUrl,
      authToken: clientConfig.authToken,
    );

    _logger.debug('Created MCP client: ${clientConfig.name} with ID $clientId');
    return clientId;
  }

  /// Start a server from configuration with improved error handling
  Future<String> _startServer(MCPServerConfig serverConfig) async {
    final serverId = await createServer(
      name: serverConfig.name,
      version: serverConfig.version,
      capabilities: serverConfig.capabilities,
      useStdioTransport: serverConfig.useStdioTransport,
      ssePort: serverConfig.ssePort,
      fallbackPorts: serverConfig.fallbackPorts,
      authToken: serverConfig.authToken,
    );

    _logger.debug('Created MCP server: ${serverConfig.name} with ID $serverId');
    return serverId;
  }

  /// Start configured components with improved error handling and parallelism
  Future<Map<String, dynamic>> _startConfiguredComponents() async {
    final config = _config!;
    final startErrors = <String, dynamic>{};

    // 1. Create MCP servers (without connection)
    final mcpServerMap = <String, String>{};  // index/name -> actual server ID mapping

    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (int i = 0; i < config.autoStartServer!.length; i++) {
        final serverConfig = config.autoStartServer![i];
        try {
          final serverId = await _startServer(serverConfig);
          mcpServerMap['server_$i'] = serverId;  // Reference by index
          mcpServerMap[serverConfig.name] = serverId;  // Reference by name
        } catch (e, stackTrace) {
          _logger.error('Failed to create server: ${serverConfig.name}', e, stackTrace);
          startErrors['server.${serverConfig.name}'] = e;
        }
      }
    }

    // 2. Create MCP clients (without connection)
    final mcpClientMap = <String, String>{};  // index/name -> actual client ID mapping

    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (int i = 0; i < config.autoStartClient!.length; i++) {
        final clientConfig = config.autoStartClient![i];
        try {
          final clientId = await _startClient(clientConfig);
          mcpClientMap['client_$i'] = clientId;  // Reference by index
          mcpClientMap[clientConfig.name] = clientId;  // Reference by name
        } catch (e, stackTrace) {
          _logger.error('Failed to create client: ${clientConfig.name}', e, stackTrace);
          startErrors['client.${clientConfig.name}'] = e;
        }
      }
    }

    // 3. Create LLM servers and connect to MCP servers
    if (config.autoStartLlmServer != null && config.autoStartLlmServer!.isNotEmpty) {
      for (int i = 0; i < config.autoStartLlmServer!.length; i++) {
        final llmConfig = config.autoStartLlmServer![i];
        try {
          // Create LLM server
          final (llmId, llmServerId) = await createLlmServer(
            providerName: llmConfig.providerName,
            config: llmConfig.config,
          );

          // Connect to MCP servers
          for (final mcpServerRef in llmConfig.mcpServerIds) {
            if (mcpServerMap.containsKey(mcpServerRef)) {
              final mcpServerId = mcpServerMap[mcpServerRef]!;

              // Add association
              await addMcpServerToLlmServer(
                mcpServerId: mcpServerId,
                llmServerId: llmServerId,
              );

              _logger.debug('Associated MCP server $mcpServerId with LLM server $llmServerId');
            } else {
              _logger.warning('MCP server reference not found: $mcpServerRef');
            }
          }

          // Set as default if needed
          if (llmConfig.isDefault) {
            _defaultLlmServerId = llmServerId;
            _logger.debug('Set default LLM server: $llmServerId');
          }

          // Register core plugins if configured
          if (config.registerCoreLlmPlugins == true) {
            try {
              await registerCoreLlmPlugins(
                  llmId,
                  llmServerId,
                  isServer: true,
                  includeRetrievalPlugins: config.enableRetrieval ?? false
              );
            } catch (e) {
              _logger.warning('Failed to register core plugins for LLM server $llmServerId: $e');
              startErrors['llm.server.plugins.$i'] = e;
            }
          }
        } catch (e, stackTrace) {
          _logger.error('Failed to create LLM server at index $i', e, stackTrace);
          startErrors['llm.server.$i'] = e;
        }
      }
    }

    // 4. Create LLM clients and connect to MCP clients
    if (config.autoStartLlmClient != null && config.autoStartLlmClient!.isNotEmpty) {
      for (int i = 0; i < config.autoStartLlmClient!.length; i++) {
        final llmConfig = config.autoStartLlmClient![i];
        try {
          // Create LLM client
          final (llmId, llmClientId) = await createLlmClient(
            providerName: llmConfig.providerName,
            config: llmConfig.config,
          );

          // Connect to MCP clients
          for (final mcpClientRef in llmConfig.mcpClientIds) {
            if (mcpClientMap.containsKey(mcpClientRef)) {
              final mcpClientId = mcpClientMap[mcpClientRef]!;

              // Add association
              await addMcpClientToLlmClient(
                mcpClientId: mcpClientId,
                llmClientId: llmClientId,
              );

              _logger.debug('Associated MCP client $mcpClientId with LLM client $llmClientId');
            } else {
              _logger.warning('MCP client reference not found: $mcpClientRef');
            }
          }

          // Set as default if needed
          if (llmConfig.isDefault) {
            _defaultLlmClientId = llmClientId;
            _logger.debug('Set default LLM client: $llmClientId');
          }

          // Register core plugins if configured
          if (config.registerCoreLlmPlugins == true) {
            try {
              await registerCoreLlmPlugins(
                  llmId,
                  llmClientId,
                  isServer: false,
                  includeRetrievalPlugins: config.enableRetrieval ?? false
              );
            } catch (e) {
              _logger.warning('Failed to register core plugins for LLM client $llmClientId: $e');
              startErrors['llm.client.plugins.$i'] = e;
            }
          }
        } catch (e, stackTrace) {
          _logger.error('Failed to create LLM client at index $i', e, stackTrace);
          startErrors['llm.client.$i'] = e;
        }
      }
    }

    // 5. Connect all MCP servers
    for (final serverId in mcpServerMap.values.toSet()) {
      try {
        connectServer(serverId);
        _logger.debug('Connected MCP server: $serverId');
      } catch (e, stackTrace) {
        _logger.error('Failed to connect server: $serverId', e, stackTrace);
        startErrors['connect.server.$serverId'] = e;
      }
    }

    // 6. Connect all MCP clients
    for (final clientId in mcpClientMap.values.toSet()) {
      try {
        await connectClient(clientId);
        _logger.debug('Connected MCP client: $clientId');
      } catch (e, stackTrace) {
        _logger.error('Failed to connect client: $clientId', e, stackTrace);
        startErrors['connect.client.$clientId'] = e;
      }
    }

    // 7. Handle MCP plugin integration
    if (config.registerMcpPluginsWithLlm == true) {
      final mcpPlugins = _pluginRegistry.getAllPlugins();
      for (final plugin in mcpPlugins) {
        if (plugin is MCPToolPlugin || plugin is MCPResourcePlugin || plugin is MCPPromptPlugin) {
          try {
            await convertMcpPluginToLlm(plugin);
          } catch (e) {
            _logger.warning('Failed to convert MCP plugin ${plugin.name} to LLM plugin: $e');
            startErrors['plugin.convert.${plugin.name}'] = e;
          }
        }
      }
    }

    if (startErrors.isNotEmpty) {
      _logger.warning(
          'Some components failed to start (${startErrors.length} errors). ' +
              'First error: ${startErrors.values.first}'
      );
    }

    return startErrors;
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
  /// Returns a tuple with llmId and llmClientId
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
      if (! _mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
        _logger.debug('Creating new MCPLlm instance: $mcpLlmInstanceId');
        createMcpLlmInstance(mcpLlmInstanceId);
      }

      final mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!.value;

      _logger.info('Creating LLM instance with client for $providerName on MCPLlm instance $mcpLlmInstanceId');

      var llmId = 'llm_$mcpLlmInstanceId';
      if(_llmManager.getLlmInfo(mcpLlmInstanceId) == null) {
        // Register with the LLM manager (no clients or servers yet)
        _llmManager.registerLlm(llmId, mcpLlm);
      }

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
      final llmClientId = _llmManager.generateLlmClientId(llmId);

      // Create a new LLM client using mcpLlm
      final llmClient = await _retryWithTimeout(
              () => mcpLlm.createClient(
            providerName: providerName,
            config: config,
            clientId: llmClientId,
            storageManager: storageManager,
            retrievalManager: retrievalManager,
          ),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Create LLM client for $providerName'
      );

      // Add to LLM manager
      await _llmManager.addLlmClient(llmId, llmClientId, llmClient);

      // Create semantic cache for this client
      _llmResponseCaches[llmId] = SemanticCache(
        maxSize: 100,
        ttl: Duration(hours: 1),
        embeddingFunction: (text) async => await llmClient.generateEmbeddings(text),
        similarityThreshold: 0.85,
      );

      if(_config?.pluginConfigurations != null) {
        // Register plugins for this client
        for (final entry in _config!.pluginConfigurations!) {
          final plugin = entry.plugin;
          final targets = entry.targets;

          if (targets != null && targets.contains(mcpLlmInstanceId)) {
            await convertMcpPluginToLlm(
              plugin,
              targetLlmIds: [llmId],
              targetLlmClientIds: [llmClientId],
            );
          }
        }
      }

      // Auto-register plugins if configured
      if (_config?.autoRegisterLlmPlugins == true) {
        try {
          await registerPluginsFromLlmClient(llmId, llmClientId);
          _logger.debug('Auto-registered plugins from new LLM client $llmClientId');
        } catch (e) {
          _logger.warning('Failed to auto-register plugins from new LLM client $llmClientId: $e');
        }
      }

      // Register core plugins if configured
      if (_config?.registerCoreLlmPlugins == true) {
        try {
          await registerCoreLlmPlugins(
              llmId,
              llmClientId,
              isServer: false,
              includeRetrievalPlugins: _config?.enableRetrieval ?? false
          );
        } catch (e) {
          _logger.warning('Failed to register core plugins for LLM client $llmClientId: $e');
        }
      }

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
  /// Returns a tuple with llmId and llmServerId
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

      var llmId = 'llm_$mcpLlmInstanceId';
      if(_llmManager.getLlmInfo(mcpLlmInstanceId) == null) {
        // Register with the LLM manager (no clients or servers yet)
        _llmManager.registerLlm(llmId, mcpLlm);
      }

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
      final llmServerId = _llmManager.generateLlmServerId(llmId);

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
      await _llmManager.addLlmServer(llmId, llmServerId, llmServer);

      // Auto-register plugins if configured
      if (_config?.autoRegisterLlmPlugins == true) {
        try {
          await registerPluginsFromLlmServer(llmId, llmServerId);
          _logger.debug('Auto-registered plugins from new LLM server $llmServerId');
        } catch (e) {
          _logger.warning('Failed to auto-register plugins from new LLM server $llmServerId: $e');
        }
      }

      if(_config?.pluginConfigurations != null) {
        // Register plugins for this client
        for (final entry in _config!.pluginConfigurations!) {
          final plugin = entry.plugin;
          final targets = entry.targets;

          if (targets != null && targets.contains(mcpLlmInstanceId)) {
            await convertMcpPluginToLlm(
              plugin,
              targetLlmIds: [llmId],
              targetLlmServerIds: [llmServerId],
            );
          }
        }
      }

      // Register core plugins if configured
      if (_config?.registerCoreLlmPlugins == true) {
        try {
          await registerCoreLlmPlugins(
              llmId,
              llmServerId,
              isServer: true,
              includeRetrievalPlugins: _config?.enableRetrieval ?? false
          );
        } catch (e) {
          _logger.warning('Failed to register core plugins for LLM server $llmServerId: $e');
        }
      }

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
  Future<void> addMcpClientToLlmClient({
    required String mcpClientId,
    required String llmClientId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating mcpClient with LlmClient: $mcpClientId + $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpClient = _clientManager.getClient(mcpClientId);
      if (mcpClient == null) {
        throw MCPResourceNotFoundException(mcpClientId, 'mcpClient not found');
      }

      // Add client to LLM with retry
      await _retryWithTimeout(
              () => _llmManager.addMcpClientToLlmClient(llmClientId, mcpClientId, mcpClient),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add mcpClient to LlmClient'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to integrate mcpClient with llmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate mcpClient with LlmClient',
          e,
          stackTrace
      );
    }
  }

  /// Remove client from LLM
  ///
  /// [clientId]: Client ID
  /// [llmId]: LLM ID
  Future<void> removeMcpClientFromLlmClient({
    required String mcpClientId,
    required String llmClientId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Removing mcpClient from llmClient: $mcpClientId from $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove client from LLM with retry
      await _retryWithTimeout(
              () => _llmManager.removeMcpClientFromLlmClient(llmClientId, mcpClientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove mcpClient from llmClient'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove mcpClient from llmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove mcpClient from llmClient',
          e,
          stackTrace
      );
    }
  }

  /// Set default client for LLM
  ///
  /// [clientId]: Client ID to set as default
  /// [llmId]: LLM ID
  Future<void> setDefaultMcpClientForLlmClient({
    required String mcpClientId,
    required String llmClientId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Setting default mcpClient for LlmClient: $mcpClientId as default for $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default client for LLM with retry
      await _retryWithTimeout(
              () => _llmManager.setDefaultMcpClientForLlmClient(llmClientId, mcpClientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default mcpClient for LlmClient'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to set default mcpClient for LlmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default mcpClient for LlmClient',
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
  Future<void> addMcpServerToLlmServer({
    required String mcpServerId,
    required String llmServerId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating mcpServer with llmServer: $mcpServerId + $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpServer = _serverManager.getServer(mcpServerId);
      if (mcpServer == null) {
        throw MCPResourceNotFoundException(mcpServerId, 'Server not found');
      }

      // Add server to LLM with retry
      await _retryWithTimeout(
              () => _llmManager.addMcpServerToLlmServer(llmServerId, mcpServerId, mcpServer),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add mcpServer to llmServer'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to integrate mcpServer with llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate mcpServer with llmServer',
          e,
          stackTrace
      );
    }
  }

  /// Remove server from LLM
  ///
  /// [serverId]: Server ID
  /// [llmId]: LLM ID
  Future<void> removeMcpServerFromLlmServer({
    required String mcpServerId,
    required String llmServerId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Removing mcpServer from llmServer: $mcpServerId from $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove server from LLM with retry
      await _retryWithTimeout(
              () => _llmManager.removeMcpServerFromLlmServer(llmServerId, mcpServerId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove mcpServer from llmServer'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to remove mcpServer from llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove mcpServer from llmServer',
          e,
          stackTrace
      );
    }
  }

  /// Set default server for LLM
  ///
  /// [serverId]: Server ID to set as default
  /// [llmId]: LLM ID
  Future<void> setDefaultMcpServerForLlmServer({
    required String mcpServerId,
    required String llmServerId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Setting default mcpServer for llmServer: $mcpServerId as default for $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default server for LLM with retry
      await _retryWithTimeout(
              () => _llmManager.setDefaultMcpServerForLlmServer(llmServerId, mcpServerId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default mcpServer for llmServer'
      );

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server',
          stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId}
      );

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId, 'error': e.toString()}
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to set default mcpServer for llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default mcpServer for llmServerM',
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
        String? llmClientId,
        bool enableTools = true,
        bool enablePlugins = true,
        Map<String, dynamic> parameters = const {},
        llm.LlmContext? context,
        bool useRetrieval = false,
        bool enhanceSystemPrompt = true,
        bool noHistory = false,
      }) async {
    // Logger instance
    final _logger = MCPLogger('mcp.llm_service');
    _logger.debug('Processing chat request: $userInput');

    try {
      // Get LLM client from manager
      llmClientId ??= await _llmManager.getDefaultLlmClientId(llmId);
      final llmClient = _llmManager.getLlmClientById(llmClientId);
      if (llmClient == null) {
        _logger.error('LLM client not found: $llmClientId');
        return llm.LlmResponse(
          text: 'Error: LLM client not found: $llmClientId',
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
      _logger.error('Error in chat: $e', e, stackTrace);

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
        String? llmClientId,
        bool enableTools = true,
        bool enablePlugins = true,
        Map<String, dynamic> parameters = const {},
        llm.LlmContext? context,
        bool useRetrieval = false,
        bool enhanceSystemPrompt = true,
        bool noHistory = false,
      }) async* {
    // Logger instance
    final logger = MCPLogger('mcp.llm_service');
    logger.debug('Processing stream chat request: $userInput');

    try {
      // Get LLM client from manager
      llmClientId ??= await _llmManager.getDefaultLlmClientId(llmId);
      final llmClient = _llmManager.getLlmClientById(llmClientId);
      if (llmClient == null) {
        logger.error('LLM client not found: $llmId');
        yield llm.LlmResponseChunk(
          textChunk: 'Error: LLM client not found: $llmId',
          isDone: true,
          metadata: {'error': 'client_not_found'},
        );
        return;
      }

      // Stream the response from LlmClient's streamChat method
      // Note: LlmClient.streamChat already includes performance monitoring
      await for (final chunk in llmClient.streamChat(
        userInput,
        enableTools: enableTools,
        enablePlugins: enablePlugins,
        parameters: parameters,
        context: context,
        useRetrieval: useRetrieval,
        enhanceSystemPrompt: enhanceSystemPrompt,
        noHistory: noHistory,
      )) {
        yield chunk;
      }
    } catch (e, stackTrace) {
      // Handle and log errors
      logger.error('Error in stream chat: $e', e, stackTrace);
      yield llm.LlmResponseChunk(
        textChunk: 'Error processing stream chat request: $e',
        isDone: true,
        metadata: {'error': e.toString()},
      );
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
          onTimeout: () => throw MCPTimeoutException(
              'Operation timed out after ${timeout.inSeconds} seconds: $operationName',
              timeout
          )
      );
    } on MCPTimeoutException catch (e) {
      _logger.error('Timeout in operation: $operationName', e);
      rethrow;
    } on TimeoutException catch (e) {
      _logger.error('Timeout in operation: $operationName', e);
      throw MCPTimeoutException(
        'Operation timed out: $operationName', 
        timeout,
        e
      );
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

  /// Register a plugin from LLM to the flutter_mcp plugin system
  ///
  /// This method enables unified plugin registration between systems
  ///
  /// Parameters:
  /// - [llmPlugin] The mcp_llm plugin to register with flutter_mcp
  /// - [config] Optional configuration for the plugin
  /// - [mcpLlmInstanceId] ID of the MCPLlm instance (defaults to 'default')
  ///
  /// Returns true if registration was successful
  Future<bool> registerLlmPluginWithSystem(
      llm.LlmPlugin llmPlugin, {
        Map<String, dynamic>? config,
        String mcpLlmInstanceId = 'default',
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Get the LLM plugin integrator from the LLM Manager
      final integrator = _llmManager.getPluginIntegrator();

      // Register the plugin with the system
      final result = await integrator.registerLlmPlugin(llmPlugin, config);

      if (result) {
        _logger.info('Successfully registered LLM plugin ${llmPlugin.name} with flutter_mcp system');

        // Publish event for plugin registration
        _eventSystem.publish('plugin.registered', {
          'name': llmPlugin.name,
          'type': 'llm_plugin',
          'source': mcpLlmInstanceId,
        });
      }

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_llm_plugin',
          stopwatch.elapsedMilliseconds,
          success: result,
          metadata: {
            'plugin': llmPlugin.name,
            'mcpLlmInstanceId': mcpLlmInstanceId,
          }
      );

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_llm_plugin',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'plugin': llmPlugin.name,
            'mcpLlmInstanceId': mcpLlmInstanceId,
            'error': e.toString(),
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to register LLM plugin with flutter_mcp system', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register LLM plugin with flutter_mcp system',
          e,
          stackTrace
      );
    }
  }

  /// Register all plugins from an LLM client with the flutter_mcp system
  ///
  /// Parameters:
  /// - [llmId] ID of the LLM instance
  /// - [llmClientId] ID of the LLM client
  ///
  /// Returns a map of plugin names to registration success status
  Future<Map<String, bool>> registerPluginsFromLlmClient(
      String llmId,
      String llmClientId
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Get the LLM client
      final llmClient = _llmManager.getLlmClientById(llmClientId);
      if (llmClient == null) {
        throw MCPResourceNotFoundException(llmClientId, 'LLM client not found');
      }

      // Get the LLM plugin integrator
      final integrator = _llmManager.getPluginIntegrator();

      // Register all plugins from the client
      final results = await integrator.registerPluginsFromLlmClient(llmClientId, llmClient);

      // Count successes
      final successCount = results.values.where((v) => v).length;

      _logger.info('Registered $successCount/${results.length} plugins from LLM client $llmClientId');

      // Publish event for plugin registration
      _eventSystem.publish('plugins.batch_registered', {
        'source': 'llm_client',
        'llmId': llmId,
        'llmClientId': llmClientId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_client',
          stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'successCount': successCount,
            'totalCount': results.length,
          }
      );

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_client',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'error': e.toString(),
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to register plugins from LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM client $llmClientId',
          e,
          stackTrace
      );
    }
  }

  /// Register all plugins from an LLM server with the flutter_mcp system
  ///
  /// Parameters:
  /// - [llmId] ID of the LLM instance
  /// - [llmServerId] ID of the LLM server
  ///
  /// Returns a map of plugin names to registration success status
  Future<Map<String, bool>> registerPluginsFromLlmServer(
      String llmId,
      String llmServerId
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Get the LLM server
      final llmServer = _llmManager.getLlmServerById(llmServerId);
      if (llmServer == null) {
        throw MCPResourceNotFoundException(llmServerId, 'LLM server not found');
      }

      // Get the LLM plugin integrator
      final integrator = _llmManager.getPluginIntegrator();

      // Register all plugins from the server
      final results = await integrator.registerPluginsFromLlmServer(llmServerId, llmServer);

      // Count successes
      final successCount = results.values.where((v) => v).length;

      _logger.info('Registered $successCount/${results.length} plugins from LLM server $llmServerId');

      // Publish event for plugin registration
      _eventSystem.publish('plugins.batch_registered', {
        'source': 'llm_server',
        'llmId': llmId,
        'llmServerId': llmServerId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_server',
          stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'successCount': successCount,
            'totalCount': results.length,
          }
      );

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_server',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'error': e.toString(),
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to register plugins from LLM server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM server $llmServerId',
          e,
          stackTrace
      );
    }
  }

  /// Register core LLM plugins with the flutter_mcp system
  ///
  /// This method creates and registers the standard set of plugins provided by mcp_llm
  ///
  /// Parameters:
  /// - [llmId] ID of the LLM instance
  /// - [clientOrServerId] ID of either an LLM client or server to use for plugin creation
  /// - [isServer] Whether the ID is for a server (true) or client (false)
  /// - [includeCompletionPlugin] Whether to include the completion plugin
  /// - [includeStreamingPlugin] Whether to include the streaming plugin
  /// - [includeEmbeddingPlugin] Whether to include the embedding plugin
  /// - [includeRetrievalPlugins] Whether to include retrieval plugins
  ///
  /// Returns a map of plugin names to registration success status
  Future<Map<String, bool>> registerCoreLlmPlugins(
      String llmId,
      String clientOrServerId, {
        bool isServer = false,
        bool includeCompletionPlugin = true,
        bool includeStreamingPlugin = true,
        bool includeEmbeddingPlugin = true,
        bool includeRetrievalPlugins = false,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Register core plugins through LLM manager
      final results = await _llmManager.registerCoreLlmPlugins(
        llmId,
        llmClientId: isServer ? null : clientOrServerId,
        llmServerId: isServer ? clientOrServerId : null,
        includeCompletionPlugin: includeCompletionPlugin,
        includeStreamingPlugin: includeStreamingPlugin,
        includeEmbeddingPlugin: includeEmbeddingPlugin,
        includeRetrievalPlugins: includeRetrievalPlugins,
      );

      // Count successes
      final successCount = results.values.where((v) => v).length;

      _logger.info('Registered $successCount/${results.length} core LLM plugins for ${isServer ? 'server' : 'client'} $clientOrServerId');

      // Publish event for plugin registration
      _eventSystem.publish('plugins.core_registered', {
        'source': isServer ? 'llm_server' : 'llm_client',
        'llmId': llmId,
        'clientOrServerId': clientOrServerId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_core_llm_plugins',
          stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'clientOrServerId': clientOrServerId,
            'isServer': isServer,
            'successCount': successCount,
            'totalCount': results.length,
          }
      );

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_core_llm_plugins',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'clientOrServerId': clientOrServerId,
            'isServer': isServer,
            'error': e.toString(),
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to register core LLM plugins', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register core LLM plugins for ${isServer ? 'server' : 'client'} $clientOrServerId',
          e,
          stackTrace
      );
    }
  }

  /// Convert an MCPPlugin to an LLM plugin
  ///
  /// This method creates an adapter that allows a flutter_mcp plugin to be used with mcp_llm
  ///
  /// Parameters:
  /// - [mcpPlugin] The flutter_mcp plugin to adapt for mcp_llm
  /// - [targetLlmIds] Optional list of LLM IDs to register the plugin with
  /// - [targetLlmClientIds] Optional list of LLM client IDs to register the plugin with
  /// - [targetLlmServerIds] Optional list of LLM server IDs to register the plugin with
  ///
  /// Returns true if the conversion and registration were successful
  Future<bool> convertMcpPluginToLlm(
      MCPPlugin mcpPlugin, {
        List<String>? targetLlmIds,
        List<String>? targetLlmClientIds,
        List<String>? targetLlmServerIds,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Create appropriate adapter
      llm.LlmPlugin? adapter;

      if (mcpPlugin is MCPToolPlugin) {
        adapter = McpToolPluginAdapter(mcpPlugin);
      } else if (mcpPlugin is MCPResourcePlugin) {
        adapter = McpResourcePluginAdapter(mcpPlugin);
      } else if (mcpPlugin is MCPPromptPlugin) {
        adapter = McpPromptPluginAdapter(mcpPlugin);
      } else {
        throw MCPValidationException(
            'Unsupported MCP plugin type: ${mcpPlugin.runtimeType}',
            {'plugin_type': mcpPlugin.runtimeType.toString()}
        );
      }

      bool anySuccess = false;

      // Register with specified LLM instances
      if (targetLlmIds != null && targetLlmIds.isNotEmpty) {
        for (final llmId in targetLlmIds) {
          final llmInfo = _llmManager.getLlmInfo(llmId);
          if (llmInfo != null) {
            // Register with the LLM instance's plugin manager
            // This is a simplified version - in a real implementation, you'd need to
            // register with the plugin managers of all clients and servers in the LLM
            anySuccess = true;
          }
        }
      }

      // Register with specified LLM clients
      if (targetLlmClientIds != null && targetLlmClientIds.isNotEmpty) {
        for (final clientId in targetLlmClientIds) {
          final client = _llmManager.getLlmClientById(clientId);
          if (client != null) {
            await client.pluginManager.registerPlugin(adapter);
            anySuccess = true;
          }
        }
      }

      // Register with specified LLM servers
      if (targetLlmServerIds != null && targetLlmServerIds.isNotEmpty) {
        for (final serverId in targetLlmServerIds) {
          final server = _llmManager.getLlmServerById(serverId);
          if (server != null) {
            await server.pluginManager.registerPlugin(adapter);
            anySuccess = true;
          }
        }
      }

      // If no specific targets were specified, register with all LLM instances
      if ((targetLlmIds == null || targetLlmIds.isEmpty) &&
          (targetLlmClientIds == null || targetLlmClientIds.isEmpty) &&
          (targetLlmServerIds == null || targetLlmServerIds.isEmpty)) {

        // Register with all LLM clients
        for (final llmId in _llmManager.getAllLlmIds()) {
          final llmInfo = _llmManager.getLlmInfo(llmId);
          if (llmInfo != null) {
            for (final clientId in llmInfo.getAllLlmClientIds()) {
              final client = llmInfo.llmClients[clientId];
              if (client != null) {
                await client.pluginManager.registerPlugin(adapter);
                anySuccess = true;
              }
            }

            for (final serverId in llmInfo.getAllLlmServerIds()) {
              final server = llmInfo.llmServers[serverId];
              if (server != null) {
                await server.pluginManager.registerPlugin(adapter);
                anySuccess = true;
              }
            }
          }
        }
      }

      _logger.info('Converted MCP plugin ${mcpPlugin.name} to LLM plugin and registered with ${anySuccess ? 'some' : 'no'} targets');

      // Publish event for plugin conversion
      _eventSystem.publish('plugin.converted', {
        'name': mcpPlugin.name,
        'source': 'mcp_plugin',
        'target': 'llm_plugin',
        'success': anySuccess,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.convert_mcp_to_llm',
          stopwatch.elapsedMilliseconds,
          success: anySuccess,
          metadata: {
            'plugin': mcpPlugin.name,
            'targetLlmCount': targetLlmIds?.length ?? 0,
            'targetClientCount': targetLlmClientIds?.length ?? 0,
            'targetServerCount': targetLlmServerIds?.length ?? 0,
          }
      );

      _stopwatchPool.release(stopwatch);
      return anySuccess;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.convert_mcp_to_llm',
          stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'plugin': mcpPlugin.name,
            'error': e.toString(),
          }
      );

      _stopwatchPool.release(stopwatch);
      _logger.error('Failed to convert MCP plugin to LLM plugin', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to convert MCP plugin ${mcpPlugin.name} to LLM plugin',
          e,
          stackTrace
      );
    }
  }

  /// Get all plugins registered with the system
  ///
  /// Returns a map of plugin information categorized by type
  Map<String, List<Map<String, dynamic>>> getAllPluginInfo() {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Get plugin registry info
    final mcpPlugins = _pluginRegistry.getAllPlugins();

    // Get LLM plugin registry info
    final llmPlugins = _llmManager.getPluginIntegrator().getRegisteredLlmPluginNames();

    // Organize plugins by type
    final result = <String, List<Map<String, dynamic>>>{
      'tool_plugins': [],
      'resource_plugins': [],
      'prompt_plugins': [],
      'other_plugins': [],
    };

    // Process MCP plugins
    for (final plugin in mcpPlugins) {
      final info = {
        'name': plugin.name,
        'version': plugin.version,
        'description': plugin.description,
        'type': 'mcp',
        'plugin_type': _getPluginTypeString(plugin),
      };

      if (plugin is MCPToolPlugin) {
        result['tool_plugins']!.add(info);
      } else if (plugin is MCPResourcePlugin) {
        result['resource_plugins']!.add(info);
      } else if (plugin is MCPPromptPlugin) {
        result['prompt_plugins']!.add(info);
      } else {
        result['other_plugins']!.add(info);
      }
    }

    // Add LLM plugins info
    for (final pluginName in llmPlugins) {
      final plugin = _llmManager.getPluginIntegrator().getLlmPlugin(pluginName);
      if (plugin != null) {
        final info = {
          'name': plugin.name,
          'version': plugin.version,
          'description': plugin.description,
          'type': 'llm',
          'plugin_type': _getLlmPluginTypeString(plugin),
        };

        if (plugin is llm.ToolPlugin) {
          result['tool_plugins']!.add(info);
        } else if (plugin is llm.ResourcePlugin) {
          result['resource_plugins']!.add(info);
        } else if (plugin is llm.PromptPlugin) {
          result['prompt_plugins']!.add(info);
        } else {
          result['other_plugins']!.add(info);
        }
      }
    }

    return result;
  }

  /// Helper to get plugin type as string
  String _getPluginTypeString(MCPPlugin plugin) {
    if (plugin is MCPToolPlugin) return 'tool';
    if (plugin is MCPResourcePlugin) return 'resource';
    if (plugin is MCPPromptPlugin) return 'prompt';
    if (plugin is MCPBackgroundPlugin) return 'background';
    if (plugin is MCPNotificationPlugin) return 'notification';
    if (plugin is MCPTrayPlugin) return 'tray';
    return 'unknown';
  }

  /// Helper to get LLM plugin type as string
  String _getLlmPluginTypeString(llm.LlmPlugin plugin) {
    if (plugin is llm.ToolPlugin) return 'tool';
    if (plugin is llm.ResourcePlugin) return 'resource';
    if (plugin is llm.PromptPlugin) return 'prompt';
    if (plugin is llm.EmbeddingPlugin) return 'embedding';
    if (plugin is llm.PreprocessorPlugin) return 'preprocessor';
    if (plugin is llm.PostprocessorPlugin) return 'postprocessor';
    if (plugin is llm.ProviderPlugin) return 'provider';
    return 'unknown';
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
  llm.LlmClient? getLlmClient(String llmId) => _llmManager.getLlmClientById(llmId);
  llm.LlmServer? getLlmServer(String llmId) => _llmManager.getLlmServerById(llmId);

  /// Get system status with enhanced diagnostics and health metrics
  /// 
  /// Returns a detailed status report of the current MCP system state
  Map<String, dynamic> getSystemStatus() {
    if (!_initialized) {
      return {
        'initialized': false,
        'timestamp': DateTime.now().toIso8601String(),
        'platformName': PlatformUtils.platformName,
        'platformFeatures': PlatformUtils.getFeatureSupport(),
      };
    }
    
    try {
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
        'platformName': PlatformUtils.platformName,
        'platformFeatures': PlatformUtils.getFeatureSupport(),
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
    
    // Add comprehensive diagnostics
    status['diagnostics'] = DiagnosticUtils.collectSystemDiagnostics(this);
    
    return status;
  } catch (e, stackTrace) {
    _logger.error('Error getting system status', e, stackTrace);
    return {
      'initialized': _initialized,
      'error': {
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      },
      'timestamp': DateTime.now().toIso8601String(),
      'platformName': PlatformUtils.platformName,
    };
  }
  }
  
  /// Check system health
  /// 
  /// Performs a series of checks to determine the overall health of the MCP system.
  /// Returns a health report with status ('healthy', 'degraded', or 'unhealthy')
  /// and detailed check results.
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      if (!_initialized) {
        return {
          'status': 'unhealthy',
          'checks': {
            'initialization': {
              'status': 'fail',
              'details': {'initialized': false},
            }
          },
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      
      return DiagnosticUtils.checkHealth(this);
    } catch (e, stackTrace) {
      _logger.error('Error checking system health', e, stackTrace);
      return {
        'status': 'unhealthy',
        'error': {
          'message': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
  
  /// Check if a specific platform feature is supported
  /// 
  /// [feature]: The feature to check ('notifications', 'tray', 'background', etc.)
  /// Returns true if the feature is supported on the current platform
  bool isFeatureSupported(String feature) {
    return PlatformUtils.isFeatureSupported(feature);
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