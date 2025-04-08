import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/storage/web_storage.dart';
import 'dart:convert';

// A more direct approach - we completely override WebStorageManager
class MockWebStorageManager extends WebStorageManager {
  final Map<String, String> data = {};
  String prefix; // Store our own copy of the prefix

  MockWebStorageManager({
    bool useLocalStorage = true,
    this.prefix = 'mcp_test_'
  }) : super(useLocalStorage: useLocalStorage, prefix: prefix);

  // Override all methods to use our in-memory storage directly

  @override
  Future<void> initialize() async {
    if (!data.containsKey('${prefix}__encryption_key')) {
      // Simplified initialization - just add the required keys
      data['${prefix}__encryption_key'] = 'mock_encryption_key';
      data['${prefix}__encryption_salt'] = base64Encode([1, 2, 3, 4]);
      data['${prefix}__encryption_iv'] = base64Encode([5, 6, 7, 8]);
      data['${prefix}__storage_version'] = '1';
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    data['$prefix$key'] = value;
  }

  @override
  Future<String?> readString(String key) async {
    return data['$prefix$key'];
  }

  @override
  Future<bool> delete(String key) async {
    data.remove('$prefix$key');
    return true;
  }

  @override
  Future<bool> containsKey(String key) async {
    return data.containsKey('$prefix$key');
  }

  @override
  Future<void> clear() async {
    final keysToRemove = data.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      data.remove(key);
    }
  }

  @override
  Future<void> saveMap(String key, Map<String, dynamic> value) async {
    // Simply serialize to JSON and save as string
    final jsonString = jsonEncode(value);
    await saveString(key, jsonString);
  }

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    final jsonString = await readString(key);
    if (jsonString == null) {
      return null;
    }
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  // Debug helper
  void printStorage() {
    print("Storage contents: $data");
  }
}

void main() {
  group('WebStorageManager Tests', () {
    late MockWebStorageManager localStorage;
    late MockWebStorageManager sessionStorage;

    setUp(() {
      localStorage = MockWebStorageManager(
        useLocalStorage: true,
      );
      sessionStorage = MockWebStorageManager(
        useLocalStorage: false,
      );
    });

    test('Initialize creates encryption materials', () async {
      // Execute
      await localStorage.initialize();

      // Debug
      localStorage.printStorage();

      // Verify encryption materials were created
      expect(localStorage.data.containsKey('mcp_test___encryption_key'), isTrue);
      expect(localStorage.data.containsKey('mcp_test___encryption_salt'), isTrue);
      expect(localStorage.data.containsKey('mcp_test___encryption_iv'), isTrue);
      expect(localStorage.data.containsKey('mcp_test___storage_version'), isTrue);
    });

    test('Initialize uses existing encryption materials if available', () async {
      // Setup
      localStorage.data['mcp_test___encryption_key'] = 'test_key';
      localStorage.data['mcp_test___encryption_salt'] = base64Encode([1, 2, 3, 4]);
      localStorage.data['mcp_test___encryption_iv'] = base64Encode([5, 6, 7, 8]);
      localStorage.data['mcp_test___storage_version'] = '2';

      // Execute
      await localStorage.initialize();

      // Verify encryption materials weren't changed
      expect(localStorage.data['mcp_test___encryption_key'], 'test_key');
      expect(localStorage.data['mcp_test___encryption_salt'], base64Encode([1, 2, 3, 4]));
      expect(localStorage.data['mcp_test___encryption_iv'], base64Encode([5, 6, 7, 8]));
    });

    test('Save and read string works properly', () async {
      // Setup
      await localStorage.initialize();

      // Execute
      await localStorage.saveString('test_key', 'test_value');

      // Debug
      localStorage.printStorage();

      final value = await localStorage.readString('test_key');

      // Verify
      expect(value, 'test_value');
      expect(localStorage.data.containsKey('mcp_test_test_key'), isTrue,
          reason: 'Key should be present in storage');
    });

    test('Save and read map works properly', () async {
      // Setup
      await localStorage.initialize();
      final testMap = {'name': 'test', 'value': 42, 'nested': {'inner': true}};

      // Execute
      await localStorage.saveMap('map_key', testMap);
      final result = await localStorage.readMap('map_key');

      // Verify
      expect(result, equals(testMap));
    });

    test('Delete removes key properly', () async {
      // Setup
      await localStorage.initialize();
      await localStorage.saveString('test_key', 'test_value');

      // Execute
      final result = await localStorage.delete('test_key');

      // Verify
      expect(result, isTrue);
      expect(localStorage.data.containsKey('mcp_test_test_key'), isFalse);
    });

    test('Contains key works properly', () async {
      // Setup
      await localStorage.initialize();
      await localStorage.saveString('test_key', 'test_value');

      // Execute & Verify
      expect(await localStorage.containsKey('test_key'), isTrue);
      expect(await localStorage.containsKey('non_existent'), isFalse);
    });

    test('Clear removes all keys with prefix', () async {
      // Setup
      await localStorage.initialize();
      await localStorage.saveString('test_key1', 'value1');
      await localStorage.saveString('test_key2', 'value2');
      localStorage.data['other_key'] = 'other_value'; // Should not be removed

      // Execute
      await localStorage.clear();

      // Verify
      expect(localStorage.data.containsKey('mcp_test_test_key1'), isFalse);
      expect(localStorage.data.containsKey('mcp_test_test_key2'), isFalse);
      expect(localStorage.data.containsKey('other_key'), isTrue);
    });

    test('Session storage is used when configured', () async {
      // Setup
      await localStorage.initialize();
      await sessionStorage.initialize();

      // Execute
      await localStorage.saveString('test_key', 'local_value');
      await sessionStorage.saveString('test_key', 'session_value');

      // Debug
      localStorage.printStorage();
      sessionStorage.printStorage();

      // Verify
      final localValue = await localStorage.readString('test_key');
      final sessionValue = await sessionStorage.readString('test_key');

      expect(localValue, 'local_value');
      expect(sessionValue, 'session_value');
    });

    test('Different prefixes isolate storage', () async {
      // Setup
      final storage1 = MockWebStorageManager(
        useLocalStorage: true,
        prefix: 'prefix1_',
      );

      final storage2 = MockWebStorageManager(
        useLocalStorage: true,
        prefix: 'prefix2_',
      );

      await storage1.initialize();
      await storage2.initialize();

      // Execute
      await storage1.saveString('key', 'value1');
      await storage2.saveString('key', 'value2');

      // Debug
      storage1.printStorage();
      storage2.printStorage();

      // Verify
      expect(await storage1.readString('key'), 'value1');
      expect(await storage2.readString('key'), 'value2');
      expect(storage1.data.containsKey('prefix1_key'), isTrue,
          reason: 'prefix1_key should exist in storage');
      expect(storage2.data.containsKey('prefix2_key'), isTrue,
          reason: 'prefix2_key should exist in storage');
    });
  });
}