/// Configuration parsing utilities for consistent JSON handling
library;

import '../utils/exceptions.dart';
import '../utils/input_validator.dart';

/// Type-safe configuration parser
class ConfigParser {
  final Map<String, dynamic> _json;
  final String _configName;

  ConfigParser(this._json, {String configName = 'config'})
      : _configName = configName;

  /// Parse string value with validation
  String getString(
    String key, {
    String? defaultValue,
    bool required = false,
    List<String>? allowedValues,
    int? minLength,
    int? maxLength,
  }) {
    final value = _json[key] as String?;

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required string field "$key" is missing from $_configName');
      }
      return defaultValue ?? '';
    }

    // Validate length
    if (minLength != null && value.length < minLength) {
      throw MCPConfigurationException(
          'String field "$key" in $_configName must be at least $minLength characters');
    }

    if (maxLength != null && value.length > maxLength) {
      throw MCPConfigurationException(
          'String field "$key" in $_configName must be at most $maxLength characters');
    }

    // Validate allowed values
    if (allowedValues != null && !allowedValues.contains(value)) {
      throw MCPConfigurationException(
          'String field "$key" in $_configName must be one of: ${allowedValues.join(', ')}');
    }

    return value;
  }

  /// Parse boolean value
  bool getBool(
    String key, {
    bool? defaultValue,
    bool required = false,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required boolean field "$key" is missing from $_configName');
      }
      return defaultValue ?? false;
    }

    if (value is bool) {
      return value;
    }

    if (value is String) {
      final lowerValue = value.toLowerCase();
      if (lowerValue == 'true' || lowerValue == '1') return true;
      if (lowerValue == 'false' || lowerValue == '0') return false;
    }

    if (value is int) {
      return value != 0;
    }

    throw MCPConfigurationException(
        'Boolean field "$key" in $_configName has invalid value: $value');
  }

  /// Parse integer value with validation
  int getInt(
    String key, {
    int? defaultValue,
    bool required = false,
    int? min,
    int? max,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required integer field "$key" is missing from $_configName');
      }
      return defaultValue ?? 0;
    }

    int intValue;
    if (value is int) {
      intValue = value;
    } else if (value is double) {
      intValue = value.toInt();
    } else if (value is String) {
      try {
        intValue = int.parse(value);
      } catch (e) {
        throw MCPConfigurationException(
            'Integer field "$key" in $_configName has invalid value: $value');
      }
    } else {
      throw MCPConfigurationException(
          'Integer field "$key" in $_configName has invalid type: ${value.runtimeType}');
    }

    // Validate range
    if (min != null && intValue < min) {
      throw MCPConfigurationException(
          'Integer field "$key" in $_configName must be at least $min');
    }

    if (max != null && intValue > max) {
      throw MCPConfigurationException(
          'Integer field "$key" in $_configName must be at most $max');
    }

    return intValue;
  }

  /// Parse double value with validation
  double getDouble(
    String key, {
    double? defaultValue,
    bool required = false,
    double? min,
    double? max,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required double field "$key" is missing from $_configName');
      }
      return defaultValue ?? 0.0;
    }

    double doubleValue;
    if (value is double) {
      doubleValue = value;
    } else if (value is int) {
      doubleValue = value.toDouble();
    } else if (value is String) {
      try {
        doubleValue = double.parse(value);
      } catch (e) {
        throw MCPConfigurationException(
            'Double field "$key" in $_configName has invalid value: $value');
      }
    } else {
      throw MCPConfigurationException(
          'Double field "$key" in $_configName has invalid type: ${value.runtimeType}');
    }

    // Validate range
    if (min != null && doubleValue < min) {
      throw MCPConfigurationException(
          'Double field "$key" in $_configName must be at least $min');
    }

    if (max != null && doubleValue > max) {
      throw MCPConfigurationException(
          'Double field "$key" in $_configName must be at most $max');
    }

    return doubleValue;
  }

  /// Parse Duration from milliseconds
  Duration getDuration(
    String key, {
    Duration? defaultValue,
    bool required = false,
    Duration? min,
    Duration? max,
  }) {
    final ms = getInt(
      key,
      defaultValue: defaultValue?.inMilliseconds,
      required: required,
      min: min?.inMilliseconds,
      max: max?.inMilliseconds,
    );

    return Duration(milliseconds: ms);
  }

  /// Parse enum value
  T getEnum<T extends Enum>(
    String key,
    List<T> values, {
    T? defaultValue,
    bool required = false,
  }) {
    final stringValue = getString(
      key,
      defaultValue: defaultValue?.name,
      required: required,
    );

    if (stringValue.isEmpty && !required) {
      return defaultValue!;
    }

    try {
      return values.firstWhere((e) => e.name == stringValue);
    } catch (e) {
      throw MCPConfigurationException(
          'Enum field "$key" in $_configName has invalid value: $stringValue. '
          'Valid values: ${values.map((e) => e.name).join(', ')}');
    }
  }

  /// Parse list value
  List<T> getList<T>(
    String key,
    T Function(dynamic) itemParser, {
    List<T>? defaultValue,
    bool required = false,
    int? minLength,
    int? maxLength,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required list field "$key" is missing from $_configName');
      }
      return defaultValue ?? [];
    }

    if (value is! List) {
      throw MCPConfigurationException(
          'List field "$key" in $_configName has invalid type: ${value.runtimeType}');
    }

    final list = value;

    // Validate length
    if (minLength != null && list.length < minLength) {
      throw MCPConfigurationException(
          'List field "$key" in $_configName must have at least $minLength items');
    }

    if (maxLength != null && list.length > maxLength) {
      throw MCPConfigurationException(
          'List field "$key" in $_configName must have at most $maxLength items');
    }

    try {
      return list.map(itemParser).toList();
    } catch (e) {
      throw MCPConfigurationException(
          'List field "$key" in $_configName contains invalid items: $e');
    }
  }

  /// Parse map value
  Map<String, T> getMap<T>(
    String key,
    T Function(dynamic) valueParser, {
    Map<String, T>? defaultValue,
    bool required = false,
    List<String>? requiredKeys,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required map field "$key" is missing from $_configName');
      }
      return defaultValue ?? {};
    }

    if (value is! Map) {
      throw MCPConfigurationException(
          'Map field "$key" in $_configName has invalid type: ${value.runtimeType}');
    }

    final map = value as Map<String, dynamic>;

    // Validate required keys
    if (requiredKeys != null) {
      final missing = requiredKeys.where((k) => !map.containsKey(k)).toList();
      if (missing.isNotEmpty) {
        throw MCPConfigurationException(
            'Map field "$key" in $_configName is missing required keys: ${missing.join(', ')}');
      }
    }

    try {
      return map.map((k, v) => MapEntry(k, valueParser(v)));
    } catch (e) {
      throw MCPConfigurationException(
          'Map field "$key" in $_configName contains invalid values: $e');
    }
  }

  /// Parse nested configuration object
  ConfigParser getObject(
    String key, {
    bool required = false,
  }) {
    final value = _json[key];

    if (value == null) {
      if (required) {
        throw MCPConfigurationException(
            'Required object field "$key" is missing from $_configName');
      }
      return ConfigParser({}, configName: '$_configName.$key');
    }

    if (value is! Map<String, dynamic>) {
      throw MCPConfigurationException(
          'Object field "$key" in $_configName has invalid type: ${value.runtimeType}');
    }

    return ConfigParser(value, configName: '$_configName.$key');
  }

  /// Check if key exists
  bool hasKey(String key) => _json.containsKey(key);

  /// Get all keys
  Set<String> get keys => _json.keys.toSet();

  /// Validate that all required fields are present
  void validateRequired(List<String> requiredFields) {
    final missing =
        requiredFields.where((field) => !_json.containsKey(field)).toList();

    if (missing.isNotEmpty) {
      throw MCPConfigurationException(
          'Required fields missing from $_configName: ${missing.join(', ')}');
    }
  }

  /// Validate that no unknown fields are present
  void validateNoUnknownFields(List<String> allowedFields) {
    final unknown =
        _json.keys.where((field) => !allowedFields.contains(field)).toList();

    if (unknown.isNotEmpty) {
      throw MCPConfigurationException(
          'Unknown fields in $_configName: ${unknown.join(', ')}. '
          'Allowed fields: ${allowedFields.join(', ')}');
    }
  }

  /// Get raw JSON data
  Map<String, dynamic> get rawData => Map.unmodifiable(_json);

  /// Convert to string for debugging
  @override
  String toString() =>
      'ConfigParser($_configName: ${_json.keys.length} fields)';
}

/// Configuration validation helper
class ConfigValidator {
  /// Validate email format
  static bool isValidEmail(String email) {
    return InputValidator.isValidEmail(email);
  }

  /// Validate URL format
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Validate file path format
  static bool isValidFilePath(String path) {
    try {
      // Basic validation - check for illegal characters
      final illegalChars = RegExp(r'[<>:"|?*]');
      return !illegalChars.hasMatch(path);
    } catch (e) {
      return false;
    }
  }

  /// Validate port number
  static bool isValidPort(int port) {
    return port >= 1 && port <= 65535;
  }

  /// Validate IPv4 address
  static bool isValidIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }

    return true;
  }
}

/// Common configuration patterns
class ConfigPatterns {
  /// Parse timeout configuration with default fallbacks
  static Duration parseTimeout(
    ConfigParser parser,
    String key, {
    Duration defaultValue = const Duration(seconds: 30),
    Duration? min,
    Duration? max,
  }) {
    return parser.getDuration(
      key,
      defaultValue: defaultValue,
      min: min ?? Duration(seconds: 1),
      max: max ?? Duration(minutes: 10),
    );
  }

  /// Parse retry configuration
  static ({int maxRetries, Duration delay}) parseRetryConfig(
      ConfigParser parser, String prefix) {
    return (
      maxRetries: parser.getInt(
        '${prefix}MaxRetries',
        defaultValue: 3,
        min: 0,
        max: 10,
      ),
      delay: parser.getDuration(
        '${prefix}Delay',
        defaultValue: Duration(seconds: 1),
        min: Duration(milliseconds: 100),
        max: Duration(seconds: 30),
      ),
    );
  }

  /// Parse URL with validation
  static String parseUrl(
    ConfigParser parser,
    String key, {
    String? defaultValue,
    bool required = false,
  }) {
    final url =
        parser.getString(key, defaultValue: defaultValue, required: required);

    if (url.isNotEmpty && !ConfigValidator.isValidUrl(url)) {
      throw MCPConfigurationException('Invalid URL format for "$key": $url');
    }

    return url;
  }

  /// Parse file path with validation
  static String parseFilePath(
    ConfigParser parser,
    String key, {
    String? defaultValue,
    bool required = false,
  }) {
    final path =
        parser.getString(key, defaultValue: defaultValue, required: required);

    if (path.isNotEmpty && !ConfigValidator.isValidFilePath(path)) {
      throw MCPConfigurationException(
          'Invalid file path format for "$key": $path');
    }

    return path;
  }
}
