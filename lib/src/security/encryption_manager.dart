import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import 'security_audit.dart';

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

/// Encryption metadata
class EncryptionMetadata {
  final EncryptionAlgorithm algorithm;
  final KeyDerivationFunction? kdf;
  final String keyId;
  final Uint8List salt;
  final Uint8List iv;
  final int iterations;
  final DateTime createdAt;
  final Map<String, dynamic> parameters;

  EncryptionMetadata({
    required this.algorithm,
    this.kdf,
    required this.keyId,
    required this.salt,
    required this.iv,
    this.iterations = 100000,
    DateTime? createdAt,
    Map<String, dynamic>? parameters,
  }) : createdAt = createdAt ?? DateTime.now(),
       parameters = parameters ?? {};

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm.name,
    'kdf': kdf?.name,
    'keyId': keyId,
    'salt': base64.encode(salt),
    'iv': base64.encode(iv),
    'iterations': iterations,
    'createdAt': createdAt.toIso8601String(),
    'parameters': parameters,
  };

  factory EncryptionMetadata.fromJson(Map<String, dynamic> json) => EncryptionMetadata(
    algorithm: EncryptionAlgorithm.values.byName(json['algorithm'] as String),
    kdf: json['kdf'] != null ? KeyDerivationFunction.values.byName(json['kdf'] as String) : null,
    keyId: json['keyId'] as String,
    salt: base64.decode(json['salt'] as String),
    iv: base64.decode(json['iv'] as String),
    iterations: json['iterations'] as int? ?? 100000,
    createdAt: DateTime.parse(json['createdAt'] as String),
    parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
  );
}

/// Encrypted data container
class EncryptedData {
  final Uint8List data;
  final EncryptionMetadata metadata;
  final String? checksum;

  EncryptedData({
    required this.data,
    required this.metadata,
    this.checksum,
  });

  Map<String, dynamic> toJson() => {
    'data': base64.encode(data),
    'metadata': metadata.toJson(),
    'checksum': checksum,
  };

  factory EncryptedData.fromJson(Map<String, dynamic> json) => EncryptedData(
    data: base64.decode(json['data'] as String),
    metadata: EncryptionMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
    checksum: json['checksum'] as String?,
  );
}

/// Encryption key information
class EncryptionKey {
  final String keyId;
  final EncryptionAlgorithm algorithm;
  final Uint8List keyData;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> metadata;

  EncryptionKey({
    required this.keyId,
    required this.algorithm,
    required this.keyData,
    DateTime? createdAt,
    this.expiresAt,
    Map<String, dynamic>? metadata,
  }) : createdAt = createdAt ?? DateTime.now(),
       metadata = metadata ?? {};

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJsonSafe() => {
    'keyId': keyId,
    'algorithm': algorithm.name,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'metadata': metadata,
    'keyLength': keyData.length,
  };
}

/// Encryption manager for secure data handling
class EncryptionManager {
  final Logger _logger = Logger('flutter_mcp.encryption_manager');
  final SecurityAuditManager _auditManager = SecurityAuditManager.instance;

  // Key storage
  final Map<String, EncryptionKey> _keys = {};
  final Map<String, String> _keyAliases = {};

  // Security settings
  int _minKeyLength = 256; // bits
  Duration _keyRotationInterval = Duration(days: 90);
  bool _requireChecksums = true;

  // Singleton instance
  static EncryptionManager? _instance;

  /// Get singleton instance
  static EncryptionManager get instance {
    _instance ??= EncryptionManager._internal();
    return _instance!;
  }

  EncryptionManager._internal();

  /// Initialize encryption manager
  void initialize({
    int? minKeyLength,
    Duration? keyRotationInterval,
    bool? requireChecksums,
  }) {
    if (minKeyLength != null) _minKeyLength = minKeyLength;
    if (keyRotationInterval != null) _keyRotationInterval = keyRotationInterval;
    if (requireChecksums != null) _requireChecksums = requireChecksums;

    _logger.info('Encryption manager initialized');
  }

  /// Generate a new encryption key
  String generateKey(
    EncryptionAlgorithm algorithm, {
    String? alias,
    Duration? expiresIn,
    Map<String, dynamic>? metadata,
  }) {
    final keyId = _generateKeyId();
    final keyLength = _getKeyLength(algorithm);

    if (keyLength < _minKeyLength) {
      throw MCPSecurityException('Key length ${keyLength} bits is below minimum ${_minKeyLength} bits');
    }

    final keyData = _generateSecureBytes(keyLength ~/ 8);
    final expiresAt = expiresIn != null ? DateTime.now().add(expiresIn) : null;

    final key = EncryptionKey(
      keyId: keyId,
      algorithm: algorithm,
      keyData: keyData,
      expiresAt: expiresAt,
      metadata: metadata ?? {},
    );

    _keys[keyId] = key;

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

    _logger.info('Generated encryption key: $keyId (${algorithm.name}, ${keyLength} bits)');
    return keyId;
  }

  /// Import an encryption key
  String importKey(
    EncryptionAlgorithm algorithm,
    Uint8List keyData, {
    String? alias,
    Duration? expiresIn,
    Map<String, dynamic>? metadata,
  }) {
    final keyLength = keyData.length * 8;
    final algorithmMinLength = _getMinimumKeyLengthForAlgorithm(algorithm);

    if (keyLength < algorithmMinLength) {
      throw MCPSecurityException('Imported key length ${keyLength} bits is below minimum ${algorithmMinLength} bits for algorithm ${algorithm.name}');
    }

    final keyId = _generateKeyId();
    final expiresAt = expiresIn != null ? DateTime.now().add(expiresIn) : null;

    final key = EncryptionKey(
      keyId: keyId,
      algorithm: algorithm,
      keyData: keyData,
      expiresAt: expiresAt,
      metadata: metadata ?? {},
    );

    _keys[keyId] = key;

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

    _logger.info('Imported encryption key: $keyId (${algorithm.name}, ${keyLength} bits)');
    return keyId;
  }

  /// Encrypt data
  EncryptedData encrypt(
    String keyIdOrAlias,
    String data, {
    Map<String, dynamic>? parameters,
  }) {
    final keyId = _resolveKeyId(keyIdOrAlias);
    final key = _keys[keyId];

    if (key == null) {
      throw MCPSecurityException('Encryption key not found: $keyIdOrAlias');
    }

    if (key.isExpired) {
      throw MCPSecurityException('Encryption key has expired: $keyIdOrAlias');
    }

    try {
      final plaintext = utf8.encode(data);
      final salt = _generateSecureBytes(32);
      final iv = _generateSecureBytes(16);

      // For this demo, we'll use a simple XOR encryption
      // In production, use proper encryption libraries
      final encrypted = _simpleEncrypt(plaintext, key.keyData, iv);

      final metadata = EncryptionMetadata(
        algorithm: key.algorithm,
        keyId: keyId,
        salt: salt,
        iv: iv,
        parameters: parameters ?? {},
      );

      String? checksum;
      if (_requireChecksums) {
        checksum = _calculateChecksum(encrypted);
      }

      // Log encryption operation
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.dataAccess,
        action: 'data_encrypted',
        resource: 'sensitive_data',
        success: true,
        metadata: {
          'keyId': keyId,
          'algorithm': key.algorithm.name,
          'dataSize': plaintext.length,
          'hasChecksum': checksum != null,
        },
      ));

      return EncryptedData(
        data: encrypted,
        metadata: metadata,
        checksum: checksum,
      );
    } catch (e, stackTrace) {
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.dataAccess,
        action: 'data_encryption_failed',
        resource: 'sensitive_data',
        success: false,
        reason: e.toString(),
        riskScore: 25,
      ));

      _logger.severe('Encryption failed for key: $keyIdOrAlias', e, stackTrace);
      throw MCPSecurityException('Encryption failed', e, stackTrace);
    }
  }

  /// Decrypt data
  String decrypt(EncryptedData encryptedData) {
    final keyId = encryptedData.metadata.keyId;
    final key = _keys[keyId];

    if (key == null) {
      throw MCPSecurityException('Decryption key not found: $keyId');
    }

    if (key.isExpired) {
      throw MCPSecurityException('Decryption key has expired: $keyId');
    }

    try {
      // Verify checksum if present
      if (encryptedData.checksum != null && _requireChecksums) {
        final computedChecksum = _calculateChecksum(encryptedData.data);
        if (computedChecksum != encryptedData.checksum) {
          throw MCPSecurityException('Data integrity check failed - checksum mismatch');
        }
      }

      // For this demo, we'll use simple XOR decryption
      final decrypted = _simpleDecrypt(encryptedData.data, key.keyData, encryptedData.metadata.iv);
      final plaintext = utf8.decode(decrypted);

      // Log decryption operation
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.dataAccess,
        action: 'data_decrypted',
        resource: 'sensitive_data',
        success: true,
        metadata: {
          'keyId': keyId,
          'algorithm': key.algorithm.name,
          'dataSize': decrypted.length,
        },
      ));

      return plaintext;
    } catch (e, stackTrace) {
      _auditManager.logSecurityEvent(SecurityAuditEvent(
        eventId: _auditManager.generateEventId(),
        type: SecurityEventType.dataAccess,
        action: 'data_decryption_failed',
        resource: 'sensitive_data',
        success: false,
        reason: e.toString(),
        riskScore: 50,
      ));

      _logger.severe('Decryption failed for key: $keyId', e, stackTrace);
      throw MCPSecurityException('Decryption failed', e, stackTrace);
    }
  }

  /// Rotate encryption key
  String rotateKey(String keyIdOrAlias, {Map<String, dynamic>? metadata}) {
    final oldKeyId = _resolveKeyId(keyIdOrAlias);
    final oldKey = _keys[oldKeyId];

    if (oldKey == null) {
      throw MCPSecurityException('Key not found for rotation: $keyIdOrAlias');
    }

    // Generate new key with same algorithm
    final newKeyId = generateKey(
      oldKey.algorithm,
      metadata: metadata,
    );

    // Update aliases to point to new key
    for (final entry in _keyAliases.entries) {
      if (entry.value == oldKeyId) {
        _keyAliases[entry.key] = newKeyId;
      }
    }

    // Mark old key as expired
    final expiredKey = EncryptionKey(
      keyId: oldKey.keyId,
      algorithm: oldKey.algorithm,
      keyData: oldKey.keyData,
      createdAt: oldKey.createdAt,
      expiresAt: DateTime.now(),
      metadata: oldKey.metadata,
    );
    _keys[oldKeyId] = expiredKey;

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
        'algorithm': oldKey.algorithm.name,
      },
    ));

    _logger.info('Rotated encryption key: $oldKeyId -> $newKeyId');
    return newKeyId;
  }

  /// Delete encryption key
  bool deleteKey(String keyIdOrAlias, {bool force = false}) {
    final keyId = _resolveKeyId(keyIdOrAlias);
    final key = _keys[keyId];

    if (key == null) {
      return false;
    }

    if (!force && !key.isExpired) {
      throw MCPSecurityException('Cannot delete active key without force flag: $keyIdOrAlias');
    }

    _keys.remove(keyId);

    // Remove from aliases
    _keyAliases.removeWhere((_, value) => value == keyId);

    // Log key deletion
    _auditManager.logSecurityEvent(SecurityAuditEvent(
      eventId: _auditManager.generateEventId(),
      type: SecurityEventType.configurationChange,
      action: 'key_deleted',
      resource: 'encryption_key',
      success: true,
      metadata: {
        'keyId': keyId,
        'algorithm': key.algorithm.name,
        'forced': force,
      },
    ));

    _logger.info('Deleted encryption key: $keyId');
    return true;
  }

  /// Get key information (safe - no key material)
  Map<String, dynamic>? getKeyInfo(String keyIdOrAlias) {
    final keyId = _resolveKeyId(keyIdOrAlias);
    final key = _keys[keyId];

    return key?.toJsonSafe();
  }

  /// List all keys (safe - no key material)
  List<Map<String, dynamic>> listKeys() {
    return _keys.values.map((key) => key.toJsonSafe()).toList();
  }

  /// Check for expired keys
  List<String> getExpiredKeys() {
    return _keys.entries
        .where((entry) => entry.value.isExpired)
        .map((entry) => entry.key)
        .toList();
  }

  /// Clean up expired keys
  int cleanupExpiredKeys() {
    final expiredKeys = getExpiredKeys();
    int deletedCount = 0;

    for (final keyId in expiredKeys) {
      if (deleteKey(keyId, force: true)) {
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      _logger.info('Cleaned up $deletedCount expired keys');
    }

    return deletedCount;
  }

  /// Generate security report
  Map<String, dynamic> generateSecurityReport() {
    final now = DateTime.now();
    final activeKeys = _keys.values.where((key) => !key.isExpired).length;
    final expiredKeys = _keys.values.where((key) => key.isExpired).length;
    final keysByAlgorithm = <String, int>{};

    for (final key in _keys.values) {
      keysByAlgorithm[key.algorithm.name] = (keysByAlgorithm[key.algorithm.name] ?? 0) + 1;
    }

    final oldestKey = _keys.values.isEmpty ? null :
        _keys.values.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);

    return {
      'generatedAt': now.toIso8601String(),
      'totalKeys': _keys.length,
      'activeKeys': activeKeys,
      'expiredKeys': expiredKeys,
      'aliases': _keyAliases.length,
      'keysByAlgorithm': keysByAlgorithm,
      'oldestKeyAge': oldestKey != null ? now.difference(oldestKey.createdAt).inDays : null,
      'settings': {
        'minKeyLength': _minKeyLength,
        'keyRotationInterval': _keyRotationInterval.inDays,
        'requireChecksums': _requireChecksums,
      },
    };
  }

  /// Simple XOR encryption (demo only - use proper encryption in production)
  Uint8List _simpleEncrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }
    return result;
  }

  /// Simple XOR decryption (demo only - use proper encryption in production)
  Uint8List _simpleDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
    return _simpleEncrypt(data, key, iv); // XOR is symmetric
  }

  /// Calculate checksum for data integrity
  String _calculateChecksum(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  /// Resolve key ID from alias or direct ID
  String _resolveKeyId(String keyIdOrAlias) {
    return _keyAliases[keyIdOrAlias] ?? keyIdOrAlias;
  }

  /// Get key length in bits for algorithm
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

  /// Generate secure random bytes
  Uint8List _generateSecureBytes(int length) {
    final random = math.Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Generate unique key ID
  String _generateKeyId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random.secure().nextInt(1000000);
    return 'key_${timestamp}_$random';
  }
  
  /// Get minimum key length for a specific algorithm
  int _getMinimumKeyLengthForAlgorithm(EncryptionAlgorithm algorithm) {
    switch (algorithm) {
      case EncryptionAlgorithm.aes256:
        return 256; // AES256 requires 256 bits (32 bytes)
      case EncryptionAlgorithm.chacha20:
        return 256; // ChaCha20 requires 256 bits (32 bytes)
      case EncryptionAlgorithm.rsa2048:
        return 2048; // RSA2048 requires 2048 bits (256 bytes)
      case EncryptionAlgorithm.rsa4096:
        return 4096; // RSA4096 requires 4096 bits (512 bytes)
    }
  }

  /// Dispose resources
  void dispose() {
    // Clear keys from memory
    for (final key in _keys.values) {
      key.keyData.fillRange(0, key.keyData.length, 0);
    }
    _keys.clear();
    _keyAliases.clear();
  }
}