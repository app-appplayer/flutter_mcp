import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';

void main() {
  group('CircuitBreaker — initial state', () {
    test('starts closed with zero failures', () {
      final cb = CircuitBreaker(
        name: 'cb',
        failureThreshold: 3,
        resetTimeout: const Duration(seconds: 1),
      );
      expect(cb.state, CircuitBreakerState.closed);
      expect(cb.failureCount, 0);
    });
  });

  group('CircuitBreaker — execute happy path', () {
    test('execute returns operation result and stays closed', () async {
      final cb = CircuitBreaker(
        name: 'ok',
        failureThreshold: 2,
        resetTimeout: const Duration(seconds: 1),
      );
      final r = await cb.execute<int>(() async => 42);
      expect(r, 42);
      expect(cb.state, CircuitBreakerState.closed);
    });

    test('execute resets failures on success in closed state', () async {
      final cb = CircuitBreaker(
        name: 'reset',
        failureThreshold: 5,
        resetTimeout: const Duration(seconds: 1),
      );
      // Two failures, still closed.
      try { await cb.execute<int>(() async => throw 'e1'); } catch (_) {}
      try { await cb.execute<int>(() async => throw 'e2'); } catch (_) {}
      expect(cb.failureCount, 2);
      // Success resets.
      await cb.execute<int>(() async => 1);
      expect(cb.failureCount, 0);
    });
  });

  group('CircuitBreaker — opens after failureThreshold', () {
    test('reaches open state and calls onOpen', () async {
      var openedCount = 0;
      final cb = CircuitBreaker(
        name: 'open',
        failureThreshold: 2,
        resetTimeout: const Duration(seconds: 1),
        onOpen: () => openedCount++,
      );
      try { await cb.execute<int>(() async => throw 'e1'); } catch (_) {}
      try { await cb.execute<int>(() async => throw 'e2'); } catch (_) {}
      expect(cb.state, CircuitBreakerState.open);
      expect(openedCount, 1);
    });

    test('next execute call rejects with CircuitBreakerOpenException', () async {
      final cb = CircuitBreaker(
        name: 'reject',
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );
      try { await cb.execute<int>(() async => throw 'e'); } catch (_) {}
      await expectLater(
        cb.execute<int>(() async => 1),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });
  });

  group('CircuitBreaker — half-open transitions', () {
    test('after resetTimeout an execute attempt enters half-open and on success closes',
        () async {
      var closedCount = 0;
      final cb = CircuitBreaker(
        name: 'recover',
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 10),
        onClose: () => closedCount++,
      );
      try { await cb.execute<int>(() async => throw 'e'); } catch (_) {}
      expect(cb.state, CircuitBreakerState.open);
      // Wait past resetTimeout.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // First execute moves to half-open then succeeds → closed.
      final r = await cb.execute<int>(() async => 7);
      expect(r, 7);
      expect(cb.state, CircuitBreakerState.closed);
      expect(closedCount, 1);
    });

    test('any failure in half-open re-opens the circuit', () async {
      final cb = CircuitBreaker(
        name: 'reopens',
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 10),
      );
      try { await cb.execute<int>(() async => throw 'e'); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 20));
      try { await cb.execute<int>(() async => throw 'still-bad'); } catch (_) {}
      expect(cb.state, CircuitBreakerState.open);
    });

    test('halfOpenSuccessThreshold > 1 requires multiple successes to close',
        () async {
      final cb = CircuitBreaker(
        name: 'tickets',
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 10),
        halfOpenSuccessThreshold: 2,
      );
      try { await cb.execute<int>(() async => throw 'e'); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // First success: still half-open.
      await cb.execute<int>(() async => 1);
      expect(cb.state, CircuitBreakerState.halfOpen);
      // Second success: closes.
      await cb.execute<int>(() async => 1);
      expect(cb.state, CircuitBreakerState.closed);
    });
  });

  group('CircuitBreaker — allowOperation', () {
    test('throws when open and within reset window', () async {
      final cb = CircuitBreaker(
        name: 'allow',
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 30),
      );
      await cb.recordFailure('boom');
      expect(cb.state, CircuitBreakerState.open);
      await expectLater(
        cb.allowOperation(),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('allowOperation moves to half-open after timeout', () async {
      final cb = CircuitBreaker(
        name: 'allow-pass',
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 10),
      );
      await cb.recordFailure('boom');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cb.allowOperation(); // should not throw
      expect(cb.state, CircuitBreakerState.halfOpen);
    });

    test('passes through when closed', () async {
      final cb = CircuitBreaker(
        name: 'closed',
        failureThreshold: 5,
        resetTimeout: const Duration(seconds: 1),
      );
      await cb.allowOperation();
      expect(cb.state, CircuitBreakerState.closed);
    });
  });

  group('CircuitBreaker — manual control', () {
    test('reset returns to clean closed state', () async {
      final cb = CircuitBreaker(
        name: 'r',
        failureThreshold: 1,
        resetTimeout: const Duration(seconds: 1),
      );
      await cb.recordFailure('e');
      expect(cb.state, CircuitBreakerState.open);
      await cb.reset();
      expect(cb.state, CircuitBreakerState.closed);
      expect(cb.failureCount, 0);
    });

    test('forceOpen calls onOpen', () async {
      var openedCount = 0;
      final cb = CircuitBreaker(
        name: 'fopen',
        failureThreshold: 5,
        resetTimeout: const Duration(seconds: 1),
        onOpen: () => openedCount++,
      );
      await cb.forceOpen();
      expect(cb.state, CircuitBreakerState.open);
      expect(openedCount, 1);
    });

    test('forceClosed calls onClose and resets failures', () async {
      var closedCount = 0;
      final cb = CircuitBreaker(
        name: 'fclosed',
        failureThreshold: 5,
        resetTimeout: const Duration(seconds: 1),
        onClose: () => closedCount++,
      );
      await cb.recordFailure('e');
      await cb.forceClosed();
      expect(cb.state, CircuitBreakerState.closed);
      expect(cb.failureCount, 0);
      expect(closedCount, 1);
    });
  });

  group('CircuitBreakerOpenException', () {
    test('toString embeds the message', () {
      final e = CircuitBreakerOpenException('open: cb');
      expect(e.toString(), contains('open: cb'));
    });
  });
}
