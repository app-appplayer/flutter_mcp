import 'package:mcp_client/mcp_client.dart' as client hide LogLevel;
import 'package:mcp_server/mcp_server.dart' as server hide LogLevel;
import 'package:mcp_llm/mcp_llm.dart'  hide LogLevel;

import 'background_config.dart';
import 'notification_config.dart';
import 'tray_config.dart';
import 'job.dart';
import '../utils/logger.dart';

/// MCP LLM Integration Configuration
class MCPLlmIntegration {
  /// Existing LLM ID (when using an existing LLM)
  final String? existingLlmId;

  /// LLM provider name (when creating a new LLM)
  final String? providerName;

  /// LLM configuration (when creating a new LLM)
  final LlmConfiguration? config;

  MCPLlmIntegration({
    this.existingLlmId,
    this.providerName,
    this.config,
  }) : assert(existingLlmId != null || (providerName != null && config != null),
  'Either existingLlmId or (providerName and config) must be provided');

  /// Validate configuration
  void validate() {
    if (existingLlmId == null && (providerName == null || config == null)) {
      throw ArgumentError('Either existingLlmId or both providerName and config must be provided');
    }

    if (config != null) {
      // Validate API key
      if (config!.apiKey == null || config!.apiKey!.isEmpty || config!.apiKey == 'placeholder-key') {
        throw ArgumentError('API key is missing or invalid in LLM configuration');
      }

      // Validate model
      if (config!.model == null || config!.model!.isEmpty) {
        throw ArgumentError('Model name is required in LLM configuration');
      }
    }
  }

  /// Create a copy with modified values
  MCPLlmIntegration copyWith({
    String? existingLlmId,
    String? providerName,
    LlmConfiguration? config,
  }) {
    return MCPLlmIntegration(
      existingLlmId: existingLlmId ?? this.existingLlmId,
      providerName: providerName ?? this.providerName,
      config: config ?? this.config,
    );
  }
}

/// MCP Server Auto Start Configuration
class MCPServerConfig {
  /// Server name
  final String name;

  /// Server version
  final String version;

  /// Server capabilities
  final server.ServerCapabilities? capabilities;

  /// Whether to use stdio transport
  final bool useStdioTransport;

  /// SSE transport port
  final int? ssePort;

  /// SSE fallback ports
  final List<int>? fallbackPorts;

  /// SSE authentication token
  final String? authToken;

  /// LLM integration settings
  final MCPLlmIntegration? integrateLlm;

  MCPServerConfig({
    required this.name,
    required this.version,
    this.capabilities,
    this.useStdioTransport = true,
    this.ssePort,
    this.fallbackPorts,
    this.authToken,
    this.integrateLlm,
  }) {
    validate();
  }

  /// Validate configuration
  void validate() {
    if (name.isEmpty) {
      throw ArgumentError('Server name cannot be empty');
    }

    if (version.isEmpty) {
      throw ArgumentError('Server version cannot be empty');
    }

    if (!useStdioTransport && ssePort == null) {
      throw ArgumentError('SSE port must be provided when using SSE transport');
    }

    if (integrateLlm != null) {
      integrateLlm!.validate();
    }
  }

  /// Create a copy with modified values
  MCPServerConfig copyWith({
    String? name,
    String? version,
    server.ServerCapabilities? capabilities,
    bool? useStdioTransport,
    int? ssePort,
    List<int>? fallbackPorts,
    String? authToken,
    MCPLlmIntegration? integrateLlm,
  }) {
    return MCPServerConfig(
      name: name ?? this.name,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      useStdioTransport: useStdioTransport ?? this.useStdioTransport,
      ssePort: ssePort ?? this.ssePort,
      fallbackPorts: fallbackPorts ?? this.fallbackPorts,
      authToken: authToken ?? this.authToken,
      integrateLlm: integrateLlm ?? this.integrateLlm,
    );
  }
}

/// MCP Client Auto Start Configuration
class MCPClientConfig {
  /// Client name
  final String name;

  /// Client version
  final String version;

  /// Client capabilities
  final client.ClientCapabilities? capabilities;

  /// stdio transport command
  final String? transportCommand;

  /// stdio transport arguments
  final List<String>? transportArgs;

  /// SSE transport URL
  final String? serverUrl;

  /// LLM integration settings
  final MCPLlmIntegration? integrateLlm;

  MCPClientConfig({
    required this.name,
    required this.version,
    this.capabilities,
    this.transportCommand,
    this.transportArgs,
    this.serverUrl,
    this.integrateLlm,
  }) {
    validate();
  }

  /// Validate configuration
  void validate() {
    if (name.isEmpty) {
      throw ArgumentError('Client name cannot be empty');
    }

    if (version.isEmpty) {
      throw ArgumentError('Client version cannot be empty');
    }

    if (transportCommand == null && serverUrl == null) {
      throw ArgumentError('Either transportCommand or serverUrl must be provided');
    }

    if (integrateLlm != null) {
      integrateLlm!.validate();
    }
  }

  /// Create a copy with modified values
  MCPClientConfig copyWith({
    String? name,
    String? version,
    client.ClientCapabilities? capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    String? serverUrl,
    MCPLlmIntegration? integrateLlm,
  }) {
    return MCPClientConfig(
      name: name ?? this.name,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      transportCommand: transportCommand ?? this.transportCommand,
      transportArgs: transportArgs ?? this.transportArgs,
      serverUrl: serverUrl ?? this.serverUrl,
      integrateLlm: integrateLlm ?? this.integrateLlm,
    );
  }
}

/// MCP Main Configuration Class
class MCPConfig {
  /// App name
  final String appName;

  /// App version
  final String appVersion;

  /// Whether to use background service
  final bool useBackgroundService;

  /// Whether to use notifications
  final bool useNotification;

  /// Whether to use tray
  final bool useTray;

  /// Whether to use secure storage
  final bool secure;

  /// Whether to manage lifecycle
  final bool lifecycleManaged;

  /// Whether to auto start
  final bool autoStart;

  /// Logging level
  final LogLevel? loggingLevel;

  /// Whether to enable performance monitoring
  final bool? enablePerformanceMonitoring;

  /// Whether to enable metrics export
  final bool? enableMetricsExport;

  /// Metrics export path
  final String? metricsExportPath;

  /// Whether to auto load plugins
  final bool? autoLoadPlugins;

  /// Plugin configurations
  final Map<String, Map<String, dynamic>>? pluginConfigurations;

  /// High memory usage threshold (MB)
  final int? highMemoryThresholdMB;

  /// Low battery warning threshold (%)
  final int? lowBatteryWarningThreshold;

  /// Connection retry limit
  final int? maxConnectionRetries;

  /// LLM request timeout (milliseconds)
  final int? llmRequestTimeoutMs;

  /// Background configuration
  final BackgroundConfig? background;

  /// Notification configuration
  final NotificationConfig? notification;

  /// Tray configuration
  final TrayConfig? tray;

  /// Scheduled jobs
  final List<MCPJob>? schedule;

  /// Auto start server configuration
  final List<MCPServerConfig>? autoStartServer;

  /// Auto start client configuration
  final List<MCPClientConfig>? autoStartClient;

  MCPConfig({
    required this.appName,
    required this.appVersion,
    this.useBackgroundService = true,
    this.useNotification = true,
    this.useTray = true,
    this.secure = true,
    this.lifecycleManaged = true,
    this.autoStart = true,
    this.loggingLevel,
    this.enablePerformanceMonitoring = false,
    this.enableMetricsExport = false,
    this.metricsExportPath,
    this.autoLoadPlugins = true,
    this.pluginConfigurations,
    this.highMemoryThresholdMB = 1024,  // 1GB
    this.lowBatteryWarningThreshold = 20,  // 20%
    this.maxConnectionRetries = 3,
    this.llmRequestTimeoutMs = 60000,  // 60 seconds
    this.background,
    this.notification,
    this.tray,
    this.schedule,
    this.autoStartServer,
    this.autoStartClient,
  }) {
    validate();
  }

  /// Validate the configuration
  void validate() {
    if (appName.isEmpty) {
      throw ArgumentError('App name cannot be empty');
    }

    if (appVersion.isEmpty) {
      throw ArgumentError('App version cannot be empty');
    }

    if (enableMetricsExport == true && metricsExportPath == null) {
      throw ArgumentError('Metrics export path must be provided when metrics export is enabled');
    }

    if (autoStartServer != null) {
      for (final config in autoStartServer!) {
        config.validate();
      }
    }

    if (autoStartClient != null) {
      for (final config in autoStartClient!) {
        config.validate();
      }
    }

    if (highMemoryThresholdMB != null && highMemoryThresholdMB! <= 0) {
      throw ArgumentError('High memory threshold must be positive');
    }

    if (lowBatteryWarningThreshold != null &&
        (lowBatteryWarningThreshold! < 0 || lowBatteryWarningThreshold! > 100)) {
      throw ArgumentError('Low battery warning threshold must be between 0 and 100');
    }

    if (maxConnectionRetries != null && maxConnectionRetries! < 0) {
      throw ArgumentError('Max connection retries must be non-negative');
    }

    if (llmRequestTimeoutMs != null && llmRequestTimeoutMs! <= 0) {
      throw ArgumentError('LLM request timeout must be positive');
    }
  }

  /// Create a copy of this configuration with modified values
  MCPConfig copyWith({
    String? appName,
    String? appVersion,
    bool? useBackgroundService,
    bool? useNotification,
    bool? useTray,
    bool? secure,
    bool? lifecycleManaged,
    bool? autoStart,
    LogLevel? loggingLevel,
    bool? enablePerformanceMonitoring,
    bool? enableMetricsExport,
    String? metricsExportPath,
    bool? autoLoadPlugins,
    Map<String, Map<String, dynamic>>? pluginConfigurations,
    int? highMemoryThresholdMB,
    int? lowBatteryWarningThreshold,
    int? maxConnectionRetries,
    int? llmRequestTimeoutMs,
    BackgroundConfig? background,
    NotificationConfig? notification,
    TrayConfig? tray,
    List<MCPJob>? schedule,
    List<MCPServerConfig>? autoStartServer,
    List<MCPClientConfig>? autoStartClient,
  }) {
    return MCPConfig(
      appName: appName ?? this.appName,
      appVersion: appVersion ?? this.appVersion,
      useBackgroundService: useBackgroundService ?? this.useBackgroundService,
      useNotification: useNotification ?? this.useNotification,
      useTray: useTray ?? this.useTray,
      secure: secure ?? this.secure,
      lifecycleManaged: lifecycleManaged ?? this.lifecycleManaged,
      autoStart: autoStart ?? this.autoStart,
      loggingLevel: loggingLevel ?? this.loggingLevel,
      enablePerformanceMonitoring: enablePerformanceMonitoring ?? this.enablePerformanceMonitoring,
      enableMetricsExport: enableMetricsExport ?? this.enableMetricsExport,
      metricsExportPath: metricsExportPath ?? this.metricsExportPath,
      autoLoadPlugins: autoLoadPlugins ?? this.autoLoadPlugins,
      pluginConfigurations: pluginConfigurations ?? this.pluginConfigurations,
      highMemoryThresholdMB: highMemoryThresholdMB ?? this.highMemoryThresholdMB,
      lowBatteryWarningThreshold: lowBatteryWarningThreshold ?? this.lowBatteryWarningThreshold,
      maxConnectionRetries: maxConnectionRetries ?? this.maxConnectionRetries,
      llmRequestTimeoutMs: llmRequestTimeoutMs ?? this.llmRequestTimeoutMs,
      background: background ?? this.background,
      notification: notification ?? this.notification,
      tray: tray ?? this.tray,
      schedule: schedule ?? this.schedule,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      autoStartClient: autoStartClient ?? this.autoStartClient,
    );
  }

  /// Create a configuration for development environments
  factory MCPConfig.development({
    required String appName,
    required String appVersion,
  }) {
    return MCPConfig(
      appName: appName,
      appVersion: appVersion,
      loggingLevel: LogLevel.debug,
      enablePerformanceMonitoring: true,
      background: BackgroundConfig.defaultConfig(),
    );
  }

  /// Create a configuration for production environments
  factory MCPConfig.production({
    required String appName,
    required String appVersion,
  }) {
    return MCPConfig(
      appName: appName,
      appVersion: appVersion,
      loggingLevel: LogLevel.info,
      enablePerformanceMonitoring: false,
      background: BackgroundConfig(
        notificationChannelId: 'production_${appName.toLowerCase()}_channel',
        notificationChannelName: '$appName Service',
        notificationDescription: '$appName Background Service',
        autoStartOnBoot: true,
        intervalMs: 30000, // 30 seconds for production
        keepAlive: true,
      ),
    );
  }

  /// Convert configuration to a map for storage/debugging
  Map<String, dynamic> toMap() {
    return {
      'appName': appName,
      'appVersion': appVersion,
      'useBackgroundService': useBackgroundService,
      'useNotification': useNotification,
      'useTray': useTray,
      'secure': secure,
      'lifecycleManaged': lifecycleManaged,
      'autoStart': autoStart,
      'loggingLevel': loggingLevel?.toString().split('.').last,
      'enablePerformanceMonitoring': enablePerformanceMonitoring,
      'enableMetricsExport': enableMetricsExport,
      'metricsExportPath': metricsExportPath,
      'autoLoadPlugins': autoLoadPlugins,
      'highMemoryThresholdMB': highMemoryThresholdMB,
      'lowBatteryWarningThreshold': lowBatteryWarningThreshold,
      'maxConnectionRetries': maxConnectionRetries,
      'llmRequestTimeoutMs': llmRequestTimeoutMs,
      'background': background != null ? {
        'notificationChannelId': background!.notificationChannelId,
        'autoStartOnBoot': background!.autoStartOnBoot,
        'intervalMs': background!.intervalMs,
        'keepAlive': background!.keepAlive,
      } : null,
      'autoStartServerCount': autoStartServer?.length,
      'autoStartClientCount': autoStartClient?.length,
    };
  }
}
