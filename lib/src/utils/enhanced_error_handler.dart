import 'dart:async';
import 'package:flutter_mcp/src/utils/logger.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';
import 'package:flutter_mcp/src/monitoring/health_monitor.dart';
import 'package:flutter_mcp/src/utils/performance_monitor.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import '../types/health_types.dart';

/// Error recovery strategy
abstract class ErrorRecoveryStrategy {
  Future<T?> recover<T>(dynamic error, StackTrace stackTrace, String context);
  bool canRecover(dynamic error);
}

/// Default error recovery strategy
class DefaultErrorRecoveryStrategy implements ErrorRecoveryStrategy {
  @override
  Future<T?> recover<T>(dynamic error, StackTrace stackTrace, String context) async {
    return null;
  }
  
  @override
  bool canRecover(dynamic error) => false;
}

/// Retry-based recovery strategy
class RetryRecoveryStrategy implements ErrorRecoveryStrategy {
  final int maxRetries;
  final Duration retryDelay;
  final bool Function(dynamic error)? shouldRetry;
  
  RetryRecoveryStrategy({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.shouldRetry,
  });
  
  @override
  bool canRecover(dynamic error) {
    if (shouldRetry != null) {
      return shouldRetry!(error);
    }
    // Default retry logic for transient errors
    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
           message.contains('connection') ||
           message.contains('network') ||
           message.contains('temporarily');
  }
  
  @override
  Future<T?> recover<T>(dynamic error, StackTrace stackTrace, String context) async {
    // Retry logic is handled by the error handler
    return null;
  }
}

/// Circuit breaker recovery strategy
class CircuitBreakerRecoveryStrategy implements ErrorRecoveryStrategy {
  final Map<String, CircuitBreaker> circuitBreakers;
  
  CircuitBreakerRecoveryStrategy(this.circuitBreakers);
  
  @override
  bool canRecover(dynamic error) {
    return error is! CircuitBreakerOpenException;
  }
  
  @override
  Future<T?> recover<T>(dynamic error, StackTrace stackTrace, String context) async {
    // Circuit breaker logic is handled separately
    return null;
  }
}

/// Error handler function type
typedef ErrorHandler<T> = Future<T> Function(
  dynamic error,
  StackTrace stackTrace,
  String context,
);

/// Enhanced unified error handler with recovery strategies and circuit breakers
class EnhancedErrorHandler {
  static EnhancedErrorHandler? _instance;
  static EnhancedErrorHandler get instance {
    _instance ??= EnhancedErrorHandler._();
    return _instance!;
  }
  
  EnhancedErrorHandler._();
  
  final Logger _logger = Logger('flutter_mcp.enhanced_error_handler');
  final EventSystem _eventSystem = EventSystem.instance;
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor.instance;
  
  // Error handlers by type
  final Map<Type, ErrorHandler> _errorHandlers = {};
  
  // Recovery strategies
  final Map<String, ErrorRecoveryStrategy> _recoveryStrategies = {
    'default': DefaultErrorRecoveryStrategy(),
    'retry': RetryRecoveryStrategy(),
  };
  
  // Circuit breakers
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  
  // Error statistics
  final Map<String, int> _errorCounts = {};
  final Map<String, DateTime> _lastErrors = {};
  
  /// Initialize error handler with default configurations
  void initialize() {
    // Register default error handlers
    _registerDefaultHandlers();
    
    // Create default circuit breakers
    _createDefaultCircuitBreakers();
    
    _logger.info('Enhanced error handler initialized');
  }
  
  /// Register a custom error handler for a specific error type
  void registerErrorHandler<T>(ErrorHandler<T> handler) {
    _errorHandlers[T] = handler as ErrorHandler;
    _logger.fine('Registered error handler for type: $T');
  }
  
  /// Register a recovery strategy
  void registerRecoveryStrategy(String name, ErrorRecoveryStrategy strategy) {
    _recoveryStrategies[name] = strategy;
    _logger.fine('Registered recovery strategy: $name');
  }
  
  /// Create or get a circuit breaker
  CircuitBreaker getCircuitBreaker(String name, {
    int failureThreshold = 5,
    Duration resetTimeout = const Duration(seconds: 30),
  }) {
    return _circuitBreakers.putIfAbsent(
      name,
      () => CircuitBreaker(
        name: name,
        failureThreshold: failureThreshold,
        resetTimeout: resetTimeout,
        onOpen: () {
          _logger.warning('Circuit breaker opened: $name');
          _reportHealthIssue(name, 'Circuit breaker opened');
        },
        onClose: () {
          _logger.info('Circuit breaker closed: $name');
          _reportHealthRecovery(name, 'Circuit breaker closed');
        },
      ),
    );
  }
  
  /// Handle error with automatic recovery and circuit breaking
  Future<T> handleError<T>(
    Future<T> Function() operation, {
    required String context,
    String? component,
    Map<String, dynamic>? metadata,
    T? fallbackValue,
    String? recoveryStrategy,
    String? circuitBreakerName,
  }) async {
    // Check circuit breaker if specified
    if (circuitBreakerName != null) {
      final breaker = getCircuitBreaker(circuitBreakerName);
      return await breaker.execute(() => _executeWithErrorHandling(
        operation,
        context: context,
        component: component,
        metadata: metadata,
        fallbackValue: fallbackValue,
        recoveryStrategy: recoveryStrategy,
      ));
    }
    
    return await _executeWithErrorHandling(
      operation,
      context: context,
      component: component,
      metadata: metadata,
      fallbackValue: fallbackValue,
      recoveryStrategy: recoveryStrategy,
    );
  }
  
  /// Execute operation with error handling
  Future<T> _executeWithErrorHandling<T>(
    Future<T> Function() operation, {
    required String context,
    String? component,
    Map<String, dynamic>? metadata,
    T? fallbackValue,
    String? recoveryStrategy,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await operation();
      
      // Record success metric
      _performanceMonitor.recordMetric(
        'operation.$context',
        stopwatch.elapsedMilliseconds,
        success: true,
        metadata: metadata,
      );
      
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      
      // Update error statistics
      _updateErrorStatistics(context, error);
      
      // Log error
      _logger.severe('Error in $context: $error', error, stackTrace);
      
      // Try to find specific handler
      final handler = _errorHandlers[error.runtimeType];
      if (handler != null) {
        try {
          return await handler(error, stackTrace, context);
        } catch (handlerError) {
          _logger.severe('Error handler failed: $handlerError', handlerError);
        }
      }
      
      // Try recovery strategy
      final strategy = _recoveryStrategies[recoveryStrategy ?? 'default'];
      if (strategy != null && strategy.canRecover(error)) {
        final recovered = await strategy.recover<T>(error, stackTrace, context);
        if (recovered != null) {
          _logger.info('Successfully recovered from error using $recoveryStrategy strategy');
          return recovered;
        }
      }
      
      // Handle specific error types
      if (error is MCPException) {
        _handleMCPException(error, context, component, metadata);
      } else if (error is TimeoutException) {
        _handleTimeoutException(error, context, component, metadata);
      } else {
        _handleGenericError(error, stackTrace, context, component, metadata);
      }
      
      // Record failure metric
      _performanceMonitor.recordMetric(
        'operation.$context',
        stopwatch.elapsedMilliseconds,
        success: false,
        metadata: {
          ...?metadata,
          'error': error.toString(),
          'errorType': error.runtimeType.toString(),
        },
      );
      
      // Return fallback value if provided
      if (fallbackValue != null) {
        _logger.warning('Returning fallback value for $context');
        return fallbackValue;
      }
      
      // Rethrow the error
      rethrow;
    }
  }
  
  /// Update error statistics
  void _updateErrorStatistics(String context, dynamic error) {
    final key = '$context:${error.runtimeType}';
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
    _lastErrors[key] = DateTime.now();
    
    // Check for error patterns
    if (_errorCounts[key]! > 10) {
      _logger.warning('High error rate detected for $key: ${_errorCounts[key]} errors');
      _reportHealthIssue(context, 'High error rate: ${_errorCounts[key]} errors');
    }
  }
  
  /// Handle MCP exceptions
  void _handleMCPException(
    MCPException exception,
    String context,
    String? component,
    Map<String, dynamic>? metadata,
  ) {
    final severity = _getSeverityForException(exception);
    
    _eventSystem.publish('error.mcp_exception', {
      'context': context,
      'component': component ?? 'unknown',
      'errorCode': exception.errorCode,
      'message': exception.message,
      'recoverable': exception.recoverable,
      'severity': severity.name,
      'metadata': metadata,
    });
    
    // Report to health monitor
    if (severity == ErrorSeverity.critical) {
      _reportHealthIssue(component ?? context, exception.message);
    }
  }
  
  /// Handle timeout exceptions
  void _handleTimeoutException(
    TimeoutException exception,
    String context,
    String? component,
    Map<String, dynamic>? metadata,
  ) {
    _eventSystem.publish('error.timeout', {
      'context': context,
      'component': component ?? 'unknown',
      'duration': exception.duration?.inMilliseconds,
      'metadata': metadata,
    });
    
    _reportHealthIssue(
      component ?? context,
      'Operation timed out after ${exception.duration?.inSeconds ?? '?'} seconds',
    );
  }
  
  /// Handle generic errors
  void _handleGenericError(
    dynamic error,
    StackTrace stackTrace,
    String context,
    String? component,
    Map<String, dynamic>? metadata,
  ) {
    _eventSystem.publish('error.generic', {
      'context': context,
      'component': component ?? 'unknown',
      'error': error.toString(),
      'errorType': error.runtimeType.toString(),
      'stackTrace': stackTrace.toString(),
      'metadata': metadata,
    });
    
    _reportHealthIssue(
      component ?? context,
      'Unhandled error: ${error.toString()}',
    );
  }
  
  /// Report health issue
  void _reportHealthIssue(String component, String message) {
    HealthMonitor.instance.updateComponentHealth(
      'error_handler_$component',
      MCPHealthStatus.degraded,
      message,
    );
  }
  
  /// Report health recovery
  void _reportHealthRecovery(String component, String message) {
    HealthMonitor.instance.updateComponentHealth(
      'error_handler_$component',
      MCPHealthStatus.healthy,
      message,
    );
  }
  
  /// Get error severity for exceptions
  ErrorSeverity _getSeverityForException(MCPException exception) {
    if (exception is MCPValidationException) return ErrorSeverity.low;
    if (exception is MCPConfigurationException) return ErrorSeverity.high;
    if (exception is MCPNetworkException) return ErrorSeverity.medium;
    if (exception is MCPTimeoutException) return ErrorSeverity.medium;
    if (exception is MCPSecurityException) return ErrorSeverity.critical;
    if (exception is MCPResourceNotFoundException) return ErrorSeverity.medium;
    return ErrorSeverity.high;
  }
  
  /// Register default error handlers
  void _registerDefaultHandlers() {
    // Network error handler
    registerErrorHandler<MCPNetworkException>((error, stackTrace, context) async {
      _logger.warning('Network error in $context: ${error.message}');
      
      // Try retry strategy
      final strategy = _recoveryStrategies['retry'] as RetryRecoveryStrategy;
      if (strategy.canRecover(error)) {
        await Future.delayed(strategy.retryDelay);
        throw error; // Let the retry mechanism handle it
      }
      
      throw error;
    });
    
    // Validation error handler
    registerErrorHandler<MCPValidationException>((error, stackTrace, context) async {
      _logger.warning('Validation error in $context: ${error.message}');
      _logger.fine('Validation errors: ${error.validationErrors}');
      throw error; // Validation errors typically can't be recovered
    });
    
    // Resource not found handler
    registerErrorHandler<MCPResourceNotFoundException>((error, stackTrace, context) async {
      _logger.warning('Resource not found in $context: ${error.resourceId}');
      throw error;
    });
  }
  
  /// Create default circuit breakers
  void _createDefaultCircuitBreakers() {
    // LLM operations circuit breaker
    getCircuitBreaker('llm.operations', 
      failureThreshold: 5,
      resetTimeout: Duration(minutes: 1),
    );
    
    // Network operations circuit breaker
    getCircuitBreaker('network.operations',
      failureThreshold: 10,
      resetTimeout: Duration(seconds: 30),
    );
    
    // Tool execution circuit breaker
    getCircuitBreaker('tool.execution',
      failureThreshold: 3,
      resetTimeout: Duration(seconds: 20),
    );
  }
  
  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    return {
      'errorCounts': Map.from(_errorCounts),
      'lastErrors': _lastErrors.map((k, v) => MapEntry(k, v.toIso8601String())),
      'circuitBreakers': _circuitBreakers.map((k, v) => MapEntry(k, {
        'state': v.state.toString(),
        'failureCount': v.failureCount,
      })),
    };
  }
  
  /// Reset error statistics
  void resetStatistics() {
    _errorCounts.clear();
    _lastErrors.clear();
    _logger.info('Error statistics reset');
  }
}