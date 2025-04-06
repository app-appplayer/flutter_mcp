import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:crypto/crypto.dart';
import 'dart:math' as math;

import '../../storage/secure_storage.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';

/// Web storage implementation
class WebStorageManager implements SecureStorageManager {
  final bool _useLocalStorage;
  final String _prefix;
  final MCPLogger _logger = MCPLogger('mcp.web_storage');

  // Encryption key for storage security
  late String _encryptionKey;

  // Salt for encryption
  late Uint8List _encryptionSalt;

  // IV for encryption (initialization vector)
  late Uint8List _encryptionIV;

  // Migration flag for legacy data
  bool _needsMigration = false;

  // Storage version
  final int _storageVersion = 2;

  /// Create a new web storage manager
  ///
  /// [useLocalStorage] determines whether to use localStorage (true) or sessionStorage (false)
  /// [prefix] is used to prefix all keys in the storage
  WebStorageManager({
    bool useLocalStorage = true,
    String prefix = 'mcp_',
  })  : _useLocalStorage = useLocalStorage,
        _prefix = prefix;

  @override
  Future<void> initialize() async {
    _logger.debug('Initializing web storage');

    // Check if we need to migrate from older storage format
    _needsMigration = _checkIfMigrationNeeded();

    // Generate encryption materials or load existing ones
    await _initializeEncryption();

    // Migrate legacy data if needed
    if (_needsMigration) {
      await _migrateFromLegacyStorage();
    }

    _logger.debug('Web storage initialized successfully');
  }

  @override
  Future<void> saveString(String key, String value) async {
    _logger.debug('Saving string to web storage: $key');

    try {
      // Encrypt value
      final encryptedValue = _encrypt(value);

      // Create metadata
      final metadata = {
        'v': _storageVersion, // Storage version
        'ts': DateTime.now().millisecondsSinceEpoch, // Timestamp
        't': 'string', // Type
      };

      // Combine metadata and encrypted value
      final entry = {
        'meta': metadata,
        'data': encryptedValue,
      };

      // Store as JSON
      _getStorage().setItem('$_prefix$key', jsonEncode(entry));
    } catch (e, stackTrace) {
      _logger.error('Failed to save string to web storage', e, stackTrace);
      throw MCPException(
          'Failed to save string to web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<String?> readString(String key) async {
    _logger.debug('Reading string from web storage: $key');

    try {
      final value = _getStorage().getItem('$_prefix$key');
      if (value == null) {
        return null;
      }

      // Check if the value is in the new format (JSON)
      if (value.startsWith('{') && value.endsWith('}')) {
        try {
          final entry = jsonDecode(value) as Map<String, dynamic>;
          final version = entry['meta']?['v'] as int? ?? 1;

          // Check if the type is string
          if (entry['meta']?['t'] != 'string' && version >= 2) {
            _logger.warning('Value is not a string: $key');
            return null;
          }

          // Decrypt value
          return _decrypt(entry['data'] as String);
        } catch (e) {
          _logger.error('Failed to parse JSON value for key: $key', e);
          return null;
        }
      } else {
        // Legacy format (backward compatibility)
        return _decryptLegacy(value);
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to read string from web storage', e, stackTrace);
      throw MCPException(
          'Failed to read string from web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<bool> delete(String key) async {
    _logger.debug('Deleting key from web storage: $key');

    try {
      _getStorage().removeItem('$_prefix$key');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to delete key from web storage', e, stackTrace);
      throw MCPException(
          'Failed to delete key from web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    try {
      return _getStorage().getItem('$_prefix$key') != null;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to check if key exists in web storage', e, stackTrace);
      throw MCPException(
          'Failed to check if key exists in web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  /// Get all keys in storage with the prefix
  Future<List<String>> getKeys() async {
    try {
      final allKeys = <String>[];
      final storage = _getStorage();

      for (int i = 0; i < storage.length; i++) {
        final key = storage.key(i).toString();
        if (key.startsWith(_prefix)) {
          allKeys.add(key.substring(_prefix.length));
        }
      }

      return allKeys;
    } catch (e, stackTrace) {
      _logger.error('Failed to get keys from web storage', e, stackTrace);
      throw MCPException('Failed to get keys from web storage: ${e.toString()}',
          e, stackTrace);
    }
  }

  /// Clear all data for this prefix
  Future<void> clear() async {
    _logger.debug('Clearing all web storage with prefix: $_prefix');

    try {
      final storage = _getStorage();
      final keysToRemove = <String>[];

      // Collect keys first to avoid modification during iteration
      for (int i = 0; i < storage.length; i++) {
        final key = storage.key(i).toString();
        if (key.startsWith(_prefix)) {
          keysToRemove.add(key);
        }
      }

      // Remove collected keys
      for (final key in keysToRemove) {
        storage.removeItem(key);
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to clear web storage', e, stackTrace);
      throw MCPException(
          'Failed to clear web storage: ${e.toString()}', e, stackTrace);
    }
  }

  /// Initialize encryption materials
  Future<void> _initializeEncryption() async {
    final storage = _getStorage();

    // Check if we already have encryption materials
    final encryptionKeyKey = '${_prefix}__encryption_key';
    final encryptionSaltKey = '${_prefix}__encryption_salt';
    final encryptionIvKey = '${_prefix}__encryption_iv';

    if (storage.getItem(encryptionKeyKey) != null) {
      _encryptionKey = storage.getItem(encryptionKeyKey)!;
      _encryptionSalt = base64Decode(storage.getItem(encryptionSaltKey)!);
      _encryptionIV = base64Decode(storage.getItem(encryptionIvKey)!);
    } else {
      // Generate new encryption materials
      _encryptionKey = _generateRandomString(32);
      _encryptionSalt = _getRandomBytes(16);
      _encryptionIV = _getRandomBytes(16);

      // Store encryption materials
      storage.setItem(encryptionKeyKey, _encryptionKey);
      storage.setItem(encryptionSaltKey, base64Encode(_encryptionSalt));
      storage.setItem(encryptionIvKey, base64Encode(_encryptionIV));

      // Store the version
      storage.setItem('${_prefix}__storage_version', _storageVersion.toString());
    }
  }

  /// Check if we need to migrate from legacy storage format
  bool _checkIfMigrationNeeded() {
    final storage = _getStorage();

    if (storage.getItem('${_prefix}__storage_version') != null) {
      final version =
          int.tryParse(storage.getItem('${_prefix}__storage_version')!) ?? 1;
      return version < _storageVersion;
    }

    for (int i = 0; i < storage.length; i++) {
      final key = storage.key(i).toString();
      if (key.startsWith(_prefix) &&
          key != '${_prefix}__encryption_key' &&
          key != '${_prefix}__encryption_salt' &&
          key != '${_prefix}__encryption_iv' &&
          key != '${_prefix}__storage_version') {
        final value = storage.getItem(key);
        if (value != null && (!value.startsWith('{') || !value.endsWith('}'))) {
          return true;
        }
      }
    }

    return false;
  }

  /// Migrate data from legacy storage format
  Future<void> _migrateFromLegacyStorage() async {
    _logger.debug('Migrating from legacy storage format');

    final storage = _getStorage();
    final legacyKeys = <String>[];

    for (int i = 0; i < storage.length; i++) {
      final key = storage.key(i).toString();
      if (key.startsWith(_prefix) &&
          key != '${_prefix}__encryption_key' &&
          key != '${_prefix}__encryption_salt' &&
          key != '${_prefix}__encryption_iv' &&
          key != '${_prefix}__storage_version') {
        final value = storage.getItem(key);
        if (value != null && (!value.startsWith('{') || !value.endsWith('}'))) {
          legacyKeys.add(key);
        }
      }
    }

    for (final key in legacyKeys) {
      try {
        final value = storage.getItem(key);
        if (value != null) {
          final decrypted = _decryptLegacy(value);
          if (decrypted != null) {
            await saveString(key.substring(_prefix.length), decrypted);
          }
        }
      } catch (e) {
        _logger.error('Failed to migrate legacy key: $key', e);
      }
    }

    storage.setItem('${_prefix}__storage_version', _storageVersion.toString());
  }

  /// Get the appropriate storage based on settings
  web.Storage _getStorage() {
    return _useLocalStorage
        ? web.window.localStorage
        : web.window.sessionStorage;
  }

  /// Generate a random string of specified length
  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = math.Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Get random bytes
  Uint8List _getRandomBytes(int length) {
    final random = math.Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }

  /// Encrypt a string (improved security)
  String _encrypt(String value) {
    // Create key from the encryption key and salt
    final keyBytes = utf8.encode(_encryptionKey);
    final keyHash = sha256.convert([...keyBytes, ..._encryptionSalt]);

    // Convert value to bytes
    final valueBytes = utf8.encode(value);

    // XOR the value with the key (repeated as needed)
    final encrypted = Uint8List(valueBytes.length);
    final keyDigest = keyHash.bytes;

    for (int i = 0; i < valueBytes.length; i++) {
      encrypted[i] = valueBytes[i] ^
      keyDigest[i % keyDigest.length] ^
      _encryptionIV[i % _encryptionIV.length];
    }

    // Return Base64 encoded result
    return base64Encode(encrypted);
  }

  /// Decrypt an encrypted string
  String? _decrypt(String encryptedValue) {
    try {
      // Create key from the encryption key and salt
      final keyBytes = utf8.encode(_encryptionKey);
      final keyHash = sha256.convert([...keyBytes, ..._encryptionSalt]);

      // Decode Base64 value
      final encrypted = base64Decode(encryptedValue);

      // XOR the value with the key (reversed operation)
      final decrypted = Uint8List(encrypted.length);
      final keyDigest = keyHash.bytes;

      for (int i = 0; i < encrypted.length; i++) {
        decrypted[i] = encrypted[i] ^
        keyDigest[i % keyDigest.length] ^
        _encryptionIV[i % _encryptionIV.length];
      }

      // Convert bytes back to string
      return utf8.decode(decrypted);
    } catch (e) {
      _logger.error('Failed to decrypt value', e);
      return null;
    }
  }

  /// Decrypt a legacy encrypted string
  String? _decryptLegacy(String encryptedValue) {
    try {
      // Legacy format was simple Base64 encoding
      final decoded = base64Decode(encryptedValue);
      return utf8.decode(decoded);
    } catch (e) {
      _logger.error('Failed to decrypt legacy value', e);
      return null;
    }
  }
}