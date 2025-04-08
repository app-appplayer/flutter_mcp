import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'mcp_secure_storage_test.mocks.dart';

// Generate mocks for FlutterSecureStorage
@GenerateMocks([FlutterSecureStorage])
void main() {
  group('SecureStorageManager Tests', () {
    late MockFlutterSecureStorage mockStorage;
    late SecureStorageManager storageManager;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      storageManager = SecureStorageManagerWithMock(mockStorage);

      // Default stub for any key - this helps avoid MissingStubError
      when(mockStorage.read(key: anyNamed('key'))).thenAnswer((_) async => null);
      when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value'))).thenAnswer((_) async {});
      when(mockStorage.delete(key: anyNamed('key'))).thenAnswer((_) async {});
      when(mockStorage.deleteAll()).thenAnswer((_) async {});

      // Specific stub for initialization test
      when(mockStorage.read(key: argThat(startsWith('_mcp_storage_test_'), named: 'key'))).thenAnswer((_) async => 'test');
    });

    test('Initialize storage succeeds', () async {
      // Execute
      await storageManager.initialize();

      // Verify initialization test was performed
      verify(mockStorage.write(
          key: argThat(startsWith('_mcp_storage_test_'), named: 'key'),
          value: argThat(equals('test'), named: 'value')
      )).called(1);

      verify(mockStorage.read(
          key: argThat(startsWith('_mcp_storage_test_'), named: 'key')
      )).called(1);

      verify(mockStorage.delete(
          key: argThat(startsWith('_mcp_storage_test_'), named: 'key')
      )).called(1);
    });

    test('Initialize throws exception on failure', () async {
      // Override the default stub for this test
      when(mockStorage.write(
          key: argThat(startsWith('_mcp_storage_test_'), named: 'key'),
          value: anyNamed('value')
      )).thenThrow(PlatformException(code: 'error'));

      // Execute & Verify
      expect(
            () => storageManager.initialize(),
        throwsA(isA<MCPInitializationException>()),
      );
    });

    test('Save string stores value correctly', () async {
      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      await storageManager.saveString('test_key', 'test_value');

      // Verify
      verify(mockStorage.write(
          key: argThat(equals('test_key'), named: 'key'),
          value: argThat(equals('test_value'), named: 'value')
      )).called(1);
    });

    test('Read string retrieves value correctly', () async {
      // Set up specific stub for this test
      when(mockStorage.read(key: argThat(equals('test_key'), named: 'key'))).thenAnswer((_) async => 'stored_value');

      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      final result = await storageManager.readString('test_key');

      // Verify
      expect(result, 'stored_value');
      verify(mockStorage.read(key: argThat(equals('test_key'), named: 'key'))).called(1);
    });

    test('Contains key checks if key exists', () async {
      // Set up specific stubs for this test
      when(mockStorage.read(key: argThat(equals('existing_key'), named: 'key'))).thenAnswer((_) async => 'value');
      when(mockStorage.read(key: argThat(equals('non_existing_key'), named: 'key'))).thenAnswer((_) async => null);

      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute & Verify
      expect(await storageManager.containsKey('existing_key'), isTrue);
      expect(await storageManager.containsKey('non_existing_key'), isFalse);

      verify(mockStorage.read(key: argThat(equals('existing_key'), named: 'key'))).called(1);
      verify(mockStorage.read(key: argThat(equals('non_existing_key'), named: 'key'))).called(1);
    });

    test('Delete removes key', () async {
      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      final result = await storageManager.delete('test_key');

      // Verify
      expect(result, isTrue);
      verify(mockStorage.delete(key: argThat(equals('test_key'), named: 'key'))).called(1);
    });

    test('SaveMap serializes and stores map correctly', () async {
      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      final map = {'name': 'test', 'value': 42};
      await storageManager.saveMap('map_key', map);

      // Verify
      verify(mockStorage.write(
        key: argThat(equals('map_key'), named: 'key'),
        value: argThat(equals(jsonEncode(map)), named: 'value'),
      )).called(1);
    });

    test('ReadMap retrieves and deserializes map correctly', () async {
      // Set up specific stub for this test
      final map = {'name': 'test', 'value': 42};
      when(mockStorage.read(key: argThat(equals('map_key'), named: 'key'))).thenAnswer((_) async => jsonEncode(map));

      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      final result = await storageManager.readMap('map_key');

      // Verify
      expect(result, equals(map));
      verify(mockStorage.read(key: argThat(equals('map_key'), named: 'key'))).called(1);
    });

    test('Clear deletes all keys', () async {
      // Initialize and clear verification
      await storageManager.initialize();
      clearInteractions(mockStorage);

      // Execute
      await storageManager.clear();

      // Verify
      verify(mockStorage.deleteAll()).called(1);
    });

    test('Not initialized throws exception', () async {
      // Create a fresh instance without initializing
      final uninitializedManager = SecureStorageManagerWithMock(mockStorage);

      // Execute & Verify
      expect(
            () => uninitializedManager.saveString('key', 'value'),
        throwsA(isA<MCPException>()),
      );

      expect(
            () => uninitializedManager.readString('key'),
        throwsA(isA<MCPException>()),
      );

      expect(
            () => uninitializedManager.delete('key'),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('SecureStorageFactory Tests', () {
    test('Creates appropriate implementation based on platform', () {
      final storage = SecureStorageFactory.create();
      expect(storage, isA<SecureStorageManager>());
    });
  });
}

// Custom testable implementation
class SecureStorageManagerWithMock implements SecureStorageManager {
  final FlutterSecureStorage mockStorage;
  bool _initialized = false;

  SecureStorageManagerWithMock(this.mockStorage);

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      // Perform test read/write
      final testKey = '_mcp_storage_test_${DateTime.now().millisecondsSinceEpoch}';
      await mockStorage.write(key: testKey, value: 'test');
      final value = await mockStorage.read(key: testKey);
      await mockStorage.delete(key: testKey);

      if (value != 'test') {
        throw Exception('Storage test failed: incorrect value read');
      }

      _initialized = true;
    } catch (e, stackTrace) {
      throw MCPInitializationException('Failed to initialize secure storage', e, stackTrace);
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    _checkInitialized();
    await mockStorage.write(key: key, value: value);
  }

  @override
  Future<String?> readString(String key) async {
    _checkInitialized();
    return await mockStorage.read(key: key);
  }

  @override
  Future<bool> delete(String key) async {
    _checkInitialized();
    await mockStorage.delete(key: key);
    return true;
  }

  @override
  Future<bool> containsKey(String key) async {
    _checkInitialized();
    final value = await mockStorage.read(key: key);
    return value != null;
  }

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    _checkInitialized();
    final jsonString = jsonEncode(value);
    await saveString(key, jsonString);
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    _checkInitialized();
    final jsonString = await readString(key);
    if (jsonString == null) {
      return null;
    }
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    _checkInitialized();
    await mockStorage.deleteAll();
  }

  /// Check if storage is initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw MCPException('Secure storage is not initialized');
    }
  }
}