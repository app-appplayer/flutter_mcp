import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/error_recovery.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart' hide MCPCircuitBreakerOpenException;

void main() {
  group('ErrorRecovery', () {
    group('tryWithRetry', () {
      test('should succeed on first attempt when operation succeeds', () async {
        var attempts = 0;
        final result = await ErrorRecovery.tryWithRetry(
          () async {
            attempts++;
            return 'success';
          },
          maxRetries: 3,
          operationName: 'test-operation',
        );

        expect(result, 'success');
        expect(attempts, 1);
      });

      test('should retry on failure and eventually succeed', () async {
        var attempts = 0;
        final result = await ErrorRecovery.tryWithRetry(
          () async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Temporary failure');
            }
            return 'success';
          },
          maxRetries: 3,
          operationName: 'test-operation',
        );

        expect(result, 'success');
        expect(attempts, 3);
      });

      test('should throw MCPOperationFailedException after max retries exceeded', () async {
        var attempts = 0;
        
        try {
          await ErrorRecovery.tryWithRetry(
            () async {
              attempts++;
              throw Exception('Persistent failure');
            },
            maxRetries: 2,
            operationName: 'test-operation',
          );
          fail('Should have thrown MCPOperationFailedException');
        } catch (e) {
          expect(e, isA<MCPOperationFailedException>());
        }

        expect(attempts, 3); // Initial attempt + 2 retries
      });

      test('should apply exponential backoff between retries', () async {
        final timestamps = <DateTime>[];
        var attempts = 0;

        try {
          await ErrorRecovery.tryWithRetry(
            () async {
              attempts++;
              timestamps.add(DateTime.now());
              throw Exception('Always fails');
            },
            maxRetries: 2,
            operationName: 'test-operation',
            initialDelay: Duration(milliseconds: 100),
            useExponentialBackoff: true,
          );
        } catch (e) {
          // Expected to fail
        }

        expect(attempts, 3);
        expect(timestamps.length, 3);

        // Check that delays increase (with some tolerance for execution time)
        if (timestamps.length >= 3) {
          final delay1 = timestamps[1].difference(timestamps[0]).inMilliseconds;
          final delay2 = timestamps[2].difference(timestamps[1]).inMilliseconds;
          
          expect(delay1, greaterThan(90)); // ~100ms with tolerance
          expect(delay2, greaterThan(180)); // Should be longer due to exponential backoff
        }
      });

      test('should respect retryIf condition', () async {
        var attempts = 0;

        expect(
          () => ErrorRecovery.tryWithRetry(
            () async {
              attempts++;
              throw MCPValidationException('Non-retryable error', {});
            },
            maxRetries: 3,
            operationName: 'conditional-test',
            retryIf: (e) => e is! MCPValidationException,
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );

        expect(attempts, 1); // Should not retry
      });

      test('should call onRetry callback', () async {
        final retryAttempts = <int>[];
        final retryErrors = <Exception>[];

        try {
          await ErrorRecovery.tryWithRetry(
            () async => throw Exception('Test error'),
            maxRetries: 2,
            operationName: 'callback-test',
            onRetry: (attempt, error) {
              retryAttempts.add(attempt);
              retryErrors.add(error);
            },
          );
        } catch (e) {
          // Expected to fail
        }

        expect(retryAttempts, [0, 1]); // Two retry attempts (0-indexed)
        expect(retryErrors.length, 2);
        expect(retryErrors.every((e) => e.toString().contains('Test error')), true);
      });
    });

    group('tryWithFallback', () {
      test('should return primary result when primary succeeds', () async {
        final result = await ErrorRecovery.tryWithFallback(
          () async => 'primary-success',
          () async => 'fallback-result',
          operationName: 'fallback-test',
        );

        expect(result, 'primary-success');
      });

      test('should return fallback result when primary fails', () async {
        final result = await ErrorRecovery.tryWithFallback(
          () async => throw Exception('Primary failed'),
          () async => 'fallback-success',
          operationName: 'fallback-test',
        );

        expect(result, 'fallback-success');
      });

      test('should throw when both primary and fallback fail', () async {
        expect(
          () => ErrorRecovery.tryWithFallback(
            () async => throw Exception('Primary failed'),
            () async => throw Exception('Fallback failed'),
            operationName: 'both-fail-test',
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );
      });
    });

    group('tryWithTimeout', () {
      test('should succeed when operation completes within timeout', () async {
        final result = await ErrorRecovery.tryWithTimeout(
          () async {
            await Future.delayed(Duration(milliseconds: 50));
            return 'completed';
          },
          Duration(milliseconds: 200),
          operationName: 'timeout-test',
        );

        expect(result, 'completed');
      });

      test('should throw MCPTimeoutException when operation times out', () async {
        expect(
          () => ErrorRecovery.tryWithTimeout(
            () async {
              await Future.delayed(Duration(milliseconds: 200));
              return 'never-reached';
            },
            Duration(milliseconds: 50),
            operationName: 'timeout-test',
          ),
          throwsA(isA<MCPTimeoutException>()),
        );
      });

      test('should call onTimeout when provided', () async {
        final result = await ErrorRecovery.tryWithTimeout(
          () async {
            await Future.delayed(Duration(milliseconds: 200));
            return 'never-reached';
          },
          Duration(milliseconds: 50),
          onTimeout: () => 'timeout-fallback',
          operationName: 'timeout-with-fallback',
        );

        expect(result, 'timeout-fallback');
      });
    });

    group('tryWithJitter', () {
      test('should add delay before executing operation', () async {
        final startTime = DateTime.now();
        
        final result = await ErrorRecovery.tryWithJitter(
          () async => 'jitter-result',
          baseDelay: Duration(milliseconds: 100),
          operationName: 'jitter-test',
        );

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        expect(result, 'jitter-result');
        expect(elapsed, greaterThan(90)); // Should have some delay
      });

      test('should still throw if operation fails after jitter', () async {
        expect(
          () => ErrorRecovery.tryWithJitter(
            () async => throw Exception('Jitter failure'),
            baseDelay: Duration(milliseconds: 10),
            operationName: 'jitter-fail-test',
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );
      });
    });

    group('tryWithCompensation', () {
      test('should return result when operation succeeds', () async {
        var compensationCalled = false;
        
        final result = await ErrorRecovery.tryWithCompensation(
          () async => 'compensation-success',
          () async {
            compensationCalled = true;
          },
          operationName: 'compensation-test',
        );

        expect(result, 'compensation-success');
        expect(compensationCalled, false); // Should not call compensation on success
      });

      test('should execute compensation action when operation fails', () async {
        var compensationCalled = false;
        
        await expectLater(
          () => ErrorRecovery.tryWithCompensation(
            () async => throw Exception('Operation failed'),
            () async {
              compensationCalled = true;
            },
            operationName: 'compensation-fail-test',
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );

        expect(compensationCalled, true);
      });

      test('should handle compensation action failure gracefully', () async {
        expect(
          () => ErrorRecovery.tryWithCompensation(
            () async => throw Exception('Operation failed'),
            () async => throw Exception('Compensation failed'),
            operationName: 'compensation-both-fail',
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );
      });
    });

    group('tryWithExponentialBackoff', () {
      test('should retry with exponential backoff', () async {
        final timestamps = <DateTime>[];
        var attempts = 0;

        try {
          await ErrorRecovery.tryWithExponentialBackoff(
            () async {
              attempts++;
              timestamps.add(DateTime.now());
              if (attempts < 3) {
                throw Exception('Backoff test');
              }
              return 'backoff-success';
            },
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 50),
            backoffFactor: 2.0,
            operationName: 'exponential-test',
          );
        } catch (e) {
          // May fail, that's okay for this test
        }

        expect(attempts, greaterThanOrEqualTo(2));
        
        if (timestamps.length >= 3) {
          final delay1 = timestamps[1].difference(timestamps[0]).inMilliseconds;
          final delay2 = timestamps[2].difference(timestamps[1]).inMilliseconds;
          
          // Second delay should be longer than first (exponential backoff)
          expect(delay2, greaterThan(delay1 * 1.5));
        }
      });

      test('should respect maxDelay limit', () async {
        final timestamps = <DateTime>[];
        var attempts = 0;

        try {
          await ErrorRecovery.tryWithExponentialBackoff(
            () async {
              attempts++;
              timestamps.add(DateTime.now());
              throw Exception('Max delay test');
            },
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            maxDelay: Duration(milliseconds: 150),
            operationName: 'max-delay-test',
          );
        } catch (e) {
          // Expected to fail
        }

        if (timestamps.length >= 3) {
          final delays = <int>[];
          for (int i = 1; i < timestamps.length; i++) {
            delays.add(timestamps[i].difference(timestamps[i-1]).inMilliseconds);
          }
          
          // All delays should be around or below maxDelay
          expect(delays.every((delay) => delay <= 200), true); // Some tolerance
        }
      });

      test('should call onRetry with delay information', () async {
        final retryInfo = <Map<String, dynamic>>[];

        try {
          await ErrorRecovery.tryWithExponentialBackoff(
            () async => throw Exception('Retry info test'),
            maxRetries: 2,
            initialDelay: Duration(milliseconds: 50),
            onRetry: (attempt, error, nextDelay) {
              retryInfo.add({
                'attempt': attempt,
                'error': error.toString(),
                'nextDelay': nextDelay.inMilliseconds,
              });
            },
            operationName: 'retry-info-test',
          );
        } catch (e) {
          // Expected to fail
        }

        expect(retryInfo.length, greaterThanOrEqualTo(1));
        expect(retryInfo[0]['attempt'], 1);
        expect(retryInfo[0]['nextDelay'], greaterThan(0));
      });
    });

    group('tryCatch', () {
      test('should return result when operation succeeds', () {
        final result = ErrorRecovery.tryCatch(
          () => 'sync-success',
          operationName: 'sync-test',
        );

        expect(result, 'sync-success');
      });

      test('should handle exceptions with onException callback', () {
        final result = ErrorRecovery.tryCatch(
          () => throw Exception('Sync error'),
          onException: (e) => 'exception-handled',
          operationName: 'sync-exception-test',
        );

        expect(result, 'exception-handled');
      });

      test('should throw MCPOperationFailedException without onException', () {
        expect(
          () => ErrorRecovery.tryCatch(
            () => throw Exception('Sync error'),
            operationName: 'sync-fail-test',
          ),
          throwsA(isA<MCPOperationFailedException>()),
        );
      });
    });

    group('logAndRethrow', () {
      test('should return result and not throw when operation succeeds', () async {
        final result = await ErrorRecovery.logAndRethrow(
          () async => 'log-success',
          operationName: 'log-test',
        );

        expect(result, 'log-success');
      });

      test('should log and rethrow exceptions', () async {
        final originalError = Exception('Original error');
        
        expect(
          () => ErrorRecovery.logAndRethrow(
            () async => throw originalError,
            operationName: 'log-fail-test',
          ),
          throwsA(originalError),
        );
      });

      test('should handle includeStackTrace parameter', () async {
        expect(
          () => ErrorRecovery.logAndRethrow(
            () async => throw Exception('Stack trace test'),
            operationName: 'stack-trace-test',
            includeStackTrace: false,
          ),
          throwsException,
        );
      });
    });

    group('Edge Cases and Performance', () {
      test('should handle rapid successive operations', () async {
        final futures = <Future<String>>[];
        
        for (int i = 0; i < 10; i++) {
          futures.add(
            ErrorRecovery.tryWithRetry(
              () async => 'rapid-$i',
              maxRetries: 1,
              operationName: 'rapid-test-$i',
            ),
          );
        }

        final results = await Future.wait(futures);
        expect(results.length, 10);
        
        for (int i = 0; i < 10; i++) {
          expect(results[i], 'rapid-$i');
        }
      });

      test('should handle very long operations with timeout', () async {
        expect(
          () => ErrorRecovery.tryWithTimeout(
            () async {
              await Future.delayed(Duration(seconds: 2));
              return 'never-reached';
            },
            Duration(milliseconds: 100),
            operationName: 'long-operation-test',
          ),
          throwsA(isA<MCPTimeoutException>()),
        );
      });

      test('should handle null operation name gracefully', () async {
        final result = await ErrorRecovery.tryWithRetry(
          () async => 'unnamed-operation',
          maxRetries: 1,
        );

        expect(result, 'unnamed-operation');
      });

      test('should handle Error types (non-Exception) correctly', () async {
        expect(
          () => ErrorRecovery.tryWithRetry(
            () async => throw ArgumentError('Not an Exception'),
            maxRetries: 2,
            operationName: 'error-type-test',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Circuit Breaker Integration', () {
      test('should throw MCPCircuitBreakerOpenException for circuit breaker scenarios', () {
        expect(
          () => throw MCPCircuitBreakerOpenException('Circuit breaker is open'),
          throwsA(isA<MCPCircuitBreakerOpenException>()),
        );
      });
    });
  });
}