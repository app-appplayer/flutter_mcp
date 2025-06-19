import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/security/security_audit.dart';
import 'package:flutter_mcp/src/security/encryption_manager.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('Security Audit Manager Tests', () {
    late SecurityAuditManager auditManager;

    setUp(() async {
      auditManager = SecurityAuditManager.instance;
      auditManager.initialize();
      // Clear any existing events
      await EventSystem.instance.reset();
    });

    tearDown(() async {
      auditManager.dispose();
      // Wait a bit to ensure all events are processed
      await Future.delayed(Duration(milliseconds: 100));
      await EventSystem.instance.reset();
    });

    group('Authentication Management', () {
      test('should handle successful authentication', () {
        // Act
        bool result = auditManager.checkAuthenticationAttempt(
          'user123',
          true,
          metadata: {'method': 'password'},
        );

        // Assert
        expect(result, isTrue);
        expect(auditManager.isUserLockedOut('user123'), isFalse);
      });

      test('should handle failed authentication attempts', () {
        // Act - First failed attempt
        bool result1 =
            auditManager.checkAuthenticationAttempt('user123', false);
        expect(result1, isTrue); // Not locked yet
        expect(auditManager.isUserLockedOut('user123'), isFalse);

        // Act - Multiple failed attempts
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.checkAuthenticationAttempt('user123', false);

        // Assert - User should be locked out after 5 failed attempts (default policy)
        expect(auditManager.isUserLockedOut('user123'), isTrue);
      });

      test('should reset failed attempts on successful authentication', () {
        // Arrange - Generate failed attempts
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.checkAuthenticationAttempt('user123', false);

        // Act - Successful authentication
        bool result = auditManager.checkAuthenticationAttempt('user123', true);

        // Assert
        expect(result, isTrue);
        expect(auditManager.isUserLockedOut('user123'), isFalse);
      });

      test('should handle custom lockout policy', () {
        // Arrange
        auditManager.updatePolicy(SecurityPolicy(
          maxFailedAttempts: 2,
          lockoutDuration: Duration(minutes: 5),
        ));

        // Act
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.checkAuthenticationAttempt('user123', false);

        // Assert
        expect(auditManager.isUserLockedOut('user123'), isTrue);
      });
    });

    group('Session Management', () {
      test('should start and end sessions correctly', () {
        // Act
        String sessionId = auditManager.startSession(
          'user123',
          metadata: {'device': 'mobile'},
        );

        // Assert
        expect(sessionId, isNotEmpty);
        expect(sessionId, startsWith('sess_'));

        // Act - End session
        auditManager.endSession('user123', sessionId);

        // Assert - Should be able to get audit events
        List<SecurityAuditEvent> events =
            auditManager.getUserAuditEvents('user123');
        expect(events.length, greaterThanOrEqualTo(2)); // start and end events
      });

      test('should handle concurrent session limits', () {
        // Arrange
        auditManager.updatePolicy(SecurityPolicy(maxConcurrentSessions: 2));

        // Act - Start multiple sessions
        auditManager.startSession('user123');
        auditManager.startSession('user123');
        auditManager.startSession('user123'); // Should remove first session

        // Assert - Should have at most 2 sessions
        List<SecurityAuditEvent> events =
            auditManager.getUserAuditEvents('user123');
        List<SecurityAuditEvent> sessionStarts =
            events.where((e) => e.action == 'session_start').toList();
        expect(sessionStarts.length, equals(3)); // All starts are logged
      });
    });

    group('Data Access Authorization', () {
      test('should authorize valid data access', () {
        // Act
        bool authorized = auditManager.checkDataAccess(
          'user123',
          'document',
          'read',
          metadata: {'documentId': 'doc_123'},
        );

        // Assert
        expect(authorized, isTrue);
      });

      test('should block restricted actions', () {
        // Arrange
        auditManager.updatePolicy(SecurityPolicy(
          blockedActions: ['admin_delete'],
        ));

        // Act
        bool authorized = auditManager.checkDataAccess(
          'user123',
          'system',
          'admin_delete',
        );

        // Assert
        expect(authorized, isFalse);
      });
    });

    group('Risk Assessment', () {
      test('should calculate user risk scores', () {
        // Arrange - Create some events
        auditManager.checkAuthenticationAttempt('user123', false);
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'test_event',
          type: SecurityEventType.suspicious,
          userId: 'user123',
          action: 'unusual_activity',
          resource: 'system',
          success: false,
          riskScore: 50,
        ));

        // Act
        Map<String, dynamic> riskAssessment =
            auditManager.getUserRiskAssessment('user123');

        // Assert
        expect(riskAssessment['riskScore'], greaterThan(0));
        expect(riskAssessment['riskLevel'], isNotNull);
        expect(riskAssessment['factors'], isA<List<String>>());
      });

      test('should update risk scores over time', () {
        // Arrange
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'event1',
          type: SecurityEventType.suspicious,
          userId: 'user123',
          action: 'test_action',
          resource: 'test_resource',
          success: false,
          riskScore: 25,
        ));

        Map<String, dynamic> initialRisk =
            auditManager.getUserRiskAssessment('user123');

        // Act - Add another risky event
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'event2',
          type: SecurityEventType.suspicious,
          userId: 'user123',
          action: 'test_action2',
          resource: 'test_resource',
          success: false,
          riskScore: 30,
        ));

        Map<String, dynamic> updatedRisk =
            auditManager.getUserRiskAssessment('user123');

        // Assert
        expect(updatedRisk['riskScore'], greaterThan(initialRisk['riskScore']));
      });
    });

    group('Security Reporting', () {
      test('should generate comprehensive security reports', () {
        // Arrange - Generate some events
        auditManager.checkAuthenticationAttempt('user123', true);
        auditManager.checkAuthenticationAttempt('user456', false);
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'suspicious_event',
          type: SecurityEventType.suspicious,
          userId: 'user789',
          action: 'multiple_attempts',
          resource: 'login_system',
          success: false,
          riskScore: 60,
        ));

        // Act
        Map<String, dynamic> report = auditManager.generateSecurityReport();

        // Assert
        expect(report['generatedAt'], isNotNull);
        expect(report['totalEvents'], greaterThan(0));
        expect(report['events24h'], greaterThan(0));
        expect(report['eventsByType'], isA<Map<String, int>>());
        expect(report['topRiskyUsers'], isA<List>());
      });
    });

    group('Event System Integration', () {
      test('should publish security events to event system', () async {
        // Arrange
        List<SecurityEvent> capturedEvents = [];
        await EventSystem.instance.subscribeTopic('security.event', (event) {
          capturedEvents.add(event);
        });

        // Act
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'test_event',
          type: SecurityEventType.authentication,
          userId: 'user123',
          action: 'login',
          resource: 'system',
          success: true,
          riskScore: 10,
        ));

        // Wait for event processing
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        expect(capturedEvents.length, equals(1));
        expect(capturedEvents.first.eventType_, equals('authentication'));
        expect(capturedEvents.first.userId, equals('user123'));
      });

      test('should publish security alerts for high-risk events', () async {
        // Arrange
        List<SecurityAlert> capturedAlerts = [];
        await EventSystem.instance.subscribeTopic('security.alert', (alert) {
          capturedAlerts.add(alert);
        });

        // Act - Log high-risk event
        auditManager.logSecurityEvent(SecurityAuditEvent(
          eventId: 'high_risk_event',
          type: SecurityEventType.breach,
          userId: 'user123',
          action: 'unauthorized_access',
          resource: 'sensitive_data',
          success: false,
          riskScore: 100, // Critical risk score
        ));

        // Wait for event processing
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        expect(capturedAlerts.length, equals(1));
        expect(capturedAlerts.first.severity, equals(AlertSeverity.critical));
      });
    });
  });

  group('Encryption Manager Tests', () {
    late EncryptionManager encryptionManager;

    setUp(() {
      encryptionManager = EncryptionManager.instance;
      encryptionManager.initialize(minKeyLength: 256); // AES256 key length
    });

    tearDown(() {
      encryptionManager.dispose();
    });

    group('Key Management', () {
      test('should generate encryption keys', () {
        // Act
        String keyId = encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          alias: 'test_key',
          metadata: {'purpose': 'testing'},
        );

        // Assert
        expect(keyId, isNotEmpty);
        expect(keyId, startsWith('key_'));

        Map<String, dynamic>? keyInfo = encryptionManager.getKeyInfo(keyId);
        expect(keyInfo, isNotNull);
        expect(keyInfo!['algorithm'], equals('aes256'));
      });

      test('should import existing keys', () {
        // Arrange
        Uint8List keyData = Uint8List.fromList(List.generate(32, (i) => i));

        // Act
        String keyId = encryptionManager.importKey(
          EncryptionAlgorithm.aes256, // 32 bytes is correct for AES256
          keyData,
          alias: 'imported_key',
        );

        // Assert
        expect(keyId, isNotEmpty);
        Map<String, dynamic>? keyInfo = encryptionManager.getKeyInfo(keyId);
        expect(keyInfo!['keyLength'], equals(32));
      });

      test('should reject keys below minimum length', () {
        // Arrange
        encryptionManager.initialize(
            minKeyLength: 512); // Set higher than AES256 (256 bits)

        // Act & Assert
        expect(
          () => encryptionManager.generateKey(EncryptionAlgorithm.aes256),
          throwsA(isA<MCPSecurityException>()),
        );
      });

      test('should handle key aliases', () {
        // Act
        String keyId = encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          alias: 'my_key',
        );

        // Assert - Should be able to reference by alias
        Map<String, dynamic>? keyInfo1 = encryptionManager.getKeyInfo(keyId);
        Map<String, dynamic>? keyInfo2 = encryptionManager.getKeyInfo('my_key');
        expect(keyInfo1!['keyId'], equals(keyInfo2!['keyId']));
      });
    });

    group('Data Encryption/Decryption', () {
      test('should encrypt and decrypt data correctly', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        String originalData = 'This is sensitive information';

        // Act
        EncryptedData encrypted =
            encryptionManager.encrypt(keyId, originalData);
        String decrypted = encryptionManager.decrypt(encrypted);

        // Assert
        expect(decrypted, equals(originalData));
        expect(encrypted.data, isNotEmpty);
        expect(encrypted.metadata.keyId, equals(keyId));
        expect(encrypted.checksum, isNotNull);
      });

      test('should handle encryption with parameters', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        Map<String, dynamic> parameters = {
          'version': '1.0',
          'format': 'text',
        };

        // Act
        EncryptedData encrypted = encryptionManager.encrypt(
          keyId,
          'test data',
          parameters: parameters,
        );

        // Assert
        expect(encrypted.metadata.parameters, equals(parameters));
      });

      test('should fail with non-existent key', () {
        // Act & Assert
        expect(
          () => encryptionManager.encrypt('non_existent_key', 'data'),
          throwsA(isA<MCPSecurityException>()),
        );
      });

      test('should fail with expired key', () async {
        // Arrange
        String keyId = encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          expiresIn: Duration(milliseconds: 1),
        );

        // Wait for key to expire
        await Future.delayed(Duration(milliseconds: 10));

        // Act & Assert
        expect(
          () => encryptionManager.encrypt(keyId, 'data'),
          throwsA(isA<MCPSecurityException>()),
        );
      });

      test('should verify data integrity with checksums', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        EncryptedData encrypted = encryptionManager.encrypt(keyId, 'test data');

        // Tamper with data
        encrypted.data[0] = encrypted.data[0] ^ 0xFF;

        // Act & Assert
        expect(
          () => encryptionManager.decrypt(encrypted),
          throwsA(isA<MCPSecurityException>()),
        );
      });
    });

    group('Key Rotation', () {
      test('should rotate keys successfully', () {
        // Arrange
        String originalKeyId = encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          alias: 'rotating_key',
        );

        // Act
        String newKeyId = encryptionManager.rotateKey('rotating_key');

        // Assert
        expect(newKeyId, isNot(equals(originalKeyId)));

        // Original key should be expired
        Map<String, dynamic>? originalKeyInfo =
            encryptionManager.getKeyInfo(originalKeyId);
        expect(originalKeyInfo!['expiresAt'], isNotNull);

        // Alias should point to new key
        Map<String, dynamic>? aliasKeyInfo =
            encryptionManager.getKeyInfo('rotating_key');
        expect(aliasKeyInfo!['keyId'], equals(newKeyId));
      });
    });

    group('Key Lifecycle Management', () {
      test('should list all keys', () {
        // Arrange
        encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        encryptionManager.generateKey(EncryptionAlgorithm.aes256);

        // Act
        List<Map<String, dynamic>> keys = encryptionManager.listKeys();

        // Assert
        expect(keys.length, greaterThanOrEqualTo(2));
        expect(keys.every((key) => key.containsKey('keyId')), isTrue);
        expect(keys.every((key) => key.containsKey('algorithm')), isTrue);
      });

      test('should identify expired keys', () async {
        // Arrange
        encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          expiresIn: Duration(milliseconds: 1),
        );

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 10));

        // Act
        List<String> expiredKeys = encryptionManager.getExpiredKeys();

        // Assert
        expect(expiredKeys.length, equals(1));
      });

      test('should cleanup expired keys', () async {
        // Arrange
        String expiredKeyId = encryptionManager.generateKey(
          EncryptionAlgorithm.aes256,
          expiresIn: Duration(milliseconds: 1),
        );

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 10));

        // Act
        int deletedCount = encryptionManager.cleanupExpiredKeys();

        // Assert
        expect(deletedCount, equals(1));
        expect(encryptionManager.getKeyInfo(expiredKeyId), isNull);
      });

      test('should prevent deletion of active keys without force', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);

        // Act & Assert
        expect(
          () => encryptionManager.deleteKey(keyId),
          throwsA(isA<MCPSecurityException>()),
        );

        // Should succeed with force
        bool deleted = encryptionManager.deleteKey(keyId, force: true);
        expect(deleted, isTrue);
      });
    });

    group('Security Reporting', () {
      test('should generate encryption security reports', () {
        // Arrange
        encryptionManager.generateKey(EncryptionAlgorithm.aes256,
            alias: 'key1');
        encryptionManager.generateKey(EncryptionAlgorithm.aes256,
            alias: 'key2');

        // Act
        Map<String, dynamic> report =
            encryptionManager.generateSecurityReport();

        // Assert
        expect(report['generatedAt'], isNotNull);
        expect(report['totalKeys'], greaterThanOrEqualTo(2));
        expect(report['activeKeys'], greaterThanOrEqualTo(2));
        expect(report['aliases'], greaterThanOrEqualTo(2));
        expect(report['keysByAlgorithm'], isA<Map<String, int>>());
        expect(report['settings'], isA<Map<String, dynamic>>());
      });
    });

    group('Serialization', () {
      test('should serialize and deserialize encrypted data', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        String originalData = 'Test serialization data';
        EncryptedData encrypted =
            encryptionManager.encrypt(keyId, originalData);

        // Act - Serialize
        Map<String, dynamic> serialized = encrypted.toJson();
        String jsonString = jsonEncode(serialized);

        // Deserialize
        Map<String, dynamic> deserialized = jsonDecode(jsonString);
        EncryptedData restored = EncryptedData.fromJson(deserialized);

        // Decrypt restored data
        String decrypted = encryptionManager.decrypt(restored);

        // Assert
        expect(decrypted, equals(originalData));
        expect(restored.metadata.keyId, equals(encrypted.metadata.keyId));
        expect(restored.checksum, equals(encrypted.checksum));
      });
    });

    group('Error Handling', () {
      test('should handle encryption errors gracefully', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);

        // Act & Assert - Invalid data types should be handled
        expect(
          () => encryptionManager.encrypt(keyId, ''),
          returnsNormally,
        );
      });

      test('should audit security events', () {
        // Arrange
        String keyId =
            encryptionManager.generateKey(EncryptionAlgorithm.aes256);
        SecurityAuditManager auditManager = SecurityAuditManager.instance;
        List<SecurityAuditEvent> initialEvents =
            auditManager.getAllAuditEvents();

        // Act
        encryptionManager.encrypt(keyId, 'test data');

        // Assert - Should have logged encryption event
        List<SecurityAuditEvent> finalEvents = auditManager.getAllAuditEvents();
        expect(finalEvents.length, greaterThan(initialEvents.length));

        SecurityAuditEvent? encryptionEvent =
            finalEvents.where((e) => e.action == 'data_encrypted').firstOrNull;
        expect(encryptionEvent, isNotNull);
      });
    });
  });
}
