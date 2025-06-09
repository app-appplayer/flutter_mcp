# Error Handling

Comprehensive guide to error handling in Flutter MCP.

## Error Types

### Core Exceptions

```dart
// MCP-specific exceptions
class MCPException implements Exception {
  final String message;
  final String? code;
  final dynamic details;
  final StackTrace? stackTrace;
  
  MCPException({
    required this.message,
    this.code,
    this.details,
    this.stackTrace,
  });
}

// Connection exception
class ConnectionException extends MCPException {
  final String serverName;
  final Duration? timeout;
  
  ConnectionException({
    required super.message,
    required this.serverName,
    this.timeout,
    super.code,
    super.details,
  });
}

// Authentication exception
class AuthenticationException extends MCPException {
  final String? user;
  final AuthError error;
  
  AuthenticationException({
    required super.message,
    this.user,
    required this.error,
    super.code,
  });
}

// Protocol exception
class ProtocolException extends MCPException {
  final String method;
  final Map<String, dynamic>? params;
  
  ProtocolException({
    required super.message,
    required this.method,
    this.params,
    super.code,
  });
}
```

### Error Codes

```dart
// Define standard error codes
enum MCPErrorCode {
  // Connection errors
  connectionFailed('E001'),
  connectionTimeout('E002'),
  connectionLost('E003'),
  
  // Authentication errors
  authFailed('E101'),
  authExpired('E102'),
  authInvalid('E103'),
  
  // Protocol errors
  protocolError('E201'),
  invalidRequest('E202'),
  invalidResponse('E203'),
  
  // Server errors
  serverError('E301'),
  serverUnavailable('E302'),
  serverOverloaded('E303'),
  
  // Client errors
  clientError('E401'),
  invalidParams('E402'),
  resourceNotFound('E403'),
  
  // Plugin errors
  pluginError('E501'),
  pluginNotFound('E502'),
  pluginInitFailed('E503');
  
  final String code;
  const MCPErrorCode(this.code);
}
```

## Error Handling Patterns

### Try-Catch Blocks

```dart
// Basic error handling
try {
  final server = await FlutterMCP.connect('my-server');
  final result = await server.execute('method', params);
} on ConnectionException catch (e) {
  // Handle connection errors
  logger.error('Connection failed: ${e.message}');
  showRetryDialog();
} on AuthenticationException catch (e) {
  // Handle auth errors
  logger.error('Auth failed: ${e.message}');
  navigateToLogin();
} on MCPException catch (e) {
  // Handle other MCP errors
  logger.error('MCP error: ${e.message}');
  showErrorMessage(e.message);
} catch (e, stack) {
  // Handle unexpected errors
  logger.error('Unexpected error', error: e, stackTrace: stack);
  showGenericError();
}
```

### Error Recovery

```dart
// Implement automatic retry with exponential backoff
class RetryHandler {
  static Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffFactor = 2.0,
    bool Function(Exception)? retryIf,
  }) async {
    Duration delay = initialDelay;
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (e is! Exception || 
            attempt == maxAttempts ||
            (retryIf != null && !retryIf(e))) {
          rethrow;
        }
        
        logger.warn('Attempt $attempt failed, retrying in ${delay.inSeconds}s');
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffFactor).round());
      }
    }
    
    throw StateError('Should not reach here');
  }
}

// Usage
final result = await RetryHandler.withRetry(
  operation: () => server.execute('method', params),
  maxAttempts: 3,
  retryIf: (e) => e is ConnectionException || e is TimeoutException,
);
```

### Circuit Breaker Pattern

```dart
// Implement circuit breaker for fault tolerance
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitState _state = CircuitState.closed;
  
  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
  });
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitState.open) {
      if (_shouldReset()) {
        _state = CircuitState.halfOpen;
      } else {
        throw CircuitOpenException('Circuit breaker is open');
      }
    }
    
    try {
      final result = await operation().timeout(timeout);
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }
  
  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitState.closed;
  }
  
  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
      logger.warn('Circuit breaker opened after $_failureCount failures');
    }
  }
  
  bool _shouldReset() {
    return _lastFailureTime != null &&
        DateTime.now().difference(_lastFailureTime!) > resetTimeout;
  }
}
```

## Global Error Handling

### Error Interceptors

```dart
// Global error handler
class GlobalErrorHandler {
  static void initialize() {
    // Handle Flutter errors
    FlutterError.onError = (FlutterErrorDetails details) {
      logger.error(
        'Flutter error',
        error: details.exception,
        stackTrace: details.stack,
      );
      _reportError(details.exception, details.stack);
    };
    
    // Handle async errors
    runZonedGuarded(() {
      runApp(MyApp());
    }, (error, stack) {
      logger.error(
        'Async error',
        error: error,
        stackTrace: stack,
      );
      _reportError(error, stack);
    });
  }
  
  static void _reportError(dynamic error, StackTrace? stack) {
    // Report to error tracking service
    if (error is MCPException) {
      _reportMCPError(error);
    } else {
      _reportGenericError(error, stack);
    }
  }
  
  static void _reportMCPError(MCPException error) {
    // Custom handling for MCP errors
    ErrorReporter.report(
      type: 'mcp_error',
      message: error.message,
      code: error.code,
      details: error.details,
      stackTrace: error.stackTrace,
    );
  }
  
  static void _reportGenericError(dynamic error, StackTrace? stack) {
    // Generic error reporting
    ErrorReporter.report(
      type: 'generic_error',
      message: error.toString(),
      stackTrace: stack,
    );
  }
}
```

### Error Boundary Widget

```dart
// Widget to catch and display errors
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace? stack)? errorBuilder;
  
  const ErrorBoundary({
    Key? key,
    required this.child,
    this.errorBuilder,
  }) : super(key: key);
  
  @override
  _ErrorBoundaryState createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stack;
  
  @override
  void initState() {
    super.initState();
    // Listen for errors in descendant widgets
    FlutterError.onError = (details) {
      setState(() {
        _error = details.exception;
        _stack = details.stack;
      });
    };
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!, _stack) ??
          _defaultErrorWidget(_error!, _stack);
    }
    
    return widget.child;
  }
  
  Widget _defaultErrorWidget(Object error, StackTrace? stack) {
    return Container(
      color: Colors.red,
      child: Center(
        child: Text(
          'Error: ${error.toString()}',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
```

## Error Logging

### Structured Logging

```dart
// Enhanced error logging
class ErrorLogger {
  static void logError({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'ERROR',
      'message': message,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      'metadata': metadata,
      'platform': Platform.operatingSystem,
      'app_version': _getAppVersion(),
      'device_info': _getDeviceInfo(),
    };
    
    // Log to console
    if (kDebugMode) {
      print(JsonEncoder.withIndent('  ').convert(logEntry));
    }
    
    // Log to file
    _writeToLogFile(logEntry);
    
    // Send to remote logging service
    _sendToRemoteLogger(logEntry);
  }
  
  static Future<void> _writeToLogFile(Map<String, dynamic> entry) async {
    final file = File('${await _getLogDirectory()}/errors.log');
    await file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  }
  
  static Future<void> _sendToRemoteLogger(Map<String, dynamic> entry) async {
    try {
      await http.post(
        Uri.parse('https://logs.example.com/errors'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entry),
      );
    } catch (e) {
      // Don't throw from error logger
      print('Failed to send log: $e');
    }
  }
}
```

### Error Metrics

```dart
// Track error metrics
class ErrorMetrics {
  static final Map<String, int> _errorCounts = {};
  static final Map<String, DateTime> _lastErrors = {};
  
  static void trackError(MCPException error) {
    final key = '${error.runtimeType}_${error.code}';
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
    _lastErrors[key] = DateTime.now();
    
    // Check for error patterns
    _checkErrorPatterns();
  }
  
  static void _checkErrorPatterns() {
    // Check for high error rate
    for (final entry in _errorCounts.entries) {
      if (entry.value > 10) {
        logger.warn('High error rate for ${entry.key}: ${entry.value} errors');
      }
    }
    
    // Check for recurring errors
    final recentErrors = _lastErrors.entries
        .where((e) => DateTime.now().difference(e.value) < Duration(minutes: 5))
        .toList();
    
    if (recentErrors.length > 5) {
      logger.warn('Multiple error types in last 5 minutes: ${recentErrors.length}');
    }
  }
  
  static Map<String, dynamic> getMetrics() {
    return {
      'error_counts': _errorCounts,
      'last_errors': _lastErrors.map((k, v) => MapEntry(k, v.toIso8601String())),
      'total_errors': _errorCounts.values.fold(0, (a, b) => a + b),
    };
  }
}
```

## User-Facing Error Messages

### Error Message Translation

```dart
// User-friendly error messages
class ErrorMessages {
  static String getUserMessage(MCPException error) {
    switch (error.code) {
      case 'E001':
        return 'Unable to connect to server. Please check your internet connection.';
      case 'E002':
        return 'Connection timed out. Please try again.';
      case 'E101':
        return 'Authentication failed. Please check your credentials.';
      case 'E102':
        return 'Your session has expired. Please login again.';
      case 'E301':
        return 'Server error occurred. Please try again later.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
  
  static Map<String, String> getErrorDetails(MCPException error) {
    return {
      'title': _getErrorTitle(error),
      'message': getUserMessage(error),
      'action': _getErrorAction(error),
      'technical': error.message,
    };
  }
  
  static String _getErrorTitle(MCPException error) {
    if (error is ConnectionException) return 'Connection Error';
    if (error is AuthenticationException) return 'Authentication Error';
    if (error is ProtocolException) return 'Protocol Error';
    return 'Error';
  }
  
  static String _getErrorAction(MCPException error) {
    if (error is ConnectionException) return 'Retry';
    if (error is AuthenticationException) return 'Login';
    return 'OK';
  }
}
```

### Error Dialog

```dart
// Error dialog widget
class ErrorDialog extends StatelessWidget {
  final MCPException error;
  final VoidCallback? onRetry;
  
  const ErrorDialog({
    Key? key,
    required this.error,
    this.onRetry,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final details = ErrorMessages.getErrorDetails(error);
    
    return AlertDialog(
      title: Text(details['title']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details['message']!),
          if (kDebugMode) ...[
            SizedBox(height: 16),
            Text(
              'Technical Details:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              details['technical']!,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: Text(details['action']!),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'),
        ),
      ],
    );
  }
}
```

## Testing Error Scenarios

### Error Simulation

```dart
// Simulate errors for testing
class ErrorSimulator {
  static bool _enabled = false;
  static double _errorRate = 0.1;
  
  static void enable({double errorRate = 0.1}) {
    _enabled = true;
    _errorRate = errorRate;
  }
  
  static void disable() {
    _enabled = false;
  }
  
  static Future<T> maybeThrow<T>(Future<T> Function() operation) async {
    if (_enabled && Random().nextDouble() < _errorRate) {
      throw _randomError();
    }
    return await operation();
  }
  
  static MCPException _randomError() {
    final errors = [
      ConnectionException(
        message: 'Simulated connection error',
        serverName: 'test-server',
      ),
      AuthenticationException(
        message: 'Simulated auth error',
        error: AuthError.invalidCredentials,
      ),
      ProtocolException(
        message: 'Simulated protocol error',
        method: 'test-method',
      ),
    ];
    return errors[Random().nextInt(errors.length)];
  }
}
```

### Error Test Cases

```dart
// Test error handling
group('Error handling tests', () {
  test('handles connection errors', () async {
    // Simulate connection error
    ErrorSimulator.enable(errorRate: 1.0);
    
    expect(
      () => FlutterMCP.connect('test-server'),
      throwsA(isA<ConnectionException>()),
    );
    
    ErrorSimulator.disable();
  });
  
  test('retries on timeout', () async {
    int attempts = 0;
    
    final result = await RetryHandler.withRetry(
      operation: () async {
        attempts++;
        if (attempts < 3) {
          throw TimeoutException('Timeout');
        }
        return 'success';
      },
      maxAttempts: 3,
    );
    
    expect(result, equals('success'));
    expect(attempts, equals(3));
  });
  
  test('circuit breaker opens after failures', () async {
    final breaker = CircuitBreaker(failureThreshold: 3);
    
    // Simulate failures
    for (int i = 0; i < 3; i++) {
      try {
        await breaker.execute(() => throw Exception('Error'));
      } catch (_) {}
    }
    
    // Circuit should be open
    expect(
      () => breaker.execute(() => Future.value('test')),
      throwsA(isA<CircuitOpenException>()),
    );
  });
});
```

## Best Practices

### Error Handling Guidelines

1. **Be Specific**: Use specific exception types
2. **Provide Context**: Include relevant information in errors
3. **User-Friendly**: Show appropriate messages to users
4. **Log Everything**: Log errors with full context
5. **Fail Fast**: Detect errors early
6. **Recover Gracefully**: Implement recovery strategies
7. **Test Errors**: Test error scenarios thoroughly
8. **Monitor**: Track error patterns and metrics

### Common Patterns

```dart
// Wrap operations with error handling
extension ErrorHandlingExtension<T> on Future<T> {
  Future<T> withErrorHandling({
    required String operation,
    Map<String, dynamic>? context,
  }) async {
    try {
      return await this;
    } catch (e, stack) {
      ErrorLogger.logError(
        message: 'Error in $operation',
        error: e,
        stackTrace: stack,
        metadata: context,
      );
      
      if (e is MCPException) {
        ErrorMetrics.trackError(e);
      }
      
      rethrow;
    }
  }
}

// Usage
final result = await server
    .execute('method', params)
    .withErrorHandling(
      operation: 'server.execute',
      context: {'method': 'method', 'params': params},
    );
```

## Error Recovery Strategies

### Graceful Degradation

```dart
// Provide fallback behavior
class GracefulDegradation {
  static Future<T?> withFallback<T>({
    required Future<T> Function() primary,
    required Future<T> Function() fallback,
    bool Function(Exception)? shouldFallback,
  }) async {
    try {
      return await primary();
    } catch (e) {
      if (e is Exception && (shouldFallback?.call(e) ?? true)) {
        logger.warn('Primary operation failed, using fallback');
        return await fallback();
      }
      rethrow;
    }
  }
}

// Usage
final data = await GracefulDegradation.withFallback(
  primary: () => fetchFromServer(),
  fallback: () => fetchFromCache(),
  shouldFallback: (e) => e is ConnectionException,
);
```

### State Recovery

```dart
// Recover application state after errors
class StateRecovery {
  static final Map<String, dynamic> _checkpoints = {};
  
  static void checkpoint(String name, dynamic state) {
    _checkpoints[name] = {
      'state': state,
      'timestamp': DateTime.now(),
    };
  }
  
  static T? recover<T>(String name) {
    final checkpoint = _checkpoints[name];
    if (checkpoint != null) {
      final age = DateTime.now().difference(checkpoint['timestamp']);
      if (age < Duration(minutes: 5)) {
        return checkpoint['state'] as T;
      }
    }
    return null;
  }
  
  static Future<T> withRecovery<T>({
    required String checkpointName,
    required Future<T> Function() operation,
    T Function()? createDefault,
  }) async {
    try {
      final result = await operation();
      checkpoint(checkpointName, result);
      return result;
    } catch (e) {
      logger.warn('Operation failed, attempting recovery');
      
      final recovered = recover<T>(checkpointName);
      if (recovered != null) {
        return recovered;
      }
      
      if (createDefault != null) {
        return createDefault();
      }
      
      rethrow;
    }
  }
}
```