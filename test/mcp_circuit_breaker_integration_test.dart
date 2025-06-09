import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:mockito/mockito.dart';

import 'mcp_integration_test.dart';
import 'mcp_integration_test.mocks.dart';

class CircuitBreakerTestFlutterMCP extends TestFlutterMCP {
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  final List<Map<String, dynamic>> circuitBreakerEvents = [];
  
  CircuitBreakerTestFlutterMCP(super.platformServices) {
    // Initialize circuit breakers first
    _initializeCircuitBreakers();
    
    // Then listen for circuit breaker events
    EventSystem.instance.subscribe<Map<String, dynamic>>('circuit_breaker.opened', (data) {
      print('Received circuit_breaker.opened event: $data');
      circuitBreakerEvents.add({
        'type': 'opened',
        'data': data
      });
    });
    
    EventSystem.instance.subscribe<Map<String, dynamic>>('circuit_breaker.closed', (data) {
      print('Received circuit_breaker.closed event: $data');
      circuitBreakerEvents.add({
        'type': 'closed',
        'data': data
      });
    });
  }
  
  void _initializeCircuitBreakers() {
    // LLM chat circuit breaker
    _circuitBreakers['llm.chat'] = CircuitBreaker(
      name: 'llm.chat',
      failureThreshold: 3,
      resetTimeout: Duration(milliseconds: 200), // Set short timeout for testing
      onOpen: () {
        print('Circuit breaker onOpen callback called for llm.chat');
        EventSystem.instance.publish('circuit_breaker.opened', {'operation': 'llm.chat'});
      },
      onClose: () {
        print('Circuit breaker onClose callback called for llm.chat');
        EventSystem.instance.publish('circuit_breaker.closed', {'operation': 'llm.chat'});
      },
    );

    // Tool execution circuit breaker
    _circuitBreakers['tool.call'] = CircuitBreaker(
      name: 'tool.call',
      failureThreshold: 2,
      resetTimeout: Duration(milliseconds: 200), // Set short timeout for testing
      onOpen: () {
        EventSystem.instance.publish('circuit_breaker.opened', {'operation': 'tool.call'});
      },
      onClose: () {
        EventSystem.instance.publish('circuit_breaker.closed', {'operation': 'tool.call'});
      },
    );
  }
  
  /// Execute through circuit breaker
  Future<T> executeWithCircuitBreaker<T>(String breakerName, Future<T> Function() operation) async {
    final breaker = _circuitBreakers[breakerName];
    if (breaker == null) {
      throw MCPException('Circuit breaker not found: $breakerName');
    }
    
    return await breaker.execute(operation);
  }
  
  /// Manually record failure for testing
  void recordCircuitBreakerFailure(String breakerName, dynamic error) {
    final breaker = _circuitBreakers[breakerName];
    if (breaker == null) {
      throw MCPException('Circuit breaker not found: $breakerName');
    }
    
    print('Recording failure for $breakerName. Current state: ${breaker.state}');
    breaker.recordFailure(error);
    print('After recording failure. New state: ${breaker.state}');
  }
  
  /// Get circuit breaker state
  CircuitBreakerState getCircuitBreakerState(String breakerName) {
    final breaker = _circuitBreakers[breakerName];
    if (breaker == null) {
      throw MCPException('Circuit breaker not found: $breakerName');
    }
    
    return breaker.state;
  }
  
  /// Reset circuit breaker
  void resetCircuitBreaker(String breakerName) {
    final breaker = _circuitBreakers[breakerName];
    if (breaker == null) {
      throw MCPException('Circuit breaker not found: $breakerName');
    }
    
    breaker.reset();
  }
  
  void clearEvents() {
    circuitBreakerEvents.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPlatformServices mockPlatformServices;
  late CircuitBreakerTestFlutterMCP flutterMcp;
  
  setUp(() {
    mockPlatformServices = MockPlatformServices();
    
    // Mock platform services behavior
    when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
    when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(false);
    when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
    when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
    when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
    when(mockPlatformServices.secureRead(any)).thenAnswer((_) async => 'mock-stored-value');
    
    flutterMcp = CircuitBreakerTestFlutterMCP(mockPlatformServices);
  });
  
  group('Circuit Breaker Integration Tests', () {
    test('Circuit breaker opens after multiple failures', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Circuit Test',
        appVersion: '1.0.0',
        autoStart: false,
      );
      
      await flutterMcp.init(config);
      flutterMcp.clearEvents();
      
      // Verify initial state is closed
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.closed);
      
      // Record failures to reach threshold
      for (int i = 0; i < 3; i++) {
        flutterMcp.recordCircuitBreakerFailure('llm.chat', 'Test failure $i');
      }
      
      // Verify circuit breaker opened
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.open);
      
      // Wait for event to be processed
      await Future.delayed(Duration(milliseconds: 10));
      
      // Debug: Print events
      print('Circuit breaker events: ${flutterMcp.circuitBreakerEvents}');
      
      // Verify event was published
      expect(flutterMcp.circuitBreakerEvents.where((e) => e['type'] == 'opened').length, 1);
      
      // Verify operation fails when circuit is open
      expect(
        () => flutterMcp.executeWithCircuitBreaker('llm.chat', () async => 'result'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      
      // Clean up
      await flutterMcp.shutdown();
    });
    
    test('Circuit breaker transitions from open to half-open to closed', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Circuit Test',
        appVersion: '1.0.0',
        autoStart: false,
      );
      
      await flutterMcp.init(config);
      flutterMcp.clearEvents();
      
      // Open the circuit breaker
      for (int i = 0; i < 3; i++) {
        flutterMcp.recordCircuitBreakerFailure('llm.chat', 'Test failure $i');
      }
      
      // Verify circuit breaker opened
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.open);
      
      // Wait for reset timeout to transition to half-open
      await Future.delayed(Duration(milliseconds: 300)); // 1.5x the reset timeout for stability
      
      // Wait for event processing
      await Future.delayed(Duration(milliseconds: 10));
      
      // Execute a successful operation
      final result = await flutterMcp.executeWithCircuitBreaker('llm.chat', () async => 'success');
      
      // Verify operation succeeded and circuit is closed
      expect(result, 'success');
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.closed);
      
      // Wait for event to be processed
      await Future.delayed(Duration(milliseconds: 10));
      
      // Verify closed event was published
      expect(flutterMcp.circuitBreakerEvents.where((e) => e['type'] == 'closed').length, 1);
      
      // Clean up
      await flutterMcp.shutdown();
    });
    
    test('Circuit breaker prevents cascading failures', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Circuit Test',
        appVersion: '1.0.0',
        autoStart: false,
      );
      
      await flutterMcp.init(config);
      flutterMcp.clearEvents();
      
      // Create a flaky operation that fails every other time
      int attemptCount = 0;
      Future<String> flakyOperation() async {
        attemptCount++;
        print('flakyOperation attempt $attemptCount');
        if (attemptCount % 2 == 0) {
          throw Exception('Flaky operation failed');
        }
        return 'Operation succeeded';
      }
      
      // First execution succeeds (odd count)
      final result1 = await flutterMcp.executeWithCircuitBreaker('tool.call', flakyOperation);
      expect(result1, 'Operation succeeded');
      
      // Second execution fails (even count)
      try {
        await flutterMcp.executeWithCircuitBreaker('tool.call', flakyOperation);
        fail('Should have thrown an exception');
      } catch (e) {
        // Exception is expected
      }
      
      // Debug: Check current state
      print('After second execution - State: ${flutterMcp.getCircuitBreakerState('tool.call')}');
      print('Failure count: ${flutterMcp._circuitBreakers['tool.call']!.failureCount}');
      
      // Third execution should fail too (odd count would succeed but we'll make it fail)
      attemptCount++; // Force even count to make it fail
      try {
        await flutterMcp.executeWithCircuitBreaker('tool.call', flakyOperation);
        fail('Should have thrown an exception');
      } catch (e) {
        // Exception is expected - this should trigger the circuit breaker to open
        print('After third execution - State: ${flutterMcp.getCircuitBreakerState('tool.call')}');
        print('Failure count: ${flutterMcp._circuitBreakers['tool.call']!.failureCount}');
      }
      
      // Wait for async event processing
      await Future.delayed(Duration(milliseconds: 10));
      
      // Circuit should now be open after 2 failures
      expect(flutterMcp.getCircuitBreakerState('tool.call'), CircuitBreakerState.open);
      
      // All subsequent calls should fail fast with CircuitBreakerOpenException (not the original exception)
      expect(
        () => flutterMcp.executeWithCircuitBreaker('tool.call', flakyOperation),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      
      // After reset timeout, circuit should transition to half-open
      await Future.delayed(Duration(milliseconds: 300)); // 1.5x the reset timeout for stability
      
      // Next call succeeds and closes the circuit (odd count)
      final result2 = await flutterMcp.executeWithCircuitBreaker('tool.call', flakyOperation);
      expect(result2, 'Operation succeeded');
      expect(flutterMcp.getCircuitBreakerState('tool.call'), CircuitBreakerState.closed);
      
      // Clean up
      await flutterMcp.shutdown();
    });
    
    test('Multiple circuit breakers operate independently', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Multi Circuit Test',
        appVersion: '1.0.0',
        autoStart: false,
      );
      
      await flutterMcp.init(config);
      flutterMcp.clearEvents();
      
      // Trigger failures in the tool circuit breaker only
      for (int i = 0; i < 2; i++) {
        flutterMcp.recordCircuitBreakerFailure('tool.call', 'Tool failure $i');
      }
      
      // Verify tool circuit is open but llm circuit is still closed
      expect(flutterMcp.getCircuitBreakerState('tool.call'), CircuitBreakerState.open);
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.closed);
      
      // LLM operations should still succeed
      final result = await flutterMcp.executeWithCircuitBreaker('llm.chat', () async => 'llm success');
      expect(result, 'llm success');
      
      // Tool operations should fail
      expect(
        () => flutterMcp.executeWithCircuitBreaker('tool.call', () async => 'tool success'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      
      // Reset the tool circuit breaker
      flutterMcp.resetCircuitBreaker('tool.call');
      expect(flutterMcp.getCircuitBreakerState('tool.call'), CircuitBreakerState.closed);
      
      // Tool operations should now succeed
      final toolResult = await flutterMcp.executeWithCircuitBreaker('tool.call', () async => 'tool success');
      expect(toolResult, 'tool success');
      
      // Clean up
      await flutterMcp.shutdown();
    });
    
    test('Recovery after transient failures', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Recovery Test',
        appVersion: '1.0.0',
        autoStart: false,
      );
      
      await flutterMcp.init(config);
      flutterMcp.clearEvents();
      
      // Simulate a service experiencing transient failures
      int errorCount = 0;
      Future<String> transientService() async {
        errorCount++;
        print('transientService attempt $errorCount');
        if (errorCount < 4) {
          throw Exception('Transient failure');
        }
        return 'Service recovered';
      }
      
      // First three calls will fail and open the circuit
      for (int i = 0; i < 3; i++) {
        try {
          await flutterMcp.executeWithCircuitBreaker('llm.chat', transientService);
          fail('Should have thrown an exception');
        } catch (e) {
          // Exception is expected
          print('Failure $i recorded. Current state: ${flutterMcp.getCircuitBreakerState('llm.chat')}');
        }
      }
      
      // Wait for async event processing
      await Future.delayed(Duration(milliseconds: 10));
      
      // Circuit should now be open after 3 failures
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.open);
      
      // Calls fail fast now
      expect(
        () => flutterMcp.executeWithCircuitBreaker('llm.chat', transientService),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      
      // Wait for reset timeout 
      await Future.delayed(Duration(milliseconds: 250));
      
      // Debug circuit state after timeout
      print('Circuit state after timeout: ${flutterMcp.getCircuitBreakerState('llm.chat')}');
      
      // Service has recovered - the next call should increment errorCount to 4 and succeed
      final result = await flutterMcp.executeWithCircuitBreaker('llm.chat', transientService);
      expect(result, 'Service recovered');
      
      // Circuit should be closed again
      expect(flutterMcp.getCircuitBreakerState('llm.chat'), CircuitBreakerState.closed);
      
      // Clean up
      await flutterMcp.shutdown();
    });
  });
}