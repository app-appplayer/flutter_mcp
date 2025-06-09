import 'dart:convert';
import '../platform/storage/secure_storage.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// Credential manager for secure storage and retrieval of credentials
class CredentialManager {
  final SecureStorageManager _storage;
  final Logger _logger = Logger('flutter_mcp.credential_manager');

  // Prefix for all credential keys in storage
  static const String _keyPrefix = 'credential_';

  // Singleton instance
  static CredentialManager? _instance;

  /// Get singleton instance
  static CredentialManager get instance {
    if (_instance == null) {
      throw MCPException('CredentialManager has not been initialized');
    }
    return _instance!;
  }

  /// Initialize credential manager with storage
  static Future<CredentialManager> initialize(SecureStorageManager storage) async {
    if (_instance != null) {
      return _instance!;
    }

    final manager = CredentialManager._internal(storage);
    await manager._initialize();
    _instance = manager;
    return manager;
  }

  /// Internal constructor
  CredentialManager._internal(this._storage);

  /// Initialize the credential manager
  Future<void> _initialize() async {
    _logger.fine('Initializing credential manager');
    await _storage.initialize();
  }

  /// Store a credential
  Future<void> storeCredential(String key, String value, {Map<String, dynamic>? metadata}) async {
    _logger.fine('Storing credential: [REDACTED]');

    try {
      final storageKey = _getStorageKey(key);

      // Create credential object with metadata
      final credential = {
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      };

      // Serialize and store
      final json = jsonEncode(credential);
      await _storage.saveString(storageKey, json);
    } catch (e, stackTrace) {
      _logger.severe('Failed to store credential: [REDACTED]', e, stackTrace);
      throw MCPSecurityException('Failed to store credential', e, stackTrace);
    }
  }

  /// Get a credential
  Future<String?> getCredential(String key) async {
    _logger.fine('Getting credential: [REDACTED]');

    try {
      final storageKey = _getStorageKey(key);
      final json = await _storage.readString(storageKey);

      if (json == null) {
        _logger.fine('Credential not found: [REDACTED]');
        return null;
      }

      final credential = jsonDecode(json) as Map<String, dynamic>;
      return credential['value'] as String?;
    } catch (e, stackTrace) {
      _logger.severe('Failed to get credential: [REDACTED]', e, stackTrace);
      throw MCPSecurityException('Failed to get credential', e, stackTrace);
    }
  }

  /// Get credential with metadata
  Future<Map<String, dynamic>?> getCredentialWithMetadata(String key) async {
    _logger.fine('Getting credential with metadata: [REDACTED]');

    try {
      final storageKey = _getStorageKey(key);
      final json = await _storage.readString(storageKey);

      if (json == null) {
        _logger.fine('Credential not found: [REDACTED]');
        return null;
      }

      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      _logger.severe('Failed to get credential with metadata: $key', e, stackTrace);
      throw MCPSecurityException('Failed to get credential with metadata', e, stackTrace);
    }
  }

  /// Delete a credential
  Future<bool> deleteCredential(String key) async {
    _logger.fine('Deleting credential: $key');

    try {
      final storageKey = _getStorageKey(key);
      return await _storage.delete(storageKey);
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete credential: $key', e, stackTrace);
      throw MCPSecurityException('Failed to delete credential', e, stackTrace);
    }
  }

  /// Check if a credential exists
  Future<bool> hasCredential(String key) async {
    try {
      final storageKey = _getStorageKey(key);
      return await _storage.containsKey(storageKey);
    } catch (e, stackTrace) {
      _logger.severe('Failed to check if credential exists: $key', e, stackTrace);
      throw MCPSecurityException('Failed to check if credential exists', e, stackTrace);
    }
  }

  /// List all credential keys
  Future<List<String>> listCredentialKeys() async {
    try {
      // Get all keys from storage
      final allKeys = await _storage.getAllKeys();
      
      // Filter those that start with _keyPrefix and remove the prefix
      final credentialKeys = allKeys
          .where((key) => key.startsWith(_keyPrefix))
          .map((key) => key.substring(_keyPrefix.length))
          .toList();
      
      _logger.fine('Found ${credentialKeys.length} credential keys');
      return credentialKeys;
    } catch (e, stackTrace) {
      _logger.severe('Failed to list credential keys', e, stackTrace);
      throw MCPSecurityException('Failed to list credential keys', e, stackTrace);
    }
  }

  /// Clear all credentials
  Future<void> clearAllCredentials() async {
    _logger.fine('Clearing all credentials');

    try {
      final keys = await listCredentialKeys();
      for (final key in keys) {
        await deleteCredential(key);
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear all credentials', e, stackTrace);
      throw MCPSecurityException('Failed to clear all credentials', e, stackTrace);
    }
  }

  /// Get the full storage key including prefix
  String _getStorageKey(String key) {
    return '$_keyPrefix$key';
  }
}

/// Security-related exception
class MCPSecurityException extends MCPException {
  MCPSecurityException(String message, [dynamic originalError, StackTrace? stackTrace])
      : super('Security error: $message', originalError, stackTrace);
}