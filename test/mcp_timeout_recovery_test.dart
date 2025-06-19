import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/utils/error_recovery.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';
import 'package:mockito/mockito.dart';
import 'dart:async';
import 'package:mcp_llm/mcp_llm.dart' as llm;

import 'mcp_integration_test.dart';
import 'mcp_integration_test.mocks.dart';

class TimeoutTestFlutterMCP extends TestFlutterMCP {
  final Map<String, int> retryAttempts = {};
  final Map<String, Map<String, dynamic>> requestLog = {};

  TimeoutTestFlutterMCP(super.platformServices);

  // Mock LLM request with configurable latency and failures
  Future<llm.LlmResponse> mockLlmRequestWithLatency(
    String llmId,
    String message, {
    bool enableTools = false,
    Map<String, dynamic> parameters = const {},
    bool useCache = true,
    Duration latency = Duration.zero,
    bool shouldFail = false,
    String? requestId,
  }) async {
    // Log the request
    final id = requestId ?? 'request_${DateTime.now().millisecondsSinceEpoch}';
    requestLog[id] = {
      'llmId': llmId,
      'message': message,
      'enableTools': enableTools,
      'parameters': parameters,
      'useCache': useCache,
      'requestTime': DateTime.now(),
    };

    // Track retry attempts
    retryAttempts[id] = (retryAttempts[id] ?? 0) + 1;

    // Simulate latency
    if (latency > Duration.zero) {
      await Future.delayed(latency);
    }

    // Simulate failure if requested
    if (shouldFail) {
      throw MCPTimeoutException(
          'Request timed out', Duration(milliseconds: 5000));
    }

    // Return mock response
    return llm.LlmResponse(
      text: 'This is a test response from mock LLM',
      metadata: {
        'latency_ms': latency.inMilliseconds,
        'retry_count': retryAttempts[id],
        'request_id': id,
      },
    );
  }

  // Chat with timeout recovery
  Future<LlmResponse> chatWithRetry(
    String llmId,
    String message, {
    bool enableTools = false,
    Map<String, dynamic> parameters = const {},
    bool useCache = true,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 3,
  }) async {
    final requestId = 'retry_${DateTime.now().millisecondsSinceEpoch}';

    return await ErrorRecovery.tryWithRetry<LlmResponse>(
      () => ErrorRecovery.tryWithTimeout<LlmResponse>(
        () => mockLlmRequestWithLatency(
          llmId,
          message,
          enableTools: enableTools,
          parameters: parameters,
          useCache: useCache,
          requestId: requestId,
          // Pass in latency and shouldFail based on retry count
          latency: Duration(milliseconds: (retryAttempts[requestId] ?? 0) * 50),
          shouldFail:
              (retryAttempts[requestId] ?? 0) < 2, // Fail first two attempts
        ),
        timeout,
      ),
      maxRetries: maxRetries,
      retryIf: (e) {
        // Check for timeout exceptions or wrapped timeout exceptions
        if (e is MCPTimeoutException || e is TimeoutException) {
          return true;
        }
        if (e is MCPOperationFailedException) {
          final inner = e.innerError;
          return inner is MCPTimeoutException || inner is TimeoutException;
        }
        return false;
      },
      initialDelay: const Duration(milliseconds: 50),
    );
  }

  // Mock storage for saved methods
  dynamic _savedMethod;

  // Save the original method
  void saveMethod(dynamic method) {
    _savedMethod = method;
  }

  // Restore the saved method
  dynamic getSavedMethod() {
    return _savedMethod;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPlatformServices mockPlatformServices;
  late TimeoutTestFlutterMCP flutterMcp;

  setUp(() {
    mockPlatformServices = MockPlatformServices();

    // Mock platform services behavior
    when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
    when(mockPlatformServices.startBackgroundService())
        .thenAnswer((_) async => true);
    when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
    when(mockPlatformServices.secureRead(any))
        .thenAnswer((_) async => 'mock-stored-value');

    flutterMcp = TimeoutTestFlutterMCP(mockPlatformServices);
  });

  group('Timeout and Recovery Tests', () {
    test('Successful recovery after timeouts', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Timeout Test',
        appVersion: '1.0.0',
        autoStart: false,
        llmRequestTimeoutMs: 100, // Short timeout for testing
      );

      await flutterMcp.init(config);

      // Create a test LLM
      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Execute request with retry logic
      final response = await flutterMcp.chatWithRetry(
        llmId,
        'Hello world',
        timeout: Duration(milliseconds: 200),
        maxRetries: 3,
      );

      // Verify request was retried and eventually succeeded
      expect(response.text, 'This is a test response from mock LLM');

      // Find the request ID from the response
      final requestId = response.metadata['request_id'] as String;

      // Verify it took 3 attempts to succeed (first two failed)
      expect(flutterMcp.retryAttempts[requestId], 3);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Failure after exhausting retries', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Timeout Test',
        appVersion: '1.0.0',
        autoStart: false,
      );

      await flutterMcp.init(config);

      // Create a test LLM
      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Save original method (not used in this test, but preserved for consistency)
      // flutterMcp.saveMethod(flutterMcp.mockLlmRequestWithLatency);

      // Replace with a function that always fails
      Future<LlmResponse> alwaysFailFn(
        String llmId,
        String message, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        bool useCache = true,
        Duration latency = Duration.zero,
        bool shouldFail = false,
        String? requestId,
      }) async {
        // Always fail for this test
        throw MCPTimeoutException(
            'Always timeout', Duration(milliseconds: 1000));
      }

      // Execute request with retry logic
      try {
        await ErrorRecovery.tryWithRetry<LlmResponse>(
          () => ErrorRecovery.tryWithTimeout<LlmResponse>(
            () => alwaysFailFn(
              llmId,
              'Hello world',
              requestId: 'test_failure',
            ),
            Duration(milliseconds: 50),
          ),
          maxRetries: 2, // Allow 2 retries (3 total attempts)
          retryIf: (e) {
            // Check for timeout exceptions or wrapped timeout exceptions
            if (e is MCPTimeoutException || e is TimeoutException) {
              return true;
            }
            if (e is MCPOperationFailedException) {
              final inner = e.innerError;
              return inner is MCPTimeoutException || inner is TimeoutException;
            }
            return false;
          },
        );

        fail('Should have thrown an exception');
      } catch (e) {
        // Verify the exception is of the expected type
        expect(e, isA<MCPOperationFailedException>());

        // Check if the inner error is wrapped correctly
        if (e is MCPOperationFailedException) {
          final inner = e.innerError;
          // The inner error might be another MCPOperationFailedException wrapping the timeout
          if (inner is MCPOperationFailedException) {
            expect(inner.innerError, isA<MCPTimeoutException>());
          } else {
            expect(inner, isA<MCPTimeoutException>());
          }
        }
      }

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Fallback to alternative implementation on timeout', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Fallback Test',
        appVersion: '1.0.0',
        autoStart: false,
      );

      await flutterMcp.init(config);

      // Primary implementation that will fail
      Future<LlmResponse> primaryImplementation() async {
        throw MCPTimeoutException(
            'Primary implementation timed out', Duration(milliseconds: 5000));
      }

      // Fallback implementation that will succeed
      Future<LlmResponse> fallbackImplementation() async {
        return llm.LlmResponse(
          text: 'Response from fallback implementation',
          metadata: {
            'fallback': true,
          },
        );
      }

      // Use fallback pattern
      final response = await ErrorRecovery.tryWithFallback<LlmResponse>(
        primaryImplementation,
        fallbackImplementation,
      );

      // Verify fallback was used
      expect(response.text, 'Response from fallback implementation');
      expect(response.metadata['fallback'], isTrue);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Progressive timeout increase for retries', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Progressive Timeout Test',
        appVersion: '1.0.0',
        autoStart: false,
      );

      await flutterMcp.init(config);

      // Mock implementation with increasing latency
      int attemptCount = 0;
      Future<LlmResponse> progressiveLatencyOperation() async {
        attemptCount++;

        // First attempt: 50ms latency (time out at 30ms) - will fail
        // Second attempt: 100ms latency (time out at 60ms) - will fail
        // Third attempt: 150ms latency (time out at 200ms) - should succeed
        final latency = Duration(milliseconds: 50 * attemptCount);

        // Ensure more stable timeout windows with greater difference between latency and timeout
        // for first two attempts and the opposite for the last
        final timeout = attemptCount < 3
            ? Duration(
                milliseconds:
                    30 * attemptCount) // Shorter than latency (will timeout)
            : Duration(milliseconds: 200); // Longer than latency (will succeed)

        // Log for testing visibility
        final logger = MCPLogger('test.timeout');
        logger.debug(
            'Attempt $attemptCount - Latency: ${latency.inMilliseconds}ms, Timeout: ${timeout.inMilliseconds}ms');

        try {
          return await ErrorRecovery.tryWithTimeout<LlmResponse>(
            () async {
              await Future.delayed(latency);
              return llm.LlmResponse(
                text: 'Response with progressive timeout',
                metadata: {
                  'attempt': attemptCount,
                  'latency_ms': latency.inMilliseconds,
                },
              );
            },
            timeout,
          );
        } catch (e) {
          logger.debug('Attempt $attemptCount timed out');
          rethrow;
        }
      }

      // Use retry pattern with progressive timeouts
      final response = await ErrorRecovery.tryWithRetry<LlmResponse>(
        progressiveLatencyOperation,
        maxRetries: 3,
        retryIf: (e) => e is MCPTimeoutException || e is TimeoutException,
      );

      // Verify it took 3 attempts to succeed
      expect(attemptCount, 3);
      expect(response.metadata['attempt'], 3);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Circuit breaker integration with timeout recovery', () async {
      // Initialize MCP
      final config = MCPConfig(
        appName: 'Circuit Breaker Test',
        appVersion: '1.0.0',
        autoStart: false,
      );

      await flutterMcp.init(config);

      // Create a simple circuit breaker
      final circuitBreaker = CircuitBreaker(
        name: 'timeout_test',
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 500),
      );

      // Create a flaky service with timeouts
      int attemptCount = 0;
      Future<String> flakyTimeoutService() async {
        attemptCount++;

        if (attemptCount <= 3) {
          await Future.delayed(Duration(milliseconds: 10));
          throw MCPTimeoutException(
              'Service timed out', Duration(milliseconds: 1000));
        }

        return 'Service response';
      }

      // Separate each invocation to the circuit breaker
      // First attempt with retry (this should fail with multiple retries)
      try {
        await circuitBreaker.execute(() => ErrorRecovery.tryWithRetry<String>(
              flakyTimeoutService,
              maxRetries: 0, // No retry on first attempt
              retryIf: (e) {
                // Check for timeout exceptions or wrapped timeout exceptions
                if (e is MCPTimeoutException || e is TimeoutException) {
                  return true;
                }
                if (e is MCPOperationFailedException) {
                  final inner = e.innerError;
                  return inner is MCPTimeoutException ||
                      inner is TimeoutException;
                }
                return false;
              },
            ));

        fail('Should have thrown an exception');
      } catch (e) {
        // First failure recorded
        expect(circuitBreaker.failureCount, 1);
      }

      // Second attempt (this should trigger the circuit breaker to open)
      try {
        await circuitBreaker.execute(() => ErrorRecovery.tryWithRetry<String>(
              flakyTimeoutService,
              maxRetries: 0, // No retry on second attempt either
              retryIf: (e) {
                // Check for timeout exceptions or wrapped timeout exceptions
                if (e is MCPTimeoutException || e is TimeoutException) {
                  return true;
                }
                if (e is MCPOperationFailedException) {
                  final inner = e.innerError;
                  return inner is MCPTimeoutException ||
                      inner is TimeoutException;
                }
                return false;
              },
            ));

        fail('Should have thrown an exception');
      } catch (e) {
        // After 2 failures, the circuit breaker should open
        expect(circuitBreaker.state, CircuitBreakerState.open);
      }

      // Subsequent calls should fail fast with CircuitBreakerOpenException
      try {
        await circuitBreaker.execute(flakyTimeoutService);
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e, isA<CircuitBreakerOpenException>());
      }

      // After reset timeout, circuit should go to half-open
      await Future.delayed(
          Duration(milliseconds: 750)); // 1.5x the reset timeout for stability

      // Service has recovered (attempt count > 3)
      // Reset our attempt count to make the service succeed
      attemptCount = 10; // Force success
      final result = await circuitBreaker.execute(flakyTimeoutService);
      expect(result, 'Service response');

      // Circuit should be closed again
      expect(circuitBreaker.state, CircuitBreakerState.closed);

      // Clean up
      await flutterMcp.shutdown();
    });
  });
}
