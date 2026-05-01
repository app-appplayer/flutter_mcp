import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  group('MCPException', () {
    test('basic constructor', () {
      final e = MCPException('msg');
      expect(e.message, 'msg');
      expect(e.errorCode, isNull);
      expect(e.context, isNull);
      expect(e.recoverable, isFalse);
      expect(e.resolution, isNull);
      expect(e.originalError, isNull);
      expect(e.toString(), contains('MCPException'));
      expect(e.toString(), contains('msg'));
    });

    test('basic constructor with original error and stack trace', () {
      final st = StackTrace.current;
      final e = MCPException('msg', 'inner', st);
      expect(e.originalError, 'inner');
      expect(e.originalStackTrace, st);
      expect(e.toString(), contains('Original error: inner'));
    });

    test('withContext constructor', () {
      final e = MCPException.withContext(
        'ctx',
        errorCode: 'CODE',
        context: {'k': 'v'},
        recoverable: true,
        resolution: 'try-again',
      );
      expect(e.errorCode, 'CODE');
      expect(e.context, {'k': 'v'});
      expect(e.recoverable, isTrue);
      expect(e.resolution, 'try-again');
      final s = e.toString();
      expect(s, contains('[CODE]'));
      expect(s, contains('Resolution: try-again'));
    });
  });

  group('MCPInitializationException', () {
    test('basic + withContext', () {
      final e1 = MCPInitializationException('boot');
      expect(e1.message, contains('Initialization error: boot'));

      final e2 = MCPInitializationException.withContext('boot',
          errorCode: 'CUSTOM');
      expect(e2.errorCode, 'CUSTOM');

      final e3 = MCPInitializationException.withContext('boot');
      expect(e3.errorCode, 'INIT_ERROR');
    });
  });

  group('MCPPlatformNotSupportedException', () {
    test('feature stored and resolution provided', () {
      final e = MCPPlatformNotSupportedException('tray');
      expect(e.feature, 'tray');
      expect(e.resolution, isNotNull);
      expect(e.errorCode, 'PLATFORM_UNSUPPORTED');
      expect(e.context!['feature'], 'tray');
    });

    test('custom errorCode and resolution propagated', () {
      final e = MCPPlatformNotSupportedException(
        'bg',
        errorCode: 'BG_OFF',
        resolution: 'use foreground',
        context: {'extra': 1},
      );
      expect(e.errorCode, 'BG_OFF');
      expect(e.resolution, 'use foreground');
      expect(e.context!['extra'], 1);
    });
  });

  group('MCPOperationFailedException', () {
    test('basic constructor', () {
      final inner = StateError('inner');
      final st = StackTrace.current;
      final e = MCPOperationFailedException('failed', inner, st);
      expect(e.innerError, inner);
      expect(e.innerStackTrace, st);
      expect(e.toString(), contains('Inner error'));
    });

    test('withContext constructor + custom errorCode', () {
      final e = MCPOperationFailedException.withContext(
        'failed',
        'inner',
        null,
        errorCode: 'X',
        recoverable: true,
        resolution: 'retry',
      );
      expect(e.errorCode, 'X');
      expect(e.recoverable, isTrue);
      expect(e.resolution, 'retry');
      expect(e.toString(), contains('[X]'));
      expect(e.toString(), contains('Resolution: retry'));
    });

    test('withContext defaults errorCode to OPERATION_FAILED', () {
      final e = MCPOperationFailedException.withContext('m', null, null);
      expect(e.errorCode, 'OPERATION_FAILED');
    });
  });

  group('MCPTimeoutException', () {
    test('stores timeout', () {
      final e = MCPTimeoutException('slow', const Duration(seconds: 5));
      expect(e.timeout, const Duration(seconds: 5));
    });

    test('withContext defaults errorCode to TIMEOUT and resolution', () {
      final e = MCPTimeoutException.withContext(
        'slow',
        const Duration(seconds: 5),
      );
      expect(e.errorCode, 'TIMEOUT');
      expect(e.context!['timeoutMs'], 5000);
      expect(e.resolution, isNotNull);
    });
  });

  group('MCPCircuitBreakerOpenException', () {
    test('default openedAt is now and recoverable is true', () {
      final before = DateTime.now();
      final e = MCPCircuitBreakerOpenException('open');
      final after = DateTime.now();
      expect(e.openedAt.isBefore(before), isFalse);
      expect(e.openedAt.isAfter(after), isFalse);
      expect(e.recoverable, isTrue);
      expect(e.errorCode, 'CIRCUIT_OPEN');
    });

    test('breakerName and resetAt propagate', () {
      final reset = DateTime(2026, 5, 1);
      final e = MCPCircuitBreakerOpenException(
        'open',
        breakerName: 'main',
        resetAt: reset,
      );
      expect(e.breakerName, 'main');
      expect(e.resetAt, reset);
      expect(e.context!['breakerName'], 'main');
    });
  });

  group('MCPPluginException', () {
    test('basic constructor includes plugin name in message', () {
      final e = MCPPluginException('myPlugin', 'broke');
      expect(e.pluginName, 'myPlugin');
      expect(e.message, contains('myPlugin'));
      expect(e.message, contains('broke'));
    });

    test('withContext defaults errorCode to PLUGIN_ERROR', () {
      final e = MCPPluginException.withContext('p', 'bad');
      expect(e.errorCode, 'PLUGIN_ERROR');
      expect(e.context!['pluginName'], 'p');
    });

    test('withContext respects custom errorCode + recoverable + resolution',
        () {
      final e = MCPPluginException.withContext(
        'p',
        'bad',
        errorCode: 'CUSTOM',
        recoverable: true,
        resolution: 'reload',
      );
      expect(e.errorCode, 'CUSTOM');
      expect(e.recoverable, isTrue);
      expect(e.resolution, 'reload');
    });
  });

  group('MCPResourceNotFoundException', () {
    test('basic constructor includes resourceId in message', () {
      final e = MCPResourceNotFoundException('xyz');
      expect(e.resourceId, 'xyz');
      expect(e.resourceType, isNull);
      expect(e.message, contains('xyz'));
    });

    test('basic constructor with additionalInfo', () {
      final e = MCPResourceNotFoundException('xyz', 'extra info');
      expect(e.message, contains('extra info'));
    });

    test('withContext stores resourceType and context', () {
      final e = MCPResourceNotFoundException.withContext(
        'r1',
        resourceType: 'tool',
        additionalInfo: 'maybe stale',
      );
      expect(e.resourceType, 'tool');
      expect(e.errorCode, 'RESOURCE_NOT_FOUND');
      expect(e.context!['resourceId'], 'r1');
      expect(e.context!['resourceType'], 'tool');
    });
  });

  group('MCPValidationException', () {
    test('stores validationErrors and defaults errorCode', () {
      final e = MCPValidationException('bad', {'name': 'required'});
      expect(e.validationErrors, {'name': 'required'});
      expect(e.errorCode, 'VALIDATION_ERROR');
      expect(e.recoverable, isTrue);
      expect(e.toString(), contains('VALIDATION_ERROR'));
    });

    test('respects custom errorCode and resolution', () {
      final e = MCPValidationException(
        'bad',
        {'k': 'v'},
        errorCode: 'CUSTOM_VALIDATE',
        recoverable: false,
        resolution: 'fix',
      );
      expect(e.errorCode, 'CUSTOM_VALIDATE');
      expect(e.recoverable, isFalse);
      expect(e.resolution, 'fix');
    });
  });

  group('MCPNetworkException', () {
    test('basic constructor', () {
      final e = MCPNetworkException('down');
      expect(e.message, contains('down'));
    });
  });

  group('MCPAuthenticationException', () {
    test('basic constructor', () {
      final e = MCPAuthenticationException('forbidden');
      expect(e.message, contains('forbidden'));
    });
  });

  group('MCPOperationCancelledException', () {
    test('basic + withContext', () {
      final e1 = MCPOperationCancelledException('user-cancelled');
      expect(e1.message, contains('user-cancelled'));

      final e2 = MCPOperationCancelledException.withContext(
        'cancelled',
        errorCode: 'CANCELLED',
      );
      expect(e2.errorCode, 'CANCELLED');
    });
  });

  group('MCPSecurityException', () {
    test('basic constructor', () {
      final e = MCPSecurityException('breach');
      expect(e.message, contains('breach'));
    });
  });

  group('MCPTransportException', () {
    test('basic constructor', () {
      final e = MCPTransportException('disconnected');
      expect(e.message, contains('disconnected'));
    });
  });
}
