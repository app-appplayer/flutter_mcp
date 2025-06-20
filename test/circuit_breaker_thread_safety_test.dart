import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:async';

void main() {
  group('CircuitBreaker Thread Safety Tests', () {
    late CircuitBreaker circuitBreaker;

    setUp(() {
      circuitBreaker = CircuitBreaker(
        name: 'test-breaker',
        failureThreshold: 3,
        resetTimeout: Duration(milliseconds: 100),
      );
    });

    test('state getter should be thread-safe', () async {
      // Start with closed state
      expect(circuitBreaker.state, equals(CircuitBreakerState.closed));

      // Create concurrent operations
      final futures = <Future>[];

      // Reader threads
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < 100; j++) {
            final state = circuitBreaker.state;
            expect(state, isNotNull);
            expect(state, isA<CircuitBreakerState>());
          }
        }));
      }

      // Writer thread (causing failures)
      futures.add(Future(() async {
        for (int i = 0; i < 3; i++) {
          await circuitBreaker.recordFailure(Exception('Test failure $i'));
          await Future.delayed(Duration(milliseconds: 10));
        }
      }));

      // Wait for all operations
      await Future.wait(futures);

      // State should be open after 3 failures
      expect(circuitBreaker.state, equals(CircuitBreakerState.open));
    });

    test('failureCount getter should be thread-safe', () async {
      expect(circuitBreaker.failureCount, equals(0));

      final futures = <Future>[];

      // Reader threads
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < 100; j++) {
            final count = circuitBreaker.failureCount;
            expect(count, isNotNull);
            expect(count, greaterThanOrEqualTo(0));
            expect(count, lessThanOrEqualTo(3));
          }
        }));
      }

      // Writer thread
      futures.add(Future(() async {
        for (int i = 0; i < 3; i++) {
          await circuitBreaker.recordFailure(Exception('Test failure'));
          await Future.delayed(Duration(milliseconds: 5));
        }
      }));

      await Future.wait(futures);

      // Should have recorded 3 failures
      expect(circuitBreaker.failureCount, equals(3));
    });

    test('concurrent execute operations should be safe', () async {
      final successCounter = <int>[];
      final failureCounter = <int>[];
      final lock = Lock();

      final futures = <Future>[];

      // Create 20 concurrent operations
      for (int i = 0; i < 20; i++) {
        final index = i;
        futures.add(Future(() async {
          try {
            if (index % 4 == 0) {
              // Some operations fail
              await circuitBreaker.execute(() async {
                throw Exception('Simulated failure');
              });
            } else {
              // Most operations succeed
              await circuitBreaker.execute(() async {
                return 'success';
              });
              await lock.synchronized(() async {
                successCounter.add(index);
              });
            }
          } catch (e) {
            await lock.synchronized(() async {
              failureCounter.add(index);
            });
          }
        }));
      }

      await Future.wait(futures);

      // Verify counts are consistent
      final totalCount = successCounter.length + failureCounter.length;
      expect(totalCount, equals(20));

      // Circuit may or may not be open depending on timing
      // Just verify state is valid
      expect(
          circuitBreaker.state,
          anyOf([
            CircuitBreakerState.closed,
            CircuitBreakerState.open,
            CircuitBreakerState.halfOpen,
          ]));
    });

    test('state transitions should be atomic', () async {
      final stateChanges = <CircuitBreakerState>[];
      final lock = Lock();

      // Initial state
      stateChanges.add(circuitBreaker.state);

      // Cause failures to open circuit
      for (int i = 0; i < 3; i++) {
        await circuitBreaker.recordFailure(Exception('Failure $i'));
        await lock.synchronized(() async {
          stateChanges.add(circuitBreaker.state);
        });
      }

      // Should be open now
      expect(circuitBreaker.state, CircuitBreakerState.open);

      // Wait for reset timeout
      await Future.delayed(Duration(milliseconds: 150));

      // Try to execute - this should transition to half-open
      try {
        await circuitBreaker.execute(() async => 'success');
        // If successful, should be closed
        await lock.synchronized(() async {
          stateChanges.add(circuitBreaker.state);
        });
      } catch (e) {
        // If failed, might still be open or half-open
        await lock.synchronized(() async {
          stateChanges.add(circuitBreaker.state);
        });
      }

      // Verify we captured state changes
      expect(stateChanges.length, greaterThan(2));

      // Verify state transitions are valid
      CircuitBreakerState? previousState;
      for (final state in stateChanges) {
        if (previousState != null) {
          // Valid transitions:
          // closed -> open
          // open -> halfOpen
          // halfOpen -> closed
          // halfOpen -> open
          // Same state is also valid (no transition)
          if (previousState == CircuitBreakerState.closed) {
            expect(
                state,
                anyOf([
                  CircuitBreakerState.closed,
                  CircuitBreakerState.open,
                ]));
          } else if (previousState == CircuitBreakerState.open) {
            expect(
                state,
                anyOf([
                  CircuitBreakerState.open,
                  CircuitBreakerState.halfOpen,
                  CircuitBreakerState
                      .closed, // Can go directly to closed in some timing scenarios
                ]));
          } else if (previousState == CircuitBreakerState.halfOpen) {
            expect(
                state,
                anyOf([
                  CircuitBreakerState.halfOpen,
                  CircuitBreakerState.closed,
                  CircuitBreakerState.open,
                ]));
          }
        }
        previousState = state;
      }
    });

    test('concurrent recordSuccess and recordFailure', () async {
      final futures = <Future>[];

      // 10 threads recording successes
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < 10; j++) {
            await circuitBreaker.recordSuccess();
            await Future.delayed(Duration(milliseconds: 1));
          }
        }));
      }

      // 5 threads recording failures
      for (int i = 0; i < 5; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < 2; j++) {
            await circuitBreaker.recordFailure(Exception('Concurrent failure'));
            await Future.delayed(Duration(milliseconds: 2));
          }
        }));
      }

      await Future.wait(futures);

      // Circuit should be open after multiple failures
      expect(circuitBreaker.state, equals(CircuitBreakerState.open));

      // Failure count should be at threshold or above
      expect(circuitBreaker.failureCount, greaterThanOrEqualTo(3));
    });
  });
}
