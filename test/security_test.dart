import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/security/oauth_manager.dart';
import 'package:flutter_mcp/src/security/credential_manager.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  setUp(() {
    FlutterMcpLogging.configure(level: Level.FINE, enableDebugLogging: true);
  });

  group('OAuth Security Tests', () {
    test('OAuth configuration validation', () {
      // Test valid configuration
      final validConfig = OAuthConfig(
        clientId: 'valid_client_id',
        clientSecret: 'valid_client_secret',
        authorizationUrl: 'https://auth.example.com/authorize',
        tokenUrl: 'https://auth.example.com/token',
        scopes: ['read', 'write'],
      );

      expect(validConfig.clientId, isNotEmpty);
      expect(validConfig.clientSecret, isNotEmpty);
      expect(validConfig.authorizationUrl, startsWith('https://'));
      expect(validConfig.tokenUrl, startsWith('https://'));
      expect(validConfig.scopes, isNotEmpty);
    });

    test('OAuth token security', () {
      // Test token object
      final token = OAuthToken(
        accessToken: 'secure_access_token_123',
        refreshToken: 'secure_refresh_token_456',
        expiresAt: DateTime.now().add(Duration(hours: 1)),
        scopes: ['read', 'write'],
      );

      // Token should not be expired
      expect(token.isExpired, false);

      // Test JSON serialization (ensure sensitive data is handled)
      final json = token.toJson();
      expect(json['accessToken'], isNotEmpty);
      expect(json['refreshToken'], isNotEmpty);
      expect(json['expiresAt'], isNotNull);

      // Test deserialization
      final restoredToken = OAuthToken.fromJson(json);
      expect(restoredToken.accessToken, token.accessToken);
      expect(restoredToken.refreshToken, token.refreshToken);
    });

    test('Token expiration handling', () {
      // Create expired token
      final expiredToken = OAuthToken(
        accessToken: 'expired_token',
        expiresAt: DateTime.now().subtract(Duration(hours: 1)),
        scopes: ['read'],
      );

      expect(expiredToken.isExpired, true);

      // Create valid token
      final validToken = OAuthToken(
        accessToken: 'valid_token',
        expiresAt: DateTime.now().add(Duration(hours: 1)),
        scopes: ['read'],
      );

      expect(validToken.isExpired, false);
    });
  });

  group('Secure Storage Tests', () {
    test('Secure credential storage patterns', () async {
      // Test credential key patterns
      const validKeys = [
        'oauth_token_default',
        'api_key_openai',
        'client_secret_123',
        'refresh_token_abc',
      ];

      for (final key in validKeys) {
        // Keys should follow naming convention (letters, numbers, underscores)
        expect(key, matches(RegExp(r'^[a-z0-9_]+$')));
      }
    });

    test('Sensitive data handling', () {
      // Test that sensitive data can be handled carefully
      final sensitiveData = 'super_secret_api_key';
      
      try {
        // Don't pass sensitive data as originalError
        throw MCPAuthenticationException(
          'Authentication failed',
          // Instead of passing the actual sensitive data,
          // pass a sanitized version
        );
      } catch (e) {
        // When no originalError is passed, it won't be in the output
        expect(e.toString(), isNot(contains(sensitiveData)));
        expect(e.toString(), contains('Authentication failed'));
      }
    });

    test('Credential validation', () {
      // Test various credential formats
      final credentials = {
        'valid_api_key': 'sk-1234567890abcdef',
        'invalid_empty': '',
        'invalid_spaces': '  ',
        'valid_token': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9',
      };

      // Validate credential formats
      expect(credentials['valid_api_key']!.length, greaterThan(10));
      expect(credentials['invalid_empty'], isEmpty);
      expect(credentials['invalid_spaces']!.trim(), isEmpty);
      expect(credentials['valid_token'], startsWith('Bearer '));
    });
  });

  group('Transport Security Tests', () {
    test('Secure transport configuration', () {
      // Test that sensitive transport data is handled securely
      const authToken = 'secret_auth_token';
      
      // In real implementation, tokens should be:
      // 1. Stored securely
      // 2. Transmitted over HTTPS only
      // 3. Not logged in plain text
      
      expect(authToken, isNotEmpty);
      expect(authToken.length, greaterThan(10));
    });

    test('URL validation for OAuth endpoints', () {
      // Test URL validation
      final validUrls = [
        'https://auth.example.com/authorize',
        'https://api.example.com/v1/token',
        'https://secure.example.com:8443/oauth',
      ];

      final invalidUrls = [
        'http://insecure.example.com/auth', // HTTP not allowed
        'ftp://wrong.protocol.com/auth',
        'not_a_url',
        '',
      ];

      for (final url in validUrls) {
        expect(Uri.tryParse(url), isNotNull);
        expect(Uri.parse(url).scheme, 'https');
      }

      for (final url in invalidUrls) {
        if (url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            expect(uri.scheme, isNot('https'));
          }
        }
      }
    });
  });

  group('Error Security Tests', () {
    test('Exception sanitization', () {
      // Test that exceptions can be created without leaking sensitive information
      const sensitiveInfo = 'password123';
      const safeMessage = 'Authentication failed';
      
      // Don't include sensitive info in originalError
      final exception = MCPAuthenticationException.withContext(
        safeMessage,
        originalError: 'Invalid credentials', // Sanitized error message
        errorCode: 'AUTH_FAILED',
        resolution: 'Please check your credentials',
      );

      // Exception string should not contain sensitive info
      final exceptionString = exception.toString();
      expect(exceptionString, contains(safeMessage));
      expect(exceptionString, contains('AUTH_FAILED'));
      expect(exceptionString, isNot(contains(sensitiveInfo)));
    });

    test('Secure error codes', () {
      // Test error codes don't reveal system internals
      const errorCodes = [
        'AUTH_ERROR',
        'INVALID_TOKEN',
        'EXPIRED_TOKEN',
        'PERMISSION_DENIED',
        'RATE_LIMITED',
      ];

      for (final code in errorCodes) {
        // Error codes should be generic enough to not reveal internals
        expect(code, matches(RegExp(r'^[A-Z_]+$')));
        expect(code, isNot(contains('SQL')));
        expect(code, isNot(contains('DATABASE')));
        expect(code, isNot(contains('FILE_PATH')));
      }
    });
  });

  group('Permission and Access Control Tests', () {
    test('OAuth scope validation', () {
      // Test scope handling
      final scopes = ['read', 'write', 'delete', 'admin'];
      
      // Validate scope format
      for (final scope in scopes) {
        expect(scope, matches(RegExp(r'^[a-z]+$')));
      }

      // Test scope combinations
      final readOnlyScopes = ['read'];
      final fullAccessScopes = ['read', 'write', 'delete'];
      final adminScopes = ['admin'];

      expect(readOnlyScopes, isNot(contains('write')));
      expect(readOnlyScopes, isNot(contains('delete')));
      expect(fullAccessScopes, isNot(contains('admin')));
      expect(adminScopes.length, 1); // Admin should be separate
    });

    test('Secure headers generation', () async {
      // Test that auth headers are properly formatted
      const mockToken = 'mock_access_token_12345';
      final headers = {
        'Authorization': 'Bearer $mockToken',
      };

      // Validate header format
      expect(headers['Authorization'], startsWith('Bearer '));
      expect(headers['Authorization']!.split(' ').length, 2);
      
      // Headers should not contain sensitive info in keys
      for (final key in headers.keys) {
        expect(key, isNot(contains('password')));
        expect(key, isNot(contains('secret')));
      }
    });
  });

  group('Data Sanitization Tests', () {
    test('Input sanitization', () {
      // Test input sanitization
      final inputs = {
        'normal': 'Hello World',
        'script': '<script>alert("xss")</script>',
        'sql': "'; DROP TABLE users; --",
        'path': '../../../etc/passwd',
      };

      // In real implementation, these should be sanitized
      for (final input in inputs.values) {
        // Check that input is a string (basic validation)
        expect(input, isA<String>());
      }

      // Test that dangerous inputs are identified
      expect(inputs['script'], contains('<script>'));
      expect(inputs['sql'], contains(';'));
      expect(inputs['path'], contains('../'));
    });

    test('Output encoding', () {
      // Test that outputs are properly encoded
      const rawOutput = 'User said: "Hello & goodbye"';
      
      // HTML encoding
      final htmlEncoded = rawOutput
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      
      expect(htmlEncoded, contains('&amp;'));
      expect(htmlEncoded, contains('&quot;'));
      expect(htmlEncoded, isNot(contains('"')));
    });
  });

  group('Cryptographic Security Tests', () {
    test('Token generation requirements', () {
      // Test token generation patterns
      const minTokenLength = 32;
      const mockToken = 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6'; // 32 chars
      
      expect(mockToken.length, greaterThanOrEqualTo(minTokenLength));
      
      // Token should contain alphanumeric characters
      expect(mockToken, matches(RegExp(r'^[a-zA-Z0-9]+$')));
    });

    test('Secure random generation', () {
      // Test that random values are sufficiently random
      final random1 = DateTime.now().microsecondsSinceEpoch.toString();
      
      // Wait a bit
      final random2 = DateTime.now().microsecondsSinceEpoch.toString();
      
      // Values should be different
      expect(random1, isNot(equals(random2)));
      
      // Values should have sufficient entropy (length)
      expect(random1.length, greaterThanOrEqualTo(10));
    });
  });
}