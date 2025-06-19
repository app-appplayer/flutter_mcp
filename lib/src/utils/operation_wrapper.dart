/// Operation wrapper utilities for consistent error handling and logging
library;

import 'dart:async';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../metrics/typed_metrics.dart';
import '../utils/performance_monitor.dart';

/// Result of an operation execution
class OperationResult<T> {
  final bool isSuccess;
  final T? data;
  final String? error;
  final Duration executionTime;
  final Object? originalException;
  final StackTrace? stackTrace;

  const OperationResult._({
    required this.isSuccess,
    this.data,
    this.error,
    required this.executionTime,
    this.originalException,
    this.stackTrace,
  });

  factory OperationResult.success(T data, Duration executionTime) {
    return OperationResult._(
      isSuccess: true,
      data: data,
      executionTime: executionTime,
    );
  }

  factory OperationResult.failure(
    String error,
    Duration executionTime, {
    Object? originalException,
    StackTrace? stackTrace,
  }) {
    return OperationResult._(
      isSuccess: false,
      error: error,
      executionTime: executionTime,
      originalException: originalException,
      stackTrace: stackTrace,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isSuccess': isSuccess,
      'data': data,
      'error': error,
      'executionTime': executionTime.inMilliseconds,
      'hasOriginalException': originalException != null,
    };
  }
}

/// Configuration for operation execution
class OperationConfig {
  final Duration? timeout;
  final int? maxRetries;
  final Duration? retryDelay;
  final bool recordMetrics;
  final String? errorCode;
  final bool throwOnError;
  final String? category;

  const OperationConfig({
    this.timeout,
    this.maxRetries,
    this.retryDelay,
    this.recordMetrics = true,
    this.errorCode,
    this.throwOnError = true,
    this.category,
  });

  static const OperationConfig defaultConfig = OperationConfig();

  static const OperationConfig quickOperation = OperationConfig(
    timeout: Duration(seconds: 5),
    recordMetrics: false,
  );

  static const OperationConfig longOperation = OperationConfig(
    timeout: Duration(minutes: 2),
    maxRetries: 3,
    retryDelay: Duration(seconds: 1),
  );

  static const OperationConfig criticalOperation = OperationConfig(
    timeout: Duration(seconds: 30),
    maxRetries: 5,
    retryDelay: Duration(milliseconds: 500),
    recordMetrics: true,
  );
}

/// Wrapper for executing operations with consistent error handling, logging, and metrics
class OperationWrapper {
  static final PerformanceMonitor _performanceMonitor =
      PerformanceMonitor.instance;

  /// Execute a synchronous operation with error handling and logging
  static OperationResult<T> execute<T>({
    required String operationName,
    required T Function() operation,
    required Logger logger,
    OperationConfig config = OperationConfig.defaultConfig,
  }) {
    final stopwatch = Stopwatch()..start();

    try {
      logger.fine('$operationName starting');

      final result = operation();

      stopwatch.stop();
      logger.fine(
          '$operationName completed in ${stopwatch.elapsedMilliseconds}ms');

      if (config.recordMetrics) {
        _recordMetric(operationName, stopwatch.elapsed, true, config);
      }

      return OperationResult.success(result, stopwatch.elapsed);
    } catch (e, stackTrace) {
      stopwatch.stop();

      final errorMessage = '$operationName failed: ${e.toString()}';
      logger.severe(errorMessage, e, stackTrace);

      if (config.recordMetrics) {
        _recordMetric(operationName, stopwatch.elapsed, false, config);
      }

      if (config.throwOnError) {
        throw MCPOperationFailedException.withContext(
          errorMessage,
          e,
          stackTrace,
          errorCode: config.errorCode,
        );
      }

      return OperationResult.failure(
        errorMessage,
        stopwatch.elapsed,
        originalException: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute an asynchronous operation with error handling, logging, and timeout
  static Future<OperationResult<T>> executeAsync<T>({
    required String operationName,
    required Future<T> Function() operation,
    required Logger logger,
    OperationConfig config = OperationConfig.defaultConfig,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      logger.fine('$operationName starting');

      Future<T> future = operation();

      // Apply timeout if specified
      if (config.timeout != null) {
        future = future.timeout(config.timeout!);
      }

      final result = await future;

      stopwatch.stop();
      logger.fine(
          '$operationName completed in ${stopwatch.elapsedMilliseconds}ms');

      if (config.recordMetrics) {
        _recordMetric(operationName, stopwatch.elapsed, true, config);
      }

      return OperationResult.success(result, stopwatch.elapsed);
    } catch (e, stackTrace) {
      stopwatch.stop();

      final errorMessage = '$operationName failed: ${e.toString()}';
      logger.severe(errorMessage, e, stackTrace);

      if (config.recordMetrics) {
        _recordMetric(operationName, stopwatch.elapsed, false, config);
      }

      if (config.throwOnError) {
        throw MCPOperationFailedException.withContext(
          errorMessage,
          e,
          stackTrace,
          errorCode: config.errorCode,
        );
      }

      return OperationResult.failure(
        errorMessage,
        stopwatch.elapsed,
        originalException: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute an operation with retry logic
  static Future<OperationResult<T>> executeWithRetry<T>({
    required String operationName,
    required Future<T> Function() operation,
    required Logger logger,
    OperationConfig config = OperationConfig.defaultConfig,
  }) async {
    final maxRetries = config.maxRetries ?? 0;
    final retryDelay = config.retryDelay ?? Duration(seconds: 1);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final attemptName = maxRetries > 0
          ? '$operationName (attempt ${attempt + 1}/${maxRetries + 1})'
          : operationName;

      final result = await executeAsync<T>(
        operationName: attemptName,
        operation: operation,
        logger: logger,
        config: config.copyWith(throwOnError: false),
      );

      if (result.isSuccess || attempt == maxRetries) {
        if (!result.isSuccess && config.throwOnError) {
          throw MCPOperationFailedException.withContext(
            result.error!,
            result.originalException,
            result.stackTrace,
            errorCode: config.errorCode,
          );
        }
        return result;
      }

      // Wait before retry
      if (attempt < maxRetries) {
        logger.warning(
            '$operationName failed, retrying in ${retryDelay.inMilliseconds}ms...');
        await Future.delayed(retryDelay);
      }
    }

    // This should never be reached
    throw StateError('Unexpected end of retry loop');
  }

  /// Execute multiple operations concurrently
  static Future<List<OperationResult<T>>> executeConcurrent<T>({
    required String groupName,
    required List<({String name, Future<T> Function() operation})> operations,
    required Logger logger,
    OperationConfig config = OperationConfig.defaultConfig,
    bool failFast = false,
  }) async {
    logger.fine(
        '$groupName: Starting ${operations.length} concurrent operations');

    final futures = operations.map((op) => executeAsync<T>(
          operationName: '$groupName.${op.name}',
          operation: op.operation,
          logger: logger,
          config: config.copyWith(throwOnError: false),
        ));

    if (failFast) {
      final results = await Future.wait(futures);
      final failed = results.where((r) => !r.isSuccess).toList();

      if (failed.isNotEmpty && config.throwOnError) {
        throw MCPOperationFailedException.withContext(
          '$groupName: ${failed.length} operations failed',
          null,
          null,
          errorCode: config.errorCode,
        );
      }

      return results;
    } else {
      // Wait for all to complete, even if some fail
      final results = await Future.wait(
        futures,
        eagerError: false,
      );

      final failed = results.where((r) => !r.isSuccess).toList();
      if (failed.isNotEmpty) {
        logger.warning(
            '$groupName: ${failed.length}/${results.length} operations failed');
      }

      return results;
    }
  }

  /// Record performance metric
  static void _recordMetric(String operationName, Duration duration,
      bool success, OperationConfig config) {
    final metric = TimerMetric(
      name: 'operation.execution',
      duration: duration,
      operation: operationName,
      success: success,
    );

    _performanceMonitor.recordTypedMetric(metric);
  }
}

/// Extension for OperationConfig to create copies with modifications
extension OperationConfigExtension on OperationConfig {
  OperationConfig copyWith({
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
    bool? recordMetrics,
    String? errorCode,
    bool? throwOnError,
    String? category,
  }) {
    return OperationConfig(
      timeout: timeout ?? this.timeout,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      recordMetrics: recordMetrics ?? this.recordMetrics,
      errorCode: errorCode ?? this.errorCode,
      throwOnError: throwOnError ?? this.throwOnError,
      category: category ?? this.category,
    );
  }
}

/// Mixin for adding operation wrapper functionality to classes
mixin OperationWrapperMixin {
  Logger get logger;

  /// Execute a synchronous operation
  OperationResult<T> executeOperation<T>({
    required String operationName,
    required T Function() operation,
    OperationConfig config = OperationConfig.defaultConfig,
  }) {
    return OperationWrapper.execute<T>(
      operationName: operationName,
      operation: operation,
      logger: logger,
      config: config,
    );
  }

  /// Execute an asynchronous operation
  Future<OperationResult<T>> executeAsyncOperation<T>({
    required String operationName,
    required Future<T> Function() operation,
    OperationConfig config = OperationConfig.defaultConfig,
  }) {
    return OperationWrapper.executeAsync<T>(
      operationName: operationName,
      operation: operation,
      logger: logger,
      config: config,
    );
  }

  /// Execute operation with retry
  Future<OperationResult<T>> executeWithRetry<T>({
    required String operationName,
    required Future<T> Function() operation,
    OperationConfig config = OperationConfig.defaultConfig,
  }) {
    return OperationWrapper.executeWithRetry<T>(
      operationName: operationName,
      operation: operation,
      logger: logger,
      config: config,
    );
  }
}
