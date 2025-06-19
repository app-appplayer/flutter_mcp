import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import '../../utils/error_recovery.dart';

/// Secure storage manager interface
abstract class SecureStorageManager {
  /// Initialize storage
  Future<void> initialize();

  /// Store string securely
  Future<void> saveString(String key, String value);

  /// Read string
  Future<String?> readString(String key);

  /// Delete key
  Future<bool> delete(String key);

  /// Check if key exists
  Future<bool> containsKey(String key);

  /// Store map data securely
  Future<void> saveMap(String key, Map<String, dynamic> value);

  /// Read map data
  Future<Map<String, dynamic>?> readMap(String key);

  /// Clear all storage
  Future<void> clear();

  /// Get all keys
  Future<Set<String>> getAllKeys();
}

/// Secure storage implementation for native platforms
class SecureStorageManagerImpl implements SecureStorageManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  final Logger _logger = Logger('flutter_mcp.secure_storage');

  /// Whether storage is initialized
  bool _initialized = false;

  SecureStorageManagerImpl();

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _logger.info('Initializing secure storage');
      _initialized = true;
      _logger.info('Secure storage initialized');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize secure storage', e, stackTrace);
      throw MCPException('Failed to initialize secure storage: $e');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    await _ensureInitialized();
    await ErrorRecovery.tryWithRetry<void>(
      () async {
        _logger.finest('Saving string to secure storage: $key');
        await _channel.invokeMethod('secureStore', {
          'key': key,
          'value': value,
        });
      },
      maxRetries: 3,
      initialDelay: Duration(milliseconds: 100),
      operationName: 'save_string',
      onRetry: (attempt, error) {
        _logger.warning(
            'Failed to save string (attempt $attempt), retrying: $error');
      },
    );
  }

  @override
  Future<String?> readString(String key) async {
    await _ensureInitialized();
    return await ErrorRecovery.tryWithRetry<String?>(
      () async {
        _logger.finest('Reading string from secure storage: $key');
        try {
          final result = await _channel.invokeMethod<String>('secureRead', {
            'key': key,
          });
          return result;
        } on PlatformException catch (e) {
          if (e.code == 'KEY_NOT_FOUND') {
            return null;
          }
          rethrow;
        }
      },
      maxRetries: 3,
      initialDelay: Duration(milliseconds: 100),
      operationName: 'read_string',
      onRetry: (attempt, error) {
        _logger.warning(
            'Failed to read string (attempt $attempt), retrying: $error');
      },
    );
  }

  @override
  Future<bool> delete(String key) async {
    await _ensureInitialized();
    try {
      _logger.finest('Deleting key from secure storage: $key');
      await _channel.invokeMethod('secureDelete', {
        'key': key,
      });
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete key: $key', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    await _ensureInitialized();
    try {
      _logger.finest('Checking if key exists: $key');
      final result = await _channel.invokeMethod<bool>('secureContainsKey', {
        'key': key,
      });
      return result ?? false;
    } catch (e, stackTrace) {
      _logger.severe('Failed to check key existence: $key', e, stackTrace);
      return false;
    }
  }

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    await _ensureInitialized();
    try {
      final jsonString = jsonEncode(value);
      await saveString(key, jsonString);
    } catch (e, stackTrace) {
      _logger.severe('Failed to save map: $key', e, stackTrace);
      throw MCPException('Failed to save map: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    await _ensureInitialized();
    try {
      final jsonString = await readString(key);
      if (jsonString == null) return null;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      _logger.severe('Failed to read map: $key', e, stackTrace);
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _ensureInitialized();
    try {
      _logger.info('Clearing all secure storage');
      await _channel.invokeMethod('secureDeleteAll');
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear secure storage', e, stackTrace);
      throw MCPException('Failed to clear secure storage: $e');
    }
  }

  @override
  Future<Set<String>> getAllKeys() async {
    await _ensureInitialized();
    try {
      _logger.finest('Getting all keys from secure storage');
      final result =
          await _channel.invokeMethod<List<dynamic>>('secureGetAllKeys');
      if (result == null) return {};
      return result.cast<String>().toSet();
    } catch (e, stackTrace) {
      _logger.severe('Failed to get all keys', e, stackTrace);
      return {};
    }
  }
}

/// Factory function for creating platform-specific secure storage
SecureStorageManager createSecureStorageManager() {
  return SecureStorageManagerImpl();
}
