import 'package:universal_html/html.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'secure_storage.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';

/// Web storage implementation
class WebStorageManager implements SecureStorageManager {
  final bool _useLocalStorage;
  final String _prefix;
  final Logger _logger = Logger('flutter_mcp.web_storage');

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
    _logger.fine('Initializing web storage');

    // Check if we need to migrate from older storage format
    _needsMigration = _checkIfMigrationNeeded();

    // Generate encryption materials or load existing ones
    await _initializeEncryption();

    // Migrate legacy data if needed
    if (_needsMigration) {
      await _migrateFromLegacyStorage();
    }

    _logger.fine('Web storage initialized successfully');
  }

  @override
  Future<void> saveString(String key, String value) async {
    _logger.fine('Saving string to web storage: $key');

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
      final storage = _getStorage();
      storage[_prefix + key] = jsonEncode(entry);
    } catch (e, stackTrace) {
      _logger.severe('Failed to save string to web storage', e, stackTrace);
      throw MCPException(
          'Failed to save string to web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<String?> readString(String key) async {
    _logger.fine('Reading string from web storage: $key');

    try {
      final storage = _getStorage();
      final value = storage[_prefix + key];
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
          _logger.severe('Failed to parse JSON value for key: $key', e);
          return null;
        }
      } else {
        // Legacy format (backward compatibility)
        return _decryptLegacy(value);
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to read string from web storage', e, stackTrace);
      throw MCPException(
          'Failed to read string from web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<bool> delete(String key) async {
    _logger.fine('Deleting key from web storage: $key');

    try {
      final storage = _getStorage();
      storage.remove(_prefix + key);
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete key from web storage', e, stackTrace);
      throw MCPException(
          'Failed to delete key from web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    try {
      final storage = _getStorage();
      return storage.containsKey(_prefix + key);
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to check if key exists in web storage: $e\nStack trace: $stackTrace');
      throw MCPException(
          'Failed to check if key exists in web storage: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    _logger.fine('Saving map to web storage: $key');

    try {
      // Convert map to JSON string
      final jsonString = jsonEncode(value);

      // Save as string with type metadata
      final metadata = {
        'v': _storageVersion,
        'ts': DateTime.now().millisecondsSinceEpoch,
        't': 'map', // Type is map
      };

      // Encrypt the JSON string
      final encryptedValue = _encrypt(jsonString);

      // Create the entry
      final entry = {
        'meta': metadata,
        'data': encryptedValue,
      };

      // Store as JSON
      final storage = _getStorage();
      storage[_prefix + key] = jsonEncode(entry);
    } catch (e, stackTrace) {
      _logger.severe('Failed to save map to web storage', e, stackTrace);
      throw MCPException(
          'Failed to save map to web storage: ${e.toString()}',
          e,
          stackTrace
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    _logger.fine('Reading map from web storage: $key');

    try {
      final storage = _getStorage();
      final value = storage[_prefix + key];
      if (value == null) {
        return null;
      }

      // Parse the JSON entry
      if (value.startsWith('{') && value.endsWith('}')) {
        try {
          final entry = jsonDecode(value) as Map<String, dynamic>;
          final version = entry['meta']?['v'] as int? ?? 1;
          final type = entry['meta']?['t'];

          // Check if it's a map type or an old format
          if (type != 'map' && version >= 2 && type != null) {
            _logger.warning('Value is not a map: $key');
            return null;
          }

          // Decrypt the data
          final decrypted = _decrypt(entry['data'] as String);
          if (decrypted == null) {
            return null;
          }

          // Parse the JSON map
          return jsonDecode(decrypted) as Map<String, dynamic>;
        } catch (e) {
          _logger.severe('Failed to parse map value for key: $key', e);
          return null;
        }
      } else {
        // Legacy format - try to parse as JSON directly
        try {
          final legacy = _decryptLegacy(value);
          if (legacy == null) {
            return null;
          }
          return jsonDecode(legacy) as Map<String, dynamic>;
        } catch (e) {
          _logger.severe('Failed to parse legacy map for key: $key', e);
          return null;
        }
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to read map from web storage', e, stackTrace);
      throw MCPException(
          'Failed to read map from web storage: ${e.toString()}',
          e,
          stackTrace
      );
    }
  }

  @override
  Future<void> clear() async {
    _logger.fine('Clearing all web storage with prefix: $_prefix');

    try {
      final storage = _getStorage();
      final keysToRemove = <String>[];

      // Collect keys first to avoid modification during iteration
      // Need to iterate through all keys
      for (var key in storage.keys) {
        if (key.startsWith(_prefix)) {
          keysToRemove.add(key);
        }
      }

      // Remove collected keys
      for (final key in keysToRemove) {
        storage.remove(key);
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear web storage', e, stackTrace);
      throw MCPException(
          'Failed to clear web storage: ${e.toString()}', e, stackTrace);
    }
  }

  /// Get all keys in storage with the prefix
  Future<List<String>> getKeys() async {
    try {
      final allKeys = <String>[];
      final storage = _getStorage();

      // Iterate through all keys
      for (var key in storage.keys) {
        if (key.startsWith(_prefix)) {
          allKeys.add(key.substring(_prefix.length));
        }
      }

      return allKeys;
    } catch (e, stackTrace) {
      _logger.severe('Failed to get keys from web storage', e, stackTrace);
      throw MCPException('Failed to get keys from web storage: ${e.toString()}',
          e, stackTrace);
    }
  }

  /// Initialize encryption materials
  Future<void> _initializeEncryption() async {
    final storage = _getStorage();

    // Check if we already have encryption materials
    final encryptionKey = storage['${_prefix}__encryption_key'];
    if (encryptionKey != null) {
      _encryptionKey = encryptionKey;
      _encryptionSalt = base64Decode(storage['${_prefix}__encryption_salt']!);
      _encryptionIV = base64Decode(storage['${_prefix}__encryption_iv']!);
    } else {
      // Generate new encryption materials
      _encryptionKey = _generateRandomString(32);
      _encryptionSalt = _getRandomBytes(16);
      _encryptionIV = _getRandomBytes(16);

      // Store encryption materials
      storage['${_prefix}__encryption_key'] = _encryptionKey;
      storage['${_prefix}__encryption_salt'] = base64Encode(_encryptionSalt);
      storage['${_prefix}__encryption_iv'] = base64Encode(_encryptionIV);

      // Store the version
      storage['${_prefix}__storage_version'] = _storageVersion.toString();
    }
  }

  /// Check if we need to migrate from legacy storage format
  bool _checkIfMigrationNeeded() {
    final storage = _getStorage();
    final versionString = storage['${_prefix}__storage_version'];

    if (versionString != null) {
      final version = int.tryParse(versionString) ?? 1;
      return version < _storageVersion;
    }

    // Check for legacy keys - iterate through all keys
    bool hasLegacyKeys = false;
    for (var key in storage.keys) {
      if (key.startsWith(_prefix) &&
          key != '${_prefix}__encryption_key' &&
          key != '${_prefix}__encryption_salt' &&
          key != '${_prefix}__encryption_iv' &&
          key != '${_prefix}__storage_version') {

        final value = storage[key];
        if (value != null && (!value.startsWith('{') || !value.endsWith('}'))) {
          hasLegacyKeys = true;
        }
      }
    }

    return hasLegacyKeys;
  }

  /// Migrate data from legacy storage format
  Future<void> _migrateFromLegacyStorage() async {
    _logger.fine('Migrating from legacy storage format');

    final storage = _getStorage();
    final legacyKeys = <String>[];

    // Collect legacy keys
    for (var key in storage.keys) {
      if (key.startsWith(_prefix) &&
          key != '${_prefix}__encryption_key' &&
          key != '${_prefix}__encryption_salt' &&
          key != '${_prefix}__encryption_iv' &&
          key != '${_prefix}__storage_version') {

        final value = storage[key];
        if (value != null && (!value.startsWith('{') || !value.endsWith('}'))) {
          legacyKeys.add(key);
        }
      }
    }

    // Migrate each legacy key
    for (final key in legacyKeys) {
      try {
        final value = storage[key];
        if (value != null) {
          final decrypted = _decryptLegacy(value);
          if (decrypted != null) {
            await saveString(key.substring(_prefix.length), decrypted);
          }
        }
      } catch (e) {
        _logger.severe('Failed to migrate legacy key: $key', e);
      }
    }

    storage['${_prefix}__storage_version'] = _storageVersion.toString();
  }

  /// Get the appropriate storage based on settings
  Storage _getStorage() {
    return _useLocalStorage
        ? window.localStorage
        : window.sessionStorage;
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
    // In a production environment, use a proper encryption library
    // This is a relatively simple implementation for demonstration

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
      _logger.severe('Failed to decrypt value', e);
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
      _logger.severe('Failed to decrypt legacy value', e);
      return null;
    }
  }

  @override
  Future<Set<String>> getAllKeys() async {
    try {
      final keys = await getKeys();
      return keys.toSet();
    } catch (e, stackTrace) {
      _logger.severe('Failed to get all keys from web storage', e, stackTrace);
      throw MCPException('Failed to get all keys from web storage: ${e.toString()}', e, stackTrace);
    }
  }
}