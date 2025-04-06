
/// Base MCP exception
class MCPException implements Exception {
  /// Error message
  final String message;

  /// Original error that caused this exception
  final dynamic originalError;

  /// Original stack trace
  final StackTrace? originalStackTrace;

  MCPException(this.message, [this.originalError, this.originalStackTrace]);

  @override
  String toString() {
    if (originalError != null) {
      return 'MCPException: $message (Original error: $originalError)';
    }
    return 'MCPException: $message';
  }
}

/// Initialization error
class MCPInitializationException extends MCPException {
  MCPInitializationException(String message, [dynamic originalError, StackTrace? stackTrace])
      : super('Initialization error: $message', originalError, stackTrace);
}

/// Platform not supported error
class MCPPlatformNotSupportedException extends MCPException {
  /// Platform feature that's not supported
  final String feature;

  MCPPlatformNotSupportedException(this.feature)
      : super('Platform does not support the feature: $feature');
}

/// Configuration error
class MCPConfigurationException extends MCPException {
  MCPConfigurationException(String message, [dynamic originalError, StackTrace? stackTrace])
      : super('Configuration error: $message', originalError, stackTrace);
}

/// Network error
class MCPNetworkException extends MCPException {
  /// HTTP status code (if applicable)
  final int? statusCode;

  /// Response body (if available)
  final String? responseBody;

  MCPNetworkException(
      String message, {
        this.statusCode,
        this.responseBody,
        dynamic originalError,
        StackTrace? stackTrace,
      }) : super(
    'Network error: $message${statusCode != null ? ' (Status: $statusCode)' : ''}',
    originalError,
    stackTrace,
  );
}

/// Authentication error
class MCPAuthenticationException extends MCPException {
  MCPAuthenticationException(String message, [dynamic originalError, StackTrace? stackTrace])
      : super('Authentication error: $message', originalError, stackTrace);
}

/// Operation failed error
class MCPOperationFailedException extends MCPException {
  /// Inner error that caused this exception
  final dynamic innerError;

  /// Inner error stack trace
  final StackTrace? innerStackTrace;

  MCPOperationFailedException(
      String message,
      this.innerError,
      this.innerStackTrace, {
        dynamic originalError,
        StackTrace? originalStackTrace,
      }) : super(message, originalError, originalStackTrace);

  @override
  String toString() {
    final baseMessage = 'MCPOperationFailedException: $message';
    if (innerError != null) {
      return '$baseMessage (Inner error: $innerError)';
    }
    return baseMessage;
  }
}

/// Timeout error
class MCPTimeoutException extends MCPException {
  /// Duration of the timeout
  final Duration timeout;

  MCPTimeoutException(String message, this.timeout, [dynamic originalError, StackTrace? stackTrace])
      : super(message, originalError, stackTrace);
}

/// Circuit breaker open error
class MCPCircuitBreakerOpenException extends MCPException {
  MCPCircuitBreakerOpenException(super.message, [super.originalError, super.stackTrace]);
}

/// Plugin error
class MCPPluginException extends MCPException {
  /// Name of the plugin
  final String pluginName;

  MCPPluginException(this.pluginName, String message, [dynamic originalError, StackTrace? stackTrace])
      : super('Plugin $pluginName error: $message', originalError, stackTrace);
}

/// Resource not found error
class MCPResourceNotFoundException extends MCPException {
  /// Resource ID
  final String resourceId;

  MCPResourceNotFoundException(this.resourceId, [String? additionalInfo])
      : super(
    'Resource not found: $resourceId${additionalInfo != null ? ' ($additionalInfo)' : ''}',
  );
}

/// Validation error
class MCPValidationException extends MCPException {
  /// Validation errors map
  final Map<String, String> validationErrors;

  MCPValidationException(String message, this.validationErrors)
      : super('Validation error: $message');

  @override
  String toString() {
    final base = 'MCPValidationException: $message';
    if (validationErrors.isEmpty) {
      return base;
    }

    final errors = validationErrors.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

    return '$base [Validation errors: $errors]';
  }
}

/// Operation cancelled exception
class MCPOperationCancelledException extends MCPException {
  MCPOperationCancelledException(super.message, [super.originalError, super.stackTrace]);
}