# Circuit Breaker Pattern Guide

Learn how to implement circuit breaker patterns in Flutter MCP to build resilient applications that gracefully handle failures.

## Overview

Flutter MCP includes built-in circuit breaker functionality to:
- Prevent cascading failures
- Provide automatic recovery
- Reduce load on failing services
- Improve overall system stability
- Enable graceful degradation

## Understanding Circuit Breakers

A circuit breaker works like an electrical circuit breaker, monitoring for failures and "tripping" when a threshold is reached:

1. **Closed**: Normal operation, requests pass through
2. **Open**: Failure threshold exceeded, requests fail fast
3. **Half-Open**: Testing if service has recovered

## Basic Circuit Breaker Usage

### Simple Circuit Breaker

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

// Create a circuit breaker
final circuitBreaker = CircuitBreaker(
  failureThreshold: 5,          // Open after 5 failures
  resetTimeout: Duration(seconds: 30), // Try again after 30 seconds
  requestTimeout: Duration(seconds: 10), // Individual request timeout
);

// Use circuit breaker for protected calls
try {
  final result = await circuitBreaker.execute(() async {
    // Your potentially failing operation
    return await riskyApiCall();
  });
  
  print('Success: $result');
} on CircuitBreakerOpenException {
  print('Circuit breaker is open - service unavailable');
  // Use fallback behavior
} on TimeoutException {
  print('Request timed out');
}
```

### Circuit Breaker with Fallback

```dart
class ResilientService {
  final CircuitBreaker _circuitBreaker = CircuitBreaker(
    failureThreshold: 3,
    resetTimeout: Duration(seconds: 60),
    successThreshold: 2, // Require 2 successes to close
  );
  
  Future<String> getData() async {
    try {
      return await _circuitBreaker.execute(() async {
        // Primary service call
        return await _primaryService.getData();
      });
    } on CircuitBreakerOpenException {
      // Fallback to cache or alternative service
      return await _getCachedData();
    }
  }
  
  Future<String> _getCachedData() async {
    // Return cached or default data
    final cached = await LocalCache.get('last_known_data');
    return cached ?? 'Default fallback data';
  }
}
```

## Advanced Circuit Breaker Configuration

### Custom Failure Detection

```dart
class SmartCircuitBreaker {
  final CircuitBreaker _breaker;
  
  SmartCircuitBreaker() : _breaker = CircuitBreaker(
    failureThreshold: 5,
    resetTimeout: Duration(minutes: 1),
    // Custom failure detection
    onError: (error) {
      // Determine if error should count as failure
      if (error is SocketException || 
          error is TimeoutException ||
          (error is ApiException && error.statusCode >= 500)) {
        return true; // Count as failure
      }
      
      // 4xx errors don't open circuit
      if (error is ApiException && error.statusCode >= 400 && error.statusCode < 500) {
        return false;
      }
      
      return true; // Default: count as failure
    },
  );
  
  Future<T> call<T>(Future<T> Function() operation) async {
    return await _breaker.execute(operation);
  }
}
```

### Circuit Breaker with Metrics

```dart
class MonitoredCircuitBreaker {
  final CircuitBreaker _breaker;
  final _metrics = CircuitBreakerMetrics();
  
  MonitoredCircuitBreaker({
    required int failureThreshold,
    required Duration resetTimeout,
  }) : _breaker = CircuitBreaker(
    failureThreshold: failureThreshold,
    resetTimeout: resetTimeout,
    onStateChange: (oldState, newState) {
      _metrics.recordStateChange(oldState, newState);
      _logStateChange(oldState, newState);
    },
  );
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await _breaker.execute(operation);
      _metrics.recordSuccess(stopwatch.elapsed);
      return result;
    } catch (e) {
      _metrics.recordFailure(stopwatch.elapsed, e);
      rethrow;
    }
  }
  
  void _logStateChange(CircuitBreakerState oldState, CircuitBreakerState newState) {
    print('Circuit breaker state changed: $oldState -> $newState');
    
    if (newState == CircuitBreakerState.open) {
      // Alert when circuit opens
      FlutterMCP.instance.backgroundService.showNotification(
        title: 'Service Degraded',
        body: 'Circuit breaker opened due to failures',
      );
    }
  }
  
  CircuitBreakerMetrics get metrics => _metrics;
}

class CircuitBreakerMetrics {
  int successCount = 0;
  int failureCount = 0;
  Duration totalSuccessTime = Duration.zero;
  Duration totalFailureTime = Duration.zero;
  final List<StateTransition> stateChanges = [];
  
  void recordSuccess(Duration duration) {
    successCount++;
    totalSuccessTime += duration;
  }
  
  void recordFailure(Duration duration, dynamic error) {
    failureCount++;
    totalFailureTime += duration;
  }
  
  void recordStateChange(CircuitBreakerState from, CircuitBreakerState to) {
    stateChanges.add(StateTransition(
      from: from,
      to: to,
      timestamp: DateTime.now(),
    ));
  }
  
  double get successRate => successCount / (successCount + failureCount);
  Duration get averageSuccessTime => totalSuccessTime ~/ successCount;
  Duration get averageFailureTime => totalFailureTime ~/ failureCount;
}
```

## Circuit Breaker for MCP Operations

### Protected MCP Client Calls

```dart
class ResilientMCPClient {
  final String _clientId;
  final CircuitBreaker _breaker;
  
  ResilientMCPClient(this._clientId) : _breaker = CircuitBreaker(
    failureThreshold: 3,
    resetTimeout: Duration(seconds: 30),
    requestTimeout: Duration(seconds: 15),
  );
  
  Future<dynamic> callTool(String toolName, Map<String, dynamic> args) async {
    try {
      return await _breaker.execute(() async {
        return await FlutterMCP.instance.clientManager.callTool(
          _clientId,
          toolName,
          args,
        );
      });
    } on CircuitBreakerOpenException {
      // Log and use fallback
      print('Circuit breaker open for tool: $toolName');
      return _getFallbackResponse(toolName);
    }
  }
  
  dynamic _getFallbackResponse(String toolName) {
    // Return cached or default responses
    switch (toolName) {
      case 'getData':
        return {'data': [], 'cached': true};
      case 'getStatus':
        return {'status': 'unavailable', 'cached': true};
      default:
        throw MCPException('Service temporarily unavailable');
    }
  }
}
```

### Protected LLM Queries

```dart
class ResilientLLMService {
  final Map<String, CircuitBreaker> _llmBreakers = {};
  
  ResilientLLMService() {
    // Create circuit breaker for each LLM
    for (final llmId in ['openai', 'anthropic', 'google']) {
      _llmBreakers[llmId] = CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: Duration(minutes: 2),
        successThreshold: 3,
      );
    }
  }
  
  Future<LLMResponse> query({
    required String prompt,
    String? preferredLlm,
  }) async {
    // Try preferred LLM first
    if (preferredLlm != null && _llmBreakers.containsKey(preferredLlm)) {
      try {
        return await _queryWithBreaker(preferredLlm, prompt);
      } catch (e) {
        print('Preferred LLM failed: $e');
      }
    }
    
    // Fallback to other LLMs
    for (final entry in _llmBreakers.entries) {
      if (entry.key == preferredLlm) continue;
      
      try {
        return await _queryWithBreaker(entry.key, prompt);
      } catch (e) {
        print('LLM ${entry.key} failed: $e');
        continue;
      }
    }
    
    throw MCPException('All LLM services are unavailable');
  }
  
  Future<LLMResponse> _queryWithBreaker(String llmId, String prompt) async {
    final breaker = _llmBreakers[llmId]!;
    
    return await breaker.execute(() async {
      return await FlutterMCP.instance.llmManager.query(
        llmId: llmId,
        prompt: prompt,
        options: QueryOptions(
          timeout: Duration(seconds: 30),
          temperature: 0.7,
        ),
      );
    });
  }
}
```

## Circuit Breaker Patterns

### Cascading Circuit Breakers

```dart
class CascadingCircuitBreakers {
  // Main service breaker
  final _mainBreaker = CircuitBreaker(
    failureThreshold: 5,
    resetTimeout: Duration(minutes: 5),
  );
  
  // Individual endpoint breakers
  final Map<String, CircuitBreaker> _endpointBreakers = {};
  
  Future<T> callEndpoint<T>(String endpoint, Future<T> Function() operation) async {
    // Check main breaker first
    if (_mainBreaker.state == CircuitBreakerState.open) {
      throw CircuitBreakerOpenException('Main service unavailable');
    }
    
    // Get or create endpoint breaker
    final endpointBreaker = _endpointBreakers.putIfAbsent(
      endpoint,
      () => CircuitBreaker(
        failureThreshold: 3,
        resetTimeout: Duration(minutes: 1),
      ),
    );
    
    try {
      // Execute through both breakers
      return await _mainBreaker.execute(() async {
        return await endpointBreaker.execute(operation);
      });
    } catch (e) {
      // Check if too many endpoints are failing
      _checkOverallHealth();
      rethrow;
    }
  }
  
  void _checkOverallHealth() {
    final failingEndpoints = _endpointBreakers.entries
      .where((e) => e.value.state == CircuitBreakerState.open)
      .length;
    
    // Open main breaker if too many endpoints fail
    if (failingEndpoints > _endpointBreakers.length * 0.5) {
      _mainBreaker.forceOpen();
    }
  }
}
```

### Adaptive Circuit Breaker

```dart
class AdaptiveCircuitBreaker {
  CircuitBreaker _breaker;
  final _performanceMonitor = PerformanceMonitor();
  
  AdaptiveCircuitBreaker() : _breaker = _createBreaker(5, 30);
  
  static CircuitBreaker _createBreaker(int threshold, int timeoutSeconds) {
    return CircuitBreaker(
      failureThreshold: threshold,
      resetTimeout: Duration(seconds: timeoutSeconds),
    );
  }
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await _breaker.execute(operation);
      _performanceMonitor.recordSuccess(stopwatch.elapsed);
      
      // Adapt based on performance
      _adaptConfiguration();
      
      return result;
    } catch (e) {
      _performanceMonitor.recordFailure(stopwatch.elapsed);
      _adaptConfiguration();
      rethrow;
    }
  }
  
  void _adaptConfiguration() {
    final stats = _performanceMonitor.getStats();
    
    // Increase sensitivity if error rate is climbing
    if (stats.errorRate > 0.3) {
      _breaker = _createBreaker(3, 60); // More sensitive
    }
    // Decrease sensitivity if stable
    else if (stats.errorRate < 0.05 && stats.successCount > 100) {
      _breaker = _createBreaker(10, 30); // Less sensitive
    }
    
    // Adjust timeout based on response times
    if (stats.averageResponseTime > Duration(seconds: 10)) {
      _breaker = _createBreaker(
        _breaker.failureThreshold,
        120, // Longer reset timeout for slow services
      );
    }
  }
}
```

## Integration with Health Monitoring

### Health-Aware Circuit Breaker

```dart
class HealthAwareCircuitBreaker {
  final String _componentId;
  final CircuitBreaker _breaker;
  Timer? _healthCheckTimer;
  
  HealthAwareCircuitBreaker(this._componentId) : _breaker = CircuitBreaker(
    failureThreshold: 5,
    resetTimeout: Duration(minutes: 1),
    onStateChange: (oldState, newState) {
      // Update component health when state changes
      _updateComponentHealth(newState);
    },
  );
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check component health first
    final health = await FlutterMCP.instance.getComponentHealth(_componentId);
    
    if (health.status == HealthStatus.unhealthy) {
      throw CircuitBreakerOpenException('Component unhealthy');
    }
    
    return await _breaker.execute(operation);
  }
  
  void _updateComponentHealth(CircuitBreakerState state) {
    final status = switch (state) {
      CircuitBreakerState.closed => HealthStatus.healthy,
      CircuitBreakerState.open => HealthStatus.unhealthy,
      CircuitBreakerState.halfOpen => HealthStatus.degraded,
    };
    
    // Update health monitoring system
    HealthMonitor.instance.updateComponentStatus(_componentId, status);
  }
  
  void startHealthChecks() {
    _healthCheckTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      if (_breaker.state == CircuitBreakerState.open) {
        // Perform active health check
        try {
          await _performHealthCheck();
          // If successful, transition to half-open
          _breaker.reset();
        } catch (e) {
          // Still unhealthy
        }
      }
    });
  }
  
  Future<void> _performHealthCheck() async {
    // Component-specific health check
    // Throws if unhealthy
  }
  
  void dispose() {
    _healthCheckTimer?.cancel();
  }
}
```

## Circuit Breaker Dashboard

### Monitoring UI

```dart
class CircuitBreakerDashboard extends StatefulWidget {
  final Map<String, MonitoredCircuitBreaker> breakers;
  
  CircuitBreakerDashboard({required this.breakers});
  
  @override
  _CircuitBreakerDashboardState createState() => _CircuitBreakerDashboardState();
}

class _CircuitBreakerDashboardState extends State<CircuitBreakerDashboard> {
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() {}); // Refresh UI
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
      ),
      itemCount: widget.breakers.length,
      itemBuilder: (context, index) {
        final entry = widget.breakers.entries.elementAt(index);
        return _buildBreakerCard(entry.key, entry.value);
      },
    );
  }
  
  Widget _buildBreakerCard(String name, MonitoredCircuitBreaker breaker) {
    final state = breaker._breaker.state;
    final metrics = breaker.metrics;
    final color = _getStateColor(state);
    
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStateIcon(state),
                  color: color,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  name,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Spacer(),
            Text('State: ${state.toString().split('.').last}'),
            Text('Success Rate: ${(metrics.successRate * 100).toStringAsFixed(1)}%'),
            Text('Failures: ${metrics.failureCount}'),
            if (state == CircuitBreakerState.open)
              Text(
                'Reset in: ${_getResetTime(breaker._breaker)}',
                style: TextStyle(color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }
  
  Color _getStateColor(CircuitBreakerState state) {
    switch (state) {
      case CircuitBreakerState.closed:
        return Colors.green;
      case CircuitBreakerState.open:
        return Colors.red;
      case CircuitBreakerState.halfOpen:
        return Colors.orange;
    }
  }
  
  IconData _getStateIcon(CircuitBreakerState state) {
    switch (state) {
      case CircuitBreakerState.closed:
        return Icons.check_circle;
      case CircuitBreakerState.open:
        return Icons.cancel;
      case CircuitBreakerState.halfOpen:
        return Icons.pending;
    }
  }
  
  String _getResetTime(CircuitBreaker breaker) {
    // Calculate remaining time until reset
    // This would need access to internal breaker state
    return '30s';
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
```

## Best Practices

### 1. Failure Threshold Configuration

```dart
// Base thresholds on criticality
class CircuitBreakerFactory {
  static CircuitBreaker create(ServiceCriticality criticality) {
    switch (criticality) {
      case ServiceCriticality.critical:
        return CircuitBreaker(
          failureThreshold: 10,    // More tolerant
          resetTimeout: Duration(seconds: 30), // Quick recovery
          successThreshold: 3,     // Ensure stability
        );
      
      case ServiceCriticality.important:
        return CircuitBreaker(
          failureThreshold: 5,
          resetTimeout: Duration(minutes: 1),
          successThreshold: 2,
        );
      
      case ServiceCriticality.standard:
        return CircuitBreaker(
          failureThreshold: 3,
          resetTimeout: Duration(minutes: 2),
          successThreshold: 1,
        );
    }
  }
}
```

### 2. Graceful Degradation

```dart
class GracefulDegradationService {
  final CircuitBreaker _primaryBreaker;
  final CircuitBreaker _fallbackBreaker;
  
  GracefulDegradationService()
    : _primaryBreaker = CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: Duration(minutes: 1),
      ),
      _fallbackBreaker = CircuitBreaker(
        failureThreshold: 10, // More tolerant for fallback
        resetTimeout: Duration(minutes: 5),
      );
  
  Future<Data> getData() async {
    // Try primary service
    try {
      return await _primaryBreaker.execute(() async {
        return await _primaryService.getData();
      });
    } catch (e) {
      print('Primary service failed: $e');
    }
    
    // Try fallback service
    try {
      return await _fallbackBreaker.execute(() async {
        return await _fallbackService.getData();
      });
    } catch (e) {
      print('Fallback service failed: $e');
    }
    
    // Last resort: return cached/default data
    return _getCachedOrDefaultData();
  }
}
```

### 3. Circuit Breaker Testing

```dart
void main() {
  group('Circuit Breaker Tests', () {
    test('Opens after threshold failures', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 3,
        resetTimeout: Duration(seconds: 1),
      );
      
      // Cause failures
      for (int i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async {
            throw Exception('Test failure');
          });
        } catch (_) {}
      }
      
      expect(breaker.state, equals(CircuitBreakerState.open));
      
      // Should fail fast when open
      expect(
        () => breaker.execute(() async => 'success'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });
    
    test('Transitions to half-open after timeout', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 1,
        resetTimeout: Duration(milliseconds: 100),
      );
      
      // Open the breaker
      try {
        await breaker.execute(() async {
          throw Exception('Test failure');
        });
      } catch (_) {}
      
      expect(breaker.state, equals(CircuitBreakerState.open));
      
      // Wait for reset timeout
      await Future.delayed(Duration(milliseconds: 150));
      
      // Next call should attempt (half-open)
      final result = await breaker.execute(() async => 'success');
      expect(result, equals('success'));
      expect(breaker.state, equals(CircuitBreakerState.closed));
    });
  });
}
```

## Common Patterns

### 1. Bulkhead Pattern

```dart
class BulkheadService {
  final Map<String, CircuitBreaker> _bulkheads = {};
  final int _maxConcurrentCalls = 10;
  final Map<String, int> _activeCalls = {};
  
  Future<T> isolatedCall<T>(
    String isolationKey,
    Future<T> Function() operation,
  ) async {
    // Get or create circuit breaker for this bulkhead
    final breaker = _bulkheads.putIfAbsent(
      isolationKey,
      () => CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: Duration(minutes: 1),
      ),
    );
    
    // Check concurrent calls limit
    final active = _activeCalls[isolationKey] ?? 0;
    if (active >= _maxConcurrentCalls) {
      throw BulkheadRejectedException('Too many concurrent calls');
    }
    
    _activeCalls[isolationKey] = active + 1;
    
    try {
      return await breaker.execute(operation);
    } finally {
      _activeCalls[isolationKey] = (_activeCalls[isolationKey] ?? 1) - 1;
    }
  }
}
```

### 2. Rate Limiting with Circuit Breaker

```dart
class RateLimitedCircuitBreaker {
  final CircuitBreaker _breaker;
  final RateLimiter _rateLimiter;
  
  RateLimitedCircuitBreaker({
    required int requestsPerMinute,
    required int failureThreshold,
  }) : _breaker = CircuitBreaker(
         failureThreshold: failureThreshold,
         resetTimeout: Duration(minutes: 1),
       ),
       _rateLimiter = RateLimiter(
         maxRequests: requestsPerMinute,
         window: Duration(minutes: 1),
       );
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check rate limit first
    if (!_rateLimiter.tryAcquire()) {
      throw RateLimitExceededException();
    }
    
    // Then check circuit breaker
    return await _breaker.execute(operation);
  }
}
```

## Troubleshooting

### Common Issues

1. **Circuit breaker opens too frequently**
   - Increase failure threshold
   - Check if transient errors should count as failures
   - Verify timeout settings aren't too aggressive

2. **Circuit breaker doesn't recover**
   - Check if service is actually healthy
   - Verify half-open test requests succeed
   - Consider implementing active health checks

3. **Memory leaks with many breakers**
   - Implement breaker pooling
   - Clean up unused breakers
   - Set maximum breaker lifetime

### Debug Logging

```dart
// Enable circuit breaker debug logging
CircuitBreaker.enableDebugLogging = true;

// Custom logger
final breaker = CircuitBreaker(
  failureThreshold: 5,
  resetTimeout: Duration(minutes: 1),
  logger: (message) {
    debugPrint('[CircuitBreaker] $message');
  },
);
```

## See Also

- [Health Monitoring Guide](../monitoring/health-checks.md)
- [Batch Processing Guide](batch-processing.md)
- [Performance Monitoring](../guides/performance-monitoring-guide.md)