/// Unified error handling system for consistent error management across the codebase
library;

import 'dart:async';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../events/event_models.dart';
import '../events/event_builder.dart';
import '../utils/performance_monitor.dart';

/// Unified error handler that provides consistent error handling across the codebase
class UnifiedErrorHandler {
  static final Logger _logger = Logger('flutter_mcp.UnifiedErrorHandler');
  static final PerformanceMonitor _performanceMonitor =
      PerformanceMonitor.instance;

  /// Global error handler for uncaught exceptions
  static void handleUncaughtError(Object error, StackTrace stackTrace) {
    _logger.severe('Uncaught error: $error', error, stackTrace);

    // Publish error event
    EventBuilder.publishErrorEvent(
      errorCode: 'UNCAUGHT_ERROR',
      message: error.toString(),
      component: 'global',
      severity: ErrorSeverity.critical,
      stackTrace: stackTrace.toString(),
      context: {
        'errorType': error.runtimeType.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Record metric for monitoring
    _performanceMonitor.recordCustomMetric(
      name: 'error.uncaught',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle MCP-specific exceptions with context
  static void handleMcpException(
    MCPException exception, {
    String? component,
    Map<String, dynamic>? additionalContext,
  }) {
    final severity = _getSeverityForException(exception);
    final errorComponent =
        component ?? exception.context?['component'] ?? 'unknown';

    _logger.log(
      _getLogLevelForSeverity(severity),
      'MCP Exception in $errorComponent: ${exception.message}',
      exception.originalError,
      exception.originalStackTrace,
    );

    // Publish detailed error event
    EventBuilder.publishErrorEvent(
      errorCode: exception.errorCode ?? 'MCP_EXCEPTION',
      message: exception.message,
      component: errorComponent,
      severity: severity,
      stackTrace: exception.originalStackTrace?.toString(),
      context: {
        'recoverable': exception.recoverable,
        'resolution': exception.resolution,
        'originalError': exception.originalError?.toString(),
        ...?exception.context,
        ...?additionalContext,
      },
    );

    // Record metric
    _performanceMonitor.recordCustomMetric(
      name: 'error.mcp_exception',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle platform-specific errors
  static void handlePlatformError(
    Object error, {
    String? platform,
    String? operation,
    Map<String, dynamic>? context,
  }) {
    final errorMessage = error.toString();
    final errorComponent = platform != null ? 'platform_$platform' : 'platform';

    _logger.severe('Platform error in $errorComponent: $errorMessage', error);

    EventBuilder.publishErrorEvent(
      errorCode: 'PLATFORM_ERROR',
      message: errorMessage,
      component: errorComponent,
      severity: ErrorSeverity.high,
      context: {
        'platform': platform,
        'operation': operation,
        'errorType': error.runtimeType.toString(),
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.platform',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle network-related errors
  static void handleNetworkError(
    Object error, {
    String? endpoint,
    int? statusCode,
    String? method,
    Map<String, dynamic>? context,
  }) {
    final errorMessage = error.toString();

    _logger.warning('Network error: $errorMessage', error);

    EventBuilder.publishErrorEvent(
      errorCode: 'NETWORK_ERROR',
      message: errorMessage,
      component: 'network',
      severity: ErrorSeverity.medium,
      context: {
        'endpoint': endpoint,
        'statusCode': statusCode,
        'method': method,
        'errorType': error.runtimeType.toString(),
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.network',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle configuration errors
  static void handleConfigurationError(
    Object error, {
    String? configFile,
    String? configKey,
    Map<String, dynamic>? context,
  }) {
    final errorMessage = error.toString();

    _logger.severe('Configuration error: $errorMessage', error);

    EventBuilder.publishErrorEvent(
      errorCode: 'CONFIG_ERROR',
      message: errorMessage,
      component: 'configuration',
      severity: ErrorSeverity.high,
      context: {
        'configFile': configFile,
        'configKey': configKey,
        'errorType': error.runtimeType.toString(),
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.configuration',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle validation errors
  static void handleValidationError(
    MCPValidationException exception, {
    String? component,
    Map<String, dynamic>? context,
  }) {
    _logger.warning(
        'Validation error in ${component ?? 'unknown'}: ${exception.message}');

    EventBuilder.publishErrorEvent(
      errorCode: 'VALIDATION_ERROR',
      message: exception.message,
      component: component ?? 'validation',
      severity: ErrorSeverity.medium,
      context: {
        'validationErrors': exception.validationErrors,
        'recoverable': exception.recoverable,
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.validation',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle timeout errors
  static void handleTimeoutError(
    Duration timeout, {
    String? operation,
    String? component,
    Map<String, dynamic>? context,
  }) {
    final message = 'Operation timed out after ${timeout.inMilliseconds}ms';

    _logger.warning('Timeout in ${component ?? 'unknown'}: $message');

    EventBuilder.publishErrorEvent(
      errorCode: 'TIMEOUT_ERROR',
      message: message,
      component: component ?? 'timeout',
      severity: ErrorSeverity.medium,
      context: {
        'operation': operation,
        'timeoutMs': timeout.inMilliseconds,
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.timeout',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Handle resource errors (memory, disk, etc.)
  static void handleResourceError(
    Object error, {
    String? resourceType,
    String? resourceId,
    Map<String, dynamic>? context,
  }) {
    final errorMessage = error.toString();

    _logger.severe('Resource error ($resourceType): $errorMessage', error);

    EventBuilder.publishErrorEvent(
      errorCode: 'RESOURCE_ERROR',
      message: errorMessage,
      component: 'resource',
      severity: ErrorSeverity.high,
      context: {
        'resourceType': resourceType,
        'resourceId': resourceId,
        'errorType': error.runtimeType.toString(),
        ...?context,
      },
    );

    _performanceMonitor.recordCustomMetric(
      name: 'error.resource',
      value: 1.0,
      type: MetricType.counter,
      category: 'error',
    );
  }

  /// Wrap a function with error handling
  static T wrapWithErrorHandling<T>(
    T Function() function, {
    required String operation,
    String? component,
    Map<String, dynamic>? context,
    T? fallbackValue,
  }) {
    try {
      return function();
    } on MCPValidationException catch (e) {
      handleValidationError(e, component: component, context: context);
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    } on MCPException catch (e) {
      handleMcpException(e, component: component, additionalContext: context);
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    } catch (e, stackTrace) {
      _logger.severe('Error in $operation: $e', e, stackTrace);

      EventBuilder.publishErrorEvent(
        errorCode: 'OPERATION_ERROR',
        message: e.toString(),
        component: component ?? 'unknown',
        severity: ErrorSeverity.high,
        stackTrace: stackTrace.toString(),
        context: {
          'operation': operation,
          'errorType': e.runtimeType.toString(),
          ...?context,
        },
      );

      _performanceMonitor.recordCustomMetric(
        name: 'error.operation',
        value: 1.0,
        type: MetricType.counter,
        category: 'error',
      );

      if (fallbackValue != null) return fallbackValue;
      rethrow;
    }
  }

  /// Wrap an async function with error handling
  static Future<T> wrapWithErrorHandlingAsync<T>(
    Future<T> Function() function, {
    required String operation,
    String? component,
    Map<String, dynamic>? context,
    T? fallbackValue,
  }) async {
    try {
      return await function();
    } on MCPValidationException catch (e) {
      handleValidationError(e, component: component, context: context);
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    } on MCPException catch (e) {
      handleMcpException(e, component: component, additionalContext: context);
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    } on TimeoutException catch (e) {
      handleTimeoutError(
        e.duration ?? Duration(seconds: 30),
        operation: operation,
        component: component,
        context: context,
      );
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    } catch (e, stackTrace) {
      _logger.severe('Async error in $operation: $e', e, stackTrace);

      EventBuilder.publishErrorEvent(
        errorCode: 'ASYNC_OPERATION_ERROR',
        message: e.toString(),
        component: component ?? 'unknown',
        severity: ErrorSeverity.high,
        stackTrace: stackTrace.toString(),
        context: {
          'operation': operation,
          'errorType': e.runtimeType.toString(),
          ...?context,
        },
      );

      _performanceMonitor.recordCustomMetric(
        name: 'error.async_operation',
        value: 1.0,
        type: MetricType.counter,
        category: 'error',
      );

      if (fallbackValue != null) return fallbackValue;
      rethrow;
    }
  }

  /// Get severity level for MCP exceptions
  static ErrorSeverity _getSeverityForException(MCPException exception) {
    if (exception is MCPValidationException) return ErrorSeverity.medium;
    if (exception is MCPConfigurationException) return ErrorSeverity.high;
    if (exception is MCPNetworkException) return ErrorSeverity.medium;
    if (exception is MCPTimeoutException) return ErrorSeverity.medium;
    if (exception is MCPSecurityException) return ErrorSeverity.critical;
    if (exception is MCPPlatformNotSupportedException) {
      return ErrorSeverity.high;
    }
    return ErrorSeverity.high;
  }

  /// Get log level for error severity
  static Level _getLogLevelForSeverity(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Level.INFO;
      case ErrorSeverity.medium:
        return Level.WARNING;
      case ErrorSeverity.high:
        return Level.SEVERE;
      case ErrorSeverity.critical:
        return Level.SHOUT;
    }
  }
}

/// Error handler mixin for easy integration into classes
mixin ErrorHandlerMixin {
  Logger get logger => Logger(runtimeType.toString());

  /// Handle error with automatic component detection
  void handleError(
    Object error, {
    String? operation,
    Map<String, dynamic>? context,
    StackTrace? stackTrace,
  }) {
    final component = runtimeType.toString().toLowerCase();

    if (error is MCPValidationException) {
      UnifiedErrorHandler.handleValidationError(
        error,
        component: component,
        context: {
          'operation': operation,
          ...?context,
        },
      );
    } else if (error is MCPException) {
      UnifiedErrorHandler.handleMcpException(
        error,
        component: component,
        additionalContext: {
          'operation': operation,
          ...?context,
        },
      );
    } else {
      logger.severe('Error in $component: $error', error, stackTrace);

      EventBuilder.publishErrorEvent(
        errorCode: 'COMPONENT_ERROR',
        message: error.toString(),
        component: component,
        severity: ErrorSeverity.high,
        stackTrace: stackTrace?.toString(),
        context: {
          'operation': operation,
          'errorType': error.runtimeType.toString(),
          ...?context,
        },
      );
    }
  }

  /// Safe execution with error handling
  T safeExecute<T>(
    T Function() function, {
    required String operation,
    T? fallbackValue,
    Map<String, dynamic>? context,
  }) {
    return UnifiedErrorHandler.wrapWithErrorHandling<T>(
      function,
      operation: operation,
      component: runtimeType.toString().toLowerCase(),
      context: context,
      fallbackValue: fallbackValue,
    );
  }

  /// Safe async execution with error handling
  Future<T> safeExecuteAsync<T>(
    Future<T> Function() function, {
    required String operation,
    T? fallbackValue,
    Map<String, dynamic>? context,
  }) {
    return UnifiedErrorHandler.wrapWithErrorHandlingAsync<T>(
      function,
      operation: operation,
      component: runtimeType.toString().toLowerCase(),
      context: context,
      fallbackValue: fallbackValue,
    );
  }
}

/// Global error zone for capturing all errors in a zone
class ErrorCaptureZone {
  static void runInErrorCaptureZone(void Function() body) {
    runZonedGuarded(
      body,
      (error, stackTrace) {
        UnifiedErrorHandler.handleUncaughtError(error, stackTrace);
      },
    );
  }

  static Future<T> runInErrorCaptureZoneAsync<T>(Future<T> Function() body) {
    return runZonedGuarded(
          body,
          (error, stackTrace) {
            UnifiedErrorHandler.handleUncaughtError(error, stackTrace);
          },
        ) ??
        Future.error('Error capture zone failed');
  }
}
