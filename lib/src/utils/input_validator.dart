import 'exceptions.dart';

/// Input validation utilities for MCP
class InputValidator {
  /// Validate API key format
  static bool isValidApiKey(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) return false;
    if (apiKey.length < 10) return false;
    // Only allow alphanumeric, dash, and underscore
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(apiKey);
  }

  /// Validate API key or throw exception
  static void validateApiKeyOrThrow(String? apiKey) {
    if (!isValidApiKey(apiKey)) {
      throw MCPValidationException('Invalid API key format', {});
    }
  }

  /// Validate URL format
  static bool isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Validate WebSocket URL format
  static bool isValidWebSocketUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'ws' || uri.scheme == 'wss');
    } catch (e) {
      return false;
    }
  }

  /// Validate URL or throw exception
  static void validateUrlOrThrow(String? url) {
    if (!isValidUrl(url)) {
      throw MCPValidationException('Invalid URL format', {});
    }
  }

  /// Validate port number
  static bool isValidPort(int? port) {
    if (port == null) return false;
    return port > 0 && port <= 65535;
  }

  /// Validate port or throw exception
  static void validatePortOrThrow(int? port) {
    if (!isValidPort(port)) {
      throw MCPValidationException('Invalid port number (must be 1-65535)', {});
    }
  }

  /// Validate file path (basic security check)
  static bool isValidFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    
    // Check for path traversal attempts
    if (path.contains('..')) return false;
    
    // Check for common sensitive paths
    final lowerPath = path.toLowerCase();
    final dangerousPaths = [
      '/etc/', '/root/', '/sys/', '/proc/',
      'c:\\windows\\system32', 'c:\\windows\\',
      '/private/etc/', '/private/var/'
    ];
    
    for (final dangerous in dangerousPaths) {
      if (lowerPath.startsWith(dangerous)) return false;
    }
    
    return true;
  }

  /// Validate app name
  static bool isValidAppName(String? name) {
    if (name == null || name.isEmpty) return false;
    if (name.length > 100) return false;
    // Allow alphanumeric, space, dash only (no underscores or dots)
    return RegExp(r'^[a-zA-Z0-9\s\-]+$').hasMatch(name);
  }

  /// Validate version string (semantic versioning)
  static bool isValidVersion(String? version) {
    if (version == null || version.isEmpty) return false;
    // Basic semantic version pattern: X.Y.Z or X.Y.Z-prerelease
    return RegExp(r'^\d+\.\d+\.\d+(-[a-zA-Z0-9\.\-]+)?$').hasMatch(version);
  }

  /// Validate email address
  static bool isValidEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    // Basic email validation
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  /// Validate email or throw exception
  static void validateEmailOrThrow(String? email) {
    if (!isValidEmail(email)) {
      throw MCPValidationException('Invalid email format', {});
    }
  }

  /// Validate JSON string
  static bool isValidJson(String? json) {
    if (json == null || json.isEmpty) return false;
    
    try {
      // Check if it starts with valid JSON characters
      final trimmed = json.trim();
      if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
        return false;
      }
      
      // Basic validation - check for matching brackets and quotes
      int bracketCount = 0;
      int bracketSquareCount = 0;
      int quoteCount = 0;
      bool inString = false;
      bool hasColon = false;
      
      for (int i = 0; i < trimmed.length; i++) {
        final char = trimmed[i];
        
        if (char == '"' && (i == 0 || trimmed[i-1] != '\\')) {
          inString = !inString;
          quoteCount++;
        }
        
        if (!inString) {
          if (char == '{') {
            bracketCount++;
          } else if (char == '}') {
            bracketCount--;
          } else if (char == '[') {
            bracketSquareCount++;
          } else if (char == ']') {
            bracketSquareCount--;
          } else if (char == ':') {
            hasColon = true;
          }
        }
      }
      
      // For objects, must have even number of quotes (key-value pairs)
      // and at least one colon
      if (trimmed.startsWith('{')) {
        if (!hasColon) return false;
        if (quoteCount % 2 != 0) return false;
      }
      
      return bracketCount == 0 && bracketSquareCount == 0;
    } catch (e) {
      return false;
    }
  }

  /// Sanitize string by removing dangerous characters
  static String sanitizeString(String? input) {
    if (input == null) return '';
    
    String result = input;
    
    // Remove script tags and their content first
    result = result.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    
    // Remove all HTML tags
    result = result.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // Remove SQL injection characters
    result = result.replaceAll(';', '').replaceAll("'", '').replaceAll('"', '').replaceAll('\\', '');
    
    // Remove other dangerous patterns
    result = result.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return result;
  }

  /// Validate string length
  static bool isValidLength(String? str, {int minLength = 0, int? maxLength}) {
    final length = str?.length ?? 0;
    if (length < minLength) return false;
    if (maxLength != null && length > maxLength) return false;
    return true;
  }

  /// Validate number range
  static bool isValidNumberRange(num? value, {num? min, num? max}) {
    if (value == null) return false;
    if (min != null && value < min) return false;
    if (max != null && value > max) return false;
    return true;
  }

  /// Validate required fields in a map
  static void validateRequired(Map<String, dynamic> data) {
    final missingFields = <String>[];
    
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null || 
          (value is String && value.isEmpty) ||
          (value is List && value.isEmpty) ||
          (value is Map && value.isEmpty)) {
        missingFields.add(entry.key);
      }
    }
    
    if (missingFields.isNotEmpty) {
      throw MCPValidationException(
        'Missing required fields: ${missingFields.join(', ')}',
        {'missingFields': missingFields},
      );
    }
  }
}