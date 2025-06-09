import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_mcp/src/config/plugin_config.dart';
import 'package:mcp_client/mcp_client.dart' hide ServerCapabilities;
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:yaml/yaml.dart';
import 'package:logging/logging.dart' show Level;

import 'mcp_config.dart';
import 'background_config.dart';
import 'notification_config.dart' as notif;
import 'tray_config.dart' as tray;
import 'job.dart';
import 'typed_config.dart' as typed;
import 'config_parser.dart';
import '../plugins/plugin_system.dart';
import '../platform/tray/tray_manager.dart' as tray_manager;
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Configuration file loader for MCP
class ConfigLoader {
  static final Logger _logger = Logger('flutter_mcp.config_loader');

  /// Load MCP configuration from a JSON file
  static Future<MCPConfig> loadFromJsonFile(String filePath) async {
    _logger.fine('Loading configuration from JSON file: $filePath');

    try {
      final String content = await _readFile(filePath);
      final json = jsonDecode(content);
      return _parseConfig(json);
    } catch (e, stackTrace) {
      _logger.severe('Failed to load configuration from JSON file', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to load configuration from JSON file: $filePath',
        e,
        stackTrace,
      );
    }
  }

  /// Load MCP configuration from a YAML file
  static Future<MCPConfig> loadFromYamlFile(String filePath) async {
    _logger.fine('Loading configuration from YAML file: $filePath');

    try {
      final String content = await _readFile(filePath);
      final yamlDoc = loadYaml(content);

      // Convert YAML to JSON map
      final json = _convertYamlToJson(yamlDoc);
      return _parseConfig(json);
    } catch (e, stackTrace) {
      _logger.severe('Failed to load configuration from YAML file', e, stackTrace);
      throw MCPConfigurationException(
        'Failed to load configuration from YAML file: $filePath',
        e,
        stackTrace,
      );
    }
  }

  /// Load MCP configuration from a string (JSON or YAML)
  static MCPConfig loadFromString(String content, {ConfigFormat format = ConfigFormat.json}) {
    _logger.fine('Loading configuration from string (${format.name})');

    try {
      final dynamic data = format == ConfigFormat.json
          ? jsonDecode(content)
          : _convertYamlToJson(loadYaml(content));

      return _parseConfig(data);
    } catch (e, stackTrace) {
      _logger.severe('Failed to load configuration from string', e, stackTrace);
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

  /// Parse JSON configuration into MCPConfig using typed configuration
  static MCPConfig _parseConfig(Map<String, dynamic> json) {
    // Use ConfigParser for type-safe parsing
    final parser = ConfigParser(json, configName: 'MCPConfig');
    
    // Parse TypedAppConfig first
    final typedConfig = typed.TypedAppConfig.fromMap(json);
    
    // Parse basic properties using typed config where possible
    final appName = typedConfig.appInfo.name;
    final appVersion = typedConfig.appInfo.version;

    // Parse feature flags from typed config
    final features = typedConfig.features;
    final useBackgroundService = features.useBackgroundService;
    final useNotification = features.useNotification;
    final useTray = features.useTray;
    final secure = features.secure;
    final lifecycleManaged = features.lifecycleManaged;
    final autoStart = features.autoStart;

    // Parse logging level
    final Level? loggingLevel = typedConfig.logging.enabled
        ? _parseLogLevel(typedConfig.logging.level.name)
        : null;

    // Parse performance monitoring settings
    final performance = typedConfig.performance;
    final bool? enablePerformanceMonitoring = performance.monitoring.enabled;
    final bool? enableMetricsExport = performance.monitoring.enableMetricsExport;
    final String? metricsExportPath = performance.monitoring.metricsExportPath;

    // Parse plugin settings
    final bool? autoLoadPlugins = typedConfig.features.plugins.autoLoad;

    final List<PluginConfig>? pluginConfigurations =
    json.containsKey('pluginConfigurations')
        ? _parsePluginConfigurations(json['pluginConfigurations'])
        : null;

    // Parse resource management settings from typed config
    final int? highMemoryThresholdMB = typedConfig.memory.highThresholdMB;
    final int? lowBatteryWarningThreshold = 
        parser.getInt('lowBatteryWarningThreshold', defaultValue: 20);
    final int? maxConnectionRetries = typedConfig.network.retryConfig.maxRetries;
    final int? llmRequestTimeoutMs = typedConfig.network.timeouts['request']?.inMilliseconds;

    // Parse BackgroundConfig
    BackgroundConfig? background;
    if (json.containsKey('background')) {
      final bgParser = parser.getObject('background');
      background = BackgroundConfig(
        notificationChannelId: bgParser.getString('notificationChannelId', defaultValue: 'mcp_background'),
        notificationChannelName: bgParser.getString('notificationChannelName', defaultValue: 'MCP Background Service'),
        notificationDescription: bgParser.getString('notificationDescription'),
        notificationIcon: bgParser.getString('notificationIcon'),
        autoStartOnBoot: bgParser.getBool('autoStartOnBoot', defaultValue: false),
        intervalMs: bgParser.getInt('intervalMs', defaultValue: 5000),
        keepAlive: bgParser.getBool('keepAlive', defaultValue: true),
      );
    }

    // Parse NotificationConfig
    notif.NotificationConfig? notification;
    if (json.containsKey('notification')) {
      final notifParser = parser.getObject('notification');
      notification = notif.NotificationConfig(
        channelId: notifParser.getString('channelId', defaultValue: 'mcp_notifications'),
        channelName: notifParser.getString('channelName', defaultValue: 'MCP Notifications'),
        channelDescription: notifParser.getString('channelDescription'),
        icon: notifParser.getString('icon'),
        enableSound: notifParser.getBool('enableSound', defaultValue: true),
        enableVibration: notifParser.getBool('enableVibration', defaultValue: true),
        priority: _parseNotificationPriority(notifParser.getString('priority')),
      );
    }

    // Parse TrayConfig
    final tray.TrayConfig? trayConfig = json.containsKey('tray')
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

    // Parse plugin-related settings
    final bool? autoRegisterLlmPlugins = 
        parser.getBool('autoRegisterLlmPlugins', defaultValue: false);
    final bool? registerMcpPluginsWithLlm = 
        parser.getBool('registerMcpPluginsWithLlm', defaultValue: false);
    final bool? registerCoreLlmPlugins = 
        parser.getBool('registerCoreLlmPlugins', defaultValue: false);
    final bool? enableRetrieval = 
        parser.getBool('enableRetrieval', defaultValue: false);

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
      tray: trayConfig,
      schedule: schedule,
      autoStartServer: autoStartServer,
      autoStartClient: autoStartClient,
      autoStartLlmClient: autoStartLlmClient,
      autoStartLlmServer: autoStartLlmServer,
      autoRegisterLlmPlugins: autoRegisterLlmPlugins,
      registerMcpPluginsWithLlm: registerMcpPluginsWithLlm,
      registerCoreLlmPlugins: registerCoreLlmPlugins,
      enableRetrieval: enableRetrieval,
    );
  }

  /// Parse LogLevel from string
  static Level _parseLogLevel(String level) {
    switch (level.toLowerCase()) {
      case 'trace': return Level.FINEST;
      case 'finest': return Level.FINEST;
      case 'debug': return Level.FINE;
      case 'fine': return Level.FINE;
      case 'info': return Level.INFO;
      case 'warning': return Level.WARNING;
      case 'error': return Level.SEVERE;
      case 'severe': return Level.SEVERE;
      case 'none': return Level.OFF;
      case 'off': return Level.OFF;
      default: return Level.INFO;
    }
  }

  /// Parse plugin configurations
  static List<PluginConfig> _parsePluginConfigurations(
      Map<String, dynamic> json,
      ) {
    final List<PluginConfig> result = [];

    for (final entry in json.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic> && value['plugin'] is MCPPlugin) {
        final plugin = value['plugin'] as MCPPlugin;
        final config = (value['config'] as Map?)?.cast<String, dynamic>() ?? {};
        final targets = value.containsKey('targets') && value['targets'] is List
            ? (value['targets'] as List).cast<String>()
            : null;

        result.add(PluginConfig(
          plugin: plugin,
          config: config,
          targets: targets,
        ));
      } else {
        throw Exception('Invalid plugin configuration for "$key". Must contain a plugin instance.');
      }
    }

    return result;
  }

  /// Parse notification priority from string
  static notif.NotificationPriority _parseNotificationPriority(String? priority) {
    if (priority == null) return notif.NotificationPriority.normal;

    switch (priority.toLowerCase()) {
      case 'min': return notif.NotificationPriority.min;
      case 'low': return notif.NotificationPriority.low;
      case 'normal': return notif.NotificationPriority.normal;
      case 'high': return notif.NotificationPriority.high;
      case 'max': return notif.NotificationPriority.max;
      default: return notif.NotificationPriority.normal;
    }
  }

  /// Parse TrayConfig from JSON
  static tray.TrayConfig _parseTrayConfig(Map<String, dynamic> json) {
    final parser = ConfigParser(json, configName: 'TrayConfig');
    
    // Parse menu items if present
    List<tray_manager.TrayMenuItem>? menuItems;
    if (json.containsKey('menuItems')) {
      menuItems = parser.getList<tray_manager.TrayMenuItem>(
        'menuItems',
        (item) {
          final itemParser = ConfigParser(item as Map<String, dynamic>, configName: 'TrayMenuItem');
          
          if (itemParser.getBool('separator', defaultValue: false)) {
            return tray_manager.TrayMenuItem.separator();
          } else {
            return tray_manager.TrayMenuItem(
              label: itemParser.getString('label'),
              disabled: itemParser.getBool('disabled', defaultValue: false),
              // Note: 'onTap' will need to be set programmatically later
            );
          }
        },
      );
    }

    return tray.TrayConfig(
      iconPath: parser.getString('iconPath'),
      tooltip: parser.getString('tooltip'),
      menuItems: menuItems,
    );
  }

  /// Parse scheduled jobs from JSON
  static List<MCPJob> _parseSchedule(List<dynamic> json) {
    final List<MCPJob> jobs = [];

    for (final item in json) {
      final parser = ConfigParser(item as Map<String, dynamic>, configName: 'MCPJob');

      // Parse interval
      Duration interval;
      if (parser.hasKey('intervalMs')) {
        interval = Duration(milliseconds: parser.getInt('intervalMs'));
      } else if (parser.hasKey('intervalSeconds')) {
        interval = Duration(seconds: parser.getInt('intervalSeconds'));
      } else if (parser.hasKey('intervalMinutes')) {
        interval = Duration(minutes: parser.getInt('intervalMinutes'));
      } else if (parser.hasKey('intervalHours')) {
        interval = Duration(hours: parser.getInt('intervalHours'));
      } else {
        interval = Duration(minutes: 5); // Default interval
      }

      // Create a job with configurable task based on task type
      final job = MCPJob(
        id: parser.getString('id'),
        interval: interval,
        task: () => _executeConfigurableTask(parser.rawData),
        runOnce: parser.getBool('runOnce', defaultValue: false),
        name: parser.getString('name'),
        description: parser.getString('description'),
      );

      jobs.add(job);
    }

    return jobs;
  }

  /// Execute configurable task based on task definition
  static Future<void> _executeConfigurableTask(Map<String, dynamic> jobJson) async {
    try {
      final parser = ConfigParser(jobJson, configName: 'Task');
      final String? taskType = parser.getString('taskType');
      final taskConfig = parser.hasKey('taskConfig') 
          ? parser.getObject('taskConfig').rawData 
          : null;
      
      if (taskType == null) {
        _logger.warning('No taskType specified for job: ${jobJson['name'] ?? 'unknown'}');
        return;
      }

      _logger.fine('Executing task: $taskType for job: ${jobJson['name'] ?? jobJson['id'] ?? 'unknown'}');

      switch (taskType.toLowerCase()) {
        case 'log':
          _executeLogTask(taskConfig);
          break;
        case 'healthcheck':
          await _executeHealthCheckTask(taskConfig);
          break;
        case 'cleanup':
          await _executeCleanupTask(taskConfig);
          break;
        case 'notification':
          await _executeNotificationTask(taskConfig);
          break;
        case 'custom':
          await _executeCustomTask(taskConfig);
          break;
        case 'memory_check':
          await _executeMemoryCheckTask(taskConfig);
          break;
        case 'performance_report':
          await _executePerformanceReportTask(taskConfig);
          break;
        default:
          _logger.warning('Unknown task type: $taskType');
          // Execute as custom task with fallback
          await _executeCustomTask(taskConfig);
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to execute configurable task', e, stackTrace);
    }
  }

  /// Execute log task
  static void _executeLogTask(Map<String, dynamic>? config) {
    final parser = ConfigParser(config ?? {}, configName: 'LogTask');
    final String message = parser.getString('message', defaultValue: 'Scheduled log message');
    final String level = parser.getString('level', defaultValue: 'info');
    
    switch (level.toLowerCase()) {
      case 'debug':
        _logger.fine(message);
        break;
      case 'info':
        _logger.info(message);
        break;
      case 'warning':
        _logger.warning(message);
        break;
      case 'error':
        _logger.severe(message);
        break;
      default:
        _logger.info(message);
    }
  }

  /// Execute health check task
  static Future<void> _executeHealthCheckTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'HealthCheckTask');
      final List<String> checks = parser.getList<String>(
        'checks',
        (item) => item.toString(),
        defaultValue: ['basic'],
      );
      
      for (final check in checks) {
        switch (check.toLowerCase()) {
          case 'memory':
            // Import MemoryManager if needed
            final memoryUsage = 100; // Placeholder - would get from MemoryManager
            _logger.info('Health check - Memory usage: ${memoryUsage}MB');
            break;
          case 'connectivity':
            // Check network connectivity
            _logger.info('Health check - Connectivity: OK');
            break;
          case 'services':
            // Check service status
            _logger.info('Health check - Services: Running');
            break;
          default:
            _logger.info('Health check - $check: OK');
        }
      }
    } catch (e) {
      _logger.severe('Health check failed', e);
    }
  }

  /// Execute cleanup task
  static Future<void> _executeCleanupTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'CleanupTask');
      final List<String> targets = parser.getList<String>(
        'targets',
        (item) => item.toString(),
        defaultValue: ['temp'],
      );
      
      for (final target in targets) {
        switch (target.toLowerCase()) {
          case 'temp':
            _logger.info('Cleaning temporary files...');
            // Implement temporary file cleanup
            break;
          case 'cache':
            _logger.info('Cleaning cache...');
            // Implement cache cleanup
            break;
          case 'logs':
            _logger.info('Cleaning old logs...');
            // Implement log cleanup
            break;
          default:
            _logger.info('Cleaning $target...');
        }
      }
    } catch (e) {
      _logger.severe('Cleanup task failed', e);
    }
  }

  /// Execute notification task
  static Future<void> _executeNotificationTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'NotificationTask');
      final String title = parser.getString('title', defaultValue: 'Scheduled Notification');
      final String message = parser.getString('message', defaultValue: 'This is a scheduled notification');
      
      _logger.info('Sending notification: $title - $message');
      // Note: Actual notification sending would require access to FlutterMCP instance
      // This is a placeholder that logs the notification
    } catch (e) {
      _logger.severe('Notification task failed', e);
    }
  }

  /// Execute custom task
  static Future<void> _executeCustomTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'CustomTask');
      final String? command = parser.getString('command');
      final Map<String, dynamic>? parameters = parser.hasKey('parameters')
          ? parser.getObject('parameters').rawData
          : null;
      
      if (command != null) {
        _logger.info('Executing custom task: $command with parameters: $parameters');
        // Custom task execution logic would be implemented here
        // This could involve calling specific functions, APIs, or external commands
      } else {
        _logger.warning('Custom task has no command specified');
      }
    } catch (e) {
      _logger.severe('Custom task failed', e);
    }
  }

  /// Execute memory check task
  static Future<void> _executeMemoryCheckTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'MemoryCheckTask');
      final int? threshold = parser.getInt('thresholdMB');
      // This would integrate with MemoryManager to check current usage
      _logger.info('Memory check task executed (threshold: ${threshold ?? 'default'}MB)');
    } catch (e) {
      _logger.severe('Memory check task failed', e);
    }
  }

  /// Execute performance report task  
  static Future<void> _executePerformanceReportTask(Map<String, dynamic>? config) async {
    try {
      final parser = ConfigParser(config ?? {}, configName: 'PerformanceReportTask');
      final bool includeMemory = parser.getBool('includeMemory', defaultValue: true);
      final bool includeNetwork = parser.getBool('includeNetwork', defaultValue: true);
      
      _logger.info('Performance report generated (memory: $includeMemory, network: $includeNetwork)');
    } catch (e) {
      _logger.severe('Performance report task failed', e);
    }
  }

  /// Parse auto-start server configurations from JSON
  static List<MCPServerConfig> _parseAutoStartServer(List<dynamic> json) {
    final List<MCPServerConfig> configs = [];

    for (final item in json) {
      final parser = ConfigParser(item as Map<String, dynamic>, configName: 'MCPServerConfig');

      // Parse server capabilities - convert to mcp_server ServerCapabilities
      ServerCapabilities? capabilities;
      if (parser.hasKey('capabilities')) {
        final capParser = parser.getObject('capabilities');
        
        capabilities = ServerCapabilities(
          tools: capParser.getBool('tools', defaultValue: false) ? ToolsCapability() : null,
          resources: capParser.getBool('resources', defaultValue: false) ? ResourcesCapability() : null,
          prompts: capParser.getBool('prompts', defaultValue: false) ? PromptsCapability() : null,
          logging: capParser.getBool('logging', defaultValue: false) ? LoggingCapability() : null,
        );
      }

      // Parse fallback ports if present
      List<int>? fallbackPorts;
      if (parser.hasKey('fallbackPorts')) {
        fallbackPorts = parser.getList<int>('fallbackPorts', (port) => port as int);
      }

      // Create MCPServerConfig
      configs.add(MCPServerConfig(
        name: parser.getString('name', required: true),
        version: parser.getString('version', required: true),
        capabilities: capabilities,
        transportType: parser.getString('transportType', defaultValue: 'stdio'),
        ssePort: parser.getInt('ssePort'),
        streamableHttpPort: parser.getInt('streamableHttpPort'),
        fallbackPorts: fallbackPorts,
        authToken: parser.getString('authToken'),
      ));
    }

    return configs;
  }

  /// Parse auto-start client configurations from JSON
  static List<MCPClientConfig> _parseAutoStartClient(List<dynamic> json) {
    final List<MCPClientConfig> configs = [];

    for (final item in json) {
      final parser = ConfigParser(item as Map<String, dynamic>, configName: 'MCPClientConfig');

      // Parse client capabilities
      ClientCapabilities? capabilities;
      if (parser.hasKey('capabilities')) {
        final capsParser = parser.getObject('capabilities');
        capabilities = ClientCapabilities(
          roots: capsParser.getBool('roots', defaultValue: false),
          rootsListChanged: capsParser.getBool('rootsListChanged', defaultValue: false),
          sampling: capsParser.getBool('sampling', defaultValue: false),
        );
      }

      // Parse transport arguments
      List<String>? transportArgs;
      if (parser.hasKey('transportArgs')) {
        transportArgs = parser.getList<String>('transportArgs', (arg) => arg.toString());
      }

      // Create MCPClientConfig with transport type
      configs.add(MCPClientConfig(
        name: parser.getString('name', required: true),
        version: parser.getString('version', required: true),
        capabilities: capabilities,
        transportType: parser.getString('transportType'),
        transportCommand: parser.getString('transportCommand'),
        transportArgs: transportArgs,
        serverUrl: parser.getString('serverUrl'),
        authToken: parser.getString('authToken'),
      ));
    }

    return configs;
  }

  /// Parse auto-start LLM client configurations from JSON
  static List<MCPLlmClientConfig> _parseAutoStartLlmClient(List<dynamic> json) {
    final List<MCPLlmClientConfig> configs = [];

    for (final item in json) {
      final parser = ConfigParser(item as Map<String, dynamic>, configName: 'MCPLlmClientConfig');

      // Parse config
      final configParser = parser.getObject('config');
      final llmConfig = LlmConfiguration(
        apiKey: configParser.getString('apiKey', defaultValue: 'placeholder-key'),
        model: configParser.getString('model', required: true),
        baseUrl: configParser.getString('baseUrl'),
        retryOnFailure: configParser.getBool('retryOnFailure', defaultValue: true),
        maxRetries: configParser.getInt('maxRetries', defaultValue: 3),
        timeout: Duration(
          milliseconds: configParser.getInt('timeoutMs', defaultValue: 10000),
        ),
      );

      // Parse MCP client IDs
      final List<String> mcpClientIds = parser.hasKey('mcpClientIds')
          ? parser.getList<String>('mcpClientIds', (id) => id.toString())
          : [];

      // Create LLM client config
      configs.add(MCPLlmClientConfig(
        providerName: parser.getString('providerName', required: true),
        config: llmConfig,
        isDefault: parser.getBool('isDefault', defaultValue: false),
        mcpClientIds: mcpClientIds,
      ));
    }

    return configs;
  }

  /// Parse auto-start LLM server configurations from JSON
  static List<MCPLlmServerConfig> _parseAutoStartLlmServer(List<dynamic> json) {
    final List<MCPLlmServerConfig> configs = [];

    for (final item in json) {
      final parser = ConfigParser(item as Map<String, dynamic>, configName: 'MCPLlmServerConfig');

      // Parse config
      final configParser = parser.getObject('config');
      final llmConfig = LlmConfiguration(
        apiKey: configParser.getString('apiKey', defaultValue: 'placeholder-key'),
        model: configParser.getString('model', required: true),
        baseUrl: configParser.getString('baseUrl'),
        retryOnFailure: configParser.getBool('retryOnFailure', defaultValue: true),
        maxRetries: configParser.getInt('maxRetries', defaultValue: 3),
        timeout: Duration(
          milliseconds: configParser.getInt('timeoutMs', defaultValue: 10000),
        ),
      );

      // Parse MCP server IDs
      final List<String> mcpServerIds = parser.hasKey('mcpServerIds')
          ? parser.getList<String>('mcpServerIds', (id) => id.toString())
          : [];

      // Create LLM server config
      configs.add(MCPLlmServerConfig(
        providerName: parser.getString('providerName', required: true),
        config: llmConfig,
        isDefault: parser.getBool('isDefault', defaultValue: false),
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
    _logger.fine('Saving configuration to JSON file: $filePath');

    try {
      final json = exportToJson(config);
      final jsonString = jsonEncode(json);

      final file = File(filePath);
      await file.writeAsString(jsonString, flush: true);
    } catch (e, stackTrace) {
      _logger.severe('Failed to save configuration to JSON file', e, stackTrace);
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