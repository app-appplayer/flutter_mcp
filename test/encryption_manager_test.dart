import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/security/encryption_manager.dart';
import 'dart:typed_data';

void main() {
  group('EncryptionManager Tests', () {
    late EncryptionManager encryptionManager;

    setUp(() {
      encryptionManager = EncryptionManager.instance;
    });

    test('should encrypt and decrypt string correctly', () async {
      const testString = 'Hello, Flutter MCP!';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-1',
      );
      expect(keyId, isNotNull);
      expect(keyId.length, greaterThan(0));

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, testString);
      expect(encrypted, isNotNull);
      expect(encrypted.data, isNotNull);
      expect(encrypted.data, isNot(equals(testString.codeUnits)));

      // Decrypt
      final decrypted = encryptionManager.decrypt(encrypted);
      expect(decrypted, equals(testString));
    });

    test('should encrypt and decrypt data correctly', () async {
      final testString = 'Test data: [1, 2, 3, 4, 5]';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-2',
      );

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, testString);
      expect(encrypted, isNotNull);
      expect(encrypted.data, isNotNull);

      // Decrypt
      final decrypted = encryptionManager.decrypt(encrypted);
      expect(decrypted, equals(testString));
    });

    test('should handle empty string encryption', () async {
      const testString = '';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-3',
      );

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, testString);
      expect(encrypted, isNotNull);

      // Decrypt
      final decrypted = encryptionManager.decrypt(encrypted);
      expect(decrypted, equals(testString));
    });

    test('should fail decryption with wrong key (AES-GCM authentication)',
        () async {
      const testString = 'Secret message';

      // Generate keys
      final keyId1 = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-4',
      );
      final keyId2 = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-5',
      );

      // Encrypt with key1
      final encrypted = encryptionManager.encrypt(keyId1, testString);

      // Modify encrypted data to simulate wrong key decryption
      // With AES-GCM, wrong key will fail authentication
      final tamperedData = EncryptedData(
        data: encrypted.data,
        metadata: EncryptionMetadata(
          algorithm: encrypted.metadata.algorithm,
          keyId: keyId2, // Use different key ID
          salt: encrypted.metadata.salt,
          iv: encrypted.metadata.iv,
          parameters: encrypted.metadata.parameters,
        ),
        checksum: encrypted.checksum,
      );

      // Try to decrypt with key2 - should throw exception
      expect(
        () => encryptionManager.decrypt(tamperedData),
        throwsA(isA<Exception>()),
      );
    });

    test('should encrypt data larger than GCM block size', () async {
      // Create data larger than 128 bits (16 bytes)
      final largeString = 'A' * 1000; // 1000 characters

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-6',
      );

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, largeString);
      expect(encrypted, isNotNull);
      expect(encrypted.data.length, greaterThan(0));

      // Decrypt
      final decrypted = encryptionManager.decrypt(encrypted);
      expect(decrypted, equals(largeString));
    });

    test('should handle special characters in string encryption', () async {
      const testString =
          'Hello! 👋 Special chars: @#\$%^&*()_+{}[]|\\:";\'<>?,./';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-7',
      );

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, testString);
      expect(encrypted, isNotNull);

      // Decrypt
      final decrypted = encryptionManager.decrypt(encrypted);
      expect(decrypted, equals(testString));
    });

    test('encryption should be non-deterministic with IV', () async {
      const testString = 'Same message';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-8',
      );

      // Encrypt the same message twice
      final encrypted1 = encryptionManager.encrypt(keyId, testString);
      final encrypted2 = encryptionManager.encrypt(keyId, testString);

      // The encrypted results should be different due to different IVs
      expect(encrypted1.data, isNot(equals(encrypted2.data)));
      expect(encrypted1.metadata.iv, isNot(equals(encrypted2.metadata.iv)));

      // But both should decrypt to the same message
      final decrypted1 = encryptionManager.decrypt(encrypted1);
      final decrypted2 = encryptionManager.decrypt(encrypted2);
      expect(decrypted1, equals(testString));
      expect(decrypted2, equals(testString));
    });

    test('should verify data integrity with checksum', () async {
      const testString = 'Data with checksum';

      // Generate a key
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-9',
      );

      // Encrypt
      final encrypted = encryptionManager.encrypt(keyId, testString);
      expect(encrypted.checksum, isNotNull);

      // Tamper with data
      final tamperedData = Uint8List.fromList(encrypted.data);
      tamperedData[0] = (tamperedData[0] + 1) % 256; // Modify first byte

      final tamperedEncrypted = EncryptedData(
        data: tamperedData,
        metadata: encrypted.metadata,
        checksum: encrypted.checksum,
      );

      // Decryption should fail due to checksum mismatch or GCM authentication
      expect(
        () => encryptionManager.decrypt(tamperedEncrypted),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle key expiration', () async {
      const testString = 'Expiring key test';

      // Generate a key with short expiration
      final keyId = encryptionManager.generateKey(
        EncryptionAlgorithm.aes256,
        alias: 'test-key-10',
        expiresIn: Duration(milliseconds: 100),
      );

      // Encrypt immediately
      final encrypted = encryptionManager.encrypt(keyId, testString);

      // Wait for key to expire
      await Future.delayed(Duration(milliseconds: 150));

      // Decryption should fail due to expired key
      expect(
        () => encryptionManager.decrypt(encrypted),
        throwsA(isA<Exception>()),
      );
    });
  });
}
