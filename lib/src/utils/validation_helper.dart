/// Validation helper utility to consolidate repeated validation logic
library;

import '../utils/exceptions.dart';
import '../utils/input_validator.dart';

/// Common validation helper methods
class ValidationHelper {
  /// Validate string is not null or empty
  static String validateNonEmptyString(
    String? value,
    String fieldName, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
    String? patternDescription,
  }) {
    if (value == null || value.isEmpty) {
      throw MCPValidationException(
        'Field "$fieldName" is required and cannot be empty',
        {fieldName: 'Required field is empty'},
      );
    }

    if (minLength != null && value.length < minLength) {
      throw MCPValidationException(
        'Field "$fieldName" must be at least $minLength characters',
        {fieldName: 'Minimum length is $minLength, got ${value.length}'},
      );
    }

    if (maxLength != null && value.length > maxLength) {
      throw MCPValidationException(
        'Field "$fieldName" must be at most $maxLength characters',
        {fieldName: 'Maximum length is $maxLength, got ${value.length}'},
      );
    }

    if (pattern != null && !pattern.allMatches(value).isNotEmpty) {
      throw MCPValidationException(
        'Field "$fieldName" has invalid format${patternDescription != null ? ': $patternDescription' : ''}',
        {fieldName: 'Value does not match required pattern'},
      );
    }

    return value;
  }

  /// Validate integer within range
  static int validateIntRange(
    int? value,
    String fieldName, {
    int? min,
    int? max,
    bool required = true,
    int? defaultValue,
  }) {
    if (value == null) {
      if (required) {
        throw MCPValidationException(
          'Field "$fieldName" is required',
          {fieldName: 'Required field is null'},
        );
      }
      return defaultValue ?? 0;
    }

    if (min != null && value < min) {
      throw MCPValidationException(
        'Field "$fieldName" must be at least $min',
        {fieldName: 'Value $value is below minimum $min'},
      );
    }

    if (max != null && value > max) {
      throw MCPValidationException(
        'Field "$fieldName" must be at most $max',
        {fieldName: 'Value $value is above maximum $max'},
      );
    }

    return value;
  }

  /// Validate double within range
  static double validateDoubleRange(
    double? value,
    String fieldName, {
    double? min,
    double? max,
    bool required = true,
    double? defaultValue,
  }) {
    if (value == null) {
      if (required) {
        throw MCPValidationException(
          'Field "$fieldName" is required',
          {fieldName: 'Required field is null'},
        );
      }
      return defaultValue ?? 0.0;
    }

    if (min != null && value < min) {
      throw MCPValidationException(
        'Field "$fieldName" must be at least $min',
        {fieldName: 'Value $value is below minimum $min'},
      );
    }

    if (max != null && value > max) {
      throw MCPValidationException(
        'Field "$fieldName" must be at most $max',
        {fieldName: 'Value $value is above maximum $max'},
      );
    }

    return value;
  }

  /// Validate list is not null or empty
  static List<T> validateNonEmptyList<T>(
    List<T>? value,
    String fieldName, {
    int? minLength,
    int? maxLength,
  }) {
    if (value == null || value.isEmpty) {
      throw MCPValidationException(
        'Field "$fieldName" is required and cannot be empty',
        {fieldName: 'Required list is empty'},
      );
    }

    if (minLength != null && value.length < minLength) {
      throw MCPValidationException(
        'Field "$fieldName" must have at least $minLength items',
        {fieldName: 'List has ${value.length} items, minimum is $minLength'},
      );
    }

    if (maxLength != null && value.length > maxLength) {
      throw MCPValidationException(
        'Field "$fieldName" must have at most $maxLength items',
        {fieldName: 'List has ${value.length} items, maximum is $maxLength'},
      );
    }

    return value;
  }

  /// Validate map is not null or empty
  static Map<K, V> validateNonEmptyMap<K, V>(
    Map<K, V>? value,
    String fieldName, {
    List<K>? requiredKeys,
  }) {
    if (value == null || value.isEmpty) {
      throw MCPValidationException(
        'Field "$fieldName" is required and cannot be empty',
        {fieldName: 'Required map is empty'},
      );
    }

    if (requiredKeys != null) {
      final missing =
          requiredKeys.where((key) => !value.containsKey(key)).toList();
      if (missing.isNotEmpty) {
        throw MCPValidationException(
          'Field "$fieldName" is missing required keys: ${missing.join(', ')}',
          {fieldName: 'Missing required keys: ${missing.join(', ')}'},
        );
      }
    }

    return value;
  }

  /// Validate email format
  static String validateEmail(String? value, String fieldName) {
    final email = validateNonEmptyString(value, fieldName);

    if (!InputValidator.isValidEmail(email)) {
      throw MCPValidationException(
        'Field "$fieldName" must be a valid email address',
        {fieldName: 'Invalid email format'},
      );
    }

    return email;
  }

  /// Validate URL format
  static String validateUrl(
    String? value,
    String fieldName, {
    List<String>? allowedSchemes,
  }) {
    final url = validateNonEmptyString(value, fieldName);

    try {
      final uri = Uri.parse(url);

      if (!uri.hasScheme) {
        throw MCPValidationException(
          'Field "$fieldName" must include a URL scheme (http/https)',
          {fieldName: 'Missing URL scheme'},
        );
      }

      if (allowedSchemes != null &&
          !allowedSchemes.contains(uri.scheme.toLowerCase())) {
        throw MCPValidationException(
          'Field "$fieldName" must use one of these schemes: ${allowedSchemes.join(', ')}',
          {fieldName: 'Invalid URL scheme: ${uri.scheme}'},
        );
      }
    } catch (e) {
      throw MCPValidationException(
        'Field "$fieldName" must be a valid URL',
        {fieldName: 'Invalid URL format: $e'},
      );
    }

    return url;
  }

  /// Validate enum value
  static T validateEnum<T extends Enum>(
    String? value,
    String fieldName,
    List<T> allowedValues, {
    T? defaultValue,
    bool required = true,
  }) {
    if (value == null || value.isEmpty) {
      if (required) {
        throw MCPValidationException(
          'Field "$fieldName" is required',
          {fieldName: 'Required enum field is null or empty'},
        );
      }
      if (defaultValue != null) {
        return defaultValue;
      }
      throw MCPValidationException(
        'Field "$fieldName" has no default value',
        {fieldName: 'No default value provided for optional enum'},
      );
    }

    try {
      return allowedValues.firstWhere((e) => e.name == value);
    } catch (e) {
      final validNames = allowedValues.map((e) => e.name).join(', ');
      throw MCPValidationException(
        'Field "$fieldName" must be one of: $validNames',
        {fieldName: 'Invalid enum value: $value'},
      );
    }
  }

  /// Validate duration is within acceptable range
  static Duration validateDuration(
    Duration? value,
    String fieldName, {
    Duration? min,
    Duration? max,
    bool required = true,
    Duration? defaultValue,
  }) {
    if (value == null) {
      if (required) {
        throw MCPValidationException(
          'Field "$fieldName" is required',
          {fieldName: 'Required duration field is null'},
        );
      }
      return defaultValue ?? Duration.zero;
    }

    if (min != null && value < min) {
      throw MCPValidationException(
        'Field "$fieldName" must be at least ${min.inMilliseconds}ms',
        {
          fieldName:
              'Duration ${value.inMilliseconds}ms is below minimum ${min.inMilliseconds}ms'
        },
      );
    }

    if (max != null && value > max) {
      throw MCPValidationException(
        'Field "$fieldName" must be at most ${max.inMilliseconds}ms',
        {
          fieldName:
              'Duration ${value.inMilliseconds}ms is above maximum ${max.inMilliseconds}ms'
        },
      );
    }

    return value;
  }

  /// Validate that a value is one of the allowed values
  static T validateAllowedValue<T>(
    T? value,
    String fieldName,
    List<T> allowedValues, {
    T? defaultValue,
    bool required = true,
  }) {
    if (value == null) {
      if (required) {
        throw MCPValidationException(
          'Field "$fieldName" is required',
          {fieldName: 'Required field is null'},
        );
      }
      if (defaultValue != null) {
        return defaultValue;
      }
      throw MCPValidationException(
        'Field "$fieldName" has no default value',
        {fieldName: 'No default value provided for optional field'},
      );
    }

    if (!allowedValues.contains(value)) {
      throw MCPValidationException(
        'Field "$fieldName" must be one of: ${allowedValues.join(', ')}',
        {fieldName: 'Invalid value: $value'},
      );
    }

    return value;
  }

  /// Validate file path format and existence (basic checks)
  static String validateFilePath(
    String? value,
    String fieldName, {
    bool checkExists = false,
    List<String>? allowedExtensions,
  }) {
    final path = validateNonEmptyString(value, fieldName);

    // Basic validation - check for illegal characters
    final illegalChars = RegExp(r'[<>:\"|?*]');
    if (illegalChars.hasMatch(path)) {
      throw MCPValidationException(
        'Field "$fieldName" contains illegal characters',
        {fieldName: 'Path contains illegal characters'},
      );
    }

    if (allowedExtensions != null) {
      final extension = path.split('.').last.toLowerCase();
      if (!allowedExtensions.map((e) => e.toLowerCase()).contains(extension)) {
        throw MCPValidationException(
          'Field "$fieldName" must have one of these extensions: ${allowedExtensions.join(', ')}',
          {fieldName: 'Invalid file extension: .$extension'},
        );
      }
    }

    // Note: File existence checking would require dart:io which may not be available on web
    // This is kept simple for cross-platform compatibility

    return path;
  }

  /// Validate port number
  static int validatePort(int? value, String fieldName) {
    final port = validateIntRange(value, fieldName, min: 1, max: 65535);
    return port;
  }

  /// Validate IPv4 address format
  static String validateIPv4(String? value, String fieldName) {
    final ip = validateNonEmptyString(value, fieldName);

    final parts = ip.split('.');
    if (parts.length != 4) {
      throw MCPValidationException(
        'Field "$fieldName" must be a valid IPv4 address',
        {fieldName: 'IPv4 address must have 4 parts separated by dots'},
      );
    }

    for (int i = 0; i < parts.length; i++) {
      final num = int.tryParse(parts[i]);
      if (num == null || num < 0 || num > 255) {
        throw MCPValidationException(
          'Field "$fieldName" must be a valid IPv4 address',
          {fieldName: 'IPv4 part ${i + 1} must be 0-255, got: ${parts[i]}'},
        );
      }
    }

    return ip;
  }

  /// Batch validation - validate multiple fields at once
  static void validateBatch(Map<String, dynamic Function()> validations) {
    final errors = <String, dynamic>{};

    for (final entry in validations.entries) {
      try {
        entry.value();
      } on MCPValidationException catch (e) {
        errors.addAll(e.validationErrors);
      } catch (e) {
        errors[entry.key] = e.toString();
      }
    }

    if (errors.isNotEmpty) {
      throw MCPValidationException(
        'Multiple validation errors occurred',
        errors,
      );
    }
  }
}
