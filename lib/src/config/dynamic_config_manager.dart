import 'dart:async';
import 'mcp_config.dart';
import 'config_validator.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/event_system.dart';

/// Configuration change event
class ConfigChangeEvent {
  final String path;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;
  final String? reason;

  ConfigChangeEvent({
    required this.path,
    required this.oldValue,
    required this.newValue,
    this.reason,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'path': path,
        'oldValue': oldValue,
        'newValue': newValue,
        'timestamp': timestamp.toIso8601String(),
        if (reason != null) 'reason': reason,
      };
}

/// Configuration change listener
typedef ConfigChangeListener = void Function(ConfigChangeEvent event);

/// Dynamic configuration manager for runtime updates
class DynamicConfigManager {
  static final Logger _logger = Logger('flutter_mcp.dynamic_config');

  // Current configuration
  MCPConfig _currentConfig;

  // Configuration history for rollback
  final List<MCPConfig> _configHistory = [];
  static const int _maxHistorySize = 10;

  // Change listeners
  final Map<String, List<ConfigChangeListener>> _listeners = {};
  final List<ConfigChangeListener> _globalListeners = [];

  // Stream controllers for reactive updates
  final StreamController<ConfigChangeEvent> _changeController =
      StreamController<ConfigChangeEvent>.broadcast();

  // Validation rules
  final List<ValidationRule> _validationRules = [];

  // Event system for integration
  final EventSystem _eventSystem = EventSystem.instance;

  /// Constructor
  DynamicConfigManager(this._currentConfig) {
    _logger.info('Dynamic config manager initialized');

    // Add to config history
    _configHistory.add(_currentConfig);

    // Set up default validation rules
    _setupDefaultValidationRules();
  }

  /// Get current configuration
  MCPConfig get currentConfig => _currentConfig;

  /// Get configuration change stream
  Stream<ConfigChangeEvent> get changeStream => _changeController.stream;

  /// Update configuration value at path
  Future<bool> updateValue(String path, dynamic newValue,
      {String? reason}) async {
    try {
      _logger.fine('Updating config value at path: $path');

      final oldValue = _getValueAtPath(path);

      // Create updated configuration
      final updatedConfig = _createUpdatedConfig(path, newValue);

      // Validate the updated configuration
      final validationResult = ConfigValidator.validate(updatedConfig);
      if (!validationResult.isValid) {
        _logger.warning(
            'Configuration validation failed: ${validationResult.summary}');

        // Throw exception with validation details
        final validationErrors = <String, dynamic>{};
        for (int i = 0; i < validationResult.criticalErrors.length; i++) {
          final error = validationResult.criticalErrors[i];
          validationErrors['error_$i'] = {
            'field': error.field,
            'message': error.message,
            'severity': error.severity.name,
          };
        }

        throw MCPValidationException(
          'Configuration update failed validation',
          validationErrors,
        );
      }

      // Apply custom validation rules
      for (final rule in _validationRules) {
        if (!rule.validate(path, newValue, updatedConfig)) {
          throw MCPValidationException(
            'Custom validation rule failed: ${rule.description}',
            {'rule_error': rule.errorMessage},
          );
        }
      }

      // Update configuration
      await _applyConfigUpdate(updatedConfig, path, oldValue, newValue, reason);

      _logger.info('Configuration updated successfully at path: $path');
      return true;
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to update configuration at path: $path', e, stackTrace);
      return false;
    }
  }

  /// Update multiple configuration values atomically
  Future<bool> updateMultiple(Map<String, dynamic> updates,
      {String? reason}) async {
    try {
      _logger
          .fine('Updating multiple config values: ${updates.keys.join(', ')}');

      var updatedConfig = _currentConfig;
      final changes = <ConfigChangeEvent>[];

      // Apply all updates to create new configuration
      for (final entry in updates.entries) {
        final path = entry.key;
        final newValue = entry.value;
        final oldValue = _getValueAtPath(path);

        updatedConfig =
            _createUpdatedConfigFromBase(updatedConfig, path, newValue);

        changes.add(ConfigChangeEvent(
          path: path,
          oldValue: oldValue,
          newValue: newValue,
          reason: reason,
        ));
      }

      // Validate the complete updated configuration
      final validationResult = ConfigValidator.validate(updatedConfig);
      if (!validationResult.isValid) {
        _logger.warning(
            'Batch configuration validation failed: ${validationResult.summary}');

        final validationErrors = <String, dynamic>{};
        for (int i = 0; i < validationResult.criticalErrors.length; i++) {
          final error = validationResult.criticalErrors[i];
          validationErrors['error_$i'] = {
            'field': error.field,
            'message': error.message,
            'severity': error.severity.name,
          };
        }

        throw MCPValidationException(
          'Batch configuration update failed validation',
          validationErrors,
        );
      }

      // Apply the batch update
      await _applyBatchConfigUpdate(updatedConfig, changes);

      _logger.info('Batch configuration update completed successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to update multiple configuration values', e, stackTrace);
      return false;
    }
  }

  /// Rollback to previous configuration
  Future<bool> rollback({int steps = 1}) async {
    if (_configHistory.length <= steps) {
      _logger.warning('Cannot rollback: insufficient history');
      return false;
    }

    try {
      final targetIndex = _configHistory.length - 1 - steps;
      final targetConfig = _configHistory[targetIndex];

      _logger.info('Rolling back configuration $steps steps');

      // Apply rollback
      await _applyConfigRollback(targetConfig, steps);

      _logger.info('Configuration rollback completed successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to rollback configuration', e, stackTrace);
      return false;
    }
  }

  /// Get value at configuration path
  dynamic getValue(String path) {
    return _getValueAtPath(path);
  }

  /// Check if path exists in configuration
  bool hasPath(String path) {
    try {
      _getValueAtPath(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add configuration change listener
  void addListener(String path, ConfigChangeListener listener) {
    _listeners.putIfAbsent(path, () => []).add(listener);
    _logger.fine('Added listener for path: $path');
  }

  /// Add global configuration change listener
  void addGlobalListener(ConfigChangeListener listener) {
    _globalListeners.add(listener);
    _logger.fine('Added global configuration listener');
  }

  /// Remove configuration change listener
  bool removeListener(String path, ConfigChangeListener listener) {
    final listeners = _listeners[path];
    if (listeners != null) {
      final removed = listeners.remove(listener);
      if (listeners.isEmpty) {
        _listeners.remove(path);
      }
      return removed;
    }
    return false;
  }

  /// Remove global configuration change listener
  bool removeGlobalListener(ConfigChangeListener listener) {
    return _globalListeners.remove(listener);
  }

  /// Add custom validation rule
  void addValidationRule(ValidationRule rule) {
    _validationRules.add(rule);
    _logger.fine('Added validation rule: ${rule.description}');
  }

  /// Remove custom validation rule
  bool removeValidationRule(ValidationRule rule) {
    return _validationRules.remove(rule);
  }

  /// Export current configuration
  Map<String, dynamic> exportConfig() {
    return _configToJson(_currentConfig);
  }

  /// Import configuration from JSON
  Future<bool> importConfig(Map<String, dynamic> configJson,
      {String? reason}) async {
    try {
      _logger.info('Importing configuration from JSON');

      // Create configuration from JSON
      final newConfig = _configFromJson(configJson);

      // Validate imported configuration
      final validationResult = ConfigValidator.validate(newConfig);
      if (!validationResult.isValid) {
        final validationErrors = <String, dynamic>{};
        for (int i = 0; i < validationResult.criticalErrors.length; i++) {
          final error = validationResult.criticalErrors[i];
          validationErrors['error_$i'] = {
            'field': error.field,
            'message': error.message,
            'severity': error.severity.name,
          };
        }

        throw MCPValidationException(
          'Imported configuration failed validation',
          validationErrors,
        );
      }

      // Apply imported configuration
      await _applyCompleteConfigUpdate(
          newConfig, reason ?? 'Configuration imported');

      _logger.info('Configuration import completed successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to import configuration', e, stackTrace);
      return false;
    }
  }

  /// Get configuration history
  List<MCPConfig> get configHistory => List.unmodifiable(_configHistory);

  /// Clear configuration history
  void clearHistory() {
    _configHistory.clear();
    _configHistory.add(_currentConfig);
    _logger.info('Configuration history cleared');
  }

  /// Setup default validation rules
  void _setupDefaultValidationRules() {
    // Memory usage validation
    addValidationRule(ValidationRule(
      description: 'Memory usage should not exceed 1GB',
      validate: (path, value, config) {
        final estimatedMemory = ConfigValidator.estimateMemoryUsage(config);
        return estimatedMemory <= 1024; // 1GB limit
      },
      errorMessage: 'Configuration would exceed memory limit',
    ));

    // Port conflict validation
    addValidationRule(ValidationRule(
      description: 'Ports should not conflict',
      validate: (path, value, config) {
        if (!path.contains('ssePort')) return true;

        final usedPorts = <int>{};
        if (config.autoStartServer != null) {
          for (final server in config.autoStartServer!) {
            if (server.ssePort != null) {
              if (usedPorts.contains(server.ssePort)) {
                return false;
              }
              usedPorts.add(server.ssePort!);
            }
          }
        }
        return true;
      },
      errorMessage: 'Port conflict detected',
    ));
  }

  /// Get value at configuration path
  dynamic _getValueAtPath(String path) {
    final parts = path.split('.');
    dynamic current = _configToJson(_currentConfig);

    for (final part in parts) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else {
        throw ArgumentError('Path not found: $path');
      }
    }

    return current;
  }

  /// Create updated configuration with new value at path
  MCPConfig _createUpdatedConfig(String path, dynamic newValue) {
    final configJson = _configToJson(_currentConfig);
    _setValueAtPath(configJson, path, newValue);
    return _configFromJson(configJson);
  }

  /// Create updated configuration from base config
  MCPConfig _createUpdatedConfigFromBase(
      MCPConfig baseConfig, String path, dynamic newValue) {
    final configJson = _configToJson(baseConfig);
    _setValueAtPath(configJson, path, newValue);
    return _configFromJson(configJson);
  }

  /// Set value at path in JSON object
  void _setValueAtPath(Map<String, dynamic> json, String path, dynamic value) {
    final parts = path.split('.');
    Map<String, dynamic> current = json;

    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (!current.containsKey(part)) {
        current[part] = <String, dynamic>{};
      }
      current = current[part] as Map<String, dynamic>;
    }

    current[parts.last] = value;
  }

  /// Apply configuration update
  Future<void> _applyConfigUpdate(
    MCPConfig newConfig,
    String path,
    dynamic oldValue,
    dynamic newValue,
    String? reason,
  ) async {
    // Save current config to history
    _addToHistory(_currentConfig);

    // Update current configuration
    _currentConfig = newConfig;

    // Create change event
    final changeEvent = ConfigChangeEvent(
      path: path,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
    );

    // Notify listeners
    await _notifyListeners(changeEvent);

    // Emit to event system
    _eventSystem.publishTopic('config.changed', changeEvent.toJson());
  }

  /// Apply batch configuration update
  Future<void> _applyBatchConfigUpdate(
    MCPConfig newConfig,
    List<ConfigChangeEvent> changes,
  ) async {
    // Save current config to history
    _addToHistory(_currentConfig);

    // Update current configuration
    _currentConfig = newConfig;

    // Notify listeners for each change
    for (final change in changes) {
      await _notifyListeners(change);
    }

    // Emit batch change event
    _eventSystem.publishTopic('config.batch_changed', {
      'changes': changes.map((c) => c.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Apply configuration rollback
  Future<void> _applyConfigRollback(MCPConfig targetConfig, int steps) async {
    // Remove rolled back configurations from history
    for (int i = 0; i < steps; i++) {
      if (_configHistory.isNotEmpty) {
        _configHistory.removeLast();
      }
    }

    // Update current configuration
    _currentConfig = targetConfig;

    // Create rollback event
    final rollbackEvent = ConfigChangeEvent(
      path: 'root',
      oldValue: 'previous_config',
      newValue: 'rolled_back_config',
      reason: 'Configuration rollback ($steps steps)',
    );

    // Notify listeners
    await _notifyListeners(rollbackEvent);

    // Emit rollback event
    _eventSystem.publishTopic('config.rollback', {
      'steps': steps,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Apply complete configuration update
  Future<void> _applyCompleteConfigUpdate(
      MCPConfig newConfig, String reason) async {
    // Save current config to history
    _addToHistory(_currentConfig);

    _currentConfig = newConfig;

    // Create import event
    final importEvent = ConfigChangeEvent(
      path: 'root',
      oldValue: 'previous_config',
      newValue: 'imported_config',
      reason: reason,
    );

    // Notify listeners
    await _notifyListeners(importEvent);

    // Emit import event
    _eventSystem.publishTopic('config.imported', {
      'reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Add configuration to history
  void _addToHistory(MCPConfig config) {
    _configHistory.add(config);

    // Maintain history size limit
    while (_configHistory.length > _maxHistorySize) {
      _configHistory.removeAt(0);
    }
  }

  /// Notify configuration change listeners
  Future<void> _notifyListeners(ConfigChangeEvent event) async {
    // Notify global listeners
    for (final listener in _globalListeners) {
      try {
        listener(event);
      } catch (e, stackTrace) {
        _logger.warning('Error in global config listener', e, stackTrace);
      }
    }

    // Notify path-specific listeners
    final pathListeners = _listeners[event.path];
    if (pathListeners != null) {
      for (final listener in pathListeners) {
        try {
          listener(event);
        } catch (e, stackTrace) {
          _logger.warning(
              'Error in path-specific config listener', e, stackTrace);
        }
      }
    }

    // Emit to stream
    _changeController.add(event);
  }

  /// Convert configuration to JSON (simplified for demo)
  Map<String, dynamic> _configToJson(MCPConfig config) {
    // This is a simplified implementation
    // In a real implementation, this would use proper serialization
    return {
      'appName': config.appName,
      'appVersion': config.appVersion,
      'useBackgroundService': config.useBackgroundService,
      'useNotification': config.useNotification,
      'useTray': config.useTray,
      'secure': config.secure,
      'lifecycleManaged': config.lifecycleManaged,
      'autoStart': config.autoStart,
      'enablePerformanceMonitoring': config.enablePerformanceMonitoring,
      'enableMetricsExport': config.enableMetricsExport,
      'metricsExportPath': config.metricsExportPath,
      'autoLoadPlugins': config.autoLoadPlugins,
      'highMemoryThresholdMB': config.highMemoryThresholdMB,
      'lowBatteryWarningThreshold': config.lowBatteryWarningThreshold,
      'maxConnectionRetries': config.maxConnectionRetries,
      'llmRequestTimeoutMs': config.llmRequestTimeoutMs,
    };
  }

  /// Create configuration from JSON (simplified for demo)
  MCPConfig _configFromJson(Map<String, dynamic> json) {
    // This is a simplified implementation
    // In a real implementation, this would use proper deserialization
    return MCPConfig(
      appName: json['appName'] as String? ?? 'Flutter MCP',
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      useBackgroundService: json['useBackgroundService'] as bool? ?? false,
      useNotification: json['useNotification'] as bool? ?? false,
      useTray: json['useTray'] as bool? ?? false,
      secure: json['secure'] as bool? ?? false,
      lifecycleManaged: json['lifecycleManaged'] as bool? ?? true,
      autoStart: json['autoStart'] as bool? ?? false,
      enablePerformanceMonitoring: json['enablePerformanceMonitoring'] as bool?,
      enableMetricsExport: json['enableMetricsExport'] as bool?,
      metricsExportPath: json['metricsExportPath'] as String?,
      autoLoadPlugins: json['autoLoadPlugins'] as bool?,
      highMemoryThresholdMB: json['highMemoryThresholdMB'] as int?,
      lowBatteryWarningThreshold: json['lowBatteryWarningThreshold'] as int?,
      maxConnectionRetries: json['maxConnectionRetries'] as int?,
      llmRequestTimeoutMs: json['llmRequestTimeoutMs'] as int?,
    );
  }

  /// Dispose resources
  void dispose() {
    _changeController.close();
    _listeners.clear();
    _globalListeners.clear();
    _validationRules.clear();
    _logger.info('Dynamic config manager disposed');
  }
}

/// Custom validation rule for configuration
class ValidationRule {
  final String description;
  final bool Function(String path, dynamic value, MCPConfig config) validate;
  final String errorMessage;

  ValidationRule({
    required this.description,
    required this.validate,
    required this.errorMessage,
  });
}
