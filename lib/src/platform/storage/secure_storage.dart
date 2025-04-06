import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import '../../utils/error_recovery.dart';
import '../../utils/platform_utils.dart';

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
}

/// Secure storage implementation for native platforms
class SecureStorageManagerImpl implements SecureStorageManager {
  final FlutterSecureStorage _storage;
  final MCPLogger _logger = MCPLogger('mcp.secure_storage');

  /// Whether storage is initialized
  bool _initialized = false;

  /// Create secure storage with platform-specific options
  SecureStorageManagerImpl({
    AndroidOptions? androidOptions,
    IOSOptions? iosOptions,
    MacOsOptions? macOsOptions,
    WindowsOptions? windowsOptions,
    LinuxOptions? linuxOptions,
  }) : _storage = FlutterSecureStorage(
    aOptions: androidOptions ?? const AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: iosOptions ?? const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: macOsOptions ?? const MacOsOptions(),
    wOptions: windowsOptions ?? const WindowsOptions(),
    lOptions: linuxOptions ?? const LinuxOptions(),
  );

  @override
  Future<void> initialize() async {
    if (_initialized) {
      _logger.debug('Secure storage already initialized');
      return;
    }

    _logger.debug('Initializing secure storage');

    try {
      // Perform a simple read/write test to verify storage is working
      await ErrorRecovery.tryWithRetry(
            () async {
          final testKey = '_mcp_storage_test_${DateTime.now().millisecondsSinceEpoch}';
          await _storage.write(key: testKey, value: 'test');
          final value = await _storage.read(key: testKey);
          await _storage.delete(key: testKey);

          if (value != 'test') {
            throw MCPException('Storage test failed: incorrect value read');
          }
        },
        operationName: 'storage initialization test',
        maxRetries: 2,
      );

      _initialized = true;
      _logger.debug('Secure storage initialized successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize secure storage', e, stackTrace);
      throw MCPInitializationException('Failed to initialize secure storage', e, stackTrace);
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    _checkInitialized();

    _logger.debug('Saving string to secure storage: $key');

    try {
      await ErrorRecovery.tryWithRetry(
            () => _storage.write(key: key, value: value),
        operationName: 'save string to secure storage',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to save string to secure storage', e, stackTrace);
      throw MCPException('Failed to save string to secure storage', e, stackTrace);
    }
  }

  @override
  Future<String?> readString(String key) async {
    _checkInitialized();

    _logger.debug('Reading string from secure storage: $key');

    try {
      return await ErrorRecovery.tryWithRetry(
            () => _storage.read(key: key),
        operationName: 'read string from secure storage',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to read string from secure storage', e, stackTrace);
      throw MCPException('Failed to read string from secure storage', e, stackTrace);
    }
  }

  @override
  Future<bool> delete(String key) async {
    _checkInitialized();

    _logger.debug('Deleting key from secure storage: $key');

    try {
      await ErrorRecovery.tryWithRetry(
            () => _storage.delete(key: key),
        operationName: 'delete from secure storage',
        maxRetries: 2,
      );
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to delete key from secure storage', e, stackTrace);
      throw MCPException('Failed to delete key from secure storage', e, stackTrace);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    _checkInitialized();

    try {
      final value = await ErrorRecovery.tryWithRetry(
            () => _storage.read(key: key),
        operationName: 'check key in secure storage',
        maxRetries: 2,
      );
      return value != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to check if key exists in secure storage', e, stackTrace);
      throw MCPException('Failed to check if key exists in secure storage', e, stackTrace);
    }
  }

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    _checkInitialized();

    _logger.debug('Saving map to secure storage: $key');

    try {
      final jsonString = jsonEncode(value);
      await saveString(key, jsonString);
    } catch (e, stackTrace) {
      _logger.error('Failed to save map to secure storage', e, stackTrace);
      throw MCPException('Failed to save map to secure storage', e, stackTrace);
    }
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    _checkInitialized();

    _logger.debug('Reading map from secure storage: $key');

    try {
      final jsonString = await readString(key);
      if (jsonString == null) {
        return null;
      }

      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      _logger.error('Failed to read map from secure storage', e, stackTrace);
      throw MCPException('Failed to read map from secure storage', e, stackTrace);
    }
  }

  @override
  Future<void> clear() async {
    _checkInitialized();

    _logger.debug('Clearing secure storage');

    try {
      await ErrorRecovery.tryWithRetry(
            () => _storage.deleteAll(),
        operationName: 'clear secure storage',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to clear secure storage', e, stackTrace);
      throw MCPException('Failed to clear secure storage', e, stackTrace);
    }
  }

  /// Check if storage is initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw MCPException('Secure storage is not initialized');
    }
  }
}

/// Factory for creating appropriate secure storage manager
class SecureStorageFactory {
  /// Create platform-appropriate secure storage manager
  static SecureStorageManager create() {
    if (kIsWeb) {
      // For web platform, implementation would be provided by web_storage.dart
      throw UnimplementedError('Web secure storage not implemented in this context');
    } else if (PlatformUtils.isDesktop) {
      // Desktop options can be customized here
      return SecureStorageManagerImpl(
        macOsOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
        windowsOptions: const WindowsOptions(),
        // Linux does not need special options in the current version of flutter_secure_storage
        // linuxOptions parameter is not required
      );
    } else if (PlatformUtils.isMobile) {
      // Mobile options can be customized here
      return SecureStorageManagerImpl(
        androidOptions: const AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
        ),
        iosOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
    } else {
      // Default implementation for any other platform
      return SecureStorageManagerImpl();
    }
  }
}