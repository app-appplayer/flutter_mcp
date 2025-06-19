/// Type-safe plugin system implementation

library;

import 'dart:async';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/event_models.dart';
import '../events/event_system.dart';
import '../metrics/typed_metrics.dart';
import '../utils/performance_monitor.dart';
import 'typed_plugin_interfaces.dart';

/// Base interface for all typed plugins
abstract class TypedMCPPlugin {
  /// Plugin name
  String get name;

  /// Plugin version
  String get version;

  /// Plugin description
  String get description;

  /// Plugin capabilities
  List<String> get capabilities;

  /// Plugin status
  PluginStatus get status;

  /// Initialize plugin with typed configuration
  Future<PluginResult<bool>> initialize(PluginContext context);

  /// Shutdown plugin gracefully
  Future<PluginResult<bool>> shutdown(PluginContext context);

  /// Get plugin health status
  Future<PluginHealthStatus> getHealth();

  /// Handle plugin events
  void onEvent(PluginEvent event);
}

/// Typed tool plugin interface
abstract class TypedToolPlugin extends TypedMCPPlugin {
  /// Tool input schema
  ToolInputSchema get inputSchema;

  /// Tool output schema
  ToolOutputSchema? get outputSchema;

  /// Execute tool with typed request
  Future<ToolResponse> execute(ToolRequest request);

  /// Validate tool request
  Future<List<ValidationError>> validateRequest(ToolRequest request);
}

/// Typed resource plugin interface
abstract class TypedResourcePlugin extends TypedMCPPlugin {
  /// Supported resource URIs pattern
  String get uriPattern;

  /// Resource input schema
  ResourceInputSchema? get inputSchema;

  /// Get resource with typed request
  Future<ResourceResponse> getResource(ResourceRequest request);

  /// List available resources
  Future<List<String>> listResources();

  /// Check if resource exists
  Future<bool> resourceExists(String uri);
}

/// Typed prompt plugin interface
abstract class TypedPromptPlugin extends TypedMCPPlugin {
  /// Prompt input schema
  PromptInputSchema get inputSchema;

  /// Execute prompt with typed request
  Future<PromptResponse> execute(PromptRequest request);

  /// Get prompt template
  String getTemplate();

  /// Validate prompt arguments
  Future<List<ValidationError>> validateArguments(
      Map<String, dynamic> arguments);
}

/// Typed background plugin interface
abstract class TypedBackgroundPlugin extends TypedMCPPlugin {
  /// Background task configuration
  BackgroundTaskConfig get taskConfig;

  /// Check if task is running
  bool get isRunning;

  /// Start background task
  Future<PluginResult<bool>> start(PluginContext context);

  /// Stop background task
  Future<PluginResult<bool>> stop(PluginContext context);

  /// Execute background task
  Future<BackgroundTaskResult> executeTask(PluginContext context);

  /// Register task completion handler
  void onTaskCompleted(Function(BackgroundTaskResult) handler);
}

/// Typed notification plugin interface
abstract class TypedNotificationPlugin extends TypedMCPPlugin {
  /// Platform support check
  bool get isSupported;

  /// Show notification with typed request
  Future<NotificationResponse> showNotification(NotificationRequest request);

  /// Hide notification by ID
  Future<PluginResult<bool>> hideNotification(String id);

  /// Register click handler
  void onNotificationClicked(
      Function(String id, Map<String, dynamic> data) handler);

  /// Get notification permissions
  Future<NotificationPermissionStatus> getPermissions();
}

/// Typed tray plugin interface
abstract class TypedTrayPlugin extends TypedMCPPlugin {
  /// Platform support check
  bool get isSupported;

  /// Set tray icon
  Future<PluginResult<bool>> setIcon(String iconPath);

  /// Set tray tooltip
  Future<PluginResult<bool>> setTooltip(String tooltip);

  /// Set tray menu
  Future<PluginResult<bool>> setMenu(TrayMenuConfig menu);

  /// Show tray
  Future<PluginResult<bool>> show();

  /// Hide tray
  Future<PluginResult<bool>> hide();

  /// Register menu action handler
  void onMenuAction(Function(String action, Map<String, dynamic> data) handler);
}

/// Plugin status enumeration
enum PluginStatus {
  uninitialized,
  initializing,
  active,
  inactive,
  error,
  shuttingDown,
}

/// Plugin health status
class PluginHealthStatus {
  final PluginStatus status;
  final bool isHealthy;
  final String? errorMessage;
  final DateTime lastCheck;
  final Map<String, dynamic> metrics;

  PluginHealthStatus({
    required this.status,
    required this.isHealthy,
    this.errorMessage,
    required this.lastCheck,
    this.metrics = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status.name,
      'isHealthy': isHealthy,
      'errorMessage': errorMessage,
      'lastCheck': lastCheck.toIso8601String(),
      'metrics': metrics,
    };
  }
}

/// Notification permission status
enum NotificationPermissionStatus {
  granted,
  denied,
  notDetermined,
  restricted,
}

/// Plugin lifecycle event extending McpEvent
class PluginLifecycleEvent extends McpEvent {
  final String pluginName;
  final PluginStatus oldStatus;
  final PluginStatus newStatus;
  final Map<String, dynamic> data;

  PluginLifecycleEvent({
    required this.pluginName,
    required this.oldStatus,
    required this.newStatus,
    super.timestamp,
    this.data = const {},
  });

  @override
  String get eventType => 'plugin.lifecycle';

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'pluginName': pluginName,
      'timestamp': timestamp.toIso8601String(),
      'oldStatus': oldStatus.name,
      'newStatus': newStatus.name,
      'data': data,
    };
  }

  static PluginLifecycleEvent fromMap(Map<String, dynamic> map) {
    return PluginLifecycleEvent(
      pluginName: map['pluginName'] as String,
      oldStatus:
          PluginStatus.values.firstWhere((s) => s.name == map['oldStatus']),
      newStatus:
          PluginStatus.values.firstWhere((s) => s.name == map['newStatus']),
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
    );
  }
}

/// Plugin error event extending McpEvent
class PluginErrorEvent extends McpEvent {
  final String pluginName;
  final String error;
  final String? details;
  final Object? originalError;
  final Map<String, dynamic> data;

  PluginErrorEvent({
    required this.pluginName,
    required this.error,
    this.details,
    this.originalError,
    super.timestamp,
    this.data = const {},
  });

  @override
  String get eventType => 'plugin.error';

  @override
  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'pluginName': pluginName,
      'timestamp': timestamp.toIso8601String(),
      'error': error,
      'details': details,
      'data': data,
    };
  }

  static PluginErrorEvent fromMap(Map<String, dynamic> map) {
    return PluginErrorEvent(
      pluginName: map['pluginName'] as String,
      error: map['error'] as String,
      details: map['details'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: Map<String, dynamic>.from(map['data'] as Map? ?? {}),
    );
  }
}

/// Type-safe plugin registry
class TypedPluginRegistry {
  final Logger _logger = Logger('flutter_mcp.typed_plugin_registry');

  /// Registered plugins by type and name
  final Map<Type, Map<String, TypedMCPPlugin>> _plugins = {};

  /// Plugin configurations
  final Map<String, PluginConfig> _configurations = {};

  /// Plugin dependencies
  final Map<String, List<String>> _dependencies = {};

  /// Plugin metrics
  final Map<String, List<PerformanceMetric>> _pluginMetrics = {};

  /// Plugin load order
  final List<String> _loadOrder = [];

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor.instance;

  /// Register a typed plugin
  Future<PluginResult<String>> registerPlugin(
    TypedMCPPlugin plugin,
    PluginConfig config,
  ) async {
    final pluginType = plugin.runtimeType;
    final pluginName = plugin.name;

    _logger.info('Registering typed plugin: $pluginName v${plugin.version}');

    try {
      // Validate plugin
      final validationResult = await _validatePlugin(plugin, config);
      if (!validationResult.isSuccess) {
        return FailureResult<String>(validationResult.error!);
      }

      // Initialize plugin type map if not exists
      _plugins.putIfAbsent(pluginType, () => {});

      // Check if plugin with same name already exists
      if (_plugins[pluginType]!.containsKey(pluginName)) {
        return FailureResult<String>(
            'Plugin with name "$pluginName" is already registered');
      }

      // Store configuration
      _configurations[pluginName] = config;

      // Create plugin context
      final context = PluginContext(
        requestId: 'register_$pluginName',
        pluginName: pluginName,
        config: config,
      );

      // Publish lifecycle event
      _publishLifecycleEvent(
          pluginName, PluginStatus.uninitialized, PluginStatus.initializing);

      // Initialize the plugin with timing
      final stopwatch = Stopwatch()..start();
      final initResult = await plugin.initialize(context);
      stopwatch.stop();

      // Record initialization metrics
      _recordPluginMetric(
          pluginName,
          TimerMetric(
            name: 'plugin.initialization',
            duration: stopwatch.elapsed,
            operation: 'initialize',
            success: initResult.isSuccess,
            errorMessage: initResult.error,
          ));

      if (initResult.isSuccess) {
        _plugins[pluginType]![pluginName] = plugin;

        // Add to load order
        if (!_loadOrder.contains(pluginName)) {
          _loadOrder.add(pluginName);
        }

        // Publish success event
        _publishLifecycleEvent(
            pluginName, PluginStatus.initializing, PluginStatus.active);

        _logger
            .info('Plugin $pluginName successfully registered and initialized');
        return SuccessResult<String>('Plugin registered successfully');
      } else {
        // Publish error event
        _publishErrorEvent(
            pluginName, 'Initialization failed', initResult.error);

        return FailureResult<String>(
          'Failed to initialize plugin: ${initResult.error}',
          originalError: initResult,
        );
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to register plugin $pluginName', e, stackTrace);
      _publishErrorEvent(pluginName, 'Registration failed', e.toString());

      return FailureResult<String>(
        'Failed to register plugin: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Unregister a typed plugin
  Future<PluginResult<String>> unregisterPlugin(String pluginName) async {
    _logger.info('Unregistering typed plugin: $pluginName');

    TypedMCPPlugin? foundPlugin;
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
      return FailureResult<String>('Plugin $pluginName not found');
    }

    try {
      // Publish lifecycle event
      _publishLifecycleEvent(
          pluginName, foundPlugin.status, PluginStatus.shuttingDown);

      // Create shutdown context
      final config = _configurations[pluginName]!;
      final context = PluginContext(
        requestId: 'shutdown_$pluginName',
        pluginName: pluginName,
        config: config,
      );

      // Shutdown the plugin with timing
      final stopwatch = Stopwatch()..start();
      final shutdownResult = await foundPlugin.shutdown(context);
      stopwatch.stop();

      // Record shutdown metrics
      _recordPluginMetric(
          pluginName,
          TimerMetric(
            name: 'plugin.shutdown',
            duration: stopwatch.elapsed,
            operation: 'shutdown',
            success: shutdownResult.isSuccess,
            errorMessage: shutdownResult.error,
          ));

      // Always clean up resources regardless of shutdown result
      _plugins[foundType]!.remove(pluginName);
      _configurations.remove(pluginName);
      _pluginMetrics.remove(pluginName);

      // Remove from load order
      _loadOrder.remove(pluginName);

      // Remove dependencies
      _dependencies.remove(pluginName);
      for (final deps in _dependencies.values) {
        deps.remove(pluginName);
      }

      _logger.info('Plugin $pluginName successfully unregistered');
      return SuccessResult<String>('Plugin unregistered successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to unregister plugin $pluginName', e, stackTrace);
      _publishErrorEvent(pluginName, 'Unregistration failed', e.toString());

      return FailureResult<String>(
        'Failed to unregister plugin: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Get a typed plugin by name and type
  T? getPlugin<T extends TypedMCPPlugin>(String name) {
    for (final entry in _plugins.entries) {
      if (entry.value.containsKey(name) && entry.value[name] is T) {
        return entry.value[name] as T;
      }
    }
    return null;
  }

  /// Get all plugins of a specific type
  List<T> getPluginsByType<T extends TypedMCPPlugin>() {
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

  /// Execute typed tool
  Future<ToolResponse> executeTool(ToolRequest request) async {
    final plugin = getPlugin<TypedToolPlugin>(request.toolName);

    if (plugin == null) {
      throw MCPPluginException(request.toolName, 'Typed tool plugin not found');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Validate request
      final validationErrors = await plugin.validateRequest(request);
      if (validationErrors.isNotEmpty) {
        stopwatch.stop();

        final response = ToolResponse(
          toolName: request.toolName,
          result: FailureResult(
              'Validation failed: ${validationErrors.map((e) => e.toString()).join(', ')}'),
          executionTime: stopwatch.elapsed,
        );

        // Record metrics
        _recordPluginMetric(
            request.toolName,
            TimerMetric(
              name: 'tool.execution',
              duration: stopwatch.elapsed,
              operation: 'execute',
              success: false,
              errorMessage: 'Validation failed',
            ));

        return response;
      }

      // Execute tool
      final response = await plugin.execute(request);
      stopwatch.stop();

      // Record metrics
      _recordPluginMetric(
          request.toolName,
          TimerMetric(
            name: 'tool.execution',
            duration: stopwatch.elapsed,
            operation: 'execute',
            success: response.result.isSuccess,
            errorMessage: response.result.error,
          ));

      return response;
    } catch (e, stackTrace) {
      stopwatch.stop();
      _logger.severe(
          'Error executing typed tool ${request.toolName}', e, stackTrace);
      _publishErrorEvent(
          request.toolName, 'Tool execution failed', e.toString());

      // Record error metrics
      _recordPluginMetric(
          request.toolName,
          TimerMetric(
            name: 'tool.execution',
            duration: stopwatch.elapsed,
            operation: 'execute',
            success: false,
            errorMessage: e.toString(),
          ));

      return ToolResponse(
        toolName: request.toolName,
        result: FailureResult('Tool execution failed: ${e.toString()}',
            originalError: e),
        executionTime: stopwatch.elapsed,
      );
    }
  }

  /// Get plugin health status
  Future<PluginHealthStatus> getPluginHealth(String pluginName) async {
    final plugin = getPlugin<TypedMCPPlugin>(pluginName);

    if (plugin == null) {
      return PluginHealthStatus(
        status: PluginStatus.error,
        isHealthy: false,
        errorMessage: 'Plugin not found',
        lastCheck: DateTime.now(),
      );
    }

    try {
      return await plugin.getHealth();
    } catch (e) {
      return PluginHealthStatus(
        status: PluginStatus.error,
        isHealthy: false,
        errorMessage: e.toString(),
        lastCheck: DateTime.now(),
      );
    }
  }

  /// Get all plugin health statuses
  Future<Map<String, PluginHealthStatus>> getAllPluginHealth() async {
    final result = <String, PluginHealthStatus>{};

    for (final pluginName in _loadOrder) {
      result[pluginName] = await getPluginHealth(pluginName);
    }

    return result;
  }

  /// Get plugin metrics
  List<PerformanceMetric> getPluginMetrics(String pluginName) {
    return _pluginMetrics[pluginName] ?? [];
  }

  /// Get all plugin metrics
  Map<String, List<PerformanceMetric>> getAllPluginMetrics() {
    return Map.from(_pluginMetrics);
  }

  /// Shutdown all typed plugins
  Future<PluginResult<String>> shutdownAll() async {
    _logger.info('Shutting down all typed plugins');

    final errors = <String, String>{};

    // Shutdown plugins in reverse registration order to respect dependencies
    final pluginsToShutdown = List<String>.from(_loadOrder.reversed);
    for (final pluginName in pluginsToShutdown) {
      final result = await unregisterPlugin(pluginName);
      if (!result.isSuccess) {
        errors[pluginName] = result.error!;
      }
    }

    if (errors.isNotEmpty) {
      return FailureResult<String>(
          'Errors occurred while shutting down plugins: $errors');
    }

    return SuccessResult<String>('All plugins shutdown successfully');
  }

  /// Validate plugin before registration
  Future<PluginResult<String>> _validatePlugin(
      TypedMCPPlugin plugin, PluginConfig config) async {
    // Basic validation
    if (plugin.name.isEmpty) {
      return FailureResult<String>('Plugin name cannot be empty');
    }

    if (plugin.version.isEmpty) {
      return FailureResult<String>('Plugin version cannot be empty');
    }

    if (config.name != plugin.name) {
      return FailureResult<String>(
          'Plugin name mismatch between plugin and config');
    }

    // Additional type-specific validation can be added here

    return SuccessResult<String>('Plugin validation passed');
  }

  /// Record plugin metric
  void _recordPluginMetric(String pluginName, PerformanceMetric metric) {
    _pluginMetrics.putIfAbsent(pluginName, () => []).add(metric);

    // Also record in global performance monitor
    _performanceMonitor.recordTypedMetric(metric);
  }

  /// Publish lifecycle event
  void _publishLifecycleEvent(
      String pluginName, PluginStatus oldStatus, PluginStatus newStatus) {
    final event = PluginLifecycleEvent(
      pluginName: pluginName,
      oldStatus: oldStatus,
      newStatus: newStatus,
    );

    EventSystem.instance.publishTyped<PluginLifecycleEvent>(event);
  }

  /// Publish error event
  void _publishErrorEvent(String pluginName, String error, String? details) {
    final event = PluginErrorEvent(
      pluginName: pluginName,
      error: error,
      details: details,
    );

    EventSystem.instance.publishTyped<PluginErrorEvent>(event);
  }

  /// Get all plugin names
  List<String> getAllPluginNames() => List.from(_loadOrder);

  /// Get plugin configuration
  PluginConfig? getPluginConfiguration(String pluginName) {
    return _configurations[pluginName];
  }

  /// Check plugin dependencies
  bool hasDependency(String plugin, String dependency) {
    return _dependencies[plugin]?.contains(dependency) ?? false;
  }

  /// Add plugin dependency
  void addDependency(String plugin, String dependency) {
    _dependencies.putIfAbsent(plugin, () => []).add(dependency);
  }
}
