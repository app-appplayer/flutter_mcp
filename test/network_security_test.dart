import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/security/network_security.dart';
import 'dart:convert';

void main() {
  group('NetworkSecurity Tests', () {
    late NetworkSecurity networkSecurity;

    setUp(() {
      networkSecurity = NetworkSecurity.instance;
      networkSecurity.clear(); // Clear any previous configuration
    });

    tearDown(() {
      networkSecurity.clear();
    });

    group('Certificate Pinning', () {
      test('should accept valid certificate when pinning is enabled', () {
        const testFingerprint =
            'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

        networkSecurity.addPinnedCertificate(testFingerprint);

        // Should accept the pinned certificate
        expect(networkSecurity.verifyCertificate(testFingerprint), isTrue);

        // Should also accept with different case
        expect(networkSecurity.verifyCertificate(testFingerprint.toLowerCase()),
            isTrue);
      });

      test('should reject invalid certificate when pinning is enabled', () {
        const pinnedFingerprint =
            'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
        const invalidFingerprint =
            'XX:YY:ZZ:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

        networkSecurity.addPinnedCertificate(pinnedFingerprint);

        // Should reject non-pinned certificate
        expect(networkSecurity.verifyCertificate(invalidFingerprint), isFalse);
      });

      test('should accept any certificate when pinning is disabled', () {
        const anyFingerprint =
            'XX:YY:ZZ:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

        // No pinned certificates added
        expect(networkSecurity.verifyCertificate(anyFingerprint), isTrue);
      });

      test('should handle multiple pinned certificates', () {
        const fingerprint1 = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
        const fingerprint2 = 'BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA';
        const fingerprint3 = 'CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB';

        networkSecurity.addPinnedCertificate(fingerprint1);
        networkSecurity.addPinnedCertificate(fingerprint2);

        expect(networkSecurity.verifyCertificate(fingerprint1), isTrue);
        expect(networkSecurity.verifyCertificate(fingerprint2), isTrue);
        expect(networkSecurity.verifyCertificate(fingerprint3), isFalse);
      });

      test('should remove pinned certificate', () {
        const testFingerprint =
            'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

        networkSecurity.addPinnedCertificate(testFingerprint);
        expect(networkSecurity.verifyCertificate(testFingerprint), isTrue);

        networkSecurity.removePinnedCertificate(testFingerprint);
        // After removal, any certificate should be accepted (no pinning)
        expect(networkSecurity.verifyCertificate(testFingerprint), isTrue);
        expect(
            networkSecurity.verifyCertificate('any:other:fingerprint'), isTrue);
      });
    });

    group('Request Signing', () {
      setUp(() {
        networkSecurity.configure(
          apiKey: 'test-api-key',
          signingSecret: 'test-signing-secret',
        );
      });

      test('should sign request with required headers', () {
        final headers = networkSecurity.signRequest(
          method: 'POST',
          path: '/api/v1/resource',
          body: {'data': 'test'},
        );

        expect(headers, isNotNull);
        expect(headers['X-API-Key'], equals('test-api-key'));
        expect(headers['X-Timestamp'], isNotNull);
        expect(headers['X-Nonce'], isNotNull);
        expect(headers['X-Signature'], isNotNull);
      });

      test('should generate different nonce for each request', () {
        final headers1 = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
        );

        final headers2 = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
        );

        expect(headers1['X-Nonce'], isNot(headers2['X-Nonce']));
      });

      test('should generate cryptographically secure nonces', () {
        // Generate multiple nonces
        final nonces = <String>{};
        for (int i = 0; i < 100; i++) {
          final headers = networkSecurity.signRequest(
            method: 'GET',
            path: '/api/v1/resource',
          );
          nonces.add(headers['X-Nonce']!);
        }

        // All nonces should be unique (high entropy)
        expect(nonces.length, equals(100));

        // Nonces should be base64 encoded
        for (final nonce in nonces) {
          expect(() => base64Url.decode(nonce), returnsNormally);
        }
      });

      test('should include custom headers in signed request', () {
        final customHeaders = {
          'User-Agent': 'Flutter MCP Client',
          'Accept': 'application/json',
        };

        final headers = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
          headers: customHeaders,
        );

        expect(headers['User-Agent'], equals('Flutter MCP Client'));
        expect(headers['Accept'], equals('application/json'));
        expect(headers['X-API-Key'], isNotNull);
      });

      test('should throw when signing without configuration', () {
        networkSecurity.clear();

        expect(
          () => networkSecurity.signRequest(
            method: 'GET',
            path: '/api/v1/resource',
          ),
          throwsStateError,
        );
      });

      test('should verify valid signed request', () {
        final headers = networkSecurity.signRequest(
          method: 'POST',
          path: '/api/v1/resource',
          body: {'data': 'test'},
        );

        final isValid = networkSecurity.verifyRequest(
          method: 'POST',
          path: '/api/v1/resource',
          headers: headers,
          body: {'data': 'test'},
        );

        expect(isValid, isTrue);
      });

      test('should reject request with invalid signature', () {
        final headers = networkSecurity.signRequest(
          method: 'POST',
          path: '/api/v1/resource',
          body: {'data': 'test'},
        );

        // Tamper with signature
        headers['X-Signature'] = 'invalid-signature';

        final isValid = networkSecurity.verifyRequest(
          method: 'POST',
          path: '/api/v1/resource',
          headers: headers,
          body: {'data': 'test'},
        );

        expect(isValid, isFalse);
      });

      test('should reject request with wrong API key', () {
        final headers = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
        );

        // Change API key
        headers['X-API-Key'] = 'wrong-api-key';

        final isValid = networkSecurity.verifyRequest(
          method: 'GET',
          path: '/api/v1/resource',
          headers: headers,
        );

        expect(isValid, isFalse);
      });

      test('should reject request with expired timestamp', () {
        final headers = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
        );

        // Set timestamp to 10 minutes ago
        final oldTimestamp = DateTime.now()
            .subtract(Duration(minutes: 10))
            .millisecondsSinceEpoch
            .toString();
        headers['X-Timestamp'] = oldTimestamp;

        final isValid = networkSecurity.verifyRequest(
          method: 'GET',
          path: '/api/v1/resource',
          headers: headers,
        );

        expect(isValid, isFalse);
      });

      test('should handle case-insensitive headers', () {
        final headers = networkSecurity.signRequest(
          method: 'GET',
          path: '/api/v1/resource',
        );

        // Convert headers to lowercase
        final lowercaseHeaders = <String, String>{};
        headers.forEach((key, value) {
          lowercaseHeaders[key.toLowerCase()] = value;
        });

        final isValid = networkSecurity.verifyRequest(
          method: 'GET',
          path: '/api/v1/resource',
          headers: lowercaseHeaders,
        );

        expect(isValid, isTrue);
      });
    });
  });
}
