import 'dart:async';
import 'dart:math' as math;
import 'logger.dart';
import 'exceptions.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

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
    Exception? lastException;

    while (true) {
      attempt++;

      try {
        // Execute the operation
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
        if (e is Exception) {
          lastException = e;

          if (retryIf != null && !retryIf(e)) {
            _logger.error('$name failed with non-retryable exception', e, stackTrace);
            throw MCPOperationFailedException(
              'Failed to complete $name with non-retryable exception',
              e,
              stackTrace,
            );
          }
        } else {
          // For non-Exception errors (like Error types), don't retry
          _logger.error('$name failed with non-Exception error', e, stackTrace);
          rethrow;
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
          lastException,
        );

        // Wait before retry
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

  /// Execute operation with jitter for distributed systems
  static Future<T> tryWithJitter<T>(
      Future<T> Function() operation, {
        Duration baseDelay = const Duration(milliseconds: 100),
        double jitterFactor = 0.5,
        String? operationName,
      }) async {
    final name = operationName ?? 'operation';
    final random = math.Random();

    // Apply jitter to delay
    final jitterMs = (baseDelay.inMilliseconds * jitterFactor * random.nextDouble()).toInt();
    final delay = Duration(milliseconds: baseDelay.inMilliseconds + jitterMs);

    // Wait for jitter delay
    await Future.delayed(delay);

    try {
      return await operation();
    } catch (e, stackTrace) {
      _logger.error('$name failed after jitter delay', e, stackTrace);
      throw MCPOperationFailedException(
        'Failed to complete $name after jitter delay',
        e,
        stackTrace,
      );
    }
  }

  /// Execute operation with saga pattern (compensation actions on failure)
  static Future<T> tryWithCompensation<T>(
      Future<T> Function() operation,
      Future<void> Function() compensationAction, {
        String? operationName,
      }) async {
    final name = operationName ?? 'operation';

    try {
      return await operation();
    } catch (e, stackTrace) {
      _logger.error('$name failed, executing compensation action', e, stackTrace);

      try {
        await compensationAction();
        _logger.info('Compensation action for $name completed successfully');
      } catch (compensationError, compensationStackTrace) {
        _logger.error(
          'Compensation action for $name also failed',
          compensationError,
          compensationStackTrace,
        );
      }

      throw MCPOperationFailedException(
        'Failed to complete $name and compensation action was executed',
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

    // Add jitter (±10%)
    final random = math.Random();
    final jitterFactor = 0.2 * random.nextDouble() - 0.1; // -10% to +10%
    final jitter = (exponentialPart * jitterFactor).toInt();
    final delayMs = exponentialPart + jitter;

    // Enforce maxDelay if provided
    if (maxDelay != null && delayMs > maxDelay.inMilliseconds) {
      return maxDelay;
    }

    return Duration(milliseconds: delayMs);
  }

  /// Wrap synchronous code with error handling
  static T tryCatch<T>(
      T Function() operation, {
        T Function(Exception)? onException,
        String? operationName,
      }) {
    final name = operationName ?? 'operation';

    try {
      return operation();
    } catch (e, stackTrace) {
      _logger.error('$name failed', e, stackTrace);

      if (e is Exception && onException != null) {
        return onException(e);
      }

      if (e is Exception) {
        throw MCPOperationFailedException(
          'Failed to complete $name',
          e,
          stackTrace,
        );
      }

      rethrow;
    }
  }

  /// Log and re-throw any exception
  static Future<T> logAndRethrow<T>(
      Future<T> Function() operation, {
        String? operationName,
        bool includeStackTrace = true,
      }) async {
    final name = operationName ?? 'operation';

    try {
      return await operation();
    } catch (e, stackTrace) {
      if (includeStackTrace) {
        _logger.error('$name failed', e, stackTrace);
      } else {
        _logger.error('$name failed: ${e.toString()}');
      }

      // Add debugging info in debug mode
      if (kDebugMode) {
        print('Error in $name: $e');
        print('Stack trace: $stackTrace');
      }

      rethrow;
    }
  }
}

/// Exception for CircuitBreaker open state
class MCPCircuitBreakerOpenException extends MCPException {
  MCPCircuitBreakerOpenException(super.message, [super.originalError, super.stackTrace]);
}

/// Circuit breaker states
enum CircuitBreakerState {
  closed,
  open,
  halfOpen,
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