// Targeted extras for the exception classes that aren't fully covered
// by exceptions_test.dart — focuses on Timeout, CircuitBreakerOpen,
// Plugin, ResourceNotFound, Validation, OperationCancelled, Security,
// Transport, Network, Configuration, Authentication.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  group('MCPTimeoutException', () {
    test('basic constructor stores timeout + message', () {
      final e = MCPTimeoutException(
        'op timed out',
        const Duration(seconds: 5),
      );
      expect(e.timeout, const Duration(seconds: 5));
      expect(e.toString(), contains('op timed out'));
    });

    test('withContext sets default errorCode + resolution', () {
      final e = MCPTimeoutException.withContext(
        'op timed out',
        const Duration(seconds: 10),
      );
      expect(e.errorCode, 'TIMEOUT');
      expect(e.context, contains('timeoutMs'));
      expect(e.resolution, contains('timeout'));
    });
  });

  group('MCPCircuitBreakerOpenException', () {
    test('captures breaker name + reset time', () {
      final reset = DateTime.now().add(const Duration(seconds: 30));
      final e = MCPCircuitBreakerOpenException(
        'open',
        breakerName: 'cb1',
        resetAt: reset,
      );
      expect(e.breakerName, 'cb1');
      expect(e.resetAt, reset);
      expect(e.openedAt, isA<DateTime>());
      expect(e.errorCode, 'CIRCUIT_OPEN');
      expect(e.recoverable, isTrue);
    });

    test('toString embeds resolution + reset time', () {
      final reset = DateTime.parse('2030-01-01T00:00:00Z');
      final e = MCPCircuitBreakerOpenException(
        'open',
        breakerName: 'cb1',
        resetAt: reset,
      );
      expect(e.toString(), contains('after 2030-01-01'));
    });

    test('without resetAt uses generic resolution', () {
      final e = MCPCircuitBreakerOpenException('open');
      expect(e.toString(), contains('later'));
    });
  });

  group('MCPPluginException', () {
    test('basic constructor prefixes plugin name', () {
      final e = MCPPluginException('myPlugin', 'broke');
      expect(e.pluginName, 'myPlugin');
      expect(e.toString(), contains('myPlugin'));
      expect(e.toString(), contains('broke'));
    });

    test('withContext stores pluginName in context map', () {
      final e = MCPPluginException.withContext(
        'p',
        'fail',
        recoverable: true,
        resolution: 'retry',
      );
      expect(e.errorCode, 'PLUGIN_ERROR');
      expect(e.context, contains('pluginName'));
      expect(e.recoverable, isTrue);
      expect(e.resolution, 'retry');
    });
  });

  group('MCPResourceNotFoundException', () {
    test('basic constructor includes resourceId in message', () {
      final e = MCPResourceNotFoundException('res-1');
      expect(e.resourceId, 'res-1');
      expect(e.resourceType, isNull);
      expect(e.toString(), contains('res-1'));
    });

    test('withContext stores resourceType + custom resolution', () {
      final e = MCPResourceNotFoundException.withContext(
        'res-2',
        resourceType: 'Client',
        resolution: 'check id',
      );
      expect(e.resourceId, 'res-2');
      expect(e.resourceType, 'Client');
      expect(e.errorCode, 'RESOURCE_NOT_FOUND');
      expect(e.context, contains('resourceId'));
      expect(e.context, contains('resourceType'));
      expect(e.resolution, 'check id');
    });
  });

  group('MCPValidationException', () {
    test('errorCode + context include validationErrors', () {
      final e = MCPValidationException('bad input', {'field': 'required'});
      expect(e.errorCode, 'VALIDATION_ERROR');
      expect(e.validationErrors, {'field': 'required'});
      expect(e.recoverable, isTrue);
    });

    test('toString includes formatted validation errors', () {
      final e = MCPValidationException('bad input', {
        'a': 'missing',
        'b': 'too short',
      });
      final s = e.toString();
      expect(s, contains('a: missing'));
      expect(s, contains('b: too short'));
      expect(s, contains('Resolution:'));
    });

    test('toString omits validation errors block when map empty', () {
      final e = MCPValidationException('bad', {});
      expect(e.toString(), isNot(contains('[Validation errors:')));
    });
  });

  group('MCPOperationCancelledException', () {
    test('basic constructor', () {
      final e = MCPOperationCancelledException('cancelled');
      expect(e.toString(), contains('cancelled'));
    });

    test('withContext sets defaults + recoverable=true', () {
      final e = MCPOperationCancelledException.withContext('cancelled');
      expect(e.errorCode, 'OPERATION_CANCELLED');
      expect(e.recoverable, isTrue);
      expect(e.resolution, contains('retry'));
    });
  });

  group('MCPSecurityException', () {
    test('basic constructor adds Security error prefix', () {
      final e = MCPSecurityException('breach');
      expect(e.toString(), contains('Security error:'));
      expect(e.toString(), contains('breach'));
    });

    test('withContext sets default errorCode', () {
      final e = MCPSecurityException.withContext('breach');
      expect(e.errorCode, 'SECURITY_ERROR');
    });
  });

  group('MCPTransportException', () {
    test('basic constructor adds Transport error prefix', () {
      final e = MCPTransportException('connection failed');
      expect(e.toString(), contains('Transport error:'));
    });

    test('withContext sets default errorCode', () {
      final e = MCPTransportException.withContext('failed');
      expect(e.errorCode, 'TRANSPORT_ERROR');
    });
  });

  group('MCPNetworkException + MCPConfigurationException + MCPAuthenticationException',
      () {
    test('MCPNetworkException constructor', () {
      final e = MCPNetworkException(
        'no route',
        statusCode: 503,
        responseBody: 'unavailable',
      );
      expect(e.toString(), contains('no route'));
      expect(e.statusCode, 503);
      expect(e.responseBody, 'unavailable');
      expect(e.errorCode, 'NETWORK_ERROR');
    });

    test('MCPConfigurationException withContext sets errorCode', () {
      final e = MCPConfigurationException.withContext('bad config');
      expect(e.errorCode, 'CONFIG_ERROR');
    });

    test('MCPAuthenticationException withContext sets errorCode', () {
      final e = MCPAuthenticationException.withContext('unauthorized');
      expect(e.errorCode, 'AUTH_ERROR');
    });
  });
}
