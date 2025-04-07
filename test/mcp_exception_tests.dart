import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:flutter_mcp/src/utils/error_recovery.dart';

void main() {
  group('MCPException Tests', () {
    test('Basic exception creation', () {
      final exception = MCPException('Test error message');

      expect(exception.message, 'Test error message');
      expect(exception.originalError, null);
      expect(exception.originalStackTrace, null);
      expect(exception.toString(), 'MCPException: Test error message');
    });

    test('Exception with original error', () {
      final originalError = FormatException('Original format error');
      final exception = MCPException('Test error message', originalError);

      expect(exception.message, 'Test error message');
      expect(exception.originalError, originalError);
      expect(exception.toString(), 'MCPException: Test error message (Original error: FormatException: Original format error)');
    });

    test('Specialized exceptions', () {
      // Test various specialized exceptions
      final initException = MCPInitializationException('Init failed');
      expect(initException.toString(), 'MCPException: Initialization error: Init failed');

      final platformException = MCPPlatformNotSupportedException('background');
      expect(platformException.toString(), 'MCPException: Platform does not support the feature: background');
      expect(platformException.feature, 'background');

      final configException = MCPConfigurationException('Invalid config');
      expect(configException.toString(), 'MCPException: Configuration error: Invalid config');

      final networkException = MCPNetworkException(
        'Connection failed',
        statusCode: 404,
        responseBody: 'Not found',
      );
      expect(networkException.toString(), 'MCPException: Network error: Connection failed (Status: 404)');
      expect(networkException.statusCode, 404);
      expect(networkException.responseBody, 'Not found');

      final authException = MCPAuthenticationException('Invalid API key');
      expect(authException.toString(), 'MCPException: Authentication error: Invalid API key');
    });

    test('Operation failed exception', () {
      final innerError = TimeoutException('Connection timed out');
      final opException = MCPOperationFailedException(
        'Operation X failed',
        innerError,
        StackTrace.current,
      );

      expect(opException.message, 'Operation X failed');
      expect(opException.innerError, innerError);
      expect(opException.toString(), contains('MCPOperationFailedException: Operation X failed'));
      expect(opException.toString(), contains('Inner error: TimeoutException: Connection timed out'));
    });

    test('Timeout exception', () {
      final timeout = Duration(seconds: 30);
      final timeoutException = MCPTimeoutException('Request timed out', timeout);

      expect(timeoutException.message, 'Request timed out');
      expect(timeoutException.timeout, timeout);
    });

    test('Validation exception', () {
      final validationErrors = {
        'username': 'Username is required',
        'password': 'Password must be at least 8 characters',
      };

      final validationException = MCPValidationException(
        'Validation failed',
        validationErrors,
      );

      expect(validationException.message, 'Validation error: Validation failed');
      expect(validationException.validationErrors, validationErrors);
      expect(validationException.toString(), contains('username: Username is required'));
      expect(validationException.toString(), contains('password: Password must be at least 8 characters'));
    });
  });

  group('ErrorRecovery Tests', () {
    test('Retry successful on second attempt', () async {
      int attempts = 0;

      final result = await ErrorRecovery.tryWithRetry<String>(
            () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('First attempt failed');
          }
          return 'Success';
        },
        maxRetries: 3,
        initialDelay: Duration(milliseconds: 10),
      );

      expect(result, 'Success');
      expect(attempts, 2);
    });

    test('Retry exhausts all attempts', () async {
      int attempts = 0;

      expect(
            () => ErrorRecovery.tryWithRetry<String>(
              () async {
            attempts++;
            throw Exception('Always fails');
          },
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );

      expect(attempts, 4); // Initial attempt + 3 retries
    });

    test('Retry only if condition is met', () async {
      int attempts = 0;

      expect(
            () => ErrorRecovery.tryWithRetry<String>(
              () async {
            attempts++;
            throw FormatException('Non-retryable error');
          },
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
          retryIf: (e) => e is! FormatException, // Don't retry FormatException
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );

      // Should only try once because the error didn't match retryIf
      expect(attempts, 1);
    });

    test('Try with timeout success', () async {
      final result = await ErrorRecovery.tryWithTimeout<String>(
            () async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'Success';
        },
        Duration(milliseconds: 100),
      );

      expect(result, 'Success');
    });

    test('Try with timeout failure', () async {
      expect(
            () => ErrorRecovery.tryWithTimeout<String>(
              () async {
            // Delay longer than timeout
            await Future.delayed(Duration(milliseconds: 50));
            return 'Success';
          },
          Duration(milliseconds: 20),
        ),
        throwsA(isA<MCPTimeoutException>()),
      );
    });

    test('Try with fallback to alternative implementation', () async {
      final result = await ErrorRecovery.tryWithFallback<String>(
            () async => throw Exception('Primary implementation failed'),
            () async => 'Fallback success',
      );

      expect(result, 'Fallback success');
    });

    test('Try with fallback where both fail', () async {
      expect(
            () => ErrorRecovery.tryWithFallback<String>(
              () async => throw Exception('Primary implementation failed'),
              () async => throw Exception('Fallback implementation also failed'),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('Circuit breaker state transitions', () {
      final breaker = CircuitBreaker(
        name: 'test',
        failureThreshold: 2,
        resetTimeout: Duration(milliseconds: 50),
        successThreshold: 1,
      );

      // Initially closed
      expect(breaker.state, CircuitBreakerState.closed);
      expect(breaker.allowRequest, true);

      // Record failures to trigger open state
      breaker.recordFailure();
      expect(breaker.state, CircuitBreakerState.closed);

      breaker.recordFailure();
      expect(breaker.state, CircuitBreakerState.open);
      expect(breaker.allowRequest, false);

      // After timeout, should transition to half-open
      Future.delayed(Duration(milliseconds: 100), () {
        expect(breaker.allowRequest, true);
        expect(breaker.state, CircuitBreakerState.halfOpen);

        // Record success to close the circuit
        breaker.recordSuccess();
        expect(breaker.state, CircuitBreakerState.closed);
      });
    });
  });
}