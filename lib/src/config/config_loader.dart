import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mcp_client/mcp_client.dart' hide LogLevel;
import 'package:mcp_llm/mcp_llm.dart' hide LogLevel;
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
    dynamic _convertNode(dynamic node) {
      if (node is YamlMap) {
        final map = <String, dynamic>{};
        for (final entry in node.entries) {
          map[entry.key.toString()] = _convertNode(entry.value);
        }
        return map;
      } else if (node is YamlList) {
        return node.map((item) => _convertNode(item)).toList();
      } else {
        return node;
      }
    }

    return _convertNode(yamlDoc) as Map<String, dynamic>;
  }

  /// Parse JSON configuration into MCPConfig
  static MCPConfig _parseConfig(Map<String, dynamic> json) {
    // Parse basic properties
    final appName = json['appName'] as String;
    final appVersion = json['appVersion'] as String;

    // Parse boolean flags
    final useBackgroundService = json['useBackgroundService'] as bool? ?? true;
    final useNotification = json['useNotification'] as bool? ?? true;
    final useTray = json['useTray'] as bool? ?? true;
    final secure = json['secure'] as bool? ?? true;
    final lifecycleManaged = json['lifecycleManaged'] as bool? ?? true;
    final autoStart = json['autoStart'] as bool? ?? true;

    // Parse logging level
    final LogLevel? loggingLevel = json.containsKey('loggingLevel')
        ? _parseLogLevel(json['loggingLevel'] as String)
        : null;

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
      background: background,
      notification: notification,
      tray: tray,
      schedule: schedule,
      autoStartServer: autoStartServer,
      autoStartClient: autoStartClient,
    );
  }

  /// Parse LogLevel from string
  static LogLevel _parseLogLevel(String level) {
    switch (level.toLowerCase()) {
      case 'trace': return LogLevel.trace;
      case 'debug': return LogLevel.debug;
      case 'info': return LogLevel.info;
      case 'warning': return LogLevel.warning;
      case 'error': return LogLevel.error;
      case 'none': return LogLevel.none;
      default: return LogLevel.info;
    }
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
        runOnce: jobJson['runOnce'] as bool? ?? false,
        task: () {
          // Placeholder task
          _logger.warning('Task not implemented for job from config');
        },
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

      // Parse server capabilities
      ServerCapabilities? capabilities;
      if (serverJson.containsKey('capabilities')) {
        final Map<String, dynamic> capsJson = serverJson['capabilities'] as Map<String, dynamic>;
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

      // Parse LLM integration
      MCPLlmIntegration? integrateLlm;
      if (serverJson.containsKey('integrateLlm')) {
        final Map<String, dynamic> llmJson = serverJson['integrateLlm'] as Map<String, dynamic>;

        // We need either existingLlmId or (providerName + config)
        final String? existingLlmId = llmJson['existingLlmId'] as String?;

        if (existingLlmId != null) {
          integrateLlm = MCPLlmIntegration(
            existingLlmId: existingLlmId,
          );
        } else if (llmJson.containsKey('providerName') && llmJson.containsKey('config')) {
          final Map<String, dynamic> configJson = llmJson['config'] as Map<String, dynamic>;

          // Parse LLM configuration - note that the apiKey should be provided elsewhere for security
          integrateLlm = MCPLlmIntegration(
            providerName: llmJson['providerName'] as String,
            config: LlmConfiguration(
              apiKey: configJson['apiKey'] as String? ?? 'placeholder-key',
              model: configJson['model'] as String,
              baseUrl: configJson['baseUrl'] as String?,
              retryOnFailure: configJson['retryOnFailure'] as bool? ?? true,
              maxRetries: configJson['maxRetries'] as int? ?? 3,
              timeout: Duration(
                milliseconds: configJson.containsKey('timeoutMs')
                    ? configJson['timeoutMs'] as int
                    : 10000,
              ),
            ),
          );
        }
      }

      // Create MCPServerConfig
      configs.add(MCPServerConfig(
        name: serverJson['name'] as String,
        version: serverJson['version'] as String,
        capabilities: capabilities,
        useStdioTransport: serverJson['useStdioTransport'] as bool? ?? true,
        ssePort: serverJson['ssePort'] as int?,
        integrateLlm: integrateLlm,
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

      // Parse LLM integration
      MCPLlmIntegration? integrateLlm;
      if (clientJson.containsKey('integrateLlm')) {
        final Map<String, dynamic> llmJson = clientJson['integrateLlm'] as Map<String, dynamic>;

        // We need either existingLlmId or (providerName + config)
        final String? existingLlmId = llmJson['existingLlmId'] as String?;

        if (existingLlmId != null) {
          integrateLlm = MCPLlmIntegration(
            existingLlmId: existingLlmId,
          );
        } else if (llmJson.containsKey('providerName') && llmJson.containsKey('config')) {
          final Map<String, dynamic> configJson = llmJson['config'] as Map<String, dynamic>;

          // Parse LLM configuration - note that the apiKey should be provided elsewhere for security
          integrateLlm = MCPLlmIntegration(
            providerName: llmJson['providerName'] as String,
            config: LlmConfiguration(
              apiKey: configJson['apiKey'] as String? ?? 'placeholder-key',
              model: configJson['model'] as String,
              baseUrl: configJson['baseUrl'] as String?,
              retryOnFailure: configJson['retryOnFailure'] as bool? ?? true,
              maxRetries: configJson['maxRetries'] as int? ?? 3,
              timeout: Duration(
                milliseconds: configJson.containsKey('timeoutMs')
                    ? configJson['timeoutMs'] as int
                    : 10000,
              ),
            ),
          );
        }
      }

      // Create MCPClientConfig
      configs.add(MCPClientConfig(
        name: clientJson['name'] as String,
        version: clientJson['version'] as String,
        capabilities: capabilities,
        transportCommand: clientJson['transportCommand'] as String?,
        transportArgs: transportArgs,
        serverUrl: clientJson['serverUrl'] as String?,
        integrateLlm: integrateLlm,
      ));
    }

    return configs;
  }

  /// Export configuration to JSON
  static Map<String, dynamic> exportToJson(MCPConfig config) {
    // This method would convert an MCPConfig object to a JSON map
    // Implementation details omitted for brevity

    // Return a placeholder map
    return {
      'appName': config.appName,
      'appVersion': config.appVersion,
      // Other fields would be included here
    };
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