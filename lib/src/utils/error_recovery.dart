import 'dart:async';
import 'logger.dart';
import '../utils/exceptions.dart';

/// Error recovery utility for handling retries and fallbacks
class ErrorRecovery {
  static final MCPLogger _logger = MCPLogger('mcp.error_recovery');

  /// Try an operation with automatic retries
  static Future<T> tryWithRetry<T>(
      Future<T> Function() operation, {
        int maxRetries = 3,
        Duration initialDelay = const Duration(milliseconds: 500),
        bool useExponentialBackoff = true,
        Duration? maxDelay,
        String? operationName,
        bool Function(Exception)? retryIf,
      }) async {
    final name = operationName ?? 'operation';
    int attempt = 0;

    while (true) {
      attempt++;

      try {
        return await operation();
      } catch (e, stackTrace) {
        // If we've reached max retries, rethrow
        if (attempt > maxRetries) {
          _logger.error('$name failed after $maxRetries attempts', e, stackTrace);
          if (e is Exception) {
            throw MCPOperationFailedException(
              'Failed to complete $name after $maxRetries attempts',
              e,
              stackTrace,
            );
          } else {
            rethrow;
          }
        }

        // Check if we should retry this exception
        if (retryIf != null && e is Exception && !retryIf(e)) {
          _logger.error('$name failed with non-retryable exception', e, stackTrace);
          throw MCPOperationFailedException(
            'Failed to complete $name with non-retryable exception',
            e,
            stackTrace,
          );
        }

        // Calculate delay for next retry
        final delay = _calculateDelay(
          attempt: attempt,
          initialDelay: initialDelay,
          useExponentialBackoff: useExponentialBackoff,
          maxDelay: maxDelay,
        );

        _logger.warning(
          '$name failed, retrying in ${delay.inMilliseconds}ms '
              '(attempt $attempt of $maxRetries)',
          e,
        );

        await Future.delayed(delay);
      }
    }
  }

  /// Try an operation with fallback
  static Future<T> tryWithFallback<T>(
      Future<T> Function() primaryOperation,
      Future<T> Function() fallbackOperation, {
        String? operationName,
      }) async {
    final name = operationName ?? 'operation';

    try {
      return await primaryOperation();
    } catch (e, stackTrace) {
      _logger.warning(
        '$name failed, falling back to alternative implementation',
        e,
      );

      try {
        return await fallbackOperation();
      } catch (fallbackError, fallbackStackTrace) {
        _logger.error(
          '$name fallback also failed',
          fallbackError,
          fallbackStackTrace,
        );

        throw MCPOperationFailedException(
          'Both primary and fallback $name failed',
          fallbackError,
          fallbackStackTrace,
          originalError: e,
          originalStackTrace: stackTrace,
        );
      }
    }
  }

  /// Perform an operation with a timeout
  static Future<T> tryWithTimeout<T>(
      Future<T> Function() operation,
      Duration timeout, {
        FutureOr<T> Function()? onTimeout,
        String? operationName,
      }) async {
    final name = operationName ?? 'operation';

    try {
      return await operation().timeout(
        timeout,
        onTimeout: onTimeout != null
            ? () async => await onTimeout()
            : () {
          throw TimeoutException('$name timed out after ${timeout.inMilliseconds}ms');
        },
      );
    } catch (e, stackTrace) {
      if (e is TimeoutException) {
        _logger.error('$name timed out after ${timeout.inMilliseconds}ms');
        throw MCPTimeoutException(
          '$name timed out after ${timeout.inMilliseconds}ms',
          timeout,
        );
      } else {
        _logger.error('$name failed', e, stackTrace);
        throw MCPOperationFailedException(
          'Failed to complete $name',
          e,
          stackTrace,
        );
      }
    }
  }

  /// Try an operation with circuit breaker pattern
  static Future<T> tryWithCircuitBreaker<T>(
      Future<T> Function() operation,
      CircuitBreaker circuitBreaker, {
        String? operationName,
      }) async {
    final name = operationName ?? 'operation';

    if (!circuitBreaker.allowRequest) {
      _logger.warning('Circuit breaker open, skipping $name');
      throw MCPCircuitBreakerOpenException(
        'Circuit breaker is open, request for $name rejected',
      );
    }

    try {
      final result = await operation();
      circuitBreaker.recordSuccess();
      return result;
    } catch (e, stackTrace) {
      circuitBreaker.recordFailure();
      _logger.error('$name failed, circuit breaker state: ${circuitBreaker.state}', e);
      throw MCPOperationFailedException(
        'Failed to complete $name',
        e,
        stackTrace,
      );
    }
  }

  /// Calculate delay for retry with optional exponential backoff
  static Duration _calculateDelay({
    required int attempt,
    required Duration initialDelay,
    required bool useExponentialBackoff,
    Duration? maxDelay,
  }) {
    if (!useExponentialBackoff) {
      return initialDelay;
    }

    // Exponential backoff with jitter
    final exponentialPart = initialDelay.inMilliseconds * (1 << (attempt - 1));
    final jitter = (DateTime.now().millisecondsSinceEpoch % 100) - 50; // -50 to +49 ms
    final delayMs = exponentialPart + jitter;

    // Enforce maxDelay if provided
    if (maxDelay != null && delayMs > maxDelay.inMilliseconds) {
      return maxDelay;
    }

    return Duration(milliseconds: delayMs);
  }
}

/// Circuit breaker implementation
class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration resetTimeout;
  final int successThreshold;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastStateChange;

  final MCPLogger _logger = MCPLogger('mcp.circuit_breaker');

  CircuitBreaker({
    required this.name,
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    this.successThreshold = 3,
  }) {
    _lastStateChange = DateTime.now();
  }

  /// Current circuit breaker state
  CircuitBreakerState get state => _state;

  /// Whether requests are allowed to proceed
  bool get allowRequest {
    // If closed, always allow
    if (_state == CircuitBreakerState.closed) {
      return true;
    }

    // If half-open, allow trials
    if (_state == CircuitBreakerState.halfOpen) {
      return true;
    }

    // If open, check if reset timeout has elapsed
    final now = DateTime.now();
    if (_state == CircuitBreakerState.open &&
        _lastStateChange != null &&
        now.difference(_lastStateChange!) >= resetTimeout) {
      _transitionToHalfOpen();
      return true;
    }

    // In open state and timeout not elapsed
    return false;
  }

  /// Record a successful operation
  void recordSuccess() {
    if (_state == CircuitBreakerState.halfOpen) {
      _successCount++;
      if (_successCount >= successThreshold) {
        _transitionToClosed();
      }
    } else if (_state == CircuitBreakerState.open) {
      // This shouldn't happen normally, but handle it anyway
      _transitionToHalfOpen();
      _successCount = 1;
    } else {
      // Reset failure count on success in closed state
      _failureCount = 0;
    }
  }

  /// Record a failed operation
  void recordFailure() {
    if (_state == CircuitBreakerState.closed) {
      _failureCount++;
      if (_failureCount >= failureThreshold) {
        _transitionToOpen();
      }
    } else if (_state == CircuitBreakerState.halfOpen) {
      _transitionToOpen();
    }
  }

  /// Reset the circuit breaker to closed state
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _successCount = 0;
    _lastStateChange = DateTime.now();
    _logger.info('Circuit breaker $name manually reset to CLOSED');
  }

  /// Transition to open state
  void _transitionToOpen() {
    _state = CircuitBreakerState.open;
    _lastStateChange = DateTime.now();
    _successCount = 0;
    _logger.warning('Circuit breaker $name transitioned to OPEN');
  }

  /// Transition to half-open state
  void _transitionToHalfOpen() {
    _state = CircuitBreakerState.halfOpen;
    _lastStateChange = DateTime.now();
    _successCount = 0;
    _logger.info('Circuit breaker $name transitioned to HALF-OPEN');
  }

  /// Transition to closed state
  void _transitionToClosed() {
    _state = CircuitBreakerState.closed;
    _lastStateChange = DateTime.now();
    _failureCount = 0;
    _successCount = 0;
    _logger.info('Circuit breaker $name transitioned to CLOSED');
  }
}

/// Circuit breaker states
enum CircuitBreakerState {
  closed,
  open,
  halfOpen,
}

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
  MCPCircuitBreakerOpenException(String message, [dynamic originalError, StackTrace? stackTrace])
      : super(message, originalError, stackTrace);
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