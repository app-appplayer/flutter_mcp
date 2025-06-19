import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;
import 'package:flutter/services.dart';
import '../utils/logger.dart';
import 'security_audit.dart';

class McpSecurityException implements Exception {
  final String message;
  McpSecurityException(this.message);

  @override
  String toString() => 'McpSecurityException: $message';
}

/// Encryption algorithm types
enum EncryptionAlgorithm {
  aes256,
  chacha20,
  rsa2048,
  rsa4096,
}

/// Key derivation function types
enum KeyDerivationFunction {
  pbkdf2,
  scrypt,
  argon2,
}

/// Encrypted data container
class EncryptedData {
  final EncryptionAlgorithm algorithm;
  final Uint8List data;
  final Uint8List iv;
  final Uint8List? salt;
  final Uint8List? tag;
  final String? checksum;
  final Map<String, dynamic> metadata;

  EncryptedData({
    required this.algorithm,
    required this.data,
    required this.iv,
    this.salt,
    this.tag,
    this.checksum,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm.name,
        'data': base64.encode(data),
        'iv': base64.encode(iv),
        if (salt != null) 'salt': base64.encode(salt!),
        if (tag != null) 'tag': base64.encode(tag!),
        if (checksum != null) 'checksum': checksum,
        'metadata': metadata,
      };

  factory EncryptedData.fromJson(Map<String, dynamic> json) {
    return EncryptedData(
      algorithm: EncryptionAlgorithm.values.firstWhere(
        (e) => e.name == json['algorithm'],
      ),
      data: base64.decode(json['data']),
      iv: base64.decode(json['iv']),
      salt: json['salt'] != null ? base64.decode(json['salt']) : null,
      tag: json['tag'] != null ? base64.decode(json['tag']) : null,
      checksum: json['checksum'],
      metadata: json['metadata'] ?? {},
    );
  }
}

/// Encryption key metadata (actual key data is stored securely)
class EncryptionKeyMetadata {
  final String keyId;
  final EncryptionAlgorithm algorithm;
  final int keyLength; // in bits
  final DateTime createdAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> metadata;

  EncryptionKeyMetadata({
    required this.keyId,
    required this.algorithm,
    required this.keyLength,
    DateTime? createdAt,
    this.expiresAt,
    Map<String, dynamic>? metadata,
  })  : createdAt = createdAt ?? DateTime.now(),
        metadata = metadata ?? {};
}

/// Secure encryption manager that uses platform secure storage
class SecureEncryptionManager {
  final _logger = Logger('SecureEncryptionManager');
  final SecurityAuditManager _auditManager = SecurityAuditManager.instance;

  // Key metadata storage - actual keys are in platform secure storage
  final Map<String, EncryptionKeyMetadata> _keyMetadata = {};
  final Map<String, String> _keyAliases = {};

  // Platform channel for secure key storage
  static const _platform = MethodChannel('flutter_mcp/secure_storage');

  // Security settings
  int _minKeyLength = 256; // bits
  bool _requireChecksums = true;

  // Singleton instance
  static SecureEncryptionManager? _instance;

  /// Get singleton instance
  static SecureEncryptionManager get instance {
    _instance ??= SecureEncryptionManager._internal();
    return _instance!;
  }

  SecureEncryptionManager._internal();

  /// Initialize encryption manager
  void initialize({
    int? minKeyLength,
    bool? requireChecksums,
  }) {
    if (minKeyLength != null) _minKeyLength = minKeyLength;
    if (requireChecksums != null) _requireChecksums = requireChecksums;

    _logger.info('Secure encryption manager initialized');
  }

  /// Generate a new encryption key
  Future<String> generateKey(
    EncryptionAlgorithm algorithm, {
    String? alias,
    Duration? expiresIn,
    Map<String, dynamic>? metadata,
  }) async {
    final keyId = _generateKeyId();
    final keyLength = _getKeyLength(algorithm);

    if (keyLength < _minKeyLength) {
      throw McpSecurityException(
          'Key length $keyLength bits is below minimum $_minKeyLength bits');
    }

    final keyData = _generateSecureBytes(keyLength ~/ 8);
    final expiresAt = expiresIn != null ? DateTime.now().add(expiresIn) : null;

    // Store key securely in platform storage
    await _storeKeySecurely(keyId, keyData);

    // Only store metadata in memory
    final keyMetadata = EncryptionKeyMetadata(
      keyId: keyId,
      algorithm: algorithm,
      keyLength: keyData.length * 8,
      expiresAt: expiresAt,
      metadata: metadata ?? {},
    );

    _keyMetadata[keyId] = keyMetadata;

    if (alias != null) {
      _keyAliases[alias] = keyId;
    }

    // Log key generation
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'key_generated',
      resource: 'encryption_key',
      success: true,
      metadata: {
        'keyId': keyId,
        'algorithm': algorithm.name,
        'keyLength': keyLength,
        'alias': alias,
        'expiresAt': expiresAt?.toIso8601String(),
      },
    ));

    _logger.info(
        'Generated encryption key: $keyId (${algorithm.name}, $keyLength bits)');
    return keyId;
  }

  /// Import an encryption key
  Future<String> importKey(
    EncryptionAlgorithm algorithm,
    Uint8List keyData, {
    String? alias,
    Duration? expiresIn,
    Map<String, dynamic>? metadata,
  }) async {
    final keyLength = keyData.length * 8;
    final algorithmMinLength = _getMinimumKeyLengthForAlgorithm(algorithm);

    if (keyLength < algorithmMinLength) {
      throw McpSecurityException(
          'Imported key length $keyLength bits is below minimum $algorithmMinLength bits for algorithm ${algorithm.name}');
    }

    final keyId = _generateKeyId();
    final expiresAt = expiresIn != null ? DateTime.now().add(expiresIn) : null;

    // Store key securely in platform storage
    await _storeKeySecurely(keyId, keyData);

    // Only store metadata in memory
    final keyMetadata = EncryptionKeyMetadata(
      keyId: keyId,
      algorithm: algorithm,
      keyLength: keyData.length * 8,
      expiresAt: expiresAt,
      metadata: metadata ?? {},
    );

    _keyMetadata[keyId] = keyMetadata;

    if (alias != null) {
      _keyAliases[alias] = keyId;
    }

    // Log key import
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'key_imported',
      resource: 'encryption_key',
      success: true,
      metadata: {
        'keyId': keyId,
        'algorithm': algorithm.name,
        'keyLength': keyLength,
        'alias': alias,
      },
    ));

    _logger.info(
        'Imported encryption key: $keyId (${algorithm.name}, $keyLength bits)');
    return keyId;
  }

  /// Encrypt data
  Future<EncryptedData> encrypt(
    String keyIdOrAlias,
    String data, {
    Map<String, dynamic>? parameters,
  }) async {
    final keyId = _resolveKeyId(keyIdOrAlias);
    final keyMetadata = _keyMetadata[keyId];

    if (keyMetadata == null) {
      throw McpSecurityException('Encryption key not found: $keyIdOrAlias');
    }

    // Retrieve key from secure storage
    final keyData = await _retrieveKeySecurely(keyId);
    if (keyData == null) {
      throw McpSecurityException(
          'Key data not found in secure storage: $keyId');
    }

    if (keyMetadata.expiresAt != null &&
        keyMetadata.expiresAt!.isBefore(DateTime.now())) {
      throw McpSecurityException('Encryption key has expired: $keyId');
    }

    final plaintext = utf8.encode(data);
    final result = _performEncryption(
        keyMetadata.algorithm, keyData, plaintext, parameters ?? {});

    // Clear sensitive data from memory
    _clearSensitiveData(keyData);

    // Log encryption operation
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.dataAccess,
      action: 'data_encrypted',
      resource: 'encrypted_data',
      success: true,
      metadata: {
        'keyId': keyId,
        'algorithm': keyMetadata.algorithm.name,
        'dataSize': plaintext.length,
      },
    ));

    return result;
  }

  /// Decrypt data
  Future<String> decrypt(
    String keyIdOrAlias,
    EncryptedData encryptedData, {
    Map<String, dynamic>? parameters,
  }) async {
    final keyId = _resolveKeyId(keyIdOrAlias);
    final keyMetadata = _keyMetadata[keyId];

    if (keyMetadata == null) {
      throw McpSecurityException('Decryption key not found: $keyIdOrAlias');
    }

    // Retrieve key from secure storage
    final keyData = await _retrieveKeySecurely(keyId);
    if (keyData == null) {
      throw McpSecurityException(
          'Key data not found in secure storage: $keyId');
    }

    if (keyMetadata.expiresAt != null &&
        keyMetadata.expiresAt!.isBefore(DateTime.now())) {
      throw McpSecurityException('Decryption key has expired: $keyId');
    }

    if (encryptedData.algorithm != keyMetadata.algorithm) {
      throw McpSecurityException(
          'Algorithm mismatch. Key: ${keyMetadata.algorithm}, Data: ${encryptedData.algorithm}');
    }

    final plaintext = _performDecryption(
        keyMetadata.algorithm, keyData, encryptedData, parameters ?? {});

    // Clear sensitive data from memory
    _clearSensitiveData(keyData);

    // Verify checksum if required
    if (_requireChecksums && encryptedData.checksum != null) {
      final calculatedChecksum = _calculateChecksum(plaintext);
      if (calculatedChecksum != encryptedData.checksum) {
        throw McpSecurityException('Checksum verification failed');
      }
    }

    // Log decryption operation
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.dataAccess,
      action: 'data_decrypted',
      resource: 'encrypted_data',
      success: true,
      metadata: {
        'keyId': keyId,
        'algorithm': keyMetadata.algorithm.name,
        'dataSize': plaintext.length,
      },
    ));

    return utf8.decode(plaintext);
  }

  /// Get key metadata (does not expose actual key data)
  EncryptionKeyMetadata? getKeyMetadata(String keyIdOrAlias) {
    final keyId = _resolveKeyId(keyIdOrAlias);
    return _keyMetadata[keyId];
  }

  /// Check if key exists
  Future<bool> hasKey(String keyIdOrAlias) async {
    final keyId = _resolveKeyId(keyIdOrAlias);
    if (!_keyMetadata.containsKey(keyId)) {
      return false;
    }
    // Verify key exists in secure storage
    return await _keyExistsInSecureStorage(keyId);
  }

  /// Delete a key
  Future<void> deleteKey(String keyIdOrAlias) async {
    final keyId = _resolveKeyId(keyIdOrAlias);

    if (!_keyMetadata.containsKey(keyId)) {
      throw McpSecurityException('Key not found: $keyIdOrAlias');
    }

    // Delete from secure storage
    await _deleteKeyFromSecureStorage(keyId);

    _keyMetadata.remove(keyId);

    // Remove alias if exists
    _keyAliases.removeWhere((alias, id) => id == keyId);

    // Log key deletion
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'key_deleted',
      resource: 'encryption_key',
      success: true,
      metadata: {
        'keyId': keyId,
      },
    ));

    _logger.info('Deleted encryption key: $keyId');
  }

  /// Rotate a key
  Future<String> rotateKey(
    String oldKeyIdOrAlias, {
    Duration? expiresIn,
  }) async {
    final oldKeyId = _resolveKeyId(oldKeyIdOrAlias);
    final oldKeyMetadata = _keyMetadata[oldKeyId];

    if (oldKeyMetadata == null) {
      throw McpSecurityException('Key not found: $oldKeyIdOrAlias');
    }

    // Generate new key with same algorithm
    final newKeyId = await generateKey(
      oldKeyMetadata.algorithm,
      expiresIn: expiresIn,
      metadata: {
        ...oldKeyMetadata.metadata,
        'rotatedFrom': oldKeyId,
        'rotatedAt': DateTime.now().toIso8601String(),
      },
    );

    // Update aliases to point to new key
    for (final entry in _keyAliases.entries) {
      if (entry.value == oldKeyId) {
        _keyAliases[entry.key] = newKeyId;
      }
    }

    // Log key rotation
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'key_rotated',
      resource: 'encryption_key',
      success: true,
      metadata: {
        'oldKeyId': oldKeyId,
        'newKeyId': newKeyId,
      },
    ));

    _logger.info('Rotated key from $oldKeyId to $newKeyId');
    return newKeyId;
  }

  /// Export all keys (for backup) - keys are encrypted before export
  Future<Map<String, dynamic>> exportKeys(String masterPassword) async {
    final export = <String, dynamic>{
      'version': '2.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'keys': <Map<String, dynamic>>[],
    };

    // Derive export key from master password
    final exportKey = await _deriveKeyFromPassword(masterPassword);

    for (final entry in _keyMetadata.entries) {
      final keyData = await _retrieveKeySecurely(entry.key);
      if (keyData != null) {
        // Encrypt key data with export key
        final encryptedKeyData = await _encryptForExport(keyData, exportKey);

        export['keys'].add({
          'keyId': entry.key,
          'algorithm': entry.value.algorithm.name,
          'encryptedKeyData': base64.encode(encryptedKeyData),
          'keyLength': entry.value.keyLength,
          'createdAt': entry.value.createdAt.toIso8601String(),
          'expiresAt': entry.value.expiresAt?.toIso8601String(),
          'metadata': entry.value.metadata,
        });

        // Clear sensitive data
        _clearSensitiveData(keyData);
      }
    }

    // Clear export key
    _clearSensitiveData(exportKey);

    // Log export operation
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.dataAccess,
      action: 'keys_exported',
      resource: 'encryption_keys',
      success: true,
      metadata: {
        'keyCount': export['keys'].length,
      },
    ));

    return export;
  }

  // Platform secure storage methods
  Future<void> _storeKeySecurely(String keyId, Uint8List keyData) async {
    try {
      await _platform.invokeMethod('storeKey', {
        'keyId': keyId,
        'keyData': base64.encode(keyData),
      });
    } catch (e) {
      throw McpSecurityException('Failed to store key securely: $e');
    }
  }

  Future<Uint8List?> _retrieveKeySecurely(String keyId) async {
    try {
      final String? encodedKey = await _platform.invokeMethod('retrieveKey', {
        'keyId': keyId,
      });
      return encodedKey != null ? base64.decode(encodedKey) : null;
    } catch (e) {
      throw McpSecurityException('Failed to retrieve key: $e');
    }
  }

  Future<bool> _keyExistsInSecureStorage(String keyId) async {
    try {
      return await _platform.invokeMethod('keyExists', {
        'keyId': keyId,
      });
    } catch (e) {
      return false;
    }
  }

  Future<void> _deleteKeyFromSecureStorage(String keyId) async {
    try {
      await _platform.invokeMethod('deleteKey', {
        'keyId': keyId,
      });
    } catch (e) {
      throw McpSecurityException('Failed to delete key: $e');
    }
  }

  // Encryption implementation methods
  EncryptedData _performEncryption(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    Uint8List plaintext,
    Map<String, dynamic> parameters,
  ) {
    switch (algorithm) {
      case EncryptionAlgorithm.aes256:
        return _encryptAES(algorithm, keyData, plaintext, parameters);
      case EncryptionAlgorithm.chacha20:
        return _encryptChaCha20(algorithm, keyData, plaintext, parameters);
      case EncryptionAlgorithm.rsa2048:
      case EncryptionAlgorithm.rsa4096:
        throw McpSecurityException('RSA encryption not yet implemented');
    }
  }

  Uint8List _performDecryption(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    EncryptedData encryptedData,
    Map<String, dynamic> parameters,
  ) {
    switch (algorithm) {
      case EncryptionAlgorithm.aes256:
        return _decryptAES(algorithm, keyData, encryptedData, parameters);
      case EncryptionAlgorithm.chacha20:
        return _decryptChaCha20(algorithm, keyData, encryptedData, parameters);
      case EncryptionAlgorithm.rsa2048:
      case EncryptionAlgorithm.rsa4096:
        throw McpSecurityException('RSA decryption not yet implemented');
    }
  }

  EncryptedData _encryptAES(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    Uint8List plaintext,
    Map<String, dynamic> parameters,
  ) {
    // Generate IV
    final iv = _generateSecureBytes(16); // 128-bit IV for AES

    // Setup cipher
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final keyParam = pc.KeyParameter(keyData);
    final params = pc.AEADParameters(keyParam, 128, iv, Uint8List(0));
    cipher.init(true, params);

    // Encrypt
    final ciphertext = cipher.process(plaintext);

    // Calculate checksum if required
    String? checksum;
    if (_requireChecksums) {
      checksum = _calculateChecksum(plaintext);
    }

    return EncryptedData(
      algorithm: algorithm,
      data: ciphertext,
      iv: iv,
      checksum: checksum,
      metadata: {
        'encryptedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Uint8List _decryptAES(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    EncryptedData encryptedData,
    Map<String, dynamic> parameters,
  ) {
    // Setup cipher
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final keyParam = pc.KeyParameter(keyData);
    final params = pc.AEADParameters(
      keyParam,
      128,
      encryptedData.iv,
      Uint8List(0),
    );
    cipher.init(false, params);

    // Decrypt
    return cipher.process(encryptedData.data);
  }

  EncryptedData _encryptChaCha20(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    Uint8List plaintext,
    Map<String, dynamic> parameters,
  ) {
    // Generate nonce
    final nonce = _generateSecureBytes(12); // 96-bit nonce for ChaCha20

    // Setup cipher
    final engine = pc.ChaCha20Engine();
    final params = pc.ParametersWithIV(pc.KeyParameter(keyData), nonce);
    engine.init(true, params);

    // Encrypt
    final ciphertext = Uint8List(plaintext.length);
    engine.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);

    // Calculate checksum if required
    String? checksum;
    if (_requireChecksums) {
      checksum = _calculateChecksum(plaintext);
    }

    return EncryptedData(
      algorithm: algorithm,
      data: ciphertext,
      iv: nonce,
      checksum: checksum,
      metadata: {
        'encryptedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Uint8List _decryptChaCha20(
    EncryptionAlgorithm algorithm,
    Uint8List keyData,
    EncryptedData encryptedData,
    Map<String, dynamic> parameters,
  ) {
    // Setup cipher
    final engine = pc.ChaCha20Engine();
    final params =
        pc.ParametersWithIV(pc.KeyParameter(keyData), encryptedData.iv);
    engine.init(false, params);

    // Decrypt
    final plaintext = Uint8List(encryptedData.data.length);
    engine.processBytes(
        encryptedData.data, 0, encryptedData.data.length, plaintext, 0);

    return plaintext;
  }

  // Helper methods
  Uint8List _generateSecureBytes(int length) {
    final random = math.Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _generateKeyId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _generateSecureBytes(8);
    final randomHex =
        random.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'key_${timestamp}_$randomHex';
  }

  String _calculateChecksum(Uint8List data) {
    return crypto.sha256.convert(data).toString();
  }

  String _resolveKeyId(String keyIdOrAlias) {
    return _keyAliases[keyIdOrAlias] ?? keyIdOrAlias;
  }

  int _getKeyLength(EncryptionAlgorithm algorithm) {
    switch (algorithm) {
      case EncryptionAlgorithm.aes256:
        return 256;
      case EncryptionAlgorithm.chacha20:
        return 256;
      case EncryptionAlgorithm.rsa2048:
        return 2048;
      case EncryptionAlgorithm.rsa4096:
        return 4096;
    }
  }

  int _getMinimumKeyLengthForAlgorithm(EncryptionAlgorithm algorithm) {
    switch (algorithm) {
      case EncryptionAlgorithm.aes256:
        return 256;
      case EncryptionAlgorithm.chacha20:
        return 256;
      case EncryptionAlgorithm.rsa2048:
        return 2048;
      case EncryptionAlgorithm.rsa4096:
        return 4096;
    }
  }

  Future<Uint8List> _deriveKeyFromPassword(String password) async {
    final salt = _generateSecureBytes(32);
    final utf8Password = utf8.encode(password);

    // Use PBKDF2 with SHA-256
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    pbkdf2.init(pc.Pbkdf2Parameters(
        salt, 100000, 32)); // 100k iterations, 32 bytes output

    final key = Uint8List(32);
    pbkdf2.deriveKey(utf8Password, 0, key, 0);

    return key;
  }

  Future<Uint8List> _encryptForExport(
      Uint8List data, Uint8List exportKey) async {
    final iv = _generateSecureBytes(16);
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final keyParam = pc.KeyParameter(exportKey);
    final params = pc.AEADParameters(keyParam, 128, iv, Uint8List(0));
    cipher.init(true, params);

    final encrypted = cipher.process(data);

    // Prepend IV to encrypted data
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);

    return result;
  }

  void _clearSensitiveData(Uint8List data) {
    // Overwrite the data with zeros
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }
}
