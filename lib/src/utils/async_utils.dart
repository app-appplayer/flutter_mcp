import 'dart:async';
import 'logger.dart';
import 'exceptions.dart';
import 'package:synchronized/synchronized.dart' show Lock;

/// Utility class for managing asynchronous operations with advanced error handling
class AsyncUtils {
  static final MCPLogger _logger = MCPLogger('mcp.async_utils');

  /// A map to track operations in progress
  static final Map<String, Completer<dynamic>> _operations = {};

  /// Locks for thread-safe operations
  static final Map<String, Lock> _locks = {};

  /// Execute an operation with retry capability
  static Future<T> executeWithRetry<T>(
      Future<T> Function() operation, {
        String operationName = 'operation',
        int maxRetries = 3,
        Duration initialDelay = const Duration(milliseconds: 500),
        bool useExponentialBackoff = true,
        Duration? maxDelay,
        bool Function(Exception)? retryIf,
      }) async {
    int attempt = 0;

    while (true) {
      attempt++;

      try {
        return await operation();
      } catch (e, stackTrace) {
        // If we've reached max retries, rethrow
        if (attempt > maxRetries) {
          _logger.error('$operationName failed after $maxRetries attempts', e, stackTrace);
          throw MCPOperationFailedException(
            'Failed to complete $operationName after $maxRetries attempts',
            e,
            stackTrace,
          );
        }

        // Check if we should retry this exception
        if (retryIf != null && e is Exception && !retryIf(e)) {
          _logger.error('$operationName failed with non-retryable exception', e, stackTrace);
          throw MCPOperationFailedException(
            'Failed to complete $operationName with non-retryable exception',
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
          '$operationName failed, retrying in ${delay.inMilliseconds}ms '
              '(attempt $attempt of $maxRetries)',
          e,
        );

        await Future.delayed(delay);
      }
    }
  }

  /// Execute operation with timeout
  static Future<T> executeWithTimeout<T>(
      Future<T> Function() operation,
      Duration timeout, {
        String operationName = 'operation',
        Future<T> Function()? onTimeout,
      }) async {
    try {
      return await operation().timeout(
        timeout,
        onTimeout: onTimeout != null
            ? () async => await onTimeout()
            : () {
          throw TimeoutException('$operationName timed out after ${timeout.inMilliseconds}ms');
        },
      );
    } catch (e, stackTrace) {
      if (e is TimeoutException) {
        _logger.error('$operationName timed out after ${timeout.inMilliseconds}ms');
        throw MCPTimeoutException(
          '$operationName timed out after ${timeout.inMilliseconds}ms',
          timeout,
        );
      } else {
        _logger.error('$operationName failed', e, stackTrace);
        throw MCPOperationFailedException(
          'Failed to complete $operationName',
          e,
          stackTrace,
        );
      }
    }
  }

  /// Execute operation with fallback
  static Future<T> executeWithFallback<T>(
      Future<T> Function() primaryOperation,
      Future<T> Function() fallbackOperation, {
        String operationName = 'operation',
      }) async {
    try {
      return await primaryOperation();
    } catch (e, stackTrace) {
      _logger.warning(
        '$operationName failed, falling back to alternative implementation',
        e,
      );

      try {
        return await fallbackOperation();
      } catch (fallbackError, fallbackStackTrace) {
        _logger.error(
          '$operationName fallback also failed',
          fallbackError,
          fallbackStackTrace,
        );

        throw MCPOperationFailedException(
          'Both primary and fallback $operationName failed',
          fallbackError,
          fallbackStackTrace,
          originalError: e,
          originalStackTrace: stackTrace,
        );
      }
    }
  }

  /// Execute operation with cancellation support
  static Future<T> executeWithCancellation<T>(
      Future<T> Function() operation,
      String operationId, {
        String operationName = 'operation',
        bool throwIfCancelled = true,
        T? valueIfCancelled,
      }) async {
    // Register operation
    final completer = Completer<T>();
    _operations[operationId] = completer;

    try {
      final result = await operation();

      // If not cancelled, complete and return the result
      if (!completer.isCompleted) {
        completer.complete(result);
        _operations.remove(operationId);
        return result;
      } else {
        // Operation was cancelled
        if (throwIfCancelled) {
          throw MCPOperationCancelledException('$operationName was cancelled');
        } else {
          return valueIfCancelled as T;
        }
      }
    } catch (e, stackTrace) {
      // If not cancelled, complete with error
      if (!completer.isCompleted) {
        completer.completeError(e, stackTrace);
        _operations.remove(operationId);
      }

      rethrow;
    }
  }

  /// Cancel an operation
  static void cancelOperation(String operationId) {
    final completer = _operations[operationId];

    if (completer != null && !completer.isCompleted) {
      _logger.debug('Cancelling operation: $operationId');
      completer.completeError(MCPOperationCancelledException('Operation cancelled'));
    }

    _operations.remove(operationId);
  }

  /// Execute with lock to ensure thread safety
  static Future<T> executeWithLock<T>(
      String lockName,
      Future<T> Function() operation, {
        String operationName = 'operation',
        Duration? timeout,
      }) async {
    // Create lock if it doesn't exist
    _locks.putIfAbsent(lockName, () => Lock());

    try {
      return await _locks[lockName]!.synchronized(() async {
        return await operation();
      }, timeout: timeout);
    } catch (e, stackTrace) {
      if (e is TimeoutException) {
        _logger.error('$operationName lock acquisition timed out', e, stackTrace);
        throw MCPTimeoutException(
          '$operationName lock acquisition timed out',
          timeout!,
        );
      } else {
        _logger.error('$operationName failed inside lock', e, stackTrace);
        throw MCPOperationFailedException(
          'Failed to complete $operationName inside lock',
          e,
          stackTrace,
        );
      }
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

  /// Run background task periodically
  static PeriodicTaskHandle runPeriodic(
      Future<void> Function() task,
      Duration interval, {
        String taskName = 'periodic task',
        bool runImmediately = false,
        Duration? timeout,
        bool skipIfStillRunning = true,
      }) {
    final taskId = 'periodic_${DateTime.now().millisecondsSinceEpoch}_${taskName.hashCode}';
    final lock = Lock();
    bool isRunning = false;
    Timer? timer;

    // Function to execute task safely
    Future<void> executeTask() async {
      // Skip if still running and configured to skip
      if (isRunning && skipIfStillRunning) {
        _logger.debug('Skipping $taskName as previous execution is still running');
        return;
      }

      // Execute task with lock
      try {
        await lock.synchronized(() async {
          isRunning = true;

          try {
            if (timeout != null) {
              await executeWithTimeout(
                task,
                timeout,
                operationName: taskName,
              );
            } else {
              await task();
            }
          } finally {
            isRunning = false;
          }
        });
      } catch (e, stackTrace) {
        _logger.error('Error executing $taskName', e, stackTrace);
      }
    }

    // Run immediately if configured
    if (runImmediately) {
      executeTask();
    }

    // Set up periodic timer
    timer = Timer.periodic(interval, (_) {
      executeTask();
    });

    // Return handle for cancellation
    return PeriodicTaskHandle(
      id: taskId,
      cancel: () {
        timer?.cancel();
        timer = null;
      },
    );
  }

  /// Run a debounced task (useful for user input or frequent events)
  static DebouncedTaskHandle debounce(
      Future<void> Function() task,
      Duration wait, {
        String taskName = 'debounced task',
      }) {
    final taskId = 'debounce_${DateTime.now().millisecondsSinceEpoch}_${taskName.hashCode}';
    Timer? timer;

    // Return handle with execute function
    return DebouncedTaskHandle(
      id: taskId,
      execute: () {
        // Cancel previous timer if still active
        timer?.cancel();

        // Set new timer
        timer = Timer(wait, () async {
          try {
            await task();
          } catch (e, stackTrace) {
            _logger.error('Error executing debounced $taskName', e, stackTrace);
          }
        });
      },
      cancel: () {
        timer?.cancel();
        timer = null;
      },
    );
  }

  /// Clean up all resources
  static void dispose() {
    // Cancel all operations
    for (final operationId in _operations.keys.toList()) {
      cancelOperation(operationId);
    }

    _operations.clear();
    _locks.clear();
  }
}

/// Handle for periodic tasks
class PeriodicTaskHandle {
  final String id;
  final void Function() cancel;

  PeriodicTaskHandle({
    required this.id,
    required this.cancel,
  });
}

/// Handle for debounced tasks
class DebouncedTaskHandle {
  final String id;
  final void Function() execute;
  final void Function() cancel;

  DebouncedTaskHandle({
    required this.id,
    required this.execute,
    required this.cancel,
  });
}

