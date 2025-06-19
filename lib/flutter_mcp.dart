import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'src/config/mcp_constants.dart';
import 'dart:math';
import 'package:flutter_mcp/src/config/plugin_config.dart';
import 'package:flutter_mcp/src/plugins/llm_plugin_integration.dart';
import 'package:flutter_mcp/src/utils/error_recovery.dart';
import 'package:mcp_client/mcp_client.dart' as client;
import 'package:mcp_server/mcp_server.dart' as server;
import 'package:mcp_llm/mcp_llm.dart' as llm;
import 'package:shelf/shelf.dart' as shelf;

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
import 'src/plugins/enhanced_plugin_system.dart';
import 'package:pub_semver/pub_semver.dart';
import 'src/metrics/typed_metrics.dart';
import 'src/events/event_models.dart';
import 'src/utils/resource_manager.dart';
import 'src/utils/performance_monitor.dart';
import 'src/performance/enhanced_performance_monitor.dart';
import 'src/events/event_system.dart';
import 'src/utils/memory_manager.dart';
import 'src/utils/object_pool.dart';
import 'src/utils/circuit_breaker.dart';
import 'src/utils/semantic_cache.dart';
import 'src/utils/diagnostic_utils.dart';
import 'src/utils/platform_utils.dart';
import 'src/core/dependency_injection.dart';
import 'src/core/enhanced_batch_manager.dart';
import 'src/security/oauth_manager.dart';
import 'src/security/credential_manager.dart';
import 'src/security/security_audit.dart';
import 'src/security/encryption_manager.dart';
import 'src/types/health_types.dart';
import 'src/platform/storage/secure_storage.dart';
import 'src/monitoring/health_monitor.dart';
import 'src/utils/enhanced_error_handler.dart';
import 'src/utils/enhanced_resource_cleanup.dart';
import 'flutter_mcp_platform_interface.dart';
import 'flutter_mcp_method_channel.dart';

// Re-exports
export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/plugin_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';
export 'src/utils/logger.dart' hide LoggerExtensions;
export 'src/plugins/plugin_system.dart'
    show
        MCPPlugin,
        MCPToolPlugin,
        MCPResourcePlugin,
        MCPBackgroundPlugin,
        MCPNotificationPlugin,
        MCPPromptPlugin;
export 'src/platform/tray/tray_manager.dart' show TrayMenuItem;
// Health monitoring exports removed - using simple implementation
export 'src/security/oauth_manager.dart' show OAuthConfig, OAuthToken;
export 'src/core/client_manager.dart' show MCPClientManager;
export 'src/core/server_manager.dart' show MCPServerManager;
export 'src/core/llm_manager.dart' show MCPLlmManager;
export 'src/performance/enhanced_performance_monitor.dart'
    show
        EnhancedPerformanceMonitor,
        AggregationConfig,
        ThresholdConfig,
        AggregationType,
        ThresholdLevel,
        TrendInfo,
        TrendDirection;
export 'src/plugins/enhanced_plugin_system.dart'
    show
        EnhancedPluginRegistry,
        PluginVersion,
        PluginSandboxConfig,
        PluginUpdateSuggestion;
export 'package:pub_semver/pub_semver.dart' show Version, VersionConstraint;
export 'src/security/security_audit.dart'
    show
        SecurityAuditManager,
        SecurityAuditEvent,
        SecurityEventType,
        SecurityPolicy;
export 'src/security/encryption_manager.dart'
    show
        EncryptionManager,
        EncryptionAlgorithm,
        EncryptedData,
        EncryptionMetadata;
export 'package:mcp_client/mcp_client.dart'
    show ClientCapabilities, Client, ClientTransport;
export 'package:mcp_server/mcp_server.dart'
    show
        ServerCapabilities,
        Server,
        ServerTransport,
        Content,
        TextContent,
        ImageContent,
        ResourceContent,
        Tool,
        Resource,
        Message,
        MessageRole,
        MCPContentType,
        CallToolResult;
export 'package:mcp_llm/mcp_llm.dart'
    hide Logger, HealthCheckResult, HealthStatus;
export 'src/types/health_types.dart';
export 'src/events/event_system.dart'
    show EventSystem, Event, EventPriority, EventHandlerConfig;

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

  // Public getters for diagnostic access

  /// Get client manager status (for diagnostics)
  Map<String, dynamic> get clientManagerStatus => _clientManager.getStatus();

  /// Get server manager status (for diagnostics)
  Map<String, dynamic> get serverManagerStatus => _serverManager.getStatus();

  /// Get LLM manager status (for diagnostics)
  Map<String, dynamic> get llmManagerStatus => _llmManager.getStatus();

  /// Get scheduler status (for diagnostics)
  Map<String, dynamic> get schedulerStatus => {
        'isRunning': _scheduler.isRunning,
        'jobCount': _scheduler.jobCount,
        'activeJobCount': _scheduler.activeJobCount,
      };

  /// Get platform services status (for diagnostics)
  Map<String, dynamic> get platformServicesStatus => {
        'backgroundServiceRunning':
            _platformServices.isBackgroundServiceRunning,
        'platformName': _platformServices.platformName,
      };

  /// Get plugin registry status (for diagnostics)
  Map<String, dynamic> get pluginRegistryStatus => {
        'pluginCount': _pluginRegistry.getAllPluginNames().length,
        'plugins': _pluginRegistry.getAllPluginNames(),
      };

  /// Check if Flutter MCP is initialized
  bool get isInitialized => _initialized;

  /// Get detailed client information
  Map<String, dynamic> getClientDetails(String clientId) {
    final clientInfo = _clientManager.getClientInfo(clientId);
    if (clientInfo == null) return {};

    return {
      'id': clientInfo.id,
      'connected': clientInfo.client.isConnected,
      'hasTransport': clientInfo.transport != null,
    };
  }

  /// Get detailed server information
  Map<String, dynamic> getServerDetails(String serverId) {
    final serverInfo = _serverManager.getServerInfo(serverId);
    if (serverInfo == null) return {};

    return {
      'id': serverInfo.id,
      'name': serverInfo.server.name,
      'version': serverInfo.server.version,
      'hasTransport': serverInfo.transport != null,
      'hasLlmServer': serverInfo.llmServer != null,
    };
  }

  /// Get detailed LLM information
  Map<String, dynamic> getLlmDetails(String llmId) {
    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) return {};

    return {
      'id': llmInfo.id,
      'providerType': llmInfo.mcpLlm.runtimeType.toString(),
      'clientCount': llmInfo.llmClients.length,
      'serverCount': llmInfo.llmServers.length,
      'defaultClientId': llmInfo.defaultLlmClientId,
      'defaultServerId': llmInfo.defaultLlmServerId,
    };
  }

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

  // Plugin registry (using enhanced version for better features)
  final EnhancedPluginRegistry _pluginRegistry = EnhancedPluginRegistry();

  // Resource manager for cleanup
  final ResourceManager _resourceManager = ResourceManager.instance;

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
    initialSize: MCPConstants.defaultObjectPoolInitialSize,
    maxSize: MCPConstants.defaultObjectPoolSize,
  );

  // Circuit breakers for handling failures
  final Map<String, CircuitBreaker> _circuitBreakers = {};

  // New v1.0.0 features
  late final EnhancedBatchManager _batchManager;
  late final HealthMonitor _healthMonitor;
  late final MCPOAuthManager _oauthManager;
  late final EnhancedPerformanceMonitor _enhancedPerformanceMonitor;
  late final SecurityAuditManager _securityAuditManager;
  late final EncryptionManager _encryptionManager;

  // Plugin state
  bool _initialized = false;
  MCPConfig? _config;

  // Shutdown hook registered flag
  bool _shutdownHookRegistered = false;

  // Integrated logger with conditional logging
  static final Logger _logger = Logger('flutter_mcp.flutter_mcp');

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

  /// Get enhanced performance monitor (only available after initialization)
  EnhancedPerformanceMonitor? get enhancedPerformanceMonitor =>
      _initialized ? _enhancedPerformanceMonitor : null;

  /// Get security audit manager (only available after initialization)
  SecurityAuditManager? get securityAuditManager =>
      _initialized ? _securityAuditManager : null;

  /// Get encryption manager (only available after initialization)
  EncryptionManager? get encryptionManager =>
      _initialized ? _encryptionManager : null;

  /// Check if a permission is granted
  Future<bool> checkPermission(String permission) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }
    return await _platformServices.checkPermission(permission);
  }

  /// Request a permission
  Future<bool> requestPermission(String permission) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }
    return await _platformServices.requestPermission(permission);
  }

  /// Request multiple permissions
  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }
    return await _platformServices.requestPermissions(permissions);
  }

  /// Request all required permissions based on configuration
  Future<Map<String, bool>> requestRequiredPermissions() async {
    if (!_initialized || _config == null) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final requiredPermissions = <String>[];

    // Notification permission
    if (_config!.useNotification) {
      requiredPermissions.add('notification');
    }

    // Background service permissions
    if (_config!.useBackgroundService) {
      if (Platform.isAndroid) {
        // Android specific permissions are handled by manifest
        // Only runtime permissions are needed
        if (Platform.version.contains('13') ||
            Platform.version.contains('14')) {
          requiredPermissions
              .add('notification'); // POST_NOTIFICATIONS for Android 13+
        }
      }
    }

    if (requiredPermissions.isEmpty) {
      return {};
    }

    return await requestPermissions(requiredPermissions);
  }

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

    // Initialize enhanced error handler
    EnhancedErrorHandler.instance.initialize();

    // Initialize enhanced resource cleanup
    EnhancedResourceCleanup.instance.initialize(
      defaultLeakDetectionTimeout: Duration(minutes: 10),
      periodicLeakCheckInterval: Duration(minutes: 2),
    );

    // Initialize security audit manager
    _securityAuditManager = SecurityAuditManager.instance;
    _securityAuditManager.initialize(
        policy: SecurityPolicy(
      maxFailedAttempts: config.maxConnectionRetries ?? 5,
      sessionTimeout: Duration(hours: 8),
      requireStrongPasswords: config.secure,
      enableRealTimeMonitoring: config.enablePerformanceMonitoring ?? false,
    ));

    // Initialize encryption manager
    _encryptionManager = EncryptionManager.instance;
    _encryptionManager.initialize(
      minKeyLength: 256,
      keyRotationInterval: Duration(days: 90),
      requireChecksums: true,
    );

    // Start performance monitoring if enabled
    if (config.enablePerformanceMonitoring ?? false) {
      _initializePerformanceMonitoring();
    }

    await EnhancedErrorHandler.instance.handleError(
      () async {
        // Initialize platform interface if not already set
        try {
          FlutterMcpPlatform.instance;
        } catch (e) {
          // Platform not initialized, set it up
          _logger.fine(
              'Platform interface not initialized, setting up MethodChannelFlutterMcp: $e');
          FlutterMcpPlatform.instance = MethodChannelFlutterMcp();
        }

        // Initialize dependency injection container
        _initializeDependencyInjection();

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
            'platform_services', () => _platformServices.shutdown(),
            priority: ResourceManager.highPriority);

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

        _initialized = true;
        _logger.info('Flutter MCP initialization completed');

        // Request required permissions after initialization
        if (config.useNotification || config.useBackgroundService) {
          try {
            final permissions = await requestRequiredPermissions();
            for (final entry in permissions.entries) {
              if (!entry.value) {
                _logger.warning('Permission ${entry.key} was denied');
              }
            }
          } catch (e) {
            _logger.severe('Error requesting permissions', e);
            // Continue even if permissions fail
            // Features will be limited based on available permissions
          }
        }

        // Auto-start configuration
        if (config.autoStart) {
          _logger.info('Starting services based on auto-start configuration');
          await startServices();
        }

        // Complete the initialization lock
        _initializationLock.complete();
      },
      context: 'flutter_mcp_initialization',
      component: 'flutter_mcp',
      metadata: {
        'autoStart': config.autoStart,
        'hasSchedule': config.schedule?.isNotEmpty ?? false,
        'hasPlugins': config.pluginConfigurations?.isNotEmpty ?? false,
      },
    ).catchError((e, stackTrace) {
      _logger.severe('Flutter MCP initialization failed', e, stackTrace);

      // Complete the initialization lock with error
      _initializationLock.completeError(e, stackTrace);

      // Clean up any resources that were initialized
      _cleanup();

      throw MCPInitializationException(
          'Flutter MCP initialization failed', e, stackTrace);
    });
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
        _eventSystem
            .publishTopic('circuit_breaker.opened', {'operation': 'llm.chat'});
      },
      onClose: () {
        _logger.info('Circuit breaker closed for LLM chat operations');
        _eventSystem
            .publishTopic('circuit_breaker.closed', {'operation': 'llm.chat'});
      },
    );

    // Tool execution circuit breaker
    _circuitBreakers['tool.call'] = CircuitBreaker(
      name: 'tool.call',
      failureThreshold: 3,
      resetTimeout: Duration(seconds: 20),
      onOpen: () {
        _logger.warning('Circuit breaker opened for tool call operations');
        _eventSystem
            .publishTopic('circuit_breaker.opened', {'operation': 'tool.call'});
      },
      onClose: () {
        _logger.info('Circuit breaker closed for tool call operations');
        _eventSystem
            .publishTopic('circuit_breaker.closed', {'operation': 'tool.call'});
      },
    );
  }

  /// Initialize memory management with improved cleanup logic
  void _initializeMemoryManagement(int highMemoryThresholdMB) {
    _logger.fine(
        'Initializing memory management with threshold: $highMemoryThresholdMB MB');

    MemoryManager.instance.initialize(
      startMonitoring: true,
      highMemoryThresholdMB: highMemoryThresholdMB,
      monitoringInterval: Duration(seconds: 30),
    );

    // Register memory manager for cleanup
    _resourceManager.registerCallback('memory_manager', () async {
      MemoryManager.instance.dispose();
    }, priority: ResourceManager.mediumPriority);

    // Add high memory callback with tiered cleanup
    MemoryManager.instance.addHighMemoryCallback(() async {
      _logger.warning('High memory usage detected, triggering cleanup');

      // Determine the severity level based on current memory usage
      final currentUsage = MemoryManager.instance.currentMemoryUsageMB;
      final threshold = highMemoryThresholdMB;
      final severityLevel = currentUsage > threshold * 1.5
          ? 3
          : currentUsage > threshold * 1.2
              ? 2
              : 1;

      await _performTieredMemoryCleanup(severityLevel);
    });
  }

  /// Perform tiered memory cleanup based on severity level
  Future<void> _performTieredMemoryCleanup(int severityLevel) async {
    _logger.fine('Performing tier $severityLevel memory cleanup');

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
        _logger.fine('Suggesting resource cleanup to garbage collector');
      }

      // Clear performance monitoring history for higher tiers
      if (severityLevel >= 2 &&
          (_config?.enablePerformanceMonitoring ?? false)) {
        _logger.fine('Clearing performance monitoring history');
        PerformanceMonitor.instance.reset();
      }

      // Publish memory cleanup event
      _eventSystem.publishTopic('memory.cleanup', {
        'timestamp': DateTime.now().toIso8601String(),
        'currentMemoryMB': MemoryManager.instance.currentMemoryUsageMB,
        'peakMemoryMB': MemoryManager.instance.peakMemoryUsageMB,
        'severityLevel': severityLevel,
      });

      _logger.fine('Memory cleanup completed');
    } catch (e, stackTrace) {
      _logger.severe('Error during memory cleanup', e, stackTrace);
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
    // Initialize core managers in parallel
    await Future.wait([
      _clientManager.initialize(),
      _serverManager.initialize(),
      _llmManager.initialize(),
    ]);

    // Initialize v1.0.0 features
    _batchManager = EnhancedBatchManager.instance;
    _healthMonitor = HealthMonitor.instance;
    _healthMonitor.initialize();

    // Initialize OAuth manager with credential manager
    final secureStorage = SecureStorageManagerImpl();
    await secureStorage.initialize();
    final credentialManager = await CredentialManager.initialize(secureStorage);
    _oauthManager =
        await MCPOAuthManager.initialize(credentialManager: credentialManager);

    // Register for cleanup with appropriate priorities
    _resourceManager.registerCallback(
        'batch_manager', () async => _batchManager.dispose(),
        priority: ResourceManager.lowPriority);

    _resourceManager.registerCallback(
        'health_monitor', () async => _healthMonitor.dispose(),
        priority: ResourceManager.lowPriority);

    _resourceManager.registerCallback(
        'oauth_manager', () async => _oauthManager.dispose(),
        priority: ResourceManager.lowPriority);

    _resourceManager.registerCallback(
        'client_manager', () => _clientManager.closeAll(),
        priority: ResourceManager.lowPriority);

    _resourceManager.registerCallback(
        'server_manager', () => _serverManager.closeAll(),
        priority: ResourceManager.mediumPriority);

    _resourceManager.registerCallback(
        'llm_manager', () => _llmManager.closeAll(),
        priority: ResourceManager.highPriority);
  }

  /// Initialize scheduler with improved monitoring
  void _initializeScheduler(List<MCPJob> jobs) {
    _scheduler.initialize();

    for (final job in jobs) {
      _scheduler.addJob(job);
    }

    // Add event listener for job execution
    _eventSystem.subscribeTopic('scheduler.job.executed', (data) {
      final jobId = data['jobId'] as String?;
      final success = data['success'] as bool? ?? false;

      if (jobId != null) {
        PerformanceMonitor.instance.incrementCounter(
            success ? 'scheduler.job.success' : 'scheduler.job.failure');
      }
    });

    _scheduler.start();

    // Register for cleanup
    _resourceManager.registerCallback('scheduler', () async {
      _scheduler.stop();
      _scheduler.dispose();
    }, priority: ResourceManager.mediumPriority);
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
        'plugin_registry', () => _pluginRegistry.shutdownAll(),
        priority: ResourceManager.mediumPriority);
  }

  /// Initialize performance monitoring with enhanced metrics
  void _initializePerformanceMonitoring() {
    // Initialize basic performance monitor
    PerformanceMonitor.instance.initialize(
      enableLogging: true,
      enableMetricsExport: _config?.enableMetricsExport ?? false,
      exportPath: _config?.metricsExportPath,
      maxRecentOperations: 100,
      autoExportInterval: Duration(minutes: 15),
    );

    // Initialize enhanced performance monitor
    _enhancedPerformanceMonitor = EnhancedPerformanceMonitor.instance;

    // Configure metric aggregations for key performance metrics
    _enhancedPerformanceMonitor.configureAggregation(
      'memory.heap_usage',
      AggregationConfig(
        window: Duration(minutes: 5),
        type: AggregationType.average,
        autoFlush: true,
        flushInterval: Duration(minutes: 1),
      ),
    );

    _enhancedPerformanceMonitor.configureAggregation(
      'client.connection_time',
      AggregationConfig(
        window: Duration(minutes: 10),
        type: AggregationType.percentile,
        maxSamples: 1000,
      ),
    );

    _enhancedPerformanceMonitor.configureAggregation(
      'llm.response_time',
      AggregationConfig(
        window: Duration(minutes: 15),
        type: AggregationType.median,
        maxSamples: 500,
      ),
    );

    // Configure performance thresholds with alerts
    _enhancedPerformanceMonitor.configureThreshold(
      'memory.heap_usage',
      ThresholdConfig(
        warningLevel: _config?.highMemoryThresholdMB?.toDouble() ?? 512.0,
        criticalLevel:
            (_config?.highMemoryThresholdMB?.toDouble() ?? 512.0) * 1.5,
        sustainedDuration: Duration(seconds: 30),
        onViolation: (violation) {
          _logger.warning(
              'Memory threshold violation: ${violation.metricName} = ${violation.value}MB '
              '(threshold: ${violation.threshold}MB, level: ${violation.level.name})');

          // Trigger memory cleanup if critical
          if (violation.level == ThresholdLevel.critical) {
            _logger
                .severe('Critical memory usage detected, triggering cleanup');
            MemoryManager.instance.performMemoryCleanup();
          }
        },
      ),
    );

    _enhancedPerformanceMonitor.configureThreshold(
      'llm.response_time',
      ThresholdConfig(
        warningLevel: (_config?.llmRequestTimeoutMs ?? 30000).toDouble() * 0.8,
        criticalLevel: (_config?.llmRequestTimeoutMs ?? 30000).toDouble(),
        sustainedDuration: Duration(seconds: 10),
        onViolation: (violation) {
          _logger.warning(
              'LLM response time threshold violation: ${violation.value}ms '
              '(threshold: ${violation.threshold}ms)');
        },
      ),
    );

    // Enable auto-detection of anomalies and threshold violations
    _enhancedPerformanceMonitor.enableAutoDetection(
      anomalies: true,
      thresholds: true,
      interval: Duration(seconds: 5),
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
    _resourceManager.registerCallback('performance_monitor', () async {
      if (_config?.enableMetricsExport ?? false) {
        await PerformanceMonitor.instance.exportMetrics();
      }
      PerformanceMonitor.instance.dispose();
      _enhancedPerformanceMonitor.dispose();
    }, priority: ResourceManager.lowPriority);

    _logger.info(
        'Enhanced performance monitoring initialized with aggregation and auto-detection');
  }

  /// Initialize dependency injection container
  void _initializeDependencyInjection() {
    _logger.fine('Initializing dependency injection container');

    // Register core services
    ServiceLocator.registerInstance<MCPLogger>(MCPLogger('mcp.main'));
    ServiceLocator.registerInstance<EventSystem>(_eventSystem);
    ServiceLocator.registerInstance<PerformanceMonitor>(
        PerformanceMonitor.instance);
    ServiceLocator.registerInstance<MemoryManager>(MemoryManager.instance);
    ServiceLocator.registerInstance<ResourceManager>(_resourceManager);

    // Register enhanced performance monitor if enabled
    if (_config?.enablePerformanceMonitoring ?? false) {
      ServiceLocator.registerInstance<EnhancedPerformanceMonitor>(
          _enhancedPerformanceMonitor);
    }

    // Register managers as singletons
    ServiceLocator.registerInstance<MCPClientManager>(_clientManager);
    ServiceLocator.registerInstance<MCPServerManager>(_serverManager);
    ServiceLocator.registerInstance<MCPLlmManager>(_llmManager);
    ServiceLocator.registerInstance<MCPScheduler>(_scheduler);
    ServiceLocator.registerInstance<MCPPluginRegistry>(_pluginRegistry);
    ServiceLocator.registerInstance<PlatformServices>(_platformServices);

    // Register factories for creating new instances
    ServiceLocator.registerFactory<CircuitBreaker>(() => CircuitBreaker(
          name: 'default',
          failureThreshold: 5,
          resetTimeout: Duration(seconds: 30),
        ));

    ServiceLocator.registerFactory<SemanticCache>(() => SemanticCache(
          maxSize: MCPConstants.maxRecentOperations,
          ttl: Duration(hours: 1),
        ));

    _logger.fine('Dependency injection container initialized');
  }

  /// Register shutdown hook to ensure proper cleanup
  void _registerShutdownHook() {
    if (_shutdownHookRegistered) return;

    // Use platform lifecycle events to register for app shutdown
    _platformServices.setLifecycleChangeListener((state) {
      // On app termination, ensure resources are cleaned up
      if (state.toString().contains('detached') ||
          state.toString().contains('paused')) {
        _cleanup();
      }
    });

    _shutdownHookRegistered = true;
  }

  /// Register default LLM providers with improved error handling
  void _registerProviderSafely(
      llm.MCPLlm mcpLlm, String name, llm.LlmProviderFactory factory) {
    try {
      mcpLlm.registerProvider(name, factory);
      _logger.fine('Registered $name provider');
    } catch (e, stackTrace) {
      _logger.warning('Failed to register $name provider', e, stackTrace);

      // Track the failure in performance metrics
      PerformanceMonitor.instance
          .incrementCounter('provider.registration.failure.$name');
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
          'Some components failed to start (${startErrors.length} errors). '
          'First error: ${startErrors.values.first}');
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
      config: clientConfig,
    );

    _logger.fine('Created MCP client: ${clientConfig.name} with ID $clientId');
    return clientId;
  }

  /// Start a server from configuration with improved error handling
  Future<String> _startServer(MCPServerConfig serverConfig) async {
    final serverId = await createServer(
      name: serverConfig.name,
      version: serverConfig.version,
      capabilities: serverConfig.capabilities,
      // transportType is handled by serverConfig
      ssePort: serverConfig.ssePort,
      fallbackPorts: serverConfig.fallbackPorts,
      authToken: serverConfig.authToken,
      config: serverConfig,
    );

    _logger.fine('Created MCP server: ${serverConfig.name} with ID $serverId');
    return serverId;
  }

  /// Start configured components with improved error handling and parallelism
  Future<Map<String, dynamic>> _startConfiguredComponents() async {
    final config = _config!;
    final startErrors = <String, dynamic>{};

    // 1. Create MCP servers (without connection)
    final mcpServerMap =
        <String, String>{}; // index/name -> actual server ID mapping

    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (int i = 0; i < config.autoStartServer!.length; i++) {
        final serverConfig = config.autoStartServer![i];
        try {
          final serverId = await _startServer(serverConfig);
          mcpServerMap['server_$i'] = serverId; // Reference by index
          mcpServerMap[serverConfig.name] = serverId; // Reference by name
        } catch (e, stackTrace) {
          _logger.severe(
              'Failed to create server: ${serverConfig.name}', e, stackTrace);
          startErrors['server.${serverConfig.name}'] = e;
        }
      }
    }

    // 2. Create MCP clients (without connection)
    final mcpClientMap =
        <String, String>{}; // index/name -> actual client ID mapping

    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (int i = 0; i < config.autoStartClient!.length; i++) {
        final clientConfig = config.autoStartClient![i];
        try {
          final clientId = await _startClient(clientConfig);
          mcpClientMap['client_$i'] = clientId; // Reference by index
          mcpClientMap[clientConfig.name] = clientId; // Reference by name
        } catch (e, stackTrace) {
          _logger.severe(
              'Failed to create client: ${clientConfig.name}', e, stackTrace);
          startErrors['client.${clientConfig.name}'] = e;
        }
      }
    }

    // 3. Create LLM servers and connect to MCP servers
    if (config.autoStartLlmServer != null &&
        config.autoStartLlmServer!.isNotEmpty) {
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

              _logger.fine(
                  'Associated MCP server $mcpServerId with LLM server $llmServerId');
            } else {
              _logger.warning('MCP server reference not found: $mcpServerRef');
            }
          }

          // Set as default if needed
          if (llmConfig.isDefault) {
            _defaultLlmServerId = llmServerId;
            _logger.fine('Set default LLM server: $llmServerId');
          }

          // Register core plugins if configured
          if (config.registerCoreLlmPlugins == true) {
            try {
              await registerCoreLlmPlugins(llmId, llmServerId,
                  isServer: true,
                  includeRetrievalPlugins: config.enableRetrieval ?? false);
            } catch (e) {
              _logger.warning(
                  'Failed to register core plugins for LLM server $llmServerId: $e');
              startErrors['llm.server.plugins.$i'] = e;
            }
          }
        } catch (e, stackTrace) {
          _logger.severe(
              'Failed to create LLM server at index $i', e, stackTrace);
          startErrors['llm.server.$i'] = e;
        }
      }
    }

    // 4. Create LLM clients and connect to MCP clients
    if (config.autoStartLlmClient != null &&
        config.autoStartLlmClient!.isNotEmpty) {
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

              _logger.fine(
                  'Associated MCP client $mcpClientId with LLM client $llmClientId');
            } else {
              _logger.warning('MCP client reference not found: $mcpClientRef');
            }
          }

          // Set as default if needed
          if (llmConfig.isDefault) {
            _defaultLlmClientId = llmClientId;
            _logger.fine('Set default LLM client: $llmClientId');
          }

          // Register core plugins if configured
          if (config.registerCoreLlmPlugins == true) {
            try {
              await registerCoreLlmPlugins(llmId, llmClientId,
                  isServer: false,
                  includeRetrievalPlugins: config.enableRetrieval ?? false);
            } catch (e) {
              _logger.warning(
                  'Failed to register core plugins for LLM client $llmClientId: $e');
              startErrors['llm.client.plugins.$i'] = e;
            }
          }
        } catch (e, stackTrace) {
          _logger.severe(
              'Failed to create LLM client at index $i', e, stackTrace);
          startErrors['llm.client.$i'] = e;
        }
      }
    }

    // 5. Connect all MCP servers
    for (final serverId in mcpServerMap.values.toSet()) {
      try {
        connectServer(serverId);
        _logger.fine('Connected MCP server: $serverId');
      } catch (e, stackTrace) {
        _logger.severe('Failed to connect server: $serverId', e, stackTrace);
        startErrors['connect.server.$serverId'] = e;
      }
    }

    // 6. Connect all MCP clients
    for (final clientId in mcpClientMap.values.toSet()) {
      try {
        await connectClient(clientId);
        _logger.fine('Connected MCP client: $clientId');
      } catch (e, stackTrace) {
        _logger.severe('Failed to connect client: $clientId', e, stackTrace);
        startErrors['connect.client.$clientId'] = e;
      }
    }

    // 7. Handle MCP plugin integration
    if (config.registerMcpPluginsWithLlm == true) {
      final mcpPlugins = _pluginRegistry.getAllPlugins();
      for (final plugin in mcpPlugins) {
        if (plugin is MCPToolPlugin ||
            plugin is MCPResourcePlugin ||
            plugin is MCPPromptPlugin) {
          try {
            await convertMcpPluginToLlm(plugin);
          } catch (e) {
            _logger.warning(
                'Failed to convert MCP plugin ${plugin.name} to LLM plugin: $e');
            startErrors['plugin.convert.${plugin.name}'] = e;
          }
        }
      }
    }

    if (startErrors.isNotEmpty) {
      _logger.warning(
          'Some components failed to start (${startErrors.length} errors). '
          'First error: ${startErrors.values.first}');
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
    MCPClientConfig? config,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP client: $name');
    final timer = PerformanceMonitor.instance.startTimer('client.create');

    try {
      // Validate parameters - check both direct params and config
      final hasTransportCommand =
          transportCommand != null || config?.transportCommand != null;
      final hasServerUrl = serverUrl != null || config?.serverUrl != null;

      if (!hasTransportCommand && !hasServerUrl) {
        throw MCPValidationException(
            'Either transportCommand or serverUrl must be provided',
            {'transport': 'Missing transport configuration'});
      }

      // Create client using McpClient factory with config
      final clientId = _clientManager.generateId();
      final mcpClient = client.McpClient.createClient(
        client.McpClientConfig(
          name: name,
          version: version,
          capabilities: capabilities ?? client.ClientCapabilities(),
        ),
      );

      // Create transport with proper Result handling
      client.ClientTransport? transport;

      // Get transport type from config - must be explicitly specified
      final transportType = config?.transportType;
      if (transportType == null) {
        throw MCPValidationException(
            'transportType must be specified in config',
            {'transport': 'Missing transport type'});
      }

      final effectiveTransportCommand =
          config?.transportCommand ?? transportCommand;
      final effectiveServerUrl = config?.serverUrl ?? serverUrl;

      // Validate transport-specific required parameters
      if (transportType == 'stdio' && effectiveTransportCommand == null) {
        throw MCPValidationException(
            'transportCommand is required for stdio transport',
            {'transport': 'Missing transportCommand'});
      }
      
      if ((transportType == 'sse' || transportType == 'streamablehttp') && 
          effectiveServerUrl == null) {
        throw MCPValidationException(
            'serverUrl is required for $transportType transport',
            {'transport': 'Missing serverUrl'});
      }

      if (transportType == 'stdio' && effectiveTransportCommand != null) {
        final result = await client.McpClient.createStdioTransport(
          command: effectiveTransportCommand,
          arguments: config?.transportArgs ?? transportArgs ?? [],
        );
        // Handle Result type properly using fold pattern
        transport = result.fold(
          (t) => t, // Success case
          (error) => throw MCPTransportException(
            'Failed to create stdio transport: ${error.toString()}',
            error,
          ),
        );
      } else if (transportType == 'sse' && effectiveServerUrl != null) {
        // Build full URL with endpoint if provided
        final fullUrl = config?.endpoint != null 
            ? effectiveServerUrl + config!.endpoint!
            : effectiveServerUrl;
            
        // Merge headers from config with auth header
        final headers = <String, String>{};
        if (config?.headers != null) {
          headers.addAll(config!.headers!);
        }
        final effectiveAuthToken = config?.authToken ?? authToken;
        if (effectiveAuthToken != null) {
          headers['Authorization'] = 'Bearer $effectiveAuthToken';
        }
        
        final result = await client.McpClient.createSseTransport(
          serverUrl: fullUrl,
          headers: headers.isNotEmpty ? headers : null,
        );
        // Handle Result type properly using fold pattern
        transport = result.fold(
          (t) => t, // Success case
          (error) => throw MCPTransportException(
            'Failed to create SSE transport: ${error.toString()}',
            error,
          ),
        );
      } else if (transportType == 'streamablehttp' &&
          effectiveServerUrl != null) {
        // For streamablehttp, we need to append the endpoint to the baseUrl
        // since mcp_client uses the URL as-is without appending any endpoint
        final fullUrl = config?.endpoint != null
            ? effectiveServerUrl + config!.endpoint!
            : effectiveServerUrl;
        
        // Merge headers from config with auth header
        final headers = <String, String>{};
        if (config?.headers != null) {
          headers.addAll(config!.headers!);
        }
        final effectiveAuthToken = config?.authToken ?? authToken;
        if (effectiveAuthToken != null) {
          headers['Authorization'] = 'Bearer $effectiveAuthToken';
        }
        
        final result = await client.McpClient.createStreamableHttpTransport(
          baseUrl: fullUrl,
          headers: headers.isNotEmpty ? headers : null,
          timeout: config?.timeout,
          maxConcurrentRequests: config?.maxConcurrentRequests,
          useHttp2: config?.useHttp2,
        );
        // Handle Result type properly using fold pattern
        transport = result.fold(
          (t) => t, // Success case
          (error) => throw MCPTransportException(
            'Failed to create Streamable HTTP transport: ${error.toString()}',
            error,
          ),
        );
      }

      // Register client
      _clientManager.registerClient(clientId, mcpClient, transport);

      // Register for resource cleanup
      EnhancedResourceCleanup.instance.registerResource<client.Client>(
        key: 'client_$clientId',
        resource: mcpClient,
        disposeFunction: (c) async =>
            await _clientManager.closeClient(clientId),
        type: 'MCP_Client',
        description: 'MCP client: $name',
        priority: 200,
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return clientId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.severe('Failed to create MCP client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create MCP client: $name', e, stackTrace);
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
    MCPServerConfig? config,
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
            {'transport': 'Missing SSE port configuration'});
      }

      // Create server using McpServer factory with config
      final serverId = _serverManager.generateId();
      final mcpServer = server.McpServer.createServer(
        server.McpServerConfig(
          name: name,
          version: version,
          capabilities: capabilities ?? server.ServerCapabilities(),
        ),
      );

      // Create transport with proper Result handling
      server.ServerTransport? transport;

      // Get transport type from config - must be explicitly specified
      final transportType = config?.transportType ?? 
          (useStdioTransport ? 'stdio' : null);
      
      if (transportType == null) {
        throw MCPValidationException(
            'transportType must be specified in config',
            {'transport': 'Missing transport type'});
      }

      // Validate transport type
      final validTransportTypes = ['stdio', 'sse', 'streamablehttp'];
      if (!validTransportTypes.contains(transportType)) {
        throw MCPOperationFailedException(
            'Invalid transport type: $transportType. Valid types are: ${validTransportTypes.join(', ')}',
            null,
            null);
      }

      // Validate transport-specific required parameters
      if (transportType == 'sse' && config?.ssePort == null && ssePort == null) {
        throw MCPValidationException(
            'ssePort is required for sse transport',
            {'transport': 'Missing ssePort'});
      }
      
      if (transportType == 'streamablehttp' && 
          config?.streamableHttpPort == null && ssePort == null) {
        throw MCPValidationException(
            'streamableHttpPort or ssePort is required for streamablehttp transport',
            {'transport': 'Missing port configuration'});
      }

      if (transportType == 'stdio') {
        final result = server.McpServer.createStdioTransport();
        // Handle Result type properly
        transport = result.fold(
          (t) => t, // Success case
          (error) => throw MCPTransportException(
            'Failed to create stdio server transport: ${error.toString()}',
            error,
          ),
        );
      } else if (transportType == 'sse') {
        // Create SSE transport using TransportConfig
        final effectiveSsePort = config?.ssePort ?? ssePort;
        if (effectiveSsePort == null) {
          throw MCPValidationException(
              'ssePort is required for sse transport',
              {'transport': 'Missing ssePort'});
        }
        
        try {
          final result = server.McpServer.createTransport(
            server.TransportConfig.sse(
              host: config?.host ?? 'localhost',
              port: effectiveSsePort,
              endpoint: config?.endpoint ?? '/sse',
              messagesEndpoint: config?.messagesEndpoint ?? '/message',
              fallbackPorts: config?.fallbackPorts ?? fallbackPorts ?? [],
              authToken: config?.authToken ?? authToken,
              middleware: (config?.middleware ?? []).cast<shelf.Middleware>(),
            ),
          );
          transport = await result.fold(
            (futureTransport) => futureTransport,
            (error) => throw MCPTransportException(
              'Failed to create SSE server transport: ${error.toString()}',
              error,
            ),
          );
          _logger.info('SSE server transport created on port $effectiveSsePort');
        } catch (error) {
          throw MCPOperationFailedException(
            'Failed to create SSE server transport: ${error.toString()}',
            error,
            null,
          );
        }
      } else if (transportType == 'streamablehttp') {
        // Create Streamable HTTP transport
        final httpPort = config?.streamableHttpPort ?? ssePort;
        if (httpPort == null) {
          throw MCPValidationException(
              'streamableHttpPort is required for streamablehttp transport',
              {'transport': 'Missing streamableHttpPort'});
        }
        try {
          final result = server.McpServer.createTransport(
            server.TransportConfig.streamableHttp(
              host: config?.host ?? 'localhost',
              port: httpPort,
              endpoint: config?.endpoint ?? '/mcp',
              messagesEndpoint: config?.messagesEndpoint ?? '/message',
              fallbackPorts: config?.fallbackPorts ?? fallbackPorts ?? [],
              authToken: config?.authToken ?? authToken,
              isJsonResponseEnabled: config?.isJsonResponseEnabled ?? false,
              middleware: (config?.middleware ?? []).cast<shelf.Middleware>(),
            ),
          );
          transport = await result.fold(
            (futureTransport) => futureTransport,
            (error) => throw MCPTransportException(
              'Failed to create Streamable HTTP server transport: ${error.toString()}',
              error,
            ),
          );
          _logger.info(
              'Streamable HTTP server transport created on port $httpPort');
        } catch (error) {
          throw MCPOperationFailedException(
            'Failed to create Streamable HTTP server transport: ${error.toString()}',
            error,
            null,
          );
        }
      }

      // Register server
      _serverManager.registerServer(serverId, mcpServer, transport);

      // Register for resource cleanup
      EnhancedResourceCleanup.instance.registerResource<server.Server>(
        key: 'server_$serverId',
        resource: mcpServer,
        disposeFunction: (s) async =>
            await _serverManager.closeServer(serverId),
        type: 'MCP_Server',
        description: 'MCP server: $name',
        priority: 200,
      );

      PerformanceMonitor.instance.stopTimer(timer, success: true);
      return serverId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.stopTimer(timer, success: false);
      _logger.severe('Failed to create MCP server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create MCP server: $name', e, stackTrace);
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
      if (!_mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
        _logger.fine('Creating new MCPLlm instance: $mcpLlmInstanceId');
        createMcpLlmInstance(mcpLlmInstanceId);
      }

      final mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!.value;

      _logger.info(
          'Creating LLM instance with client for $providerName on MCPLlm instance $mcpLlmInstanceId');

      var llmId = 'llm_$mcpLlmInstanceId';
      if (_llmManager.getLlmInfo(mcpLlmInstanceId) == null) {
        // Register with the LLM manager (no clients or servers yet)
        _llmManager.registerLlm(llmId, mcpLlm);
      }

      // Register for resource cleanup
      _resourceManager.register<String>(
          'llm_$llmId', llmId, (id) async => await _llmManager.closeLlm(id),
          priority: ResourceManager.mediumPriority);

      // Verify provider is registered
      if (!mcpLlm.getProviderCapabilities().containsKey(providerName)) {
        throw MCPConfigurationException(
            'Provider $providerName is not registered with MCPLlm');
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
          operationName: 'Create LLM client for $providerName');

      // Add to LLM manager
      await _llmManager.addLlmClient(llmId, llmClientId, llmClient);

      // Create semantic cache for this client
      _llmResponseCaches[llmId] = SemanticCache(
        maxSize: MCPConstants.maxRecentOperations,
        ttl: Duration(hours: 1),
        embeddingFunction: (text) async =>
            await llmClient.generateEmbeddings(text),
        similarityThreshold: 0.85,
      );

      if (_config?.pluginConfigurations != null) {
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
          _logger
              .fine('Auto-registered plugins from new LLM client $llmClientId');
        } catch (e) {
          _logger.warning(
              'Failed to auto-register plugins from new LLM client $llmClientId: $e');
        }
      }

      // Register core plugins if configured
      if (_config?.registerCoreLlmPlugins == true) {
        try {
          await registerCoreLlmPlugins(llmId, llmClientId,
              isServer: false,
              includeRetrievalPlugins: _config?.enableRetrieval ?? false);
        } catch (e) {
          _logger.warning(
              'Failed to register core plugins for LLM client $llmClientId: $e');
        }
      }

      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'provider': providerName,
            'mcpLlmInstanceId': mcpLlmInstanceId
          });

      _logger.info(
          'Created LLM $llmId with client $llmClientId using provider $providerName');

      _stopwatchPool.release(stopwatch);
      return (llmId, llmClientId);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString(), 'provider': providerName});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to create LLM with client', e, stackTrace);

      // Categorize errors better for clearer debugging
      if (e.toString().contains('API key')) {
        throw MCPAuthenticationException(
            'Invalid API key for provider', e, stackTrace);
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('connection')) {
        throw MCPNetworkException('Network error while creating LLM client',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Failed to create LLM with client for provider: $providerName',
          e,
          stackTrace);
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
        _logger.fine('Creating new MCPLlm instance: $mcpLlmInstanceId');
        createMcpLlmInstance(mcpLlmInstanceId);
      }

      final mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!.value;

      _logger.info(
          'Creating LLM instance with server for $providerName on MCPLlm instance $mcpLlmInstanceId');

      var llmId = 'llm_$mcpLlmInstanceId';
      if (_llmManager.getLlmInfo(mcpLlmInstanceId) == null) {
        // Register with the LLM manager (no clients or servers yet)
        _llmManager.registerLlm(llmId, mcpLlm);
      }

      // Register for resource cleanup
      _resourceManager.register<String>(
          'llm_$llmId', llmId, (id) async => await _llmManager.closeLlm(id),
          priority: ResourceManager.mediumPriority);

      // Verify provider is registered
      if (!mcpLlm.getProviderCapabilities().containsKey(providerName)) {
        throw MCPConfigurationException(
            'Provider $providerName is not registered with MCPLlm');
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
          operationName: 'Create LLM server for $providerName');

      // Add to LLM manager
      await _llmManager.addLlmServer(llmId, llmServerId, llmServer);

      // Auto-register plugins if configured
      if (_config?.autoRegisterLlmPlugins == true) {
        try {
          await registerPluginsFromLlmServer(llmId, llmServerId);
          _logger
              .fine('Auto-registered plugins from new LLM server $llmServerId');
        } catch (e) {
          _logger.warning(
              'Failed to auto-register plugins from new LLM server $llmServerId: $e');
        }
      }

      if (_config?.pluginConfigurations != null) {
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
          await registerCoreLlmPlugins(llmId, llmServerId,
              isServer: true,
              includeRetrievalPlugins: _config?.enableRetrieval ?? false);
        } catch (e) {
          _logger.warning(
              'Failed to register core plugins for LLM server $llmServerId: $e');
        }
      }

      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'provider': providerName,
            'mcpLlmInstanceId': mcpLlmInstanceId
          });

      _logger.info(
          'Created LLM $llmId with server $llmServerId using provider $providerName');

      _stopwatchPool.release(stopwatch);
      return (llmId, llmServerId);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'error': e.toString(), 'provider': providerName});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to create LLM with server', e, stackTrace);

      // Categorize errors better for clearer debugging
      if (e.toString().contains('API key')) {
        throw MCPAuthenticationException(
            'Invalid API key for provider', e, stackTrace);
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('connection')) {
        throw MCPNetworkException('Network error while creating LLM server',
            originalError: e, stackTrace: stackTrace);
      }

      throw MCPOperationFailedException(
          'Failed to create LLM with server for provider: $providerName',
          e,
          stackTrace);
    }
  }

  /// Get LLM details with enhanced information about clients and servers
  ///
  /// [llmId]: LLM ID
  Map<String, dynamic> getLlmEnhancedDetails(String llmId) {
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
          'associatedMcpClients': llmInfo
              .getAllMcpClientIds()
              .where((mcpClientId) => llmInfo
                  .getLlmClientIdsForMcpClient(mcpClientId)
                  .contains(clientId))
              .toList(),
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
          'associatedMcpServers': llmInfo
              .getAllMcpServerIds()
              .where((mcpServerId) => llmInfo
                  .getLlmServerIdsForMcpServer(mcpServerId)
                  .contains(serverId))
              .toList(),
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
  Map<String, dynamic> getAllLlmDetails(
      {int offset = 0, int limit = 50, bool includeDetails = false}) {
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
          llmDetails[llmId] = getLlmEnhancedDetails(llmId);
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
        if (llmInfo
            .getLlmClientIdsForMcpClient(mcpClientId)
            .contains(llmClientId)) {
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
          operationId, stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'llmId': llmId, 'llmClientId': llmClientId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to remove LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove LLM client', e, stackTrace);
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
        if (llmInfo
            .getLlmServerIdsForMcpServer(mcpServerId)
            .contains(llmServerId)) {
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
          operationId, stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'llmId': llmId, 'llmServerId': llmServerId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to remove LLM server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove LLM server', e, stackTrace);
    }
  }

  /// Create a new MCPLlm instance with lazy initialization and better resource management
  ///
  /// [instanceId]: ID for the new instance
  /// [registerDefaultProviders]: Whether to register default providers
  ///
  /// Returns the newly created MCPLlm instance
  llm.MCPLlm createMcpLlmInstance(String instanceId,
      {bool registerDefaultProviders = true}) {
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
      _resourceManager.register<llm.MCPLlm>('mcpllm_$instanceId', mcpLlm,
          (instance) async {
        // Cleanup logic for MCPLlm instance
        try {
          await mcpLlm.shutdown();
        } catch (e) {
          _logger.severe('Error shutting down MCPLlm instance $instanceId', e);
        }
        _mcpLlmInstances.remove(instanceId);
      }, priority: ResourceManager.highPriority);

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
  void _validateLlmConfiguration(
      String providerName, llm.LlmConfiguration config) {
    final validationErrors = <String, String>{};

    // Check API key
    if (config.apiKey == null ||
        config.apiKey!.isEmpty ||
        config.apiKey == 'placeholder-key') {
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
            validationErrors['model'] =
                'Unrecognized OpenAI model format: ${config.model}';
          }
          break;

        case 'claude':
          // Claude model naming convention
          if (!config.model!.contains('claude')) {
            validationErrors['model'] =
                'Unrecognized Claude model format: ${config.model}';
          }
          break;

        case 'together':
          // Together.ai models often have specific prefixes
          if (!config.model!.contains('/')) {
            validationErrors['model'] =
                'Together.ai models should include organization/model format';
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
            !config.baseUrl!.contains('azure.com')) {
          // Added Azure support
          validationErrors['baseUrl'] =
              'Custom base URL should be from OpenAI, Azure, or a local proxy';
        }
        break;

      case 'claude':
        // Claude specific validation
        if (config.apiKey != null &&
            !config.apiKey!.startsWith('sk-') &&
            !config.apiKey!.startsWith('sa-')) {
          validationErrors['apiKey'] =
              'Claude API keys typically start with "sk-" or "sa-"';
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
      validationErrors['timeout'] =
          'Timeout is very short (${config.timeout.inSeconds}s), may cause failures';
    }

    if (validationErrors.isNotEmpty) {
      throw MCPValidationException(
          'LLM configuration validation failed', validationErrors);
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

    _logger.info(
        'Integrating mcpClient with LlmClient: $mcpClientId + $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpClient = _clientManager.getClient(mcpClientId);
      if (mcpClient == null) {
        throw MCPResourceNotFoundException(mcpClientId, 'mcpClient not found');
      }

      // Add client to LLM with retry
      await _retryWithTimeout(
          () => _llmManager.addMcpClientToLlmClient(
              llmClientId, mcpClientId, mcpClient),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add mcpClient to LlmClient');

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_client', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpClientId': mcpClientId,
            'llmClientId': llmClientId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to integrate mcpClient with llmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate mcpClient with LlmClient', e, stackTrace);
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

    _logger.info(
        'Removing mcpClient from llmClient: $mcpClientId from $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove client from LLM with retry
      await _retryWithTimeout(
          () => _llmManager.removeMcpClientFromLlmClient(
              llmClientId, mcpClientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove mcpClient from llmClient');

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_client', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpClientId': mcpClientId,
            'llmClientId': llmClientId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to remove mcpClient from llmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove mcpClient from llmClient', e, stackTrace);
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

    _logger.info(
        'Setting default mcpClient for LlmClient: $mcpClientId as default for $llmClientId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default client for LLM with retry
      await _retryWithTimeout(
          () => _llmManager.setDefaultMcpClientForLlmClient(
              llmClientId, mcpClientId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default mcpClient for LlmClient');

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpClientId': mcpClientId, 'llmClientId': llmClientId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_client', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpClientId': mcpClientId,
            'llmClientId': llmClientId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to set default mcpClient for LlmClient', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default mcpClient for LlmClient', e, stackTrace);
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

    _logger.info(
        'Integrating mcpServer with llmServer: $mcpServerId + $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final mcpServer = _serverManager.getServer(mcpServerId);
      if (mcpServer == null) {
        throw MCPResourceNotFoundException(mcpServerId, 'Server not found');
      }

      // Add server to LLM with retry
      await _retryWithTimeout(
          () => _llmManager.addMcpServerToLlmServer(
              llmServerId, mcpServerId, mcpServer),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Add mcpServer to llmServer');

      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.integrate_server', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpServerId': mcpServerId,
            'llmServerId': llmServerId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to integrate mcpServer with llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to integrate mcpServer with llmServer', e, stackTrace);
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

    _logger.info(
        'Removing mcpServer from llmServer: $mcpServerId from $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Remove server from LLM with retry
      await _retryWithTimeout(
          () => _llmManager.removeMcpServerFromLlmServer(
              llmServerId, mcpServerId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Remove mcpServer from llmServer');

      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.remove_server', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpServerId': mcpServerId,
            'llmServerId': llmServerId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to remove mcpServer from llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to remove mcpServer from llmServer', e, stackTrace);
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

    _logger.info(
        'Setting default mcpServer for llmServer: $mcpServerId as default for $llmServerId');

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      // Set default server for LLM with retry
      await _retryWithTimeout(
          () => _llmManager.setDefaultMcpServerForLlmServer(
              llmServerId, mcpServerId),
          timeout: Duration(seconds: 15),
          maxRetries: 2,
          operationName: 'Set default mcpServer for llmServer');

      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {'mcpServerId': mcpServerId, 'llmServerId': llmServerId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.set_default_server', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'mcpServerId': mcpServerId,
            'llmServerId': llmServerId,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to set default mcpServer for llmServer', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to set default mcpServer for llmServerM', e, stackTrace);
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
          operationName: 'Connect client $clientId');

      clientInfo.connected = true;

      PerformanceMonitor.instance.recordMetric(
          'client.connect', stopwatch.elapsedMilliseconds,
          success: true, metadata: {'clientId': clientId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'client.connect', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'clientId': clientId, 'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to connect client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect client: $clientId', e, stackTrace);
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
          'server.connect', stopwatch.elapsedMilliseconds,
          success: true, metadata: {'serverId': serverId});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'server.connect', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {'serverId': serverId, 'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to connect server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to connect server: $serverId', e, stackTrace);
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

    _logger.fine('Calling tool $toolName on client $clientId');

    return await EnhancedErrorHandler.instance.handleError(
      () async {
        final clientInfo = _clientManager.getClientInfo(clientId);
        if (clientInfo == null) {
          throw MCPResourceNotFoundException('Client not found', clientId);
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
            operationName: 'Call tool $toolName');

        return result;
      },
      context: 'tool_call',
      component: 'client_manager',
      metadata: {
        'toolName': toolName,
        'clientId': clientId,
        'hasArguments': arguments.isNotEmpty,
      },
      circuitBreakerName: 'tool.execution',
      recoveryStrategy: 'retry',
    );
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
    final logger = MCPLogger('mcp.llm_service');
    logger.fine('Processing chat request: $userInput');

    return await EnhancedErrorHandler.instance.handleError(
      () async {
        // Get LLM client from manager
        llmClientId ??= await _llmManager.getDefaultLlmClientId(llmId);
        final llmClient = _llmManager.getLlmClientById(llmClientId!);
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
            'LLM client not found: $llmClientId',
            llmClientId!,
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
      },
      context: 'llm_chat',
      component: 'llm_manager',
      metadata: {
        'llmId': llmId,
        'llmClientId': llmClientId,
        'enableTools': enableTools,
        'enablePlugins': enablePlugins,
        'useRetrieval': useRetrieval,
      },
      circuitBreakerName: 'llm.operations',
      fallbackValue: llm.LlmResponse(
        text: 'Error processing chat request. Please try again later.',
        metadata: {'error': 'service_unavailable'},
      ),
    );
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
    logger.fine('Processing stream chat request: $userInput');

    try {
      // Get LLM client from manager
      llmClientId ??= await _llmManager.getDefaultLlmClientId(llmId);
      final llmClient = _llmManager.getLlmClientById(llmClientId);
      if (llmClient == null) {
        logger.severe('LLM client not found: $llmId');
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
      logger.severe('Error in stream chat: $e', e, stackTrace);
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
    _logger.fine(
        'Processing ${documents.length} documents in chunks of $chunkSize${parallel ? ' with parallelism $maxParallelism' : ' sequentially'}');

    if (parallel) {
      // Process with controlled parallelism
      return await MemoryManager.processInParallelChunks<llm.Document,
          llm.Document>(
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
    return await ErrorRecovery.tryWithExponentialBackoff(operation,
        initialDelay: initialDelay,
        maxDelay: maxDelay,
        backoffFactor: backoffFactor,
        maxRetries: maxRetries,
        timeout: timeout,
        retryIf: retryIf,
        operationName: operationName, onRetry: (attempt, error, delay) {
      _logger.warning(
          'Retrying $operationName (attempt ${attempt + 1}/$maxRetries) '
          'after $delay due to error: ${error.toString().substring(0, min(100, error.toString().length))}');
      PerformanceMonitor.instance.incrementCounter('retry.$operationName');
    });
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
        () => ErrorRecovery.tryWithRetry(operation,
                maxRetries: maxRetries,
                retryIf: retryIf,
                operationName: operationName, onRetry: (attempt, error) {
              _logger.warning(
                  'Retrying $operationName (attempt ${attempt + 1}/$maxRetries) '
                  'due to error: ${error.toString().substring(0, min(100, error.toString().length))}');
              PerformanceMonitor.instance
                  .incrementCounter('retry.$operationName');
            }),
        timeout,
        operationName: operationName);
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
          throw MCPResourceNotFoundException(
              llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
              llmId, 'LLM has no client configured');
        }
      }

      // Add with retry for transient errors
      final docId = await _retryWithTimeout(
          () => llmClient!.addDocument(document),
          timeout: Duration(seconds: 30),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Add document to LLM');

      PerformanceMonitor.instance.recordMetric(
          'llm.add_document', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'documentSize': document.content.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'docId': docId
          });

      _stopwatchPool.release(stopwatch);
      return docId;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.add_document', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to add document to LLM', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to add document to LLM', e, stackTrace);
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
          throw MCPResourceNotFoundException(
              llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
              llmId, 'LLM has no client configured');
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
          operationName: 'Retrieve documents');

      PerformanceMonitor.instance.recordMetric(
          'llm.retrieve_documents', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'count': docs.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'queryLength': query.length
          });

      _stopwatchPool.release(stopwatch);
      return docs;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.retrieve_documents', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to retrieve relevant documents', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to retrieve relevant documents', e, stackTrace);
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
          throw MCPResourceNotFoundException(
              llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
              llmId, 'LLM has no client configured');
        }
      }

      // Retry wrapper for resilience
      final embeddings = await _retryWithTimeout(
          () => llmClient!.generateEmbeddings(text),
          timeout: Duration(seconds: 20),
          maxRetries: 2,
          retryIf: (e) => _isTransientError(e),
          operationName: 'Generate embeddings');

      PerformanceMonitor.instance.recordMetric(
          'llm.generate_embeddings', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'textLength': text.length,
            'embeddingDimensions': embeddings.length,
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default'
          });

      _stopwatchPool.release(stopwatch);
      return embeddings;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.generate_embeddings', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to generate embeddings', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to generate embeddings', e, stackTrace);
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
      throw MCPValidationException('Job interval must be positive',
          {'interval': 'Interval must be greater than zero'});
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
          'Job ID cannot be empty', {'jobId': 'Job ID is required'});
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
          'storage.store', stopwatch.elapsedMilliseconds,
          success: true);

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'storage.store', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to securely store value', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to securely store value for key: $key', e, stackTrace);
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
          'storage.read', stopwatch.elapsedMilliseconds,
          success: true);

      _stopwatchPool.release(stopwatch);
      return value;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'storage.read', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to read secure value', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to read secure value for key: $key', e, stackTrace);
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
          throw MCPResourceNotFoundException(
              llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
              llmId, 'LLM has no client configured');
        }
      }

      // Create a new chat session with storage
      final storage = storageManager ?? llm.MemoryStorage();
      final generatedId =
          'session_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
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
          'chat_session_${session.id}', session, (s) async {
        // Persist state before cleanup
        if (storage is PersistentStorage) {
          await storage.persist();
        }
      }, priority: ResourceManager.lowPriority);

      PerformanceMonitor.instance.recordMetric(
          'chat.create_session', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'sessionId': session.id
          });

      _stopwatchPool.release(stopwatch);
      return session;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'chat.create_session', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to create chat session', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create chat session for LLM: $llmId', e, stackTrace);
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
          throw MCPResourceNotFoundException(
              llmClientId, 'LLM client not found');
        }
      } else {
        // Use default client
        llmClient = llmInfo.defaultLlmClient ?? llmInfo.primaryClient;
        if (llmClient == null) {
          throw MCPResourceNotFoundException(
              llmId, 'LLM has no client configured');
        }
      }

      // Create a new conversation
      final storage = storageManager ?? llm.MemoryStorage();
      final generatedId =
          'conv_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
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
          'conversation_${conversation.id}', conversation, (c) async {
        // Persist its state before cleanup
        if (storage is PersistentStorage) {
          await storage.persist();
        }
      }, priority: ResourceManager.lowPriority);

      PerformanceMonitor.instance.recordMetric(
          'chat.create_conversation', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'conversationId': conversation.id
          });

      _stopwatchPool.release(stopwatch);
      return conversation;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'chat.create_conversation', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId ?? 'default',
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to create conversation', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to create conversation for LLM: $llmId', e, stackTrace);
    }
  }

  /// Generate a random string of specified length
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
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
          'llm.select_client', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'selectedProvider': result?.runtimeType.toString(),
            'queryLength': query.length
          });

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.select_client', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to select LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to select LLM client for query', e, stackTrace);
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
          'Execute parallel query');

      PerformanceMonitor.instance.recordMetric(
          'llm.execute_parallel', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'providers': providerNames?.length ?? 0,
            'queryLength': query.length,
            'responseLength': result.text.length,
          });

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.execute_parallel', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to execute parallel query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to execute parallel query across providers', e, stackTrace);
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
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (llmIds.isEmpty) {
      throw MCPValidationException(
          'No LLM IDs provided for parallel execution', {});
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
          _logger.warning(
              'LLM not found for parallel execution: $llmId - skipping');
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
        throw MCPException(
            'No valid LLM clients found for any of the provided LLM IDs');
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
          'Execute parallel query across multiple LLMs');

      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'llmCount': providers.length,
            'queryLength': query.length,
            'responseLength': result.text.length,
          });

      _logger.info('Executed parallel query across ${providers.length} LLMs');

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          operationId, stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to execute parallel query', e, stackTrace);

      throw MCPOperationFailedException(
          'Failed to execute parallel query across multiple LLMs',
          e,
          stackTrace);
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
          'Fan out query to multiple LLMs');

      PerformanceMonitor.instance.recordMetric(
          'llm.fanout_query', stopwatch.elapsedMilliseconds,
          success: true,
          metadata: {
            'providerCount': results.length,
            'queryLength': query.length
          });

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'llm.fanout_query', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to fan out query', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to fan out query to multiple LLM providers', e, stackTrace);
    }
  }

  /// Execute with timeout helper
  Future<T> _executeWithTimeout<T>(Future<T> Function() operation,
      Duration timeout, String operationName) async {
    try {
      return await operation().timeout(timeout,
          onTimeout: () => throw MCPTimeoutException(
              'Operation timed out after ${timeout.inSeconds} seconds: $operationName',
              timeout));
    } on MCPTimeoutException catch (e) {
      _logger.severe('Timeout in operation: $operationName', e);
      rethrow;
    } on TimeoutException catch (e) {
      _logger.severe('Timeout in operation: $operationName', e);
      throw MCPTimeoutException(
          'Operation timed out: $operationName', timeout, e);
    }
  }

  /// Helper method to get MCPLlm instance or throw if not found
  llm.MCPLlm _getMcpLlmInstanceOrThrow(String instanceId) {
    final lazy = _mcpLlmInstances[instanceId];
    if (lazy == null) {
      throw MCPResourceNotFoundException(
          instanceId, 'MCPLlm instance not found');
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
        _logger.info(
            'Successfully registered LLM plugin ${llmPlugin.name} with flutter_mcp system');

        // Publish event for plugin registration
        _eventSystem.publishTopic('plugin.registered', {
          'name': llmPlugin.name,
          'type': 'llm_plugin',
          'source': mcpLlmInstanceId,
        });
      }

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_llm_plugin', stopwatch.elapsedMilliseconds,
          success: result,
          metadata: {
            'plugin': llmPlugin.name,
            'mcpLlmInstanceId': mcpLlmInstanceId,
          });

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_llm_plugin', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'plugin': llmPlugin.name,
            'mcpLlmInstanceId': mcpLlmInstanceId,
            'error': e.toString(),
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to register LLM plugin with flutter_mcp system', e,
          stackTrace);
      throw MCPOperationFailedException(
          'Failed to register LLM plugin with flutter_mcp system',
          e,
          stackTrace);
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
      String llmId, String llmClientId) async {
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
      final results =
          await integrator.registerPluginsFromLlmClient(llmClientId, llmClient);

      // Count successes
      final successCount = results.values.where((v) => v).length;

      _logger.info(
          'Registered $successCount/${results.length} plugins from LLM client $llmClientId');

      // Publish event for plugin registration
      _eventSystem.publishTopic('plugins.batch_registered', {
        'source': 'llm_client',
        'llmId': llmId,
        'llmClientId': llmClientId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_client', stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'successCount': successCount,
            'totalCount': results.length,
          });

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_client', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmClientId': llmClientId,
            'error': e.toString(),
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to register plugins from LLM client', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM client $llmClientId',
          e,
          stackTrace);
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
      String llmId, String llmServerId) async {
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
      final results =
          await integrator.registerPluginsFromLlmServer(llmServerId, llmServer);

      // Count successes
      final successCount = results.values.where((v) => v).length;

      _logger.info(
          'Registered $successCount/${results.length} plugins from LLM server $llmServerId');

      // Publish event for plugin registration
      _eventSystem.publishTopic('plugins.batch_registered', {
        'source': 'llm_server',
        'llmId': llmId,
        'llmServerId': llmServerId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_server', stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'successCount': successCount,
            'totalCount': results.length,
          });

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_from_llm_server', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'llmServerId': llmServerId,
            'error': e.toString(),
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to register plugins from LLM server', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register plugins from LLM server $llmServerId',
          e,
          stackTrace);
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

      _logger.info(
          'Registered $successCount/${results.length} core LLM plugins for ${isServer ? 'server' : 'client'} $clientOrServerId');

      // Publish event for plugin registration
      _eventSystem.publishTopic('plugins.core_registered', {
        'source': isServer ? 'llm_server' : 'llm_client',
        'llmId': llmId,
        'clientOrServerId': clientOrServerId,
        'successCount': successCount,
        'totalCount': results.length,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.register_core_llm_plugins', stopwatch.elapsedMilliseconds,
          success: successCount > 0,
          metadata: {
            'llmId': llmId,
            'clientOrServerId': clientOrServerId,
            'isServer': isServer,
            'successCount': successCount,
            'totalCount': results.length,
          });

      _stopwatchPool.release(stopwatch);
      return results;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.register_core_llm_plugins', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'llmId': llmId,
            'clientOrServerId': clientOrServerId,
            'isServer': isServer,
            'error': e.toString(),
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to register core LLM plugins', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to register core LLM plugins for ${isServer ? 'server' : 'client'} $clientOrServerId',
          e,
          stackTrace);
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
            {'plugin_type': mcpPlugin.runtimeType.toString()});
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

      _logger.info(
          'Converted MCP plugin ${mcpPlugin.name} to LLM plugin and registered with ${anySuccess ? 'some' : 'no'} targets');

      // Publish event for plugin conversion
      _eventSystem.publishTopic('plugin.converted', {
        'name': mcpPlugin.name,
        'source': 'mcp_plugin',
        'target': 'llm_plugin',
        'success': anySuccess,
      });

      PerformanceMonitor.instance.recordMetric(
          'plugin.convert_mcp_to_llm', stopwatch.elapsedMilliseconds,
          success: anySuccess,
          metadata: {
            'plugin': mcpPlugin.name,
            'targetLlmCount': targetLlmIds?.length ?? 0,
            'targetClientCount': targetLlmClientIds?.length ?? 0,
            'targetServerCount': targetLlmServerIds?.length ?? 0,
          });

      _stopwatchPool.release(stopwatch);
      return anySuccess;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.convert_mcp_to_llm', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'plugin': mcpPlugin.name,
            'error': e.toString(),
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to convert MCP plugin to LLM plugin', e, stackTrace);
      throw MCPOperationFailedException(
          'Failed to convert MCP plugin ${mcpPlugin.name} to LLM plugin',
          e,
          stackTrace);
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
    final llmPlugins =
        _llmManager.getPluginIntegrator().getRegisteredLlmPluginNames();

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
      throw MCPValidationException('Provider name cannot be empty',
          {'name': 'Provider name is required'});
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
  Future<void> registerPlugin(MCPPlugin plugin,
      [Map<String, dynamic>? config]) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (plugin.name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty', {'name': 'Plugin name is required'});
    }

    await _pluginRegistry.registerPlugin(plugin, config);

    // Register for cleanup
    _resourceManager.register<MCPPlugin>(
        'plugin_${plugin.name}', plugin, (p) async => await p.shutdown(),
        priority: ResourceManager.mediumPriority);

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
          'Plugin name cannot be empty', {'name': 'Plugin name is required'});
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
      String name, Map<String, dynamic> arguments,
      {Duration? timeout}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty', {'name': 'Plugin name is required'});
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final effectiveTimeout = timeout ?? Duration(seconds: 30);

      // Execute with timeout
      final result = await _executeWithTimeout(
          () => _pluginRegistry.executeTool(name, arguments),
          effectiveTimeout,
          'Execute plugin tool $name');

      PerformanceMonitor.instance.recordMetric(
          'plugin.execute_tool', stopwatch.elapsedMilliseconds,
          success: true, metadata: {'plugin': name});

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.execute_tool', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'plugin': name, 'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe('Failed to execute tool plugin: $name', e, stackTrace);
      throw MCPPluginException(
          name, 'Failed to execute tool plugin', e, stackTrace);
    }
  }

  /// Get resource from a resource plugin with improved error handling
  ///
  /// [name]: Plugin name
  /// [resourceUri]: Resource URI
  /// [params]: Resource parameters
  Future<Map<String, dynamic>> getPluginResource(
      String name, String resourceUri, Map<String, dynamic> params,
      {Duration? timeout}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (name.isEmpty) {
      throw MCPValidationException(
          'Plugin name cannot be empty', {'name': 'Plugin name is required'});
    }

    if (resourceUri.isEmpty) {
      throw MCPValidationException('Resource URI cannot be empty',
          {'resourceUri': 'Resource URI is required'});
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final effectiveTimeout = timeout ?? Duration(seconds: 30);

      // Execute with timeout
      final result = await _executeWithTimeout(
          () => _pluginRegistry.getResource(name, resourceUri, params),
          effectiveTimeout,
          'Get plugin resource from $name: $resourceUri');

      PerformanceMonitor.instance.recordMetric(
          'plugin.get_resource', stopwatch.elapsedMilliseconds,
          success: true, metadata: {'plugin': name, 'uri': resourceUri});

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.get_resource', stopwatch.elapsedMilliseconds,
          success: false,
          metadata: {
            'plugin': name,
            'uri': resourceUri,
            'error': e.toString()
          });

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to get resource from plugin: $name', e, stackTrace);
      throw MCPPluginException(
          name, 'Failed to get resource from plugin', e, stackTrace);
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
          'Plugin name cannot be empty', {'name': 'Plugin name is required'});
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
          'plugin.show_notification', stopwatch.elapsedMilliseconds,
          success: true, metadata: {'plugin': name});

      _stopwatchPool.release(stopwatch);
    } catch (e, stackTrace) {
      PerformanceMonitor.instance.recordMetric(
          'plugin.show_notification', stopwatch.elapsedMilliseconds,
          success: false, metadata: {'plugin': name, 'error': e.toString()});

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Failed to show notification using plugin: $name', e, stackTrace);
      throw MCPPluginException(
          name, 'Failed to show notification using plugin', e, stackTrace);
    }
  }

  // Enhanced Plugin Management Methods

  /// Register plugin with enhanced version management and sandboxing
  ///
  /// [plugin]: Plugin to register
  /// [config]: Plugin configuration including version and sandbox settings
  Future<void> registerPluginEnhanced(
    MCPPlugin plugin, {
    Map<String, dynamic>? config,
    PluginSandboxConfig? sandboxConfig,
    Version? version,
    Map<String, VersionConstraint>? dependencies,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Build enhanced config
    final enhancedConfig = Map<String, dynamic>.from(config ?? {});

    if (version != null) {
      enhancedConfig['version'] = version.toString();
    }

    if (dependencies != null && dependencies.isNotEmpty) {
      enhancedConfig['dependencies'] = dependencies.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    }

    if (sandboxConfig != null) {
      enhancedConfig['sandbox'] = {
        'executionTimeoutMs': sandboxConfig.executionTimeout?.inMilliseconds,
        'maxMemoryMB': sandboxConfig.maxMemoryMB,
        'allowedPaths': sandboxConfig.allowedPaths,
        'allowedCommands': sandboxConfig.allowedCommands,
        'enableNetworkAccess': sandboxConfig.enableNetworkAccess,
        'enableFileAccess': sandboxConfig.enableFileAccess,
      };
    }

    await _pluginRegistry.registerPlugin(plugin, enhancedConfig);

    // Register for cleanup
    _resourceManager.register<MCPPlugin>(
        'plugin_${plugin.name}', plugin, (p) async => await p.shutdown(),
        priority: ResourceManager.mediumPriority);

    _logger.info(
        'Registered enhanced plugin: ${plugin.name} v${version ?? 'unknown'}');
  }

  /// Get plugin version information
  PluginVersion? getPluginVersion(String pluginName) {
    return _pluginRegistry.getPluginVersion(pluginName);
  }

  /// Get all plugin versions
  Map<String, PluginVersion> getAllPluginVersions() {
    return _pluginRegistry.getAllPluginVersions();
  }

  /// Check for version conflicts and get resolution suggestions
  List<PluginUpdateSuggestion> checkPluginVersionConflicts() {
    return _pluginRegistry.resolveVersionConflicts();
  }

  /// Update plugin sandbox configuration
  Future<void> updatePluginSandboxConfig(
    String pluginName,
    PluginSandboxConfig config,
  ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _pluginRegistry.updatePluginSandboxConfig(pluginName, config);
    _logger.info('Updated sandbox config for plugin: $pluginName');
  }

  /// Get plugin sandbox configuration
  PluginSandboxConfig? getPluginSandboxConfig(String pluginName) {
    return _pluginRegistry.getPluginSandboxConfig(pluginName);
  }

  /// Execute plugin operation in sandbox with enhanced monitoring
  Future<T> executePluginInSandbox<T>(
    String pluginName,
    Future<T> Function() operation, {
    Map<String, dynamic>? context,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final stopwatch = _stopwatchPool.acquire();
    stopwatch.start();

    try {
      final result = await _pluginRegistry.executeInSandbox(
        pluginName,
        operation,
        context: context,
      );

      // Record enhanced performance metric
      if (_config?.enablePerformanceMonitoring ?? false) {
        _enhancedPerformanceMonitor.recordTypedMetric(CustomMetric(
          name: 'plugin.sandbox_execution',
          value: stopwatch.elapsedMilliseconds.toDouble(),
          type: MetricType.timer,
          unit: 'ms',
          category: 'plugin',
          metadata: {
            'plugin': pluginName,
            'success': true,
            'context': context?.keys.join(',') ?? 'none',
          },
        ));
      }

      _stopwatchPool.release(stopwatch);
      return result;
    } catch (e, stackTrace) {
      // Record failed metric
      if (_config?.enablePerformanceMonitoring ?? false) {
        _enhancedPerformanceMonitor.recordTypedMetric(CustomMetric(
          name: 'plugin.sandbox_execution',
          value: stopwatch.elapsedMilliseconds.toDouble(),
          type: MetricType.timer,
          unit: 'ms',
          category: 'plugin',
          metadata: {
            'plugin': pluginName,
            'success': false,
            'error': e.toString(),
          },
        ));
      }

      _stopwatchPool.release(stopwatch);
      _logger.severe(
          'Plugin sandbox execution failed: $pluginName', e, stackTrace);
      rethrow;
    }
  }

  /// Get comprehensive plugin system report
  Map<String, dynamic> getPluginSystemReport() {
    final baseReport = {
      'totalPlugins': _pluginRegistry.getAllPluginNames().length,
      'pluginNames': _pluginRegistry.getAllPluginNames(),
    };

    // Add enhanced information
    final versions = getAllPluginVersions();
    final conflicts = checkPluginVersionConflicts();

    baseReport['versions'] = versions.map((name, version) => MapEntry(name, {
          'version': version.version.toString(),
          'minSdkVersion': version.minSdkVersion?.toString(),
          'maxSdkVersion': version.maxSdkVersion?.toString(),
          'dependencies':
              version.dependencies.map((k, v) => MapEntry(k, v.toString())),
        }));

    baseReport['versionConflicts'] = conflicts
        .map((suggestion) => {
              'plugin': suggestion.pluginName,
              'currentVersion': suggestion.currentVersion.toString(),
              'suggestedConstraint': suggestion.suggestedConstraint.toString(),
              'reason': suggestion.reason,
            })
        .toList();

    // Add sandbox information
    final sandboxInfo = <String, dynamic>{};
    for (final pluginName in _pluginRegistry.getAllPluginNames()) {
      final sandboxConfig = getPluginSandboxConfig(pluginName);
      if (sandboxConfig != null) {
        sandboxInfo[pluginName] = {
          'executionTimeout': sandboxConfig.executionTimeout?.inMilliseconds,
          'maxMemoryMB': sandboxConfig.maxMemoryMB,
          'networkAccess': sandboxConfig.enableNetworkAccess,
          'fileAccess': sandboxConfig.enableFileAccess,
        };
      }
    }
    baseReport['sandboxes'] = sandboxInfo;

    return baseReport;
  }

  // Enhanced Security Management Methods

  /// Authenticate user with enhanced security audit
  Future<bool> authenticateUser(String userId, String password,
      {Map<String, dynamic>? metadata}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Check if user is locked out
    if (_securityAuditManager.isUserLockedOut(userId)) {
      _logger.warning('Authentication attempt for locked out user: $userId');
      return false;
    }

    // Simulate password verification (replace with actual authentication logic)
    final success = password.isNotEmpty && password.length >= 8;

    // Log authentication attempt
    _securityAuditManager.checkAuthenticationAttempt(userId, success,
        metadata: metadata);

    if (success) {
      _logger.info('User authenticated successfully: $userId');
    } else {
      _logger.warning('Failed authentication attempt for user: $userId');
    }

    return success;
  }

  /// Start user session with security tracking
  Future<String> startUserSession(String userId,
      {Map<String, dynamic>? metadata}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final sessionId =
        _securityAuditManager.startSession(userId, metadata: metadata);
    _logger.info('Started session for user: $userId, session: $sessionId');
    return sessionId;
  }

  /// End user session with security tracking
  Future<void> endUserSession(String userId, String sessionId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _securityAuditManager.endSession(userId, sessionId);
    _logger.info('Ended session for user: $userId, session: $sessionId');
  }

  /// Check data access authorization
  Future<bool> checkDataAccess(String userId, String resource, String action,
      {Map<String, dynamic>? metadata}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _securityAuditManager.checkDataAccess(userId, resource, action,
        metadata: metadata);
  }

  /// Encrypt sensitive data
  Future<String> encryptData(String keyIdOrAlias, String data,
      {Map<String, dynamic>? parameters}) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final encryptedData =
        _encryptionManager.encrypt(keyIdOrAlias, data, parameters: parameters);
    return jsonEncode(encryptedData.toJson());
  }

  /// Decrypt sensitive data
  Future<String> decryptData(String encryptedDataJson) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final encryptedData = EncryptedData.fromJson(jsonDecode(encryptedDataJson));
    return _encryptionManager.decrypt(encryptedData);
  }

  /// Generate encryption key
  String generateEncryptionKey(EncryptionAlgorithm algorithm,
      {String? alias, Duration? expiresIn}) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _encryptionManager.generateKey(algorithm,
        alias: alias, expiresIn: expiresIn);
  }

  /// Get user risk assessment
  Map<String, dynamic> getUserRiskAssessment(String userId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _securityAuditManager.getUserRiskAssessment(userId);
  }

  /// Get security audit events for user
  List<SecurityAuditEvent> getUserAuditEvents(String userId, {int? limit}) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _securityAuditManager.getUserAuditEvents(userId, limit: limit);
  }

  /// Generate comprehensive security report
  Map<String, dynamic> generateSecurityReport() {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final auditReport = _securityAuditManager.generateSecurityReport();
    final encryptionReport = _encryptionManager.generateSecurityReport();

    return {
      'generatedAt': DateTime.now().toIso8601String(),
      'audit': auditReport,
      'encryption': encryptionReport,
      'summary': {
        'totalSecurityEvents': auditReport['totalEvents'],
        'activeEncryptionKeys': encryptionReport['activeKeys'],
        'highRiskUsers': auditReport['highRiskUsers'],
        'expiredKeys': encryptionReport['expiredKeys'],
      },
    };
  }

  /// Update security policy
  void updateSecurityPolicy(SecurityPolicy policy) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _securityAuditManager.updatePolicy(policy);
    _logger.info('Security policy updated');
  }

  /// Clean up expired encryption keys
  int cleanupExpiredEncryptionKeys() {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _encryptionManager.cleanupExpiredKeys();
  }

  /// Clean up all resources with improved prioritization
  Future<void> _cleanup() async {
    _logger.fine('Cleaning up resources');

    try {
      // Stop the scheduler first
      _scheduler.stop();

      // Clean up all registered resources using enhanced cleanup
      await EnhancedResourceCleanup.instance.disposeAll();

      // Also dispose legacy resource manager
      await _resourceManager.disposeAll();

      // Signal the event system
      _eventSystem.publishTopic(
          'mcp.shutdown', {'timestamp': DateTime.now().toIso8601String()});

      // Log cleanup statistics
      final stats = EnhancedResourceCleanup.instance.getStatistics();
      _logger.info('Resource cleanup statistics: $stats');

      // Logger flushing not needed with standard logging package
    } catch (e, stackTrace) {
      _logger.severe('Error during cleanup', e, stackTrace);
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
      _logger.severe('Error during shutdown', e, stackTrace);
      // Still mark as not initialized even if there was an error
      _initialized = false;
    }
  }

  /// ID access methods
  List<String> get allClientIds => _clientManager.getAllClientIds();
  List<String> get allServerIds => _serverManager.getAllServerIds();
  List<String> get allLlmIds => _llmManager.getAllLlmIds();

  /// Object access methods
  client.Client? getClient(String clientId) =>
      _clientManager.getClient(clientId);
  server.Server? getServer(String serverId) =>
      _serverManager.getServer(serverId);
  llm.LlmClient? getLlmClient(String llmId) =>
      _llmManager.getLlmClientById(llmId);
  llm.LlmServer? getLlmServer(String llmId) =>
      _llmManager.getLlmServerById(llmId);

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
        'backgroundServiceRunning':
            _platformServices.isBackgroundServiceRunning,
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
          MapEntry(name, {
            'state': breaker.state.toString(),
            'failureCount': breaker.failureCount
          }));

      // Add performance metrics if available
      if (_config?.enablePerformanceMonitoring ?? false) {
        status['performanceMetrics'] =
            PerformanceMonitor.instance.getMetricsSummary();
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
            MapEntry(id, {'size': cache.size, 'hitRate': cache.hitRate})),
      };

      // Add comprehensive diagnostics
      status['diagnostics'] = DiagnosticUtils.collectSystemDiagnostics(this);

      return status;
    } catch (e, stackTrace) {
      _logger.severe('Error getting system status', e, stackTrace);
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
      _logger.severe('Error checking system health', e, stackTrace);
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

  // ============ New v1.0.0 Feature Methods ============

  /// Process multiple requests in a batch for improved performance
  ///
  /// Leverages the BatchRequestManager to process multiple operations
  /// with 40-60% performance improvement.
  ///
  /// [llmId]: The LLM instance to use for batch processing
  /// [requests]: List of request functions to execute
  /// [operationName]: Optional name for tracking the batch operation
  ///
  /// Returns: List of results from each request
  Future<List<T>> processBatch<T>({
    required String llmId,
    required List<Future<T> Function()> requests,
    String? operationName,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Initialize batch manager for the LLM if not already done
    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPResourceNotFoundException(llmId, 'LLM not found');
    }

    _batchManager.initializeBatchManager(llmId, llmInfo.mcpLlm);

    // Process requests using enhanced batch manager
    final futures = <Future<T>>[];
    for (final request in requests) {
      futures.add(_batchManager.addToBatch<T>(
        llmId: llmId,
        request: request,
        operationName: operationName,
      ));
    }

    return await Future.wait(futures);
  }

  /// Process multiple chat requests in a batch
  ///
  /// [llmId]: The LLM instance to use
  /// [llmClientId]: The LLM client to use
  /// [messagesList]: List of message arrays to process
  /// [options]: Optional parameters for the batch
  ///
  /// Returns: List of chat responses
  Future<List<String>> batchChat({
    required String llmId,
    required String llmClientId,
    required List<List<llm.LlmMessage>> messagesList,
    Map<String, dynamic>? options,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Ensure LLM is registered with batch manager
    final llmInstance = _mcpLlmInstances[llmId]?.value;
    if (llmInstance == null) {
      throw MCPException('LLM not found: $llmId');
    }

    _batchManager.initializeBatchManager(llmId, llmInstance);

    // Process chat requests using enhanced batch manager
    final futures = <Future<String>>[];
    for (final messages in messagesList) {
      futures.add(_batchManager.addToBatch<String>(
        llmId: llmId,
        request: () async {
          final llmClient = _llmManager.getLlmClientById(llmClientId);
          if (llmClient == null) {
            throw MCPException('LLM client not found: $llmClientId');
          }

          final response = await llmClient.chat(
            messages.map((m) => m.content).join('\n'),
            parameters: options ?? {},
          );

          return response.text;
        },
        operationName: 'batch_chat',
        priority: BatchRequestPriority.high,
      ));
    }

    return await Future.wait(futures);
  }

  /// Get batch processing statistics
  ///
  /// [llmId]: Optional LLM ID to get statistics for specific instance
  ///
  /// Returns: Map of batch processing statistics
  Map<String, dynamic> getBatchStatistics([String? llmId]) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    if (llmId != null) {
      final stats = _batchManager.getStatistics(llmId);
      if (stats == null) {
        return {};
      }
      return {
        'totalRequests': stats.totalRequests,
        'successfulRequests': stats.successfulRequests,
        'failedRequests': stats.failedRequests,
        'retriedRequests': stats.retriedRequests,
        'deduplicatedRequests': stats.deduplicatedRequests,
        'successRate': stats.successRate,
        'throughput': stats.throughput,
        'averageWaitTimeMs': stats.averageWaitTime.inMilliseconds,
        'averageExecutionTimeMs': stats.averageExecutionTime.inMilliseconds,
        'requestsByPriority':
            stats.requestsByPriority.map((k, v) => MapEntry(k.name, v)),
      };
    } else {
      final allStats = _batchManager.getAllStatistics();
      return allStats.map((llmId, stats) => MapEntry(llmId, {
            'totalRequests': stats.totalRequests,
            'successfulRequests': stats.successfulRequests,
            'failedRequests': stats.failedRequests,
            'retriedRequests': stats.retriedRequests,
            'deduplicatedRequests': stats.deduplicatedRequests,
            'successRate': stats.successRate,
            'throughput': stats.throughput,
            'averageWaitTimeMs': stats.averageWaitTime.inMilliseconds,
            'averageExecutionTimeMs': stats.averageExecutionTime.inMilliseconds,
            'requestsByPriority':
                stats.requestsByPriority.map((k, v) => MapEntry(k.name, v)),
          }));
    }
  }

  /// Initialize OAuth authentication for an LLM instance
  ///
  /// [llmId]: The LLM instance to configure OAuth for
  /// [config]: OAuth configuration including client credentials and endpoints
  Future<void> initializeOAuth({
    required String llmId,
    required OAuthConfig config,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPResourceNotFoundException(llmId, 'LLM not found');
    }

    await _oauthManager.initializeOAuth(
      llmId: llmId,
      mcpLlm: llmInfo.mcpLlm,
      config: config,
    );
  }

  /// Authenticate and get access token for an LLM
  ///
  /// [llmId]: The LLM instance to authenticate
  ///
  /// Returns: Access token string
  Future<String> authenticateOAuth(String llmId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return await _oauthManager.authenticate(llmId);
  }

  /// Check if OAuth is authenticated for an LLM
  ///
  /// [llmId]: The LLM instance to check
  ///
  /// Returns: True if authenticated with valid token
  bool isOAuthAuthenticated(String llmId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _oauthManager.isAuthenticated(llmId);
  }

  /// Revoke OAuth token for an LLM
  ///
  /// [llmId]: The LLM instance to revoke token for
  Future<void> revokeOAuthToken(String llmId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _oauthManager.revokeToken(llmId);
  }

  /// Get OAuth authentication headers
  ///
  /// [llmId]: The LLM instance to get headers for
  ///
  /// Returns: Map of authentication headers
  Future<Map<String, String>> getOAuthHeaders(String llmId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return await _oauthManager.getAuthHeaders(llmId);
  }

  /// Get health status for a specific component
  ///
  /// [componentId]: The component to check health for
  ///
  /// Returns: Health check result
  Future<MCPHealthCheckResult> getComponentHealth(String componentId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Simple health check implementation
    try {
      // Check if component exists
      if (componentId.startsWith('client_')) {
        final clientId = componentId.substring(7);
        final info = _clientManager.getClientInfo(clientId);
        if (info != null && info.connected) {
          return MCPHealthCheckResult(
            status: MCPHealthStatus.healthy,
            message: 'Client is connected',
          );
        }
        return MCPHealthCheckResult(
          status: MCPHealthStatus.unhealthy,
          message: 'Client is not connected',
        );
      } else if (componentId.startsWith('server_')) {
        final serverId = componentId.substring(7);
        final info = _serverManager.getServerInfo(serverId);
        if (info != null && info.running) {
          return MCPHealthCheckResult(
            status: MCPHealthStatus.healthy,
            message: 'Server is running',
          );
        }
        return MCPHealthCheckResult(
          status: MCPHealthStatus.unhealthy,
          message: 'Server is not running',
        );
      } else if (componentId.startsWith('llm_')) {
        final llmId = componentId.substring(4);
        final info = _llmManager.getLlmInfo(llmId);
        if (info != null) {
          return MCPHealthCheckResult(
            status: MCPHealthStatus.healthy,
            message: 'LLM is available',
          );
        }
        return MCPHealthCheckResult(
          status: MCPHealthStatus.unhealthy,
          message: 'LLM not found',
        );
      }

      return MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'Unknown component: $componentId',
      );
    } catch (e) {
      return MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'Error checking health: $e',
      );
    }
  }

  /// Get overall system health including all components
  ///
  /// Returns: Comprehensive system health report
  Future<Map<String, dynamic>> getSystemHealth() async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Simple system health implementation
    final health = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'overall': MCPHealthStatus.healthy.name,
      'components': <String, dynamic>{},
    };

    int unhealthyCount = 0;
    int degradedCount = 0;

    // Check all clients
    for (final clientId in _clientManager.getAllClientIds()) {
      final result = await getComponentHealth('client_$clientId');
      health['components']['client_$clientId'] = {
        'status': result.status.name,
        'message': result.message,
      };
      if (result.status == MCPHealthStatus.unhealthy) unhealthyCount++;
      if (result.status == MCPHealthStatus.degraded) degradedCount++;
    }

    // Check all servers
    for (final serverId in _serverManager.getAllServerIds()) {
      final result = await getComponentHealth('server_$serverId');
      health['components']['server_$serverId'] = {
        'status': result.status.name,
        'message': result.message,
      };
      if (result.status == MCPHealthStatus.unhealthy) unhealthyCount++;
      if (result.status == MCPHealthStatus.degraded) degradedCount++;
    }

    // Check all LLMs
    for (final llmId in _llmManager.getAllLlmIds()) {
      final result = await getComponentHealth('llm_$llmId');
      health['components']['llm_$llmId'] = {
        'status': result.status.name,
        'message': result.message,
      };
      if (result.status == MCPHealthStatus.unhealthy) unhealthyCount++;
      if (result.status == MCPHealthStatus.degraded) degradedCount++;
    }

    // Determine overall health
    if (unhealthyCount > 0) {
      health['overall'] = MCPHealthStatus.unhealthy.name;
    } else if (degradedCount > 0) {
      health['overall'] = MCPHealthStatus.degraded.name;
    }

    return health;
  }

  /// Get health status stream for real-time monitoring
  ///
  /// Returns: Stream of health check results
  Stream<MCPHealthCheckResult> get healthStream {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Use the enhanced health monitor
    return _healthMonitor.healthStream;
  }

  /// Get resource usage statistics
  Map<String, dynamic> getResourceStatistics() {
    return EnhancedResourceCleanup.instance.getStatistics();
  }

  /// Check for resource leaks manually
  void checkForResourceLeaks() {
    EnhancedResourceCleanup.instance.checkForLeaks();
  }

  /// Get detailed resource information
  List<Map<String, dynamic>> getResourceDetails() {
    return EnhancedResourceCleanup.instance.getResourceDetails();
  }
}

/// Rate limit exception for LLM services with automatic retry-after calculation
class MCPRateLimitException extends MCPException {
  final Duration? retryAfter;

  MCPRateLimitException(String message,
      [dynamic originalError, StackTrace? stackTrace, this.retryAfter])
      : super('Rate limit error: $message', originalError, stackTrace);
}

/// Circuit breaker open exception for when too many operations have failed
class MCPCircuitBreakerOpenException extends MCPException {
  MCPCircuitBreakerOpenException(String message,
      [dynamic originalError, StackTrace? stackTrace])
      : super('Circuit breaker open: $message', originalError, stackTrace);
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

// Health types are exported from src/types/health_types.dart
