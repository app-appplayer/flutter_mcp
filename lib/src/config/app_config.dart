/// Application configuration management for Flutter MCP
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'typed_config.dart';

/// Global application configuration singleton
class AppConfig {
  static AppConfig? _instance;
  static const String _loggerName = 'mcp.app_config';

  // Internal configuration storage
  final Map<String, dynamic> _config = <String, dynamic>{};
  bool _isInitialized = false;

  /// Private constructor for singleton pattern
  AppConfig._internal() {
    _loadDefaults();
  }

  /// Get the singleton instance
  static AppConfig get instance {
    return _instance ??= AppConfig._internal();
  }

  /// Initialize configuration with optional overrides
  static Future<void> initialize({
    Map<String, dynamic>? overrides,
    String? configFile,
  }) async {
    final config = instance;

    if (config._isInitialized) {
      if (kDebugMode) {
        print('[$_loggerName] Configuration already initialized');
      }
      return;
    }

    try {
      // Load from config file if provided
      if (configFile != null) {
        await config._loadFromFile(configFile);
      }

      // Load from environment variables (non-web only)
      if (!kIsWeb) {
        config._loadFromEnvironment();
      }

      // Apply overrides last
      if (overrides != null) {
        config._mergeConfig(overrides);
      }

      config._isInitialized = true;

      if (kDebugMode) {
        print('[$_loggerName] Configuration initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[$_loggerName] Failed to initialize configuration: $e');
      }
      // Continue with defaults if initialization fails
      config._isInitialized = true;
    }
  }

  /// Load default configuration values
  void _loadDefaults() {
    _config.clear();
    _config.addAll({
      // Async/Retry Configuration
      'async': {
        'defaultMaxRetries': 3,
        'defaultInitialDelay': 500, // milliseconds
        'defaultJitterRange': 50, // +/- milliseconds
        'defaultBackoffFactor': 2.0,
      },

      // Memory Management
      'memory': {
        'monitoringInterval': 30000, // milliseconds
        'maxReadings': 10,
        'defaultThresholdMB': null, // null means auto-detect
        'initialSimulationMB': 100,
        'gcProbability': 0.2,
        'gcHintArraySize': 10000,
      },

      // Batch Processing
      'batch': {
        'defaultMaxSize': 50,
        'defaultMaxWaitTime': 100, // milliseconds
        'defaultMaxConcurrent': 3,
        'defaultRetryEnabled': true,
        'defaultMaxRetries': 3,
        'exponentialBackoffBase': 100, // milliseconds
      },

      // Background Processing
      'background': {
        'maxConsecutiveErrors': 5,
        'defaultInterval': 60000, // milliseconds
        'flushDelay': 10, // milliseconds
      },

      // Health Monitoring
      'health': {
        'defaultCheckInterval': 30000, // milliseconds
        'criticalCheckInterval': 10000, // milliseconds
      },

      // Performance Monitoring
      'performance': {
        'updateInterval': 1000, // milliseconds
        'maxHistorySize': 300,
        'thresholds': {
          'cpu.usage': 80.0,
          'memory.usage': 75.0,
          'error.rate': 5.0,
          'response.time': 1000.0, // milliseconds
        },
      },

      // Error Handling
      'errorHandling': {
        'maxHistory': 100,
        'enableReporting': true,
      },

      // Error Monitoring
      'errorMonitoring': {
        'interval': 60000, // milliseconds
        'maxHistory': 1440, // 24 hours at 1-minute intervals
      },

      // Logging
      'logging': {
        'defaultLevel': 'info',
        'enableFileLogging': false,
        'maxLogFileSize': 10485760, // 10MB
      },
    });
  }

  /// Load configuration from file
  Future<void> _loadFromFile(String filePath) async {
    if (kIsWeb) {
      if (kDebugMode) {
        print('[$_loggerName] File loading not supported on web platform');
      }
      return;
    }

    try {
      final file = io.File(filePath);
      if (!await file.exists()) {
        if (kDebugMode) {
          print('[$_loggerName] Config file not found: $filePath');
        }
        return;
      }

      final content = await file.readAsString();
      Map<String, dynamic> fileConfig;

      if (filePath.endsWith('.json')) {
        fileConfig = jsonDecode(content) as Map<String, dynamic>;
      } else {
        // For simplicity, only support JSON for now
        if (kDebugMode) {
          print('[$_loggerName] Only JSON config files are supported');
        }
        return;
      }

      _mergeConfig(fileConfig);

      if (kDebugMode) {
        print('[$_loggerName] Loaded configuration from: $filePath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[$_loggerName] Failed to load config file: $e');
      }
    }
  }

  /// Load configuration from environment variables
  void _loadFromEnvironment() {
    if (kIsWeb) return;

    try {
      final env = io.Platform.environment;
      for (final entry in env.entries) {
        if (entry.key.startsWith('MCP_')) {
          final configKey =
              entry.key.substring(4).toLowerCase().replaceAll('_', '.');
          _setNestedValue(configKey, _parseEnvValue(entry.value));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[$_loggerName] Failed to load environment variables: $e');
      }
    }
  }

  /// Parse environment variable value
  dynamic _parseEnvValue(String value) {
    // Try to parse as number
    final intValue = int.tryParse(value);
    if (intValue != null) return intValue;

    final doubleValue = double.tryParse(value);
    if (doubleValue != null) return doubleValue;

    // Parse boolean
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;

    // Try to parse as JSON
    try {
      return jsonDecode(value);
    } catch (e) {
      // Return as string if not JSON
      if (kDebugMode) {
        print(
            '[$_loggerName] Value "$value" is not valid JSON, returning as string: $e');
      }
      return value;
    }
  }

  /// Merge configuration with existing values
  void _mergeConfig(Map<String, dynamic> newConfig) {
    _deepMerge(_config, newConfig);
  }

  /// Deep merge two maps
  void _deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    source.forEach((key, value) {
      if (value is Map<String, dynamic> &&
          target[key] is Map<String, dynamic>) {
        _deepMerge(target[key] as Map<String, dynamic>, value);
      } else {
        target[key] = value;
      }
    });
  }

  /// Set nested configuration value using dot notation
  void _setNestedValue(String key, dynamic value) {
    final parts = key.split('.');
    Map<String, dynamic> current = _config;

    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (!current.containsKey(part) || current[part] is! Map) {
        current[part] = <String, dynamic>{};
      }
      current = current[part] as Map<String, dynamic>;
    }

    current[parts.last] = value;
  }

  /// Get configuration value using dot notation
  T get<T>(String key, {T? defaultValue}) {
    final parts = key.split('.');
    dynamic value = _config;

    for (final part in parts) {
      if (value is Map && value.containsKey(part)) {
        value = value[part];
      } else {
        if (defaultValue != null) {
          return defaultValue;
        }
        throw ConfigException('Configuration key not found: $key');
      }
    }

    if (value is T) {
      return value;
    } else if (defaultValue != null) {
      return defaultValue;
    } else {
      throw ConfigException(
          'Configuration value "$key" is not of type $T (actual: ${value.runtimeType})');
    }
  }

  /// Get typed configuration (new type-safe API)
  TypedAppConfig getTypedConfig() {
    return TypedAppConfig.fromMap(_config);
  }

  /// Update typed configuration
  void updateTypedConfig(TypedAppConfig typedConfig) {
    _mergeConfig(typedConfig.toMap());
  }

  /// Get memory configuration as typed object
  MemoryConfig getMemoryConfig() {
    final memoryMap = get<Map<String, dynamic>>('memory', defaultValue: {});
    return MemoryConfig.fromMap(memoryMap);
  }

  /// Get logging configuration as typed object
  LoggingConfig getLoggingConfig() {
    final loggingMap = get<Map<String, dynamic>>('logging', defaultValue: {});
    return LoggingConfig.fromMap(loggingMap);
  }

  /// Get performance configuration as typed object
  PerformanceConfig getPerformanceConfig() {
    final performanceMap =
        get<Map<String, dynamic>>('performance', defaultValue: {});
    return PerformanceConfig.fromMap(performanceMap);
  }

  /// Get security configuration as typed object
  SecurityConfig getSecurityConfig() {
    final securityMap = get<Map<String, dynamic>>('security', defaultValue: {});
    return SecurityConfig.fromMap(securityMap);
  }

  /// Get platform configuration as typed object
  PlatformConfig getPlatformConfig() {
    final platformMap = get<Map<String, dynamic>>('platform', defaultValue: {});
    return PlatformConfig.fromMap(platformMap);
  }

  /// Set configuration value using dot notation
  void set(String key, dynamic value) {
    _setNestedValue(key, value);
  }

  /// Check if configuration key exists
  bool containsKey(String key) {
    try {
      get<dynamic>(key);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[$_loggerName] Configuration key "$key" not found: $e');
      }
      return false;
    }
  }

  /// Get all configuration as a map
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_config);

  /// Export configuration to JSON string
  String toJson() => const JsonEncoder.withIndent('  ').convert(_config);

  /// Create a scoped configuration accessor
  ScopedConfig scoped(String prefix) => ScopedConfig._(this, prefix);

  /// Check if configuration is initialized
  bool get isInitialized => _isInitialized;

  /// Reset configuration to defaults (for testing)
  @visibleForTesting
  void reset() {
    _config.clear();
    _isInitialized = false;
    _loadDefaults();
  }
}

/// Scoped configuration accessor for a specific module
class ScopedConfig {
  final AppConfig _config;
  final String _prefix;

  ScopedConfig._(this._config, this._prefix);

  /// Get scoped configuration value
  T get<T>(String key, {T? defaultValue}) {
    return _config.get<T>('$_prefix.$key', defaultValue: defaultValue);
  }

  /// Set scoped configuration value
  void set(String key, dynamic value) {
    _config.set('$_prefix.$key', value);
  }

  /// Check if scoped key exists
  bool containsKey(String key) {
    return _config.containsKey('$_prefix.$key');
  }

  /// Get duration from milliseconds configuration
  Duration getDuration(String key, {Duration? defaultValue}) {
    final ms = get<int>(key, defaultValue: defaultValue?.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  /// Get all values for this scope
  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};
    final fullMap = _config.toMap();

    if (fullMap.containsKey(_prefix) && fullMap[_prefix] is Map) {
      return Map<String, dynamic>.from(fullMap[_prefix] as Map);
    }

    return result;
  }
}

/// Configuration exception
class ConfigException implements Exception {
  final String message;

  const ConfigException(this.message);

  @override
  String toString() => 'ConfigException: $message';
}
