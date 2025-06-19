import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'mcp_config.dart';
import '../utils/logger.dart';

/// Severity levels for configuration errors
enum ErrorSeverity {
  error,
  warning,
  info,
}

/// Configuration error details
class ConfigError {
  final String field;
  final String message;
  final ErrorSeverity severity;
  final String? suggestion;
  final Map<String, dynamic>? context;

  ConfigError({
    required this.field,
    required this.message,
    required this.severity,
    this.suggestion,
    this.context,
  });

  @override
  String toString() {
    var result = '${severity.name.toUpperCase()}: $field - $message';
    if (suggestion != null) {
      result += '\nSuggestion: $suggestion';
    }
    return result;
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => {
        'field': field,
        'message': message,
        'severity': severity.name,
        if (suggestion != null) 'suggestion': suggestion,
        if (context != null) 'context': context,
      };
}

/// Validation result containing errors and warnings
class ValidationResult {
  final List<ConfigError> errors;
  final bool isValid;
  final Map<String, dynamic> metadata;

  ValidationResult({
    required this.errors,
    this.metadata = const {},
  }) : isValid = !errors.any((e) => e.severity == ErrorSeverity.error);

  /// Get only errors (not warnings or info)
  List<ConfigError> get criticalErrors =>
      errors.where((e) => e.severity == ErrorSeverity.error).toList();

  /// Get only warnings
  List<ConfigError> get warnings =>
      errors.where((e) => e.severity == ErrorSeverity.warning).toList();

  /// Get only info messages
  List<ConfigError> get infoMessages =>
      errors.where((e) => e.severity == ErrorSeverity.info).toList();

  /// Check if there are any errors
  bool get hasErrors => criticalErrors.isNotEmpty;

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Get summary of validation
  String get summary {
    final errorCount = criticalErrors.length;
    final warningCount = warnings.length;
    final infoCount = infoMessages.length;

    return 'Validation ${isValid ? 'passed' : 'failed'}: '
        '$errorCount errors, $warningCount warnings, $infoCount info';
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => {
        'isValid': isValid,
        'summary': summary,
        'errors': errors.map((e) => e.toJson()).toList(),
        'metadata': metadata,
      };
}

/// Platform compatibility matrix
class PlatformCompatibility {
  static const Map<String, Set<String>> _featureSupport = {
    'background_service': {'android', 'ios', 'macos', 'windows', 'linux'},
    'notifications': {'android', 'ios', 'macos', 'windows', 'linux', 'web'},
    'system_tray': {'macos', 'windows', 'linux'},
    'secure_storage': {'android', 'ios', 'macos', 'windows', 'linux', 'web'},
    'native_libraries': {'android', 'ios', 'macos', 'windows', 'linux'},
    'file_system': {'android', 'ios', 'macos', 'windows', 'linux'},
    'network_access': {'android', 'ios', 'macos', 'windows', 'linux', 'web'},
  };

  /// Check if a feature is supported on the current platform
  static bool isFeatureSupported(String feature) {
    final supportedPlatforms = _featureSupport[feature];
    if (supportedPlatforms == null) return false;

    final currentPlatform = _getCurrentPlatform();
    return supportedPlatforms.contains(currentPlatform);
  }

  /// Get current platform name
  static String _getCurrentPlatform() {
    if (kIsWeb) return 'web';

    try {
      if (io.Platform.isAndroid) return 'android';
      if (io.Platform.isIOS) return 'ios';
      if (io.Platform.isMacOS) return 'macos';
      if (io.Platform.isWindows) return 'windows';
      if (io.Platform.isLinux) return 'linux';
    } catch (e) {
      // Fallback for unknown platforms
    }

    return 'unknown';
  }

  /// Get all supported features for current platform
  static List<String> getSupportedFeatures() {
    final currentPlatform = _getCurrentPlatform();
    return _featureSupport.entries
        .where((entry) => entry.value.contains(currentPlatform))
        .map((entry) => entry.key)
        .toList();
  }

  /// Get unsupported features for current platform
  static List<String> getUnsupportedFeatures() {
    final currentPlatform = _getCurrentPlatform();
    return _featureSupport.entries
        .where((entry) => !entry.value.contains(currentPlatform))
        .map((entry) => entry.key)
        .toList();
  }
}

/// Configuration validator with platform-specific rules
class ConfigValidator {
  static final Logger _logger = Logger('flutter_mcp.config_validator');

  /// Validate MCP configuration
  static ValidationResult validate(MCPConfig config) {
    final errors = <ConfigError>[];
    final metadata = <String, dynamic>{
      'platform': PlatformCompatibility._getCurrentPlatform(),
      'validatedAt': DateTime.now().toIso8601String(),
    };

    _logger.fine('Starting configuration validation');

    // Basic validation
    _validateBasicConfig(config, errors);

    // Platform-specific validation
    _validatePlatformCompatibility(config, errors);

    final result = ValidationResult(errors: errors, metadata: metadata);
    _logger.info('Configuration validation completed: ${result.summary}');

    return result;
  }

  /// Validate basic configuration requirements
  static void _validateBasicConfig(MCPConfig config, List<ConfigError> errors) {
    // Check required fields
    final hasClients = config.autoStartClient?.isNotEmpty ?? false;
    final hasServers = config.autoStartServer?.isNotEmpty ?? false;
    final hasLlms = config.autoStartLlmClient?.isNotEmpty ?? false;

    if (!hasClients && !hasServers && !hasLlms) {
      errors.add(ConfigError(
        field: 'config',
        message: 'At least one client, server, or LLM must be configured',
        severity: ErrorSeverity.warning,
        suggestion: 'Add at least one client, server, or LLM configuration',
      ));
    }

    // Validate client configurations
    if (config.autoStartClient != null) {
      for (int i = 0; i < config.autoStartClient!.length; i++) {
        final client = config.autoStartClient![i];

        if (client.name.isEmpty) {
          errors.add(ConfigError(
            field: 'autoStartClient[$i].name',
            message: 'Client name cannot be empty',
            severity: ErrorSeverity.error,
          ));
        }

        if (client.transportType == 'sse' && client.serverUrl == null) {
          errors.add(ConfigError(
            field: 'autoStartClient[$i].serverUrl',
            message: 'Server URL is required for SSE transport',
            severity: ErrorSeverity.error,
            suggestion:
                'Provide a valid server URL or change transport type to stdio',
          ));
        }

        if (client.transportType == 'stdio' &&
            client.transportCommand == null) {
          errors.add(ConfigError(
            field: 'autoStartClient[$i].transportCommand',
            message: 'Transport command is required for stdio transport',
            severity: ErrorSeverity.error,
            suggestion:
                'Provide a valid command or change transport type to sse',
          ));
        }
      }
    }

    // Validate server configurations
    if (config.autoStartServer != null) {
      for (int i = 0; i < config.autoStartServer!.length; i++) {
        final server = config.autoStartServer![i];

        if (server.name.isEmpty) {
          errors.add(ConfigError(
            field: 'autoStartServer[$i].name',
            message: 'Server name cannot be empty',
            severity: ErrorSeverity.error,
          ));
        }

        if (server.version.isEmpty) {
          errors.add(ConfigError(
            field: 'autoStartServer[$i].version',
            message: 'Server version cannot be empty',
            severity: ErrorSeverity.error,
          ));
        }
      }
    }
  }

  /// Validate platform compatibility
  static void _validatePlatformCompatibility(
      MCPConfig config, List<ConfigError> errors) {
    // Background service validation
    if (config.useBackgroundService) {
      if (!PlatformCompatibility.isFeatureSupported('background_service')) {
        errors.add(ConfigError(
          field: 'useBackgroundService',
          message: 'Background service not supported on current platform',
          severity: ErrorSeverity.error,
          suggestion: 'Disable background service or use a supported platform',
          context: {
            'platform': PlatformCompatibility._getCurrentPlatform(),
            'supportedPlatforms':
                PlatformCompatibility._featureSupport['background_service'],
          },
        ));
      }
    }

    // System tray validation
    if (config.useTray) {
      if (!PlatformCompatibility.isFeatureSupported('system_tray')) {
        errors.add(ConfigError(
          field: 'useTray',
          message: 'System tray not supported on current platform',
          severity: kIsWeb ? ErrorSeverity.error : ErrorSeverity.warning,
          suggestion: 'Disable system tray or use a desktop platform',
          context: {
            'platform': PlatformCompatibility._getCurrentPlatform(),
            'supportedPlatforms':
                PlatformCompatibility._featureSupport['system_tray'],
          },
        ));
      }
    }

    // Web-specific validations
    if (kIsWeb) {
      if (config.useBackgroundService) {
        errors.add(ConfigError(
          field: 'useBackgroundService',
          message:
              'Web platform has limited background processing capabilities',
          severity: ErrorSeverity.warning,
          suggestion:
              'Consider using Web Workers or Service Workers for background tasks',
        ));
      }

      // Check for native library usage
      if (config.autoStartClient != null) {
        for (int i = 0; i < config.autoStartClient!.length; i++) {
          final client = config.autoStartClient![i];
          if (client.transportType == 'stdio') {
            errors.add(ConfigError(
              field: 'autoStartClient[$i].transportType',
              message: 'Stdio transport not available on web platform',
              severity: ErrorSeverity.error,
              suggestion: 'Use SSE or HTTP transport for web deployment',
            ));
          }
        }
      }
    }
  }

  /// Estimate memory usage based on configuration
  static int estimateMemoryUsage(MCPConfig config) {
    var usage = 50; // Base usage

    // Estimate per client/server
    usage += (config.autoStartClient?.length ?? 0) * 10; // 10MB per client
    usage += (config.autoStartServer?.length ?? 0) * 15; // 15MB per server
    usage += (config.autoStartLlmClient?.length ?? 0) * 20; // 20MB per LLM

    return usage;
  }

  /// Validate and suggest configuration improvements
  static List<ConfigError> suggestImprovements(MCPConfig config) {
    final suggestions = <ConfigError>[];

    // Performance suggestions
    if (config.enablePerformanceMonitoring != true) {
      suggestions.add(ConfigError(
        field: 'enablePerformanceMonitoring',
        message: 'Performance monitoring is disabled',
        severity: ErrorSeverity.info,
        suggestion: 'Enable performance monitoring to track system health',
      ));
    }

    // Monitoring suggestions
    if (config.enableMetricsExport != true) {
      suggestions.add(ConfigError(
        field: 'enableMetricsExport',
        message: 'Metrics export is disabled',
        severity: ErrorSeverity.info,
        suggestion: 'Enable metrics export for better monitoring',
      ));
    }

    // Security suggestions
    if (config.secure != true) {
      suggestions.add(ConfigError(
        field: 'secure',
        message: 'Secure mode is disabled',
        severity: ErrorSeverity.warning,
        suggestion: 'Enable secure mode for better security',
      ));
    }

    // Memory usage warning
    final estimatedMemory = estimateMemoryUsage(config);
    if (estimatedMemory > 200) {
      suggestions.add(ConfigError(
        field: 'memory_usage',
        message: 'High estimated memory usage: ${estimatedMemory}MB',
        severity: ErrorSeverity.warning,
        suggestion: 'Consider reducing the number of clients/servers',
        context: {'estimatedMemoryMB': estimatedMemory},
      ));
    }

    return suggestions;
  }
}

/// Configuration migration helper
class ConfigMigration {
  static final Logger _logger = Logger('flutter_mcp.config_migration');

  /// Check if configuration needs migration
  static bool needsMigration(Map<String, dynamic> configJson) {
    // Check for old format indicators
    final hasOldFormat = configJson.containsKey('oldVersion') ||
        configJson.containsKey('legacy') ||
        !configJson.containsKey('appVersion');

    if (hasOldFormat) {
      _logger.info('Configuration migration needed');
      return true;
    }

    return false;
  }

  /// Migrate configuration from old format to new format
  static Map<String, dynamic> migrate(Map<String, dynamic> oldConfig) {
    _logger.info('Starting configuration migration');

    final migratedConfig = Map<String, dynamic>.from(oldConfig);

    // Add default values for new fields
    migratedConfig['appVersion'] ??= '1.0.0';
    migratedConfig['lifecycleManaged'] ??= true;
    migratedConfig['enablePerformanceMonitoring'] ??= false;
    migratedConfig['enableMetricsExport'] ??= false;

    // Migrate old field names
    if (oldConfig.containsKey('background')) {
      migratedConfig['useBackgroundService'] = oldConfig['background'];
    }

    if (oldConfig.containsKey('notifications')) {
      migratedConfig['useNotification'] = oldConfig['notifications'];
    }

    if (oldConfig.containsKey('tray')) {
      migratedConfig['useTray'] = oldConfig['tray'];
    }

    _logger.info('Configuration migration completed');

    return migratedConfig;
  }
}
