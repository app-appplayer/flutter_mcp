import 'package:flutter_mcp/src/config/plugin_config.dart';
import 'package:mcp_client/mcp_client.dart' hide ServerCapabilities;
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

import 'background_config.dart';
import 'notification_config.dart';
import 'tray_config.dart';
import 'job.dart';

/// Configuration for MCP clients
class MCPClientConfig {
  /// Name of the client
  final String name;

  /// Version of the client
  final String version;

  /// Client capabilities
  final ClientCapabilities? capabilities;

  /// Transport type to use (stdio, sse, streamablehttp)
  final String transportType;

  /// Transport command for stdio transport
  final String? transportCommand;

  /// Transport command arguments
  final List<String>? transportArgs;

  /// Server URL for SSE/streamablehttp transport
  final String? serverUrl;

  /// Authentication token for the transport
  final String? authToken;

  /// Endpoint path for SSE/StreamableHttp (e.g., '/sse', '/mcp')
  final String? endpoint;

  /// Request timeout
  final Duration? timeout;

  /// SSE read timeout (longer for streaming)
  final Duration? sseReadTimeout;

  /// Maximum number of concurrent requests
  final int? maxConcurrentRequests;

  /// Whether to use HTTP/2 if available
  final bool? useHttp2;

  /// Whether to terminate session on close
  final bool? terminateOnClose;

  /// Additional headers to send with requests
  final Map<String, String>? headers;

  /// Creates a new MCP client configuration
  MCPClientConfig({
    required this.name,
    required this.version,
    this.capabilities,
    String? transportType,
    this.transportCommand,
    this.transportArgs,
    this.serverUrl,
    this.authToken,
    this.endpoint,
    this.timeout,
    this.sseReadTimeout,
    this.maxConcurrentRequests,
    this.useHttp2,
    this.terminateOnClose,
    this.headers,
  }) : transportType = transportType ?? 
            (throw ArgumentError('transportType must be specified. Valid values: stdio, sse, streamablehttp'));

  /// Converts this configuration to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'name': name,
      'version': version,
      'transportType': transportType,
    };

    if (capabilities != null) {
      json['capabilities'] = capabilities!.toJson();
    }

    if (transportCommand != null) {
      json['transportCommand'] = transportCommand;
    }

    if (transportArgs != null) {
      json['transportArgs'] = transportArgs;
    }

    if (serverUrl != null) {
      json['serverUrl'] = serverUrl;
    }

    if (authToken != null) {
      json['authToken'] = authToken;
    }

    if (endpoint != null) {
      json['endpoint'] = endpoint;
    }

    if (timeout != null) {
      json['timeout'] = timeout!.inMilliseconds;
    }

    if (sseReadTimeout != null) {
      json['sseReadTimeout'] = sseReadTimeout!.inMilliseconds;
    }

    if (maxConcurrentRequests != null) {
      json['maxConcurrentRequests'] = maxConcurrentRequests;
    }

    if (useHttp2 != null) {
      json['useHttp2'] = useHttp2;
    }

    if (terminateOnClose != null) {
      json['terminateOnClose'] = terminateOnClose;
    }

    if (headers != null) {
      json['headers'] = headers;
    }

    return json;
  }
}

/// Configuration for MCP servers
class MCPServerConfig {
  /// Name of the server
  final String name;

  /// Version of the server
  final String version;

  /// Server capabilities
  final ServerCapabilities? capabilities;

  /// Transport type to use (stdio, sse, streamablehttp)
  final String transportType;

  /// Whether to use stdio transport (deprecated - use transportType)
  @Deprecated('Use transportType instead')
  bool get useStdioTransport => transportType == 'stdio';

  /// SSE port for SSE transport
  final int? ssePort;

  /// Streamable HTTP port for streamablehttp transport
  final int? streamableHttpPort;

  /// Fallback ports for SSE/streamablehttp transport
  final List<int>? fallbackPorts;

  /// Authentication token for the transport
  final String? authToken;

  /// Host to bind the server to (default: 'localhost')
  final String? host;

  /// Endpoint path for SSE/StreamableHttp (default: '/sse' for SSE, '/mcp' for StreamableHttp)
  final String? endpoint;

  /// Messages endpoint path for SSE (default: '/message')
  final String? messagesEndpoint;

  /// CORS configuration (host, methods, headers)
  final Map<String, dynamic>? corsConfig;

  /// Maximum request size in bytes (default: 4MB)
  final int? maxRequestSize;

  /// Request timeout
  final Duration? requestTimeout;

  /// Enable JSON response mode for StreamableHttp (default: false for SSE mode)
  final bool? isJsonResponseEnabled;

  /// JSON response mode for StreamableHttp ('sync' or 'async', default: 'sync')
  final String? jsonResponseMode;

  /// Custom middleware for SSE transport
  final List<dynamic>? middleware;

  /// Creates a new MCP server configuration
  MCPServerConfig({
    required this.name,
    required this.version,
    this.capabilities,
    String? transportType,
    bool? useStdioTransport,
    this.ssePort,
    this.streamableHttpPort,
    this.fallbackPorts,
    this.authToken,
    this.host,
    this.endpoint,
    this.messagesEndpoint,
    this.corsConfig,
    this.maxRequestSize,
    this.requestTimeout,
    this.isJsonResponseEnabled,
    this.jsonResponseMode,
    this.middleware,
  }) : transportType = transportType ??
            (useStdioTransport == true
                ? 'stdio'
                : throw ArgumentError('transportType must be specified. Valid values: stdio, sse, streamablehttp'));

  /// Converts this configuration to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'name': name,
      'version': version,
      'transportType': transportType,
    };

    if (capabilities != null) {
      json['capabilities'] = capabilities!.toJson();
    }

    if (ssePort != null) {
      json['ssePort'] = ssePort;
    }

    if (streamableHttpPort != null) {
      json['streamableHttpPort'] = streamableHttpPort;
    }

    if (fallbackPorts != null) {
      json['fallbackPorts'] = fallbackPorts;
    }

    if (authToken != null) {
      json['authToken'] = authToken;
    }

    if (host != null) {
      json['host'] = host;
    }

    if (endpoint != null) {
      json['endpoint'] = endpoint;
    }

    if (messagesEndpoint != null) {
      json['messagesEndpoint'] = messagesEndpoint;
    }

    if (corsConfig != null) {
      json['corsConfig'] = corsConfig;
    }

    if (maxRequestSize != null) {
      json['maxRequestSize'] = maxRequestSize;
    }

    if (requestTimeout != null) {
      json['requestTimeout'] = requestTimeout!.inMilliseconds;
    }

    if (isJsonResponseEnabled != null) {
      json['isJsonResponseEnabled'] = isJsonResponseEnabled;
    }

    if (jsonResponseMode != null) {
      json['jsonResponseMode'] = jsonResponseMode;
    }

    if (middleware != null) {
      json['middleware'] = middleware;
    }

    return json;
  }
}

/// Configuration for LLM clients with explicit MCP client relationships
class MCPLlmClientConfig {
  /// LLM provider name (e.g., 'openai', 'claude', 'together')
  final String providerName;

  /// Configuration for the LLM provider
  final LlmConfiguration config;

  /// Whether this client should be set as the default LLM client
  final bool isDefault;

  /// List of MCP client references (either by index "client_0" or by name "ClientName")
  final List<String> mcpClientIds;

  /// Creates a new LLM client configuration
  MCPLlmClientConfig({
    required this.providerName,
    required this.config,
    this.isDefault = false,
    this.mcpClientIds = const [],
  });

  /// Converts this configuration to JSON
  Map<String, dynamic> toJson() => {
        'providerName': providerName,
        'config': config.toJson(),
        'isDefault': isDefault,
        'mcpClientIds': mcpClientIds,
      };
}

/// Configuration for LLM servers with explicit MCP server relationships
class MCPLlmServerConfig {
  /// LLM provider name (e.g., 'openai', 'claude', 'together')
  final String providerName;

  /// Configuration for the LLM provider
  final LlmConfiguration config;

  /// Whether this server should be set as the default LLM server
  final bool isDefault;

  /// List of MCP server references (either by index "server_0" or by name "ServerName")
  final List<String> mcpServerIds;

  /// Creates a new LLM server configuration
  MCPLlmServerConfig({
    required this.providerName,
    required this.config,
    this.isDefault = false,
    this.mcpServerIds = const [],
  });

  /// Converts this configuration to JSON
  Map<String, dynamic> toJson() => {
        'providerName': providerName,
        'config': config.toJson(),
        'isDefault': isDefault,
        'mcpServerIds': mcpServerIds,
      };
}

/// Main configuration class for Flutter MCP
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
  final Level? loggingLevel;

  /// Whether to enable performance monitoring
  final bool? enablePerformanceMonitoring;

  /// Whether to enable metrics export
  final bool? enableMetricsExport;

  /// Metrics export path
  final String? metricsExportPath;

  /// Whether to auto load plugins
  final bool? autoLoadPlugins;

  /// Plugin configurations
  final List<PluginConfig>? pluginConfigurations;

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

  /// Auto-start LLM client configurations (new field)
  final List<MCPLlmClientConfig>? autoStartLlmClient;

  /// Auto-start LLM server configurations (new field)
  final List<MCPLlmServerConfig>? autoStartLlmServer;

  /// Whether to automatically register LLM plugins with the flutter_mcp system
  final bool? autoRegisterLlmPlugins;

  /// Whether to register MCP plugins with the LLM system
  final bool? registerMcpPluginsWithLlm;

  /// Whether to register core LLM plugins
  final bool? registerCoreLlmPlugins;

  /// Whether to enable retrieval capabilities
  final bool? enableRetrieval;

  /// Any extra configuration options
  final Map<String, dynamic>? extraOptions;

  /// Creates a new MCP configuration
  MCPConfig({
    required this.appName,
    required this.appVersion,
    this.useBackgroundService = false,
    this.useNotification = false,
    this.useTray = false,
    this.secure = true,
    this.lifecycleManaged = true,
    this.autoStart = true,
    this.loggingLevel,
    this.enablePerformanceMonitoring,
    this.enableMetricsExport,
    this.metricsExportPath,
    this.autoLoadPlugins,
    this.pluginConfigurations,
    this.highMemoryThresholdMB,
    this.lowBatteryWarningThreshold,
    this.maxConnectionRetries,
    this.llmRequestTimeoutMs,
    this.background,
    this.notification,
    this.tray,
    this.schedule,
    this.autoStartServer,
    this.autoStartClient,
    this.autoStartLlmClient,
    this.autoStartLlmServer,
    this.autoRegisterLlmPlugins = false,
    this.registerMcpPluginsWithLlm = false,
    this.registerCoreLlmPlugins = false,
    this.enableRetrieval = false,
    this.extraOptions,
  });

  /// Converts this configuration to JSON map
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'appName': appName,
      'appVersion': appVersion,
      'useBackgroundService': useBackgroundService,
      'useNotification': useNotification,
      'useTray': useTray,
      'secure': secure,
      'lifecycleManaged': lifecycleManaged,
      'autoStart': autoStart,
    };

    if (loggingLevel != null) {
      json['loggingLevel'] = loggingLevel.toString();
    }

    if (enablePerformanceMonitoring != null) {
      json['enablePerformanceMonitoring'] = enablePerformanceMonitoring;
    }

    if (enableMetricsExport != null) {
      json['enableMetricsExport'] = enableMetricsExport;
    }

    if (metricsExportPath != null) {
      json['metricsExportPath'] = metricsExportPath;
    }

    if (autoLoadPlugins != null) {
      json['autoLoadPlugins'] = autoLoadPlugins;
    }

    if (pluginConfigurations != null) {
      json['pluginConfigurations'] = pluginConfigurations;
    }

    if (highMemoryThresholdMB != null) {
      json['highMemoryThresholdMB'] = highMemoryThresholdMB;
    }

    if (lowBatteryWarningThreshold != null) {
      json['lowBatteryWarningThreshold'] = lowBatteryWarningThreshold;
    }

    if (maxConnectionRetries != null) {
      json['maxConnectionRetries'] = maxConnectionRetries;
    }

    if (llmRequestTimeoutMs != null) {
      json['llmRequestTimeoutMs'] = llmRequestTimeoutMs;
    }

    if (background != null) {
      // Background doesn't have toJson, we create it manually
      json['background'] = {
        'notificationChannelId': background!.notificationChannelId,
        'notificationChannelName': background!.notificationChannelName,
        'notificationDescription': background!.notificationDescription,
        'notificationIcon': background!.notificationIcon,
        'autoStartOnBoot': background!.autoStartOnBoot,
        'intervalMs': background!.intervalMs,
        'keepAlive': background!.keepAlive,
      };
    }

    if (notification != null) {
      // Notification doesn't have toJson, we create it manually
      json['notification'] = {
        'channelId': notification!.channelId,
        'channelName': notification!.channelName,
        'channelDescription': notification!.channelDescription,
        'icon': notification!.icon,
        'enableSound': notification!.enableSound,
        'enableVibration': notification!.enableVibration,
        'priority': notification!.priority.toString(),
      };
    }

    if (tray != null) {
      // Tray doesn't have toJson, we create it manually
      final Map<String, dynamic> trayJson = {
        'iconPath': tray!.iconPath,
        'tooltip': tray!.tooltip,
      };

      if (tray!.menuItems != null) {
        // We can't serialize menu item callbacks, so we just save basic info
        trayJson['menuItems'] = tray!.menuItems!.map((item) {
          if (item.isSeparator) {
            return {'separator': true};
          }
          return {
            'label': item.label,
            'disabled': item.disabled,
          };
        }).toList();
      }

      json['tray'] = trayJson;
    }

    if (schedule != null && schedule!.isNotEmpty) {
      // We can't serialize job tasks, so we just store basic properties
      json['schedule'] = schedule!.map((job) => job.toMap()).toList();
    }

    if (autoStartServer != null) {
      // Convert to JSON using existing methods
      json['autoStartServer'] =
          autoStartServer!.map((server) => server.toJson()).toList();
    }

    if (autoStartClient != null) {
      // Convert to JSON using existing methods
      json['autoStartClient'] =
          autoStartClient!.map((client) => client.toJson()).toList();
    }

    if (autoStartLlmClient != null) {
      json['autoStartLlmClient'] =
          autoStartLlmClient!.map((e) => e.toJson()).toList();
    }

    if (autoStartLlmServer != null) {
      json['autoStartLlmServer'] =
          autoStartLlmServer!.map((e) => e.toJson()).toList();
    }

    // Add new plugin-related options
    if (autoRegisterLlmPlugins != null) {
      json['autoRegisterLlmPlugins'] = autoRegisterLlmPlugins;
    }

    if (registerMcpPluginsWithLlm != null) {
      json['registerMcpPluginsWithLlm'] = registerMcpPluginsWithLlm;
    }

    if (registerCoreLlmPlugins != null) {
      json['registerCoreLlmPlugins'] = registerCoreLlmPlugins;
    }

    if (enableRetrieval != null) {
      json['enableRetrieval'] = enableRetrieval;
    }

    // Add any extra options
    if (extraOptions != null) {
      extraOptions!.forEach((key, value) {
        if (!json.containsKey(key)) {
          json[key] = value;
        }
      });
    }

    return json;
  }

  /// Creates a copy of this configuration with the specified fields replaced
  MCPConfig copyWith({
    String? appName,
    String? appVersion,
    bool? useBackgroundService,
    bool? useNotification,
    bool? useTray,
    bool? secure,
    bool? lifecycleManaged,
    bool? autoStart,
    Level? loggingLevel,
    bool? enablePerformanceMonitoring,
    bool? enableMetricsExport,
    String? metricsExportPath,
    bool? autoLoadPlugins,
    List<PluginConfig>? pluginConfigurations,
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
    List<MCPLlmClientConfig>? autoStartLlmClient,
    List<MCPLlmServerConfig>? autoStartLlmServer,
    bool? autoRegisterLlmPlugins,
    bool? registerMcpPluginsWithLlm,
    bool? registerCoreLlmPlugins,
    bool? enableRetrieval,
    Map<String, dynamic>? extraOptions,
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
      enablePerformanceMonitoring:
          enablePerformanceMonitoring ?? this.enablePerformanceMonitoring,
      enableMetricsExport: enableMetricsExport ?? this.enableMetricsExport,
      metricsExportPath: metricsExportPath ?? this.metricsExportPath,
      autoLoadPlugins: autoLoadPlugins ?? this.autoLoadPlugins,
      pluginConfigurations: pluginConfigurations ?? this.pluginConfigurations,
      highMemoryThresholdMB:
          highMemoryThresholdMB ?? this.highMemoryThresholdMB,
      lowBatteryWarningThreshold:
          lowBatteryWarningThreshold ?? this.lowBatteryWarningThreshold,
      maxConnectionRetries: maxConnectionRetries ?? this.maxConnectionRetries,
      llmRequestTimeoutMs: llmRequestTimeoutMs ?? this.llmRequestTimeoutMs,
      background: background ?? this.background,
      notification: notification ?? this.notification,
      tray: tray ?? this.tray,
      schedule: schedule ?? this.schedule,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      autoStartClient: autoStartClient ?? this.autoStartClient,
      autoStartLlmClient: autoStartLlmClient ?? this.autoStartLlmClient,
      autoStartLlmServer: autoStartLlmServer ?? this.autoStartLlmServer,
      autoRegisterLlmPlugins:
          autoRegisterLlmPlugins ?? this.autoRegisterLlmPlugins,
      registerMcpPluginsWithLlm:
          registerMcpPluginsWithLlm ?? this.registerMcpPluginsWithLlm,
      registerCoreLlmPlugins:
          registerCoreLlmPlugins ?? this.registerCoreLlmPlugins,
      enableRetrieval: enableRetrieval ?? this.enableRetrieval,
      extraOptions: extraOptions ?? this.extraOptions,
    );
  }
}
