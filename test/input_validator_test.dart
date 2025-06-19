import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/input_validator.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  group('InputValidator', () {
    group('API Key Validation', () {
      test('should accept valid API keys', () {
        expect(
            InputValidator.isValidApiKey(
                'sk-1234567890abcdefghijklmnopqrstuvwxyz'),
            true);
        expect(InputValidator.isValidApiKey('gpt-4-turbo-preview-token'), true);
        expect(InputValidator.isValidApiKey('anthropic_claude_3_api_key_123'),
            true);
        expect(InputValidator.isValidApiKey('0123456789abcdef-ghij'), true);
      });

      test('should reject invalid API keys', () {
        expect(InputValidator.isValidApiKey(null), false);
        expect(InputValidator.isValidApiKey(''), false);
        expect(InputValidator.isValidApiKey('short'), false);
        expect(
            InputValidator.isValidApiKey('contains spaces and invalid'), false);
        expect(InputValidator.isValidApiKey('has@invalid#chars'), false);
        expect(InputValidator.isValidApiKey('ὕλη'), false); // unicode chars
      });

      test('validateApiKeyOrThrow should throw for invalid keys', () {
        expect(() => InputValidator.validateApiKeyOrThrow(null),
            throwsA(isA<MCPValidationException>()));
        expect(() => InputValidator.validateApiKeyOrThrow('short'),
            throwsA(isA<MCPValidationException>()));
        expect(() => InputValidator.validateApiKeyOrThrow('invalid@key'),
            throwsA(isA<MCPValidationException>()));
      });

      test('validateApiKeyOrThrow should not throw for valid keys', () {
        expect(
            () => InputValidator.validateApiKeyOrThrow(
                'sk-1234567890abcdefghijklmnopqrstuvwxyz'),
            returnsNormally);
      });
    });

    group('URL Validation', () {
      test('should accept valid HTTP/HTTPS URLs', () {
        expect(InputValidator.isValidUrl('https://api.openai.com'), true);
        expect(InputValidator.isValidUrl('http://localhost:8080'), true);
        expect(
            InputValidator.isValidUrl('https://api.anthropic.com/v1/messages'),
            true);
        expect(InputValidator.isValidUrl('http://192.168.1.1:3000/api'), true);
      });

      test('should reject invalid URLs', () {
        expect(InputValidator.isValidUrl(null), false);
        expect(InputValidator.isValidUrl(''), false);
        expect(InputValidator.isValidUrl('ftp://example.com'), false);
        expect(InputValidator.isValidUrl('not-a-url'), false);
        expect(InputValidator.isValidUrl('javascript:alert(1)'), false);
        expect(InputValidator.isValidUrl('file:///etc/passwd'), false);
      });

      test('should accept valid WebSocket URLs', () {
        expect(InputValidator.isValidWebSocketUrl('wss://api.example.com/ws'),
            true);
        expect(
            InputValidator.isValidWebSocketUrl('ws://localhost:8080/ws'), true);
      });

      test('should reject invalid WebSocket URLs', () {
        expect(
            InputValidator.isValidWebSocketUrl('https://example.com'), false);
        expect(InputValidator.isValidWebSocketUrl('not-a-url'), false);
        expect(InputValidator.isValidWebSocketUrl(null), false);
      });

      test('validateUrlOrThrow should throw for invalid URLs', () {
        expect(() => InputValidator.validateUrlOrThrow('invalid-url'),
            throwsA(isA<MCPValidationException>()));
        expect(() => InputValidator.validateUrlOrThrow('ftp://example.com'),
            throwsA(isA<MCPValidationException>()));
      });
    });

    group('Port Validation', () {
      test('should accept valid port numbers', () {
        expect(InputValidator.isValidPort(80), true);
        expect(InputValidator.isValidPort(443), true);
        expect(InputValidator.isValidPort(8080), true);
        expect(InputValidator.isValidPort(65535), true);
        expect(InputValidator.isValidPort(1), true);
      });

      test('should reject invalid port numbers', () {
        expect(InputValidator.isValidPort(null), false);
        expect(InputValidator.isValidPort(0), false);
        expect(InputValidator.isValidPort(-1), false);
        expect(InputValidator.isValidPort(65536), false);
        expect(InputValidator.isValidPort(100000), false);
      });

      test('validatePortOrThrow should throw for invalid ports', () {
        expect(() => InputValidator.validatePortOrThrow(0),
            throwsA(isA<MCPValidationException>()));
        expect(() => InputValidator.validatePortOrThrow(65536),
            throwsA(isA<MCPValidationException>()));
      });
    });

    group('File Path Validation', () {
      test('should accept valid file paths', () {
        expect(InputValidator.isValidFilePath('/home/user/document.txt'), true);
        expect(InputValidator.isValidFilePath('configs/app.yaml'), true);
        expect(InputValidator.isValidFilePath('data.json'), true);
      });

      test('should reject dangerous file paths', () {
        expect(InputValidator.isValidFilePath('../../../etc/passwd'), false);
        expect(InputValidator.isValidFilePath('~/../../etc/shadow'), false);
        expect(InputValidator.isValidFilePath('/etc/passwd'), false);
        expect(InputValidator.isValidFilePath('/root/secret'), false);
        expect(InputValidator.isValidFilePath('C:\\Windows\\System32'), false);
        expect(
            InputValidator.isValidFilePath('..\\..\\windows\\system32'), false);
      });

      test('should reject null or empty paths', () {
        expect(InputValidator.isValidFilePath(null), false);
        expect(InputValidator.isValidFilePath(''), false);
      });
    });

    group('App Name Validation', () {
      test('should accept valid app names', () {
        expect(InputValidator.isValidAppName('My Flutter App'), true);
        expect(InputValidator.isValidAppName('MCP-Client-2024'), true);
        expect(InputValidator.isValidAppName('Test123'), true);
        expect(InputValidator.isValidAppName('a'), true);
      });

      test('should reject invalid app names', () {
        expect(InputValidator.isValidAppName(null), false);
        expect(InputValidator.isValidAppName(''), false);
        expect(InputValidator.isValidAppName('App@Name'), false);
        expect(InputValidator.isValidAppName('App_With_Underscores'), false);
        expect(
            InputValidator.isValidAppName(
                'Very very very very very very very very very very long app name that exceeds 100 characters limit test'),
            false);
      });
    });

    group('Version Validation', () {
      test('should accept valid semantic versions', () {
        expect(InputValidator.isValidVersion('1.0.0'), true);
        expect(InputValidator.isValidVersion('2.1.3'), true);
        expect(InputValidator.isValidVersion('1.0.0-beta'), true);
        expect(InputValidator.isValidVersion('1.0.0-alpha.1'), true);
        expect(InputValidator.isValidVersion('10.20.30-rc1'), true);
      });

      test('should reject invalid versions', () {
        expect(InputValidator.isValidVersion(null), false);
        expect(InputValidator.isValidVersion(''), false);
        expect(InputValidator.isValidVersion('1.0'), false);
        expect(InputValidator.isValidVersion('v1.0.0'), false);
        expect(InputValidator.isValidVersion('1.0.0.0'), false);
        expect(InputValidator.isValidVersion('1.0.0-'), false);
      });
    });

    group('Email Validation', () {
      test('should accept valid email addresses', () {
        expect(InputValidator.isValidEmail('user@example.com'), true);
        expect(InputValidator.isValidEmail('test.email@domain.co.uk'), true);
        expect(InputValidator.isValidEmail('user+tag@example.org'), true);
        expect(InputValidator.isValidEmail('user123@domain123.com'), true);
      });

      test('should reject invalid email addresses', () {
        expect(InputValidator.isValidEmail(null), false);
        expect(InputValidator.isValidEmail(''), false);
        expect(InputValidator.isValidEmail('invalid-email'), false);
        expect(InputValidator.isValidEmail('@domain.com'), false);
        expect(InputValidator.isValidEmail('user@'), false);
        expect(InputValidator.isValidEmail('user@domain'), false);
        expect(InputValidator.isValidEmail('user space@domain.com'), false);
      });

      test('validateEmailOrThrow should throw for invalid emails', () {
        expect(() => InputValidator.validateEmailOrThrow('invalid-email'),
            throwsA(isA<MCPValidationException>()));
      });
    });

    group('JSON Validation', () {
      test('should accept valid JSON strings', () {
        expect(InputValidator.isValidJson('{"key": "value"}'), true);
        expect(InputValidator.isValidJson('[1, 2, 3]'), true);
      });

      test('should reject invalid JSON strings', () {
        expect(InputValidator.isValidJson(null), false);
        expect(InputValidator.isValidJson(''), false);
        expect(InputValidator.isValidJson('not json'), false);
        expect(InputValidator.isValidJson('{invalid}'), false);
      });
    });

    group('String Sanitization', () {
      test('should remove HTML tags', () {
        final result =
            InputValidator.sanitizeString('<script>alert("xss")</script>Hello');
        expect(result, 'Hello');
      });

      test('should remove SQL injection characters', () {
        final result = InputValidator.sanitizeString(
            'SELECT * FROM users WHERE id = 1; DROP TABLE users;');
        expect(result.contains(';'), false);
        expect(result.contains("'"), false);
        expect(result.contains('"'), false);
      });

      test('should remove script-related keywords', () {
        final result = InputValidator.sanitizeString('javascript:alert(1)');
        expect(result.toLowerCase().contains('javascript:'), false);
      });

      test('should handle null input', () {
        expect(InputValidator.sanitizeString(null), '');
      });
    });

    group('Length Validation', () {
      test('should validate string length correctly', () {
        expect(
            InputValidator.isValidLength('hello', minLength: 3, maxLength: 10),
            true);
        expect(InputValidator.isValidLength('ab', minLength: 3), false);
        expect(InputValidator.isValidLength('very long string', maxLength: 10),
            false);
        expect(InputValidator.isValidLength(null, minLength: 0), true);
        expect(InputValidator.isValidLength(null), true);
      });
    });

    group('Number Range Validation', () {
      test('should validate number ranges correctly', () {
        expect(InputValidator.isValidNumberRange(5, min: 1, max: 10), true);
        expect(InputValidator.isValidNumberRange(0, min: 1), false);
        expect(InputValidator.isValidNumberRange(15, max: 10), false);
        expect(InputValidator.isValidNumberRange(null), false);
      });
    });

    group('Required Fields Validation', () {
      test('should pass when all required fields are present', () {
        expect(
            () => InputValidator.validateRequired({
                  'name': 'Test App',
                  'version': '1.0.0',
                  'port': 8080,
                }),
            returnsNormally);
      });

      test('should throw when required fields are missing', () {
        expect(
            () => InputValidator.validateRequired({
                  'name': '',
                  'version': null,
                  'data': [],
                  'config': {},
                }),
            throwsA(isA<MCPValidationException>()));
      });

      test('should provide missing field names in exception', () {
        try {
          InputValidator.validateRequired({
            'name': '',
            'version': null,
            'port': 8080,
          });
          fail('Should have thrown exception');
        } catch (e) {
          expect(e, isA<MCPValidationException>());
          final exception = e as MCPValidationException;
          expect(exception.message.contains('name'), true);
          expect(exception.message.contains('version'), true);
          final errors = exception.validationErrors;
          if (errors['missingFields'] != null) {
            expect(errors['missingFields'], contains('name'));
            expect(errors['missingFields'], contains('version'));
          }
        }
      });
    });

    group('Edge Cases', () {
      test('should handle unicode characters appropriately', () {
        expect(InputValidator.isValidAppName('app_name'), false); // Non-ASCII
        expect(InputValidator.sanitizeString('Hello 世界'),
            'Hello 世界'); // Should preserve non-malicious unicode
      });

      test('should handle very long inputs', () {
        final longString = 'a' * 10000;
        expect(InputValidator.isValidLength(longString, maxLength: 100), false);
        expect(InputValidator.sanitizeString(longString).length,
            10000); // Should not crash
      });

      test('should handle empty and whitespace inputs', () {
        expect(InputValidator.isValidAppName('   '),
            true); // Spaces are allowed in app names
        expect(
            InputValidator.sanitizeString('   '), '   '); // Preserve whitespace
      });
    });
  });
}
