
/// Base MCP exception with enhanced error context
class MCPException implements Exception {
  /// Error message
  final String message;

  /// Original error that caused this exception
  final dynamic originalError;

  /// Original stack trace
  final StackTrace? originalStackTrace;
  
  /// Error code for programmatic handling
  final String? errorCode;
  
  /// Additional context for debugging
  final Map<String, dynamic>? context;
  
  /// Whether this error is recoverable
  final bool recoverable;
  
  /// Suggestions for resolving the error
  final String? resolution;

  MCPException(
    this.message, [
    this.originalError, 
    this.originalStackTrace,
  ]) : errorCode = null,
       context = null,
       recoverable = false,
       resolution = null;
       
  MCPException.withContext(
    this.message, {
    this.originalError,
    this.originalStackTrace,
    this.errorCode,
    this.context,
    this.recoverable = false,
    this.resolution,
  });

  @override
  String toString() {
    final buffer = StringBuffer('MCPException');
    
    if (errorCode != null) {
      buffer.write(' [$errorCode]');
    }
    
    buffer.write(': $message');
    
    if (originalError != null) {
      buffer.write(' (Original error: $originalError)');
    }
    
    if (resolution != null) {
      buffer.write('\nResolution: $resolution');
    }
    
    return buffer.toString();
  }
}

/// Initialization error
class MCPInitializationException extends MCPException {
  MCPInitializationException(
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super('Initialization error: $message', originalError, stackTrace);
  
  MCPInitializationException.withContext(
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Initialization error: $message', 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'INIT_ERROR',
    context: context,
    recoverable: recoverable,
    resolution: resolution,
  );
}

/// Platform not supported error
class MCPPlatformNotSupportedException extends MCPException {
  /// Platform feature that's not supported
  final String feature;

  MCPPlatformNotSupportedException(
    this.feature, {
    String? errorCode,
    Map<String, dynamic>? context,
    String? resolution,
  }) : super.withContext(
    'Platform does not support the feature: $feature',
    errorCode: errorCode ?? 'PLATFORM_UNSUPPORTED',
    context: {'feature': feature, ...?context},
    recoverable: false,
    resolution: resolution ?? 'Check if this feature is supported on your platform before using it',
  );
}

/// Configuration error
class MCPConfigurationException extends MCPException {
  MCPConfigurationException(
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super('Configuration error: $message', originalError, stackTrace);
  
  MCPConfigurationException.withContext(
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Configuration error: $message', 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'CONFIG_ERROR',
    context: context,
    recoverable: recoverable,
    resolution: resolution,
  );
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
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Network error: $message${statusCode != null ? ' (Status: $statusCode)' : ''}',
    originalError: originalError,
    originalStackTrace: stackTrace,
    errorCode: errorCode ?? 'NETWORK_ERROR',
    context: {
      if (statusCode != null) 'statusCode': statusCode,
      if (responseBody != null) 'responseBodyPreview': responseBody.length > 100 
          ? '${responseBody.substring(0, 100)}...' 
          : responseBody,
      ...?context,
    },
    recoverable: recoverable,
    resolution: resolution,
  );
}

/// Authentication error
class MCPAuthenticationException extends MCPException {
  MCPAuthenticationException(
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super('Authentication error: $message', originalError, stackTrace);
  
  MCPAuthenticationException.withContext(
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Authentication error: $message', 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'AUTH_ERROR',
    context: context,
    recoverable: recoverable,
    resolution: resolution,
  );
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
      this.innerStackTrace) : super(message, innerError, innerStackTrace);
      
  MCPOperationFailedException.withContext(
      String message,
      this.innerError,
      this.innerStackTrace, {
      String? errorCode,
      Map<String, dynamic>? context,
      bool recoverable = false,
      String? resolution,
  }) : super.withContext(
      message, 
      originalError: innerError,
      originalStackTrace: innerStackTrace,
      errorCode: errorCode ?? 'OPERATION_FAILED',
      context: context,
      recoverable: recoverable,
      resolution: resolution,
  );

  @override
  String toString() {
    final buffer = StringBuffer('MCPOperationFailedException');
    
    if (errorCode != null) {
      buffer.write(' [$errorCode]');
    }
    
    buffer.write(': $message');
    
    if (innerError != null) {
      buffer.write(' (Inner error: $innerError)');
    }
    
    if (resolution != null) {
      buffer.write('\nResolution: $resolution');
    }
    
    return buffer.toString();
  }
}

/// Timeout error
class MCPTimeoutException extends MCPException {
  /// Duration of the timeout
  final Duration timeout;

  MCPTimeoutException(
    String message, 
    this.timeout, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super(message, originalError, stackTrace);
  
  MCPTimeoutException.withContext(
    String message, 
    this.timeout, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    message, 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'TIMEOUT',
    context: {'timeoutMs': timeout.inMilliseconds, ...context ?? {}},
    recoverable: recoverable,
    resolution: resolution ?? 'Consider increasing the timeout duration or optimizing the operation',
  );
}

/// Circuit breaker open error
class MCPCircuitBreakerOpenException extends MCPException {
  /// Name of the circuit breaker
  final String? breakerName;
  
  /// When the circuit breaker was opened
  final DateTime openedAt;
  
  /// When the circuit breaker might reset
  final DateTime? resetAt;

  MCPCircuitBreakerOpenException(
    String message, {
    this.breakerName,
    DateTime? openedAt,
    this.resetAt,
    dynamic originalError,
    StackTrace? stackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
  }) : openedAt = openedAt ?? DateTime.now(),
       super.withContext(
        message, 
        originalError: originalError, 
        originalStackTrace: stackTrace,
        errorCode: errorCode ?? 'CIRCUIT_OPEN',
        context: {
          if (breakerName != null) 'breakerName': breakerName,
          ...?context,
        },
        recoverable: true,
        resolution: 'The circuit breaker is open due to previous failures. '
            'Try again ${resetAt != null ? 'after ${resetAt.toIso8601String()}' : 'later'} '
            'or check for underlying issues.',
    );
}

/// Plugin error
class MCPPluginException extends MCPException {
  /// Name of the plugin
  final String pluginName;

  MCPPluginException(
    this.pluginName, 
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super('Plugin $pluginName error: $message', originalError, stackTrace);
  
  MCPPluginException.withContext(
    this.pluginName, 
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Plugin $pluginName error: $message', 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'PLUGIN_ERROR',
    context: {'pluginName': pluginName, ...context ?? {}},
    recoverable: recoverable,
    resolution: resolution,
  );
}

/// Resource not found error
class MCPResourceNotFoundException extends MCPException {
  /// Resource ID
  final String resourceId;
  
  /// Resource type
  final String? resourceType;

  MCPResourceNotFoundException(
    this.resourceId, [
    String? additionalInfo,
  ]) : resourceType = null,
      super('Resource not found: $resourceId${additionalInfo != null ? ' ($additionalInfo)' : ''}');
  
  MCPResourceNotFoundException.withContext(
    this.resourceId, {
    String? additionalInfo,
    this.resourceType,
    String? errorCode,
    Map<String, dynamic>? context,
    String? resolution,
  }) : super.withContext(
    'Resource not found: $resourceId${additionalInfo != null ? ' ($additionalInfo)' : ''}',
    errorCode: errorCode ?? 'RESOURCE_NOT_FOUND',
    context: {
      'resourceId': resourceId,
      if (resourceType != null) 'resourceType': resourceType,
      if (additionalInfo != null) 'info': additionalInfo,
      ...context ?? {},
    },
    recoverable: false,
    resolution: resolution,
  );
}

/// Validation error
class MCPValidationException extends MCPException {
  /// Validation errors map
  final Map<String, dynamic> validationErrors;

  MCPValidationException(
    String message, 
    this.validationErrors, {
    String? errorCode,
    bool recoverable = true,
    String? resolution,
  }) : super.withContext(
    'Validation error: $message',
    errorCode: errorCode ?? 'VALIDATION_ERROR',
    context: {'validationErrors': validationErrors},
    recoverable: recoverable,
    resolution: resolution ?? 'Please check the provided inputs and try again',
  );

  @override
  String toString() {
    final buffer = StringBuffer('MCPValidationException');
    
    if (errorCode != null) {
      buffer.write(' [$errorCode]');
    }
    
    buffer.write(': $message');
    
    if (validationErrors.isNotEmpty) {
      final errors = validationErrors.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      
      buffer.write(' [Validation errors: $errors]');
    }
    
    if (resolution != null) {
      buffer.write('\nResolution: $resolution');
    }
    
    return buffer.toString();
  }
}

/// Operation cancelled exception
class MCPOperationCancelledException extends MCPException {
  MCPOperationCancelledException(
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super(message, originalError, stackTrace);
  
  MCPOperationCancelledException.withContext(
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    String? resolution,
  }) : super.withContext(
    message, 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'OPERATION_CANCELLED',
    context: context,
    recoverable: true,
    resolution: resolution ?? 'The operation was cancelled. You can retry the operation if needed.',
  );
}

/// Security-related exception
class MCPSecurityException extends MCPException {
  MCPSecurityException(
    String message, [
    dynamic originalError, 
    StackTrace? stackTrace,
  ]) : super('Security error: $message', originalError, stackTrace);
  
  MCPSecurityException.withContext(
    String message, {
    dynamic originalError, 
    StackTrace? originalStackTrace,
    String? errorCode,
    Map<String, dynamic>? context,
    bool recoverable = false,
    String? resolution,
  }) : super.withContext(
    'Security error: $message', 
    originalError: originalError, 
    originalStackTrace: originalStackTrace,
    errorCode: errorCode ?? 'SECURITY_ERROR',
    context: context,
    recoverable: recoverable,
    resolution: resolution,
  );
}