import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mcp_client/mcp_client.dart' hide ServerCapabilities;
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:yaml/yaml.dart';

import 'mcp_config.dart';
import 'background_config.dart';
import 'notification_config.dart';
import 'tray_config.dart';
import 'job.dart';
import '../platform/tray/tray_manager.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Configuration file loader for MCP
class ConfigLoader {
  static final MCPLogger _logger = MCPLogger('mcp.config_loader');

  /// Load MCP configuration from a JSON file
  static Future<MCPConfig> loadFromJsonFile(String filePath) async {
    _logger.debug('Loading configuration from JSON file: $filePath');

    try {
      final String content = await _readFile(filePath);
      final json = jsonDecode(content);
      return _parseConfig(json);
    } catch (e, stackTrace) {
      _logger.error('Failed to load configuration from JSON file', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to load configuration from JSON file: $filePath',
        e,
        stackTrace,
      );
    }
  }

  /// Load MCP configuration from a YAML file
  static Future<MCPConfig> loadFromYamlFile(String filePath) async {
    _logger.debug('Loading configuration from YAML file: $filePath');

    try {
      final String content = await _readFile(filePath);
      final yamlDoc = loadYaml(content);

      // Convert YAML to JSON map
      final json = _convertYamlToJson(yamlDoc);
      return _parseConfig(json);
    } catch (e, stackTrace) {
      _logger.error('Failed to load configuration from YAML file', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to load configuration from YAML file: $filePath',
        e,
        stackTrace,
      );
    }
  }

  /// Load MCP configuration from a string (JSON or YAML)
  static MCPConfig loadFromString(String content, {ConfigFormat format = ConfigFormat.json}) {
    _logger.debug('Loading configuration from string (${format.name})');

    try {
      final dynamic data = format == ConfigFormat.json
          ? jsonDecode(content)
          : _convertYamlToJson(loadYaml(content));

      return _parseConfig(data);
    } catch (e, stackTrace) {
      _logger.error('Failed to load configuration from string', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to load configuration from string',
        e,
        stackTrace,
      );
    }
  }

  /// Read file from filesystem or assets
  static Future<String> _readFile(String filePath) async {
    if (kIsWeb) {
      // On web, we can only load from assets
      if (!filePath.startsWith('assets/')) {
        filePath = 'assets/$filePath';
      }
      return await rootBundle.loadString(filePath);
    } else {
      // Check if it's an asset path
      if (filePath.startsWith('assets/')) {
        return await rootBundle.loadString(filePath);
      }

      // Regular file
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('Configuration file not found', filePath);
      }

      return await file.readAsString();
    }
  }

  /// Convert YAML document to JSON map
  static Map<String, dynamic> _convertYamlToJson(YamlMap yamlDoc) {
    // Helper function to convert YAML nodes to JSON-compatible objects
    dynamic convertNode(dynamic node) {
      if (node is YamlMap) {
        final map = <String, dynamic>{};
        for (final entry in node.entries) {
          map[entry.key.toString()] = convertNode(entry.value);
        }
        return map;
      } else if (node is YamlList) {
        return node.map((item) => convertNode(item)).toList();
      } else {
        return node;
      }
    }

    return convertNode(yamlDoc) as Map<String, dynamic>;
  }

  /// Parse JSON configuration into MCPConfig
  static MCPConfig _parseConfig(Map<String, dynamic> json) {
    // Parse basic properties
    final appName = json['appName'] as String;
    final appVersion = json['appVersion'] as String;

    // Parse boolean flags
    final useBackgroundService = json['useBackgroundService'] as bool? ?? false;
    final useNotification = json['useNotification'] as bool? ?? false;
    final useTray = json['useTray'] as bool? ?? false;
    final secure = json['secure'] as bool? ?? true;
    final lifecycleManaged = json['lifecycleManaged'] as bool? ?? true;
    final autoStart = json['autoStart'] as bool? ?? true;

    // Parse logging level
    final MCPLogLevel? loggingLevel = json.containsKey('loggingLevel')
        ? _parseLogLevel(json['loggingLevel'] as String)
        : null;

    // Parse performance monitoring settings
    final bool? enablePerformanceMonitoring = json['enablePerformanceMonitoring'] as bool?;
    final bool? enableMetricsExport = json['enableMetricsExport'] as bool?;
    final String? metricsExportPath = json['metricsExportPath'] as String?;

    // Parse plugin settings
    final bool? autoLoadPlugins = json['autoLoadPlugins'] as bool?;
    final Map<String, Map<String, dynamic>>? pluginConfigurations =
    json.containsKey('pluginConfigurations')
        ? _parsePluginConfigurations(json['pluginConfigurations'])
        : null;

    // Parse resource management settings
    final int? highMemoryThresholdMB = json['highMemoryThresholdMB'] as int?;
    final int? lowBatteryWarningThreshold = json['lowBatteryWarningThreshold'] as int?;
    final int? maxConnectionRetries = json['maxConnectionRetries'] as int?;
    final int? llmRequestTimeoutMs = json['llmRequestTimeoutMs'] as int?;

    // Parse BackgroundConfig
    final BackgroundConfig? background = json.containsKey('background')
        ? _parseBackgroundConfig(json['background'] as Map<String, dynamic>)
        : null;

    // Parse NotificationConfig
    final NotificationConfig? notification = json.containsKey('notification')
        ? _parseNotificationConfig(json['notification'] as Map<String, dynamic>)
        : null;

    // Parse TrayConfig
    final TrayConfig? tray = json.containsKey('tray')
        ? _parseTrayConfig(json['tray'] as Map<String, dynamic>)
        : null;

    // Parse scheduled jobs
    final List<MCPJob>? schedule = json.containsKey('schedule')
        ? _parseSchedule(json['schedule'] as List<dynamic>)
        : null;

    // Parse auto-start server configurations
    final List<MCPServerConfig>? autoStartServer = json.containsKey('autoStartServer')
        ? _parseAutoStartServer(json['autoStartServer'] as List<dynamic>)
        : null;

    // Parse auto-start client configurations
    final List<MCPClientConfig>? autoStartClient = json.containsKey('autoStartClient')
        ? _parseAutoStartClient(json['autoStartClient'] as List<dynamic>)
        : null;

    // Parse auto-start LLM client configurations
    final List<MCPLlmClientConfig>? autoStartLlmClient = json.containsKey('autoStartLlmClient')
        ? _parseAutoStartLlmClient(json['autoStartLlmClient'] as List<dynamic>)
        : null;

    // Parse auto-start LLM server configurations
    final List<MCPLlmServerConfig>? autoStartLlmServer = json.containsKey('autoStartLlmServer')
        ? _parseAutoStartLlmServer(json['autoStartLlmServer'] as List<dynamic>)
        : null;

    // Create and return the config
    return MCPConfig(
      appName: appName,
      appVersion: appVersion,
      useBackgroundService: useBackgroundService,
      useNotification: useNotification,
      useTray: useTray,
      secure: secure,
      lifecycleManaged: lifecycleManaged,
      autoStart: autoStart,
      loggingLevel: loggingLevel,
      enablePerformanceMonitoring: enablePerformanceMonitoring,
      enableMetricsExport: enableMetricsExport,
      metricsExportPath: metricsExportPath,
      autoLoadPlugins: autoLoadPlugins,
      pluginConfigurations: pluginConfigurations,
      highMemoryThresholdMB: highMemoryThresholdMB,
      lowBatteryWarningThreshold: lowBatteryWarningThreshold,
      maxConnectionRetries: maxConnectionRetries,
      llmRequestTimeoutMs: llmRequestTimeoutMs,
      background: background,
      notification: notification,
      tray: tray,
      schedule: schedule,
      autoStartServer: autoStartServer,
      autoStartClient: autoStartClient,
      autoStartLlmClient: autoStartLlmClient,
      autoStartLlmServer: autoStartLlmServer,
    );
  }

  /// Parse LogLevel from string
  static MCPLogLevel _parseLogLevel(String level) {
    switch (level.toLowerCase()) {
      case 'trace': return MCPLogLevel.trace;
      case 'debug': return MCPLogLevel.debug;
      case 'info': return MCPLogLevel.info;
      case 'warning': return MCPLogLevel.warning;
      case 'error': return MCPLogLevel.error;
      case 'none': return MCPLogLevel.none;
      default: return MCPLogLevel.info;
    }
  }

  /// Parse plugin configurations
  static Map<String, Map<String, dynamic>> _parsePluginConfigurations(dynamic json) {
    final Map<String, Map<String, dynamic>> result = {};

    if (json is Map) {
      json.forEach((key, value) {
        if (value is Map) {
          result[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
    }

    return result;
  }

  /// Parse BackgroundConfig from JSON
  static BackgroundConfig _parseBackgroundConfig(Map<String, dynamic> json) {
    return BackgroundConfig(
      notificationChannelId: json['notificationChannelId'] as String?,
      notificationChannelName: json['notificationChannelName'] as String?,
      notificationDescription: json['notificationDescription'] as String?,
      notificationIcon: json['notificationIcon'] as String?,
      autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
      intervalMs: json['intervalMs'] as int? ?? 5000,
      keepAlive: json['keepAlive'] as bool? ?? true,
    );
  }

  /// Parse NotificationConfig from JSON
  static NotificationConfig _parseNotificationConfig(Map<String, dynamic> json) {
    return NotificationConfig(
      channelId: json['channelId'] as String?,
      channelName: json['channelName'] as String?,
      channelDescription: json['channelDescription'] as String?,
      icon: json['icon'] as String?,
      enableSound: json['enableSound'] as bool? ?? true,
      enableVibration: json['enableVibration'] as bool? ?? true,
      priority: _parseNotificationPriority(json['priority'] as String?),
    );
  }

  /// Parse notification priority from string
  static NotificationPriority _parseNotificationPriority(String? priority) {
    if (priority == null) return NotificationPriority.normal;

    switch (priority.toLowerCase()) {
      case 'min': return NotificationPriority.min;
      case 'low': return NotificationPriority.low;
      case 'normal': return NotificationPriority.normal;
      case 'high': return NotificationPriority.high;
      case 'max': return NotificationPriority.max;
      default: return NotificationPriority.normal;
    }
  }

  /// Parse TrayConfig from JSON
  static TrayConfig _parseTrayConfig(Map<String, dynamic> json) {
    // Parse menu items if present
    List<TrayMenuItem>? menuItems;
    if (json.containsKey('menuItems')) {
      menuItems = (json['menuItems'] as List<dynamic>).map((item) {
        final Map<String, dynamic> itemJson = item as Map<String, dynamic>;

        if (itemJson.containsKey('separator') && itemJson['separator'] == true) {
          return TrayMenuItem.separator();
        } else {
          return TrayMenuItem(
            label: itemJson['label'] as String?,
            disabled: itemJson['disabled'] as bool? ?? false,
            // Note: 'onTap' will need to be set programmatically later
          );
        }
      }).toList();
    }

    return TrayConfig(
      iconPath: json['iconPath'] as String?,
      tooltip: json['tooltip'] as String?,
      menuItems: menuItems,
    );
  }

  /// Parse scheduled jobs from JSON
  static List<MCPJob> _parseSchedule(List<dynamic> json) {
    final List<MCPJob> jobs = [];

    for (final item in json) {
      final Map<String, dynamic> jobJson = item as Map<String, dynamic>;

      // Parse interval
      Duration interval;
      if (jobJson.containsKey('intervalMs')) {
        interval = Duration(milliseconds: jobJson['intervalMs'] as int);
      } else if (jobJson.containsKey('intervalSeconds')) {
        interval = Duration(seconds: jobJson['intervalSeconds'] as int);
      } else if (jobJson.containsKey('intervalMinutes')) {
        interval = Duration(minutes: jobJson['intervalMinutes'] as int);
      } else if (jobJson.containsKey('intervalHours')) {
        interval = Duration(hours: jobJson['intervalHours'] as int);
      } else {
        interval = Duration(minutes: 5); // Default interval
      }

      // We can't parse the task function from JSON - it will need to be set programmatically later
      // Create a placeholder job with the parsed interval
      final job = MCPJob(
        id: jobJson['id'] as String?,
        interval: interval,
        task: () {
          // Placeholder task
          _logger.warning('Task not implemented for job from config');
        },
        runOnce: jobJson['runOnce'] as bool? ?? false,
        name: jobJson['name'] as String?,
        description: jobJson['description'] as String?,
      );

      jobs.add(job);
    }

    return jobs;
  }

  /// Parse auto-start server configurations from JSON
  static List<MCPServerConfig> _parseAutoStartServer(List<dynamic> json) {
    final List<MCPServerConfig> configs = [];

    for (final item in json) {
      final Map<String, dynamic> serverJson = item as Map<String, dynamic>;

      // Parse server capabilities - convert to mcp_server ServerCapabilities
      ServerCapabilities? capabilities;
      if (serverJson.containsKey('capabilities')) {
        final Map<String, dynamic> capsJson = serverJson['capabilities'] as Map<String, dynamic>;

        // Create using mcp_server ServerCapabilities constructor
        capabilities = ServerCapabilities(
          tools: capsJson['tools'] as bool? ?? false,
          toolsListChanged: capsJson['toolsListChanged'] as bool? ?? false,
          resources: capsJson['resources'] as bool? ?? false,
          resourcesListChanged: capsJson['resourcesListChanged'] as bool? ?? false,
          prompts: capsJson['prompts'] as bool? ?? false,
          promptsListChanged: capsJson['promptsListChanged'] as bool? ?? false,
          sampling: capsJson['sampling'] as bool? ?? false,
        );
      }

      // Parse fallback ports if present
      List<int>? fallbackPorts;
      if (serverJson.containsKey('fallbackPorts')) {
        fallbackPorts = (serverJson['fallbackPorts'] as List<dynamic>)
            .map((port) => port as int)
            .toList();
      }

      // Create MCPServerConfig
      configs.add(MCPServerConfig(
        name: serverJson['name'] as String,
        version: serverJson['version'] as String,
        capabilities: capabilities,
        useStdioTransport: serverJson['useStdioTransport'] as bool? ?? true,
        ssePort: serverJson['ssePort'] as int?,
        fallbackPorts: fallbackPorts,
        authToken: serverJson['authToken'] as String?,
      ));
    }

    return configs;
  }

  /// Parse auto-start client configurations from JSON
  static List<MCPClientConfig> _parseAutoStartClient(List<dynamic> json) {
    final List<MCPClientConfig> configs = [];

    for (final item in json) {
      final Map<String, dynamic> clientJson = item as Map<String, dynamic>;

      // Parse client capabilities
      ClientCapabilities? capabilities;
      if (clientJson.containsKey('capabilities')) {
        final Map<String, dynamic> capsJson = clientJson['capabilities'] as Map<String, dynamic>;
        capabilities = ClientCapabilities(
          roots: capsJson['roots'] as bool? ?? false,
          rootsListChanged: capsJson['rootsListChanged'] as bool? ?? false,
          sampling: capsJson['sampling'] as bool? ?? false,
        );
      }

      // Parse transport arguments
      List<String>? transportArgs;
      if (clientJson.containsKey('transportArgs')) {
        transportArgs = (clientJson['transportArgs'] as List<dynamic>)
            .map((arg) => arg.toString())
            .toList();
      }

      // Create MCPClientConfig
      configs.add(MCPClientConfig(
        name: clientJson['name'] as String,
        version: clientJson['version'] as String,
        capabilities: capabilities,
        transportCommand: clientJson['transportCommand'] as String?,
        transportArgs: transportArgs,
        serverUrl: clientJson['serverUrl'] as String?,
        authToken: clientJson['authToken'] as String?,
      ));
    }

    return configs;
  }

  /// Parse auto-start LLM client configurations from JSON
  static List<MCPLlmClientConfig> _parseAutoStartLlmClient(List<dynamic> json) {
    final List<MCPLlmClientConfig> configs = [];

    for (final item in json) {
      final Map<String, dynamic> llmClientJson = item as Map<String, dynamic>;

      // Parse config
      final Map<String, dynamic> configJson = llmClientJson['config'] as Map<String, dynamic>;
      final llmConfig = LlmConfiguration(
        apiKey: configJson['apiKey'] ?? 'placeholder-key', // apiKey should be provided securely elsewhere
        model: configJson['model'] as String,
        baseUrl: configJson['baseUrl'] as String?,
        retryOnFailure: configJson['retryOnFailure'] as bool? ?? true,
        maxRetries: configJson['maxRetries'] as int? ?? 3,
        timeout: Duration(
          milliseconds: configJson.containsKey('timeoutMs')
              ? configJson['timeoutMs'] as int
              : 10000,
        ),
      );

      // Parse MCP client IDs
      final List<String> mcpClientIds = llmClientJson.containsKey('mcpClientIds')
          ? (llmClientJson['mcpClientIds'] as List<dynamic>).map((id) => id.toString()).toList()
          : [];

      // Create LLM client config
      configs.add(MCPLlmClientConfig(
        providerName: llmClientJson['providerName'] as String,
        config: llmConfig,
        isDefault: llmClientJson['isDefault'] as bool? ?? false,
        mcpClientIds: mcpClientIds,
      ));
    }

    return configs;
  }

  /// Parse auto-start LLM server configurations from JSON
  static List<MCPLlmServerConfig> _parseAutoStartLlmServer(List<dynamic> json) {
    final List<MCPLlmServerConfig> configs = [];

    for (final item in json) {
      final Map<String, dynamic> llmServerJson = item as Map<String, dynamic>;

      // Parse config
      final Map<String, dynamic> configJson = llmServerJson['config'] as Map<String, dynamic>;
      final llmConfig = LlmConfiguration(
        apiKey: configJson['apiKey'] ?? 'placeholder-key', // apiKey should be provided securely elsewhere
        model: configJson['model'] as String,
        baseUrl: configJson['baseUrl'] as String?,
        retryOnFailure: configJson['retryOnFailure'] as bool? ?? true,
        maxRetries: configJson['maxRetries'] as int? ?? 3,
        timeout: Duration(
          milliseconds: configJson.containsKey('timeoutMs')
              ? configJson['timeoutMs'] as int
              : 10000,
        ),
      );

      // Parse MCP server IDs
      final List<String> mcpServerIds = llmServerJson.containsKey('mcpServerIds')
          ? (llmServerJson['mcpServerIds'] as List<dynamic>).map((id) => id.toString()).toList()
          : [];

      // Create LLM server config
      configs.add(MCPLlmServerConfig(
        providerName: llmServerJson['providerName'] as String,
        config: llmConfig,
        isDefault: llmServerJson['isDefault'] as bool? ?? false,
        mcpServerIds: mcpServerIds,
      ));
    }

    return configs;
  }

  /// Export configuration to JSON
  static Map<String, dynamic> exportToJson(MCPConfig config) {
    return config.toJson();
  }

  /// Save configuration to a JSON file
  static Future<void> saveToJsonFile(MCPConfig config, String filePath) async {
    _logger.debug('Saving configuration to JSON file: $filePath');

    try {
      final json = exportToJson(config);
      final jsonString = jsonEncode(json);

      final file = File(filePath);
      await file.writeAsString(jsonString, flush: true);
    } catch (e, stackTrace) {
      _logger.error('Failed to save configuration to JSON file', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to save configuration to JSON file: $filePath',
        e,
        stackTrace,
      );
    }
  }
}

/// Configuration file format enum
enum ConfigFormat {
  json,
  yaml,
}