import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/operation_wrapper.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:flutter_mcp/src/utils/logger.dart';

void main() {
  final logger = Logger('test.operation_wrapper');

  group('OperationResult factories + toMap', () {
    test('success', () {
      final r = OperationResult<int>.success(42, const Duration(milliseconds: 50));
      expect(r.isSuccess, isTrue);
      expect(r.data, 42);
      expect(r.error, isNull);
      expect(r.executionTime, const Duration(milliseconds: 50));
      expect(r.toMap(), {
        'isSuccess': true,
        'data': 42,
        'error': null,
        'executionTime': 50,
        'hasOriginalException': false,
      });
    });

    test('failure with original exception', () {
      final ex = StateError('boom');
      final st = StackTrace.current;
      final r = OperationResult<int>.failure(
        'failed',
        const Duration(milliseconds: 10),
        originalException: ex,
        stackTrace: st,
      );
      expect(r.isSuccess, isFalse);
      expect(r.error, 'failed');
      expect(r.originalException, ex);
      expect(r.stackTrace, st);
      final map = r.toMap();
      expect(map['hasOriginalException'], isTrue);
    });
  });

  group('OperationConfig presets and copyWith', () {
    test('defaultConfig has expected defaults', () {
      const c = OperationConfig.defaultConfig;
      expect(c.timeout, isNull);
      expect(c.maxRetries, isNull);
      expect(c.recordMetrics, isTrue);
      expect(c.throwOnError, isTrue);
    });

    test('quickOperation preset', () {
      const c = OperationConfig.quickOperation;
      expect(c.timeout, const Duration(seconds: 5));
      expect(c.recordMetrics, isFalse);
    });

    test('longOperation preset', () {
      const c = OperationConfig.longOperation;
      expect(c.timeout, const Duration(minutes: 2));
      expect(c.maxRetries, 3);
      expect(c.retryDelay, const Duration(seconds: 1));
    });

    test('criticalOperation preset', () {
      const c = OperationConfig.criticalOperation;
      expect(c.timeout, const Duration(seconds: 30));
      expect(c.maxRetries, 5);
      expect(c.retryDelay, const Duration(milliseconds: 500));
    });

    test('copyWith replaces only specified fields', () {
      const original = OperationConfig.longOperation;
      final updated = original.copyWith(throwOnError: false, maxRetries: 7);
      expect(updated.throwOnError, isFalse);
      expect(updated.maxRetries, 7);
      // Untouched fields preserved.
      expect(updated.timeout, original.timeout);
      expect(updated.retryDelay, original.retryDelay);
    });

    test('copyWith with no args returns equivalent config', () {
      final updated = OperationConfig.defaultConfig.copyWith();
      expect(updated.recordMetrics, isTrue);
      expect(updated.throwOnError, isTrue);
    });
  });

  group('OperationWrapper.execute (sync)', () {
    test('returns success result on normal execution', () {
      final r = OperationWrapper.execute<int>(
        operationName: 'add',
        operation: () => 1 + 2,
        logger: logger,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(r.isSuccess, isTrue);
      expect(r.data, 3);
    });

    test('throws MCPOperationFailedException by default on failure', () {
      expect(
        () => OperationWrapper.execute<int>(
          operationName: 'fail',
          operation: () => throw StateError('boom'),
          logger: logger,
          config: const OperationConfig(recordMetrics: false),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('returns failure result when throwOnError is false', () {
      final r = OperationWrapper.execute<int>(
        operationName: 'soft-fail',
        operation: () => throw StateError('boom'),
        logger: logger,
        config: const OperationConfig(
          throwOnError: false,
          recordMetrics: false,
        ),
      );
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('soft-fail failed'));
      expect(r.originalException, isA<StateError>());
    });
  });

  group('OperationWrapper.executeAsync', () {
    test('returns success', () async {
      final r = await OperationWrapper.executeAsync<int>(
        operationName: 'async-ok',
        operation: () async => 7,
        logger: logger,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(r.isSuccess, isTrue);
      expect(r.data, 7);
    });

    test('respects timeout', () async {
      final r = await OperationWrapper.executeAsync<int>(
        operationName: 'async-timeout',
        operation: () => Future.delayed(const Duration(seconds: 5), () => 1),
        logger: logger,
        config: const OperationConfig(
          timeout: Duration(milliseconds: 50),
          throwOnError: false,
          recordMetrics: false,
        ),
      );
      expect(r.isSuccess, isFalse);
      // The error message contains the underlying timeout text.
      expect(r.error, contains('TimeoutException'));
    });

    test('throws on failure when throwOnError is true (default)', () async {
      await expectLater(
        OperationWrapper.executeAsync<int>(
          operationName: 'async-fail',
          operation: () async => throw StateError('boom'),
          logger: logger,
          config: const OperationConfig(recordMetrics: false),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });
  });

  group('OperationWrapper.executeWithRetry', () {
    test('returns success on first attempt without retry', () async {
      var calls = 0;
      final r = await OperationWrapper.executeWithRetry<int>(
        operationName: 'retry-success',
        operation: () async {
          calls++;
          return 99;
        },
        logger: logger,
        config: const OperationConfig(
          maxRetries: 3,
          retryDelay: Duration(milliseconds: 1),
          recordMetrics: false,
        ),
      );
      expect(r.isSuccess, isTrue);
      expect(calls, 1);
    });

    test('retries until success', () async {
      var calls = 0;
      final r = await OperationWrapper.executeWithRetry<int>(
        operationName: 'retry-eventual',
        operation: () async {
          calls++;
          if (calls < 3) throw StateError('flake');
          return 7;
        },
        logger: logger,
        config: const OperationConfig(
          maxRetries: 5,
          retryDelay: Duration(milliseconds: 1),
          recordMetrics: false,
        ),
      );
      expect(r.isSuccess, isTrue);
      expect(r.data, 7);
      expect(calls, 3);
    });

    test('throws after exhausting retries when throwOnError is true',
        () async {
      await expectLater(
        OperationWrapper.executeWithRetry<int>(
          operationName: 'retry-exhausted',
          operation: () async => throw StateError('always'),
          logger: logger,
          config: const OperationConfig(
            maxRetries: 2,
            retryDelay: Duration(milliseconds: 1),
            recordMetrics: false,
            throwOnError: true,
          ),
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('returns failure result after retries when throwOnError is false',
        () async {
      final r = await OperationWrapper.executeWithRetry<int>(
        operationName: 'retry-soft-fail',
        operation: () async => throw StateError('always'),
        logger: logger,
        config: const OperationConfig(
          maxRetries: 1,
          retryDelay: Duration(milliseconds: 1),
          recordMetrics: false,
          throwOnError: false,
        ),
      );
      expect(r.isSuccess, isFalse);
    });
  });

  group('OperationWrapper.executeConcurrent', () {
    test('runs all and aggregates results', () async {
      final results = await OperationWrapper.executeConcurrent<int>(
        groupName: 'group',
        operations: [
          (name: 'one', operation: () async => 1),
          (name: 'two', operation: () async => 2),
          (name: 'three', operation: () async => 3),
        ],
        logger: logger,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(results, hasLength(3));
      expect(results.map((r) => r.data).toList(), [1, 2, 3]);
    });

    test('reports per-op failures without throwing when failFast is false',
        () async {
      final results = await OperationWrapper.executeConcurrent<int>(
        groupName: 'group',
        operations: [
          (name: 'ok', operation: () async => 1),
          (name: 'bad', operation: () async => throw StateError('boom')),
        ],
        logger: logger,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(results, hasLength(2));
      expect(results.first.isSuccess, isTrue);
      expect(results.last.isSuccess, isFalse);
    });

    test('failFast + throwOnError raises when any operation fails', () async {
      await expectLater(
        OperationWrapper.executeConcurrent<int>(
          groupName: 'group',
          operations: [
            (name: 'ok', operation: () async => 1),
            (name: 'bad', operation: () async => throw StateError('boom')),
          ],
          logger: logger,
          config: const OperationConfig(recordMetrics: false),
          failFast: true,
        ),
        throwsA(isA<MCPOperationFailedException>()),
      );
    });

    test('failFast without throwOnError still returns results', () async {
      final results = await OperationWrapper.executeConcurrent<int>(
        groupName: 'group',
        operations: [
          (name: 'bad', operation: () async => throw StateError('boom')),
        ],
        logger: logger,
        config: const OperationConfig(
          recordMetrics: false,
          throwOnError: false,
        ),
        failFast: true,
      );
      expect(results, hasLength(1));
      expect(results.first.isSuccess, isFalse);
    });
  });

  group('OperationWrapperMixin', () {
    test('mixin methods delegate to OperationWrapper', () async {
      final stub = _Stub();
      final r1 = stub.executeOperation<int>(
        operationName: 'sync',
        operation: () => 1,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(r1.isSuccess, isTrue);

      final r2 = await stub.executeAsyncOperation<int>(
        operationName: 'async',
        operation: () async => 2,
        config: const OperationConfig(recordMetrics: false),
      );
      expect(r2.isSuccess, isTrue);

      final r3 = await stub.executeWithRetry<int>(
        operationName: 'retry',
        operation: () async => 3,
        config: const OperationConfig(
          recordMetrics: false,
          maxRetries: 1,
          retryDelay: Duration(milliseconds: 1),
        ),
      );
      expect(r3.isSuccess, isTrue);
    });
  });
}

class _Stub with OperationWrapperMixin {
  @override
  Logger get logger => Logger('test.stub');
}
