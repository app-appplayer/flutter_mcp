import 'dart:html' as html;
import 'dart:convert';
import 'dart:math' as math;
import '../../storage/secure_storage.dart';
import '../../utils/logger.dart';

/// Web storage implementation
class WebStorageManager implements SecureStorageManager {
  final bool _useLocalStorage;
  final String _prefix;
  final MCPLogger _logger = MCPLogger('mcp.web_storage');

  // Encryption key for "secure" storage on web (limited security)
  late String _encryptionKey;

  /// Create a new web storage manager
  ///
  /// [useLocalStorage] determines whether to use localStorage (true) or sessionStorage (false)
  /// [prefix] is used to prefix all keys in the storage
  WebStorageManager({
    bool useLocalStorage = true,
    String prefix = 'mcp_',
  }) :
        _useLocalStorage = useLocalStorage,
        _prefix = prefix;

  @override
  Future<void> initialize() async {
    _logger.debug('Initializing web storage');

    // Generate a simple key for basic obfuscation (not truly secure)
    _encryptionKey = _generateKey();

    // Store the key in the storage itself (just for persistence)
    final storage = _getStorage();
    if (!storage.containsKey('${_prefix}key')) {
      storage['${_prefix}key'] = _encryptionKey;
    } else {
      _encryptionKey = storage['${_prefix}key'] ?? _encryptionKey;
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    _logger.debug('Saving string: $key');

    // Simple obfuscation for "secure" storage
    final encryptedValue = _encrypt(value);

    _getStorage()['$_prefix$key'] = encryptedValue;
  }

  @override
  Future<String?> readString(String key) async {
    _logger.debug('Reading string: $key');

    final encryptedValue = _getStorage()['$_prefix$key'];
    if (encryptedValue == null) {
      return null;
    }

    return _decrypt(encryptedValue);
  }

  @override
  Future<bool> delete(String key) async {
    _logger.debug('Deleting key: $key');

    _getStorage().remove('$_prefix$key');
    return true;
  }

  @override
  Future<bool> containsKey(String key) async {
    return _getStorage().containsKey('$_prefix$key');
  }

  /// Get all keys in storage
  Future<List<String>> getKeys() async {
    final allKeys = _getStorage().keys.where((key) => key.startsWith(_prefix)).toList();
    return allKeys.map((key) => key.substring(_prefix.length)).toList();
  }

  /// Get appropriate storage based on settings
  html.Storage _getStorage() {
    return _useLocalStorage ?
    html.window.localStorage :
    html.window.sessionStorage;
  }

  /// Generate a simple key for basic obfuscation
  String _generateKey() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = now.toString() + math.Random().nextInt(10000).toString();
    return base64Encode(utf8.encode(random));
  }

  /// Very simple encryption (just for obfuscation)
  String _encrypt(String value) {
    // In a real implementation, use a proper encryption library
    // This is just basic encoding to prevent casual inspection
    final valueBytes = utf8.encode(value);
    final encoded = base64Encode(valueBytes);
    return encoded;
  }

  /// Decrypt the obfuscated value
  String _decrypt(String encryptedValue) {
    // In a real implementation, use a proper encryption library
    try {
      final decoded = base64Decode(encryptedValue);
      return utf8.decode(decoded);
    } catch (e) {
      _logger.error('Failed to decrypt value', e);
      return '';
    }
  }

  /// Clear all data for this prefix
  Future<void> clear() async {
    _logger.debug('Clearing all storage with prefix: $_prefix');

    final storage = _getStorage();
    final keysToRemove = storage.keys.where((key) => key.startsWith(_prefix)).toList();

    for (final key in keysToRemove) {
      storage.remove(key);
    }
  }
}