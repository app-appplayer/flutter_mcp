import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart' show Lock;
import '../config/app_config.dart';
import 'exceptions.dart';
import 'logger.dart';

/// Utility class for managing asynchronous operations
class AsyncUtils {
  static final Logger _logger = Logger('flutter_mcp.async_utils');

  // Track operations in progress by ID
  static final Map<String, Completer<dynamic>> _operations =
      <String, Completer<dynamic>>{};

  // Locks for thread-safe operations by ID
  static final Map<String, Lock> _locks = <String, Lock>{};

  /// Execute an operation with retry capability and exponential backoff
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    String operationName = 'operation',
    int? maxRetries,
    Duration? initialDelay,
    bool useExponentialBackoff = true,
    Duration? maxDelay,
    bool Function(Exception)? retryIf,
  }) async {
    // Get configuration values
    final config = AppConfig.instance.scoped('async');
    maxRetries ??= config.get<int>('defaultMaxRetries', defaultValue: 3);
    initialDelay ??= config.getDuration('defaultInitialDelay',
        defaultValue: const Duration(milliseconds: 500));
    final backoffFactor =
        config.get<double>('defaultBackoffFactor', defaultValue: 2.0);

    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (attempt < maxRetries) {
      attempt++;

      try {
        final result = await operation();
        if (attempt > 1) {
          _logger
              .info('Operation "$operationName" succeeded on attempt $attempt');
        }
        return result;
      } on Exception catch (e) {
        final shouldRetry = retryIf?.call(e) ?? true;

        if (attempt >= maxRetries || !shouldRetry) {
          _logger.severe(
              'Operation "$operationName" failed after $attempt attempts', e);
          rethrow;
        }

        _logger.warning(
            'Operation "$operationName" failed on attempt $attempt, retrying in ${currentDelay.inMilliseconds}ms: $e');

        // Wait before retrying with jitter
        await Future.delayed(_addJitter(currentDelay));

        // Update delay for next iteration
        if (useExponentialBackoff) {
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * backoffFactor).round(),
          );
          if (maxDelay != null && currentDelay > maxDelay) {
            currentDelay = maxDelay;
          }
        }
      }
    }

    // If we've exhausted all retries, this should have been caught above,
    // but adding for completeness
    throw Exception(
        'Operation "$operationName" failed after $maxRetries attempts');
  }

  /// Add jitter to delay to avoid thundering herd problem
  static Duration _addJitter(Duration delay) {
    final config = AppConfig.instance.scoped('async');
    final jitterRange = config.get<int>('defaultJitterRange', defaultValue: 50);
    final random = math.Random();
    final jitter = random.nextInt(jitterRange * 2) - jitterRange;
    return Duration(
      milliseconds: math.max(0, delay.inMilliseconds + jitter),
    );
  }

  /// Execute operation with a unique lock to prevent concurrent execution
  static Future<T> executeWithLock<T>(
    String lockId,
    Future<T> Function() operation, {
    Duration? timeout,
  }) async {
    final lock = _locks.putIfAbsent(lockId, () => Lock());

    try {
      return await lock.synchronized(() async {
        if (timeout != null) {
          return await operation().timeout(timeout);
        } else {
          return await operation();
        }
      });
    } catch (e) {
      _logger.severe('Locked operation "$lockId" failed', e);
      rethrow;
    }
  }

  /// Execute operation with timeout and proper error handling
  static Future<T> executeWithTimeout<T>(
    Future<T> Function() operation,
    Duration timeout, {
    String operationName = 'operation',
    T? fallback,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException catch (e) {
      final errorMessage =
          'Operation "$operationName" timed out after ${timeout.inMilliseconds}ms';
      _logger.warning(errorMessage);

      if (fallback != null) {
        _logger.info('Using fallback value for "$operationName"');
        return fallback;
      }

      throw MCPTimeoutException.withContext(
        errorMessage,
        timeout,
        originalError: e,
        errorCode: 'OPERATION_TIMEOUT',
        recoverable: true,
      );
    }
  }

  /// Track a long-running operation by ID
  static Future<T> trackOperation<T>(
    String operationId,
    Future<T> Function() operation, {
    Duration? timeout,
  }) async {
    if (_operations.containsKey(operationId)) {
      throw MCPOperationFailedException.withContext(
        'Operation with ID "$operationId" is already in progress',
        null,
        null,
        errorCode: 'OPERATION_IN_PROGRESS',
        recoverable: false,
      );
    }

    final completer = Completer<T>();
    _operations[operationId] = completer;

    try {
      final future = operation();
      final result =
          timeout != null ? await future.timeout(timeout) : await future;

      completer.complete(result);
      return result;
    } catch (e, stackTrace) {
      completer.completeError(e, stackTrace);
      rethrow;
    } finally {
      _operations.remove(operationId);
    }
  }

  /// Cancel a tracked operation by ID
  static bool cancelOperation(String operationId) {
    final completer = _operations.remove(operationId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        MCPOperationCancelledException.withContext(
          'Operation "$operationId" was cancelled',
          errorCode: 'OPERATION_CANCELLED',
        ),
      );
      return true;
    }
    return false;
  }

  /// Get list of currently running operation IDs
  static List<String> getRunningOperations() {
    return _operations.keys.toList();
  }

  /// Check if a specific operation is running
  static bool isOperationRunning(String operationId) {
    return _operations.containsKey(operationId);
  }

  /// Wait for multiple operations to complete
  static Future<List<T>> waitForAll<T>(
    List<Future<T>> futures, {
    Duration? timeout,
    bool failFast = true,
  }) async {
    try {
      final future = failFast
          ? Future.wait(futures)
          : Future.wait(futures, eagerError: false);

      if (timeout != null) {
        return await future.timeout(timeout);
      } else {
        return await future;
      }
    } on TimeoutException catch (e) {
      throw MCPTimeoutException.withContext(
        'Waiting for ${futures.length} operations timed out',
        timeout!,
        originalError: e,
        errorCode: 'MULTI_OPERATION_TIMEOUT',
        recoverable: true,
      );
    }
  }

  /// Execute operations with controlled concurrency
  static Future<List<T>> executeConcurrently<T>(
    List<Future<T> Function()> operations, {
    int maxConcurrency = 3,
    Duration? operationTimeout,
  }) async {
    if (operations.isEmpty) return <T>[];

    final results = <T>[]..length = operations.length;
    final semaphore = Semaphore(maxConcurrency);

    final futures = operations.asMap().entries.map((entry) async {
      final index = entry.key;
      final operation = entry.value;

      await semaphore.acquire();
      try {
        final future = operation();
        final result = operationTimeout != null
            ? await future.timeout(operationTimeout)
            : await future;
        results[index] = result;
      } finally {
        semaphore.release();
      }
    });

    await Future.wait(futures);
    return results;
  }

  /// Create a debounced function that delays execution
  static Timer Function() debounce(
    void Function() function,
    Duration delay,
  ) {
    Timer? timer;

    return () {
      timer?.cancel();
      timer = Timer(delay, function);
      return timer!;
    };
  }

  /// Create a throttled function that limits execution frequency
  static void Function() throttle(
    void Function() function,
    Duration interval,
  ) {
    DateTime? lastExecution;

    return () {
      final now = DateTime.now();
      if (lastExecution == null || now.difference(lastExecution!) >= interval) {
        lastExecution = now;
        function();
      }
    };
  }

  /// Clean up resources (mainly for testing)
  @visibleForTesting
  static void cleanup() {
    // Cancel all pending operations
    for (final completer in _operations.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          MCPOperationCancelledException(
              'System cleanup - operation cancelled'),
        );
      }
    }

    _operations.clear();
    _locks.clear();
  }

  /// Get statistics about async operations
  static Map<String, dynamic> getStatistics() {
    return {
      'runningOperations': _operations.length,
      'activeLocks': _locks.length,
      'operationIds': _operations.keys.toList(),
    };
  }
}

/// Simple semaphore implementation for controlling concurrency
class Semaphore {
  final int _maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this._maxCount) : _currentCount = _maxCount;

  /// Maximum permits available
  int get maxCount => _maxCount;

  /// Acquire a permit
  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  /// Release a permit
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }

  /// Current available permits
  int get availablePermits => _currentCount;

  /// Number of threads waiting for permits
  int get queueLength => _waitQueue.length;
}
