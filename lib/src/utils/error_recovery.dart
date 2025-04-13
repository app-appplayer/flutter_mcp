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
        void Function(int attempt, Exception error)? onRetry, // 추가된 부분
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

          // 추가된 onRetry 콜백
          if (onRetry != null) {
            onRetry(attempt - 1, lastException);
          }

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

  /// Try an operation with detailed exponential backoff and retry strategy
  static Future<T> tryWithExponentialBackoff<T>(
      Future<T> Function() operation, {
        int maxRetries = 3,
        Duration initialDelay = const Duration(milliseconds: 500),
        double backoffFactor = 2.0,  // 추가된 부분
        Duration? maxDelay,
        Duration? timeout,
        bool Function(Exception)? retryIf,
        String? operationName,
        void Function(int attempt, Exception e, Duration nextDelay)? onRetry,
      }) async {
    final name = operationName ?? 'operation';
    int attempt = 0;
    Exception? lastException;

    while (true) {
      attempt++;

      try {
        // Apply timeout if specified
        if (timeout != null) {
          return await tryWithTimeout(
              operation,
              timeout,
              operationName: name
          );
        }

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
          useExponentialBackoff: true,
          maxDelay: maxDelay,
          backoffFactor: backoffFactor,
        );

        // Invoke onRetry callback if provided
        if (onRetry != null) {
          onRetry(attempt, lastException, delay);
        }

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

  /// Calculate delay for retry with optional exponential backoff
  static Duration _calculateDelay({
    required int attempt,
    required Duration initialDelay,
    required bool useExponentialBackoff,
    Duration? maxDelay,
    double backoffFactor = 2.0,
  }) {
    if (!useExponentialBackoff) {
      return initialDelay;
    }

    // Exponential backoff with jitter
    final exponentialPart = (initialDelay.inMilliseconds * math.pow(backoffFactor, attempt - 1)).toInt();

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
