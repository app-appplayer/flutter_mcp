import 'dart:async';
import 'dart:collection';
import 'exceptions.dart';
import 'logger.dart';
import 'event_system.dart';
import '../config/app_config.dart';

/// Centralized error handling system for MCP
class MCPErrorHandler {
  static final Logger _logger = Logger('flutter_mcp.error_handler');
  static MCPErrorHandler? _instance;
  
  final Queue<ErrorReport> _errorHistory = Queue();
  final Map<String, int> _errorCounts = {};
  final Map<String, DateTime> _lastErrorTime = {};
  final List<ErrorHandlerCallback> _errorCallbacks = [];
  final List<ErrorRecoveryStrategy> _recoveryStrategies = [];
  
  int _maxErrorHistory = 100;
  bool _enableErrorReporting = true;
  
  /// Get singleton instance
  static MCPErrorHandler get instance {
    _instance ??= MCPErrorHandler._internal();
    return _instance!;
  }
  
  MCPErrorHandler._internal() {
    _initializeConfiguration();
    _setupDefaultRecoveryStrategies();
  }
  
  /// Initialize configuration
  void _initializeConfiguration() {
    try {
      final config = AppConfig.instance.scoped('errorHandling');
      _maxErrorHistory = config.get<int>('maxHistory', defaultValue: 100);
      _enableErrorReporting = config.get<bool>('enableReporting', defaultValue: true);
    } catch (e) {
      // Use defaults if config not available
      _logger.fine('Using default error handling configuration');
    }
  }
  
  /// Set up default recovery strategies
  void _setupDefaultRecoveryStrategies() {
    // Network error recovery
    addRecoveryStrategy(ErrorRecoveryStrategy(
      errorType: MCPNetworkException,
      canRecover: (error) => error is MCPNetworkException && (error.statusCode == null || error.statusCode! >= 500),
      recover: (error, context) async {
        _logger.info('Attempting network error recovery');
        await Future.delayed(Duration(seconds: 2));
        return true;
      },
      description: 'Network error recovery with retry delay',
    ));
    
    // Timeout error recovery
    addRecoveryStrategy(ErrorRecoveryStrategy(
      errorType: MCPTimeoutException,
      canRecover: (error) => error is MCPTimeoutException,
      recover: (error, context) async {
        _logger.info('Attempting timeout error recovery');
        // Increase timeout for retry
        if (context != null && context.containsKey('increaseTimeout')) {
          context['increaseTimeout'] = true;
        }
        return true;
      },
      description: 'Timeout error recovery with increased timeout',
    ));
    
    // Circuit breaker recovery
    addRecoveryStrategy(ErrorRecoveryStrategy(
      errorType: MCPCircuitBreakerOpenException,
      canRecover: (error) => error is MCPCircuitBreakerOpenException,
      recover: (error, context) async {
        final cbError = error as MCPCircuitBreakerOpenException;
        final now = DateTime.now();
        
        if (cbError.resetAt != null && now.isAfter(cbError.resetAt!)) {
          _logger.info('Circuit breaker reset time reached, allowing retry');
          return true;
        }
        
        // Wait for reset time if available
        if (cbError.resetAt != null) {
          final waitTime = cbError.resetAt!.difference(now);
          if (waitTime.inSeconds < 30) { // Only wait if less than 30 seconds
            _logger.info('Waiting ${waitTime.inSeconds}s for circuit breaker reset');
            await Future.delayed(waitTime);
            return true;
          }
        }
        
        return false;
      },
      description: 'Circuit breaker recovery with wait',
    ));
  }
  
  /// Handle an error with comprehensive reporting and recovery
  Future<ErrorHandlingResult> handleError(
    dynamic error, {
    StackTrace? stackTrace,
    String? operation,
    Map<String, dynamic>? context,
    bool attemptRecovery = true,
  }) async {
    // Convert to MCPException if needed
    MCPException mcpError;
    if (error is MCPException) {
      mcpError = error;
    } else {
      mcpError = MCPException.withContext(
        'Unexpected error: ${error.toString()}',
        originalError: error,
        originalStackTrace: stackTrace,
        errorCode: 'UNEXPECTED_ERROR',
        context: context,
        recoverable: true,
        resolution: 'This error was not expected. Please check logs for more details.',
      );
    }
    
    // Create error report
    final report = ErrorReport(
      error: mcpError,
      stackTrace: stackTrace ?? StackTrace.current,
      operation: operation,
      context: context,
      timestamp: DateTime.now(),
    );
    
    // Log the error
    _logError(report);
    
    // Update error statistics
    _updateErrorStatistics(mcpError);
    
    // Store error in history
    _addToHistory(report);
    
    // Notify error callbacks
    _notifyErrorCallbacks(report);
    
    // Publish error event
    _publishErrorEvent(report);
    
    // Attempt recovery if enabled
    bool recovered = false;
    if (attemptRecovery && mcpError.recoverable) {
      recovered = await _attemptRecovery(mcpError, context);
    }
    
    return ErrorHandlingResult(
      report: report,
      recovered: recovered,
      canRetry: recovered || mcpError.recoverable,
    );
  }
  
  /// Log error with appropriate level
  void _logError(ErrorReport report) {
    if (!_enableErrorReporting) return;
    
    final error = report.error;
    final severity = _getErrorSeverity(error);
    
    final message = 'Error in ${report.operation ?? 'unknown operation'}: ${error.message}';
    
    switch (severity) {
      case ErrorSeverity.critical:
        _logger.severe(message, error.originalError, report.stackTrace);
        break;
      case ErrorSeverity.high:
        _logger.severe(message, error.originalError);
        break;
      case ErrorSeverity.medium:
        _logger.warning(message, error.originalError);
        break;
      case ErrorSeverity.low:
        _logger.info(message);
        break;
    }
  }
  
  /// Determine error severity
  ErrorSeverity _getErrorSeverity(MCPException error) {
    // Security errors are always critical
    if (error is MCPSecurityException) {
      return ErrorSeverity.critical;
    }
    
    // Initialization errors are critical
    if (error is MCPInitializationException) {
      return ErrorSeverity.critical;
    }
    
    // Platform not supported is high
    if (error is MCPPlatformNotSupportedException) {
      return ErrorSeverity.high;
    }
    
    // Validation errors are usually medium
    if (error is MCPValidationException) {
      return ErrorSeverity.medium;
    }
    
    // Cancelled operations are low
    if (error is MCPOperationCancelledException) {
      return ErrorSeverity.low;
    }
    
    // Network errors depend on recoverability
    if (error is MCPNetworkException) {
      return error.recoverable ? ErrorSeverity.medium : ErrorSeverity.high;
    }
    
    // Default to medium
    return ErrorSeverity.medium;
  }
  
  /// Update error statistics
  void _updateErrorStatistics(MCPException error) {
    final errorKey = error.errorCode ?? error.runtimeType.toString();
    _errorCounts[errorKey] = (_errorCounts[errorKey] ?? 0) + 1;
    _lastErrorTime[errorKey] = DateTime.now();
  }
  
  /// Add error to history
  void _addToHistory(ErrorReport report) {
    _errorHistory.add(report);
    
    // Keep history size under limit
    while (_errorHistory.length > _maxErrorHistory) {
      _errorHistory.removeFirst();
    }
  }
  
  /// Notify error callbacks
  void _notifyErrorCallbacks(ErrorReport report) {
    for (final callback in _errorCallbacks) {
      try {
        callback(report);
      } catch (e) {
        _logger.warning('Error in error callback: $e');
      }
    }
  }
  
  /// Publish error event
  void _publishErrorEvent(ErrorReport report) {
    try {
      EventSystem.instance.publish('error.occurred', {
        'errorCode': report.error.errorCode,
        'errorType': report.error.runtimeType.toString(),
        'message': report.error.message,
        'operation': report.operation,
        'recoverable': report.error.recoverable,
        'timestamp': report.timestamp.toIso8601String(),
      });
    } catch (e) {
      _logger.warning('Failed to publish error event: $e');
    }
  }
  
  /// Attempt error recovery
  Future<bool> _attemptRecovery(MCPException error, Map<String, dynamic>? context) async {
    for (final strategy in _recoveryStrategies) {
      if (strategy.canRecover(error)) {
        try {
          _logger.fine('Attempting recovery with strategy: ${strategy.description}');
          final recovered = await strategy.recover(error, context);
          
          if (recovered) {
            _logger.info('Successfully recovered from error using: ${strategy.description}');
            
            // Publish recovery event
            EventSystem.instance.publish('error.recovered', {
              'errorCode': error.errorCode,
              'strategy': strategy.description,
              'timestamp': DateTime.now().toIso8601String(),
            });
            
            return true;
          }
        } catch (e) {
          _logger.warning('Recovery strategy failed: ${strategy.description}: $e');
        }
      }
    }
    
    return false;
  }
  
  /// Add error callback
  void addErrorCallback(ErrorHandlerCallback callback) {
    _errorCallbacks.add(callback);
  }
  
  /// Remove error callback
  void removeErrorCallback(ErrorHandlerCallback callback) {
    _errorCallbacks.remove(callback);
  }
  
  /// Add recovery strategy
  void addRecoveryStrategy(ErrorRecoveryStrategy strategy) {
    _recoveryStrategies.add(strategy);
  }
  
  /// Remove recovery strategy
  void removeRecoveryStrategy(ErrorRecoveryStrategy strategy) {
    _recoveryStrategies.remove(strategy);
  }
  
  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final now = DateTime.now();
    
    return {
      'totalErrors': _errorHistory.length,
      'uniqueErrorTypes': _errorCounts.length,
      'errorCounts': Map.from(_errorCounts),
      'recentErrors': _errorHistory
          .where((e) => now.difference(e.timestamp).inHours < 24)
          .length,
      'lastErrorTime': _lastErrorTime.isNotEmpty
          ? _lastErrorTime.values.reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String()
          : null,
      'mostFrequentError': _errorCounts.isNotEmpty
          ? _errorCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : null,
    };
  }
  
  /// Get recent error reports
  List<ErrorReport> getRecentErrors({Duration? within}) {
    within ??= Duration(hours: 24);
    final cutoff = DateTime.now().subtract(within);
    
    return _errorHistory
        .where((report) => report.timestamp.isAfter(cutoff))
        .toList();
  }
  
  /// Clear error history
  void clearErrorHistory() {
    _errorHistory.clear();
    _errorCounts.clear();
    _lastErrorTime.clear();
    _logger.info('Cleared error history');
  }
  
  /// Export error data for analysis
  Map<String, dynamic> exportErrorData() {
    return {
      'metadata': {
        'exportTime': DateTime.now().toIso8601String(),
        'totalErrors': _errorHistory.length,
        'maxHistorySize': _maxErrorHistory,
      },
      'statistics': getErrorStatistics(),
      'errorHistory': _errorHistory.map((e) => e.toJson()).toList(),
      'recoveryStrategies': _recoveryStrategies.map((s) => {
        'errorType': s.errorType.toString(),
        'description': s.description,
      }).toList(),
    };
  }
  
  /// Create a safe wrapper for operations
  static Future<T> safeExecute<T>(
    Future<T> Function() operation, {
    String? operationName,
    Map<String, dynamic>? context,
    T? fallback,
    bool rethrowOnFailure = true,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      final result = await instance.handleError(
        error,
        stackTrace: stackTrace,
        operation: operationName,
        context: context,
      );
      
      if (result.canRetry && fallback != null) {
        return fallback;
      }
      
      if (rethrowOnFailure) {
        rethrow;
      } else {
        throw result.report.error;
      }
    }
  }
}

/// Error report containing all error information
class ErrorReport {
  final MCPException error;
  final StackTrace stackTrace;
  final String? operation;
  final Map<String, dynamic>? context;
  final DateTime timestamp;
  
  ErrorReport({
    required this.error,
    required this.stackTrace,
    this.operation,
    this.context,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'error': {
      'type': error.runtimeType.toString(),
      'code': error.errorCode,
      'message': error.message,
      'recoverable': error.recoverable,
      'resolution': error.resolution,
    },
    'operation': operation,
    'context': context,
    'timestamp': timestamp.toIso8601String(),
    'stackTrace': stackTrace.toString(),
  };
}

/// Result of error handling
class ErrorHandlingResult {
  final ErrorReport report;
  final bool recovered;
  final bool canRetry;
  
  ErrorHandlingResult({
    required this.report,
    required this.recovered,
    required this.canRetry,
  });
}

/// Error recovery strategy
class ErrorRecoveryStrategy {
  final Type errorType;
  final bool Function(MCPException error) canRecover;
  final Future<bool> Function(MCPException error, Map<String, dynamic>? context) recover;
  final String description;
  
  ErrorRecoveryStrategy({
    required this.errorType,
    required this.canRecover,
    required this.recover,
    required this.description,
  });
}

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// Error handler callback type
typedef ErrorHandlerCallback = void Function(ErrorReport report);