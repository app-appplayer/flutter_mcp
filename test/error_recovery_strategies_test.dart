import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/enhanced_error_handler.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';

void main() {
  group('DefaultErrorRecoveryStrategy', () {
    final s = DefaultErrorRecoveryStrategy();

    test('canRecover always returns false', () {
      expect(s.canRecover(Exception('any')), isFalse);
      expect(s.canRecover('string'), isFalse);
      expect(s.canRecover(42), isFalse);
    });

    test('recover always returns null', () async {
      expect(
        await s.recover<int>('e', StackTrace.current, 'ctx'),
        isNull,
      );
    });
  });

  group('RetryRecoveryStrategy', () {
    test('default recognises transient errors via message keywords', () {
      final s = RetryRecoveryStrategy();
      expect(s.canRecover('Connection timeout'), isTrue);
      expect(s.canRecover('connection refused'), isTrue);
      expect(s.canRecover('network unavailable'), isTrue);
      expect(s.canRecover('temporarily unavailable'), isTrue);
    });

    test('default rejects unrelated errors', () {
      final s = RetryRecoveryStrategy();
      expect(s.canRecover('parse error'), isFalse);
      expect(s.canRecover(StateError('bad state')), isFalse);
    });

    test('custom shouldRetry overrides default', () {
      final s = RetryRecoveryStrategy(
        shouldRetry: (e) => e.toString().contains('retry-me'),
      );
      expect(s.canRecover('retry-me please'), isTrue);
      expect(s.canRecover('connection timeout'), isFalse);
    });

    test('recover returns null (handled at higher layer)', () async {
      final s = RetryRecoveryStrategy();
      expect(
        await s.recover<String>('e', StackTrace.current, 'ctx'),
        isNull,
      );
    });

    test('respects maxRetries / retryDelay constructor parameters', () {
      final s = RetryRecoveryStrategy(
        maxRetries: 7,
        retryDelay: const Duration(milliseconds: 250),
      );
      expect(s.maxRetries, 7);
      expect(s.retryDelay, const Duration(milliseconds: 250));
    });
  });

  group('CircuitBreakerRecoveryStrategy', () {
    test('canRecover excludes CircuitBreakerOpenException', () {
      final s = CircuitBreakerRecoveryStrategy({});
      expect(
        s.canRecover(CircuitBreakerOpenException('open')),
        isFalse,
      );
      expect(s.canRecover('other'), isTrue);
    });

    test('recover returns null', () async {
      final s = CircuitBreakerRecoveryStrategy({});
      expect(
        await s.recover<int>('e', StackTrace.current, 'ctx'),
        isNull,
      );
    });
  });

  group('EnhancedErrorHandler — singleton + statistics', () {
    test('instance is identical across calls', () {
      expect(
        identical(EnhancedErrorHandler.instance, EnhancedErrorHandler.instance),
        isTrue,
      );
    });

    test('initialize is idempotent', () {
      EnhancedErrorHandler.instance.initialize();
      EnhancedErrorHandler.instance.initialize();
    });

    test('resetStatistics does not throw', () {
      EnhancedErrorHandler.instance.resetStatistics();
    });

    test('registerRecoveryStrategy + registerErrorHandler are idempotent', () {
      EnhancedErrorHandler.instance.registerRecoveryStrategy(
        'custom',
        DefaultErrorRecoveryStrategy(),
      );
      EnhancedErrorHandler.instance.registerErrorHandler<String>(
        (error, stack, ctx) async => 'handled',
      );
    });
  });
}
