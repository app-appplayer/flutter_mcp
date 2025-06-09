import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';
import 'dart:convert';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('SecureStorageManager Tests', () {
    late SecureStorageManager storageManager;
    late List<MethodCall> methodCalls;

    setUp(() {
      storageManager = SecureStorageManagerImpl();
      methodCalls = [];
      
      // Mock the method channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          
          // Mock responses based on method name
          switch (methodCall.method) {
            case 'secureStore':
              return null; // Successful storage
            case 'secureRead':
              final key = methodCall.arguments['key'] as String;
              if (key == 'test_key') {
                return 'test_value';
              } else if (key == 'json_key') {
                return '{"name":"test","value":123}';
              }
              throw PlatformException(code: 'KEY_NOT_FOUND', message: 'Key not found');
            case 'secureDelete':
              return null; // Successful deletion
            case 'secureDeleteAll':
              return null; // Successful clear
            case 'secureGetAllKeys':
              return ['test_key', 'json_key'];
            case 'secureContainsKey':
              final key = methodCall.arguments['key'] as String;
              return key == 'test_key' || key == 'json_key';
            default:
              throw PlatformException(code: 'METHOD_NOT_IMPLEMENTED', message: 'Method not implemented');
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_mcp'), null);
      methodCalls.clear();
    });

    test('Initialize storage manager', () async {
      await storageManager.initialize();
      expect(storageManager, isNotNull);
    });

    test('Save and read string value', () async {
      await storageManager.initialize();
      
      // Save string
      await storageManager.saveString('test_key', 'test_value');
      
      // Verify method was called correctly
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureStore');
      expect(methodCalls[0].arguments['key'], 'test_key');
      expect(methodCalls[0].arguments['value'], 'test_value');
      
      // Read string
      methodCalls.clear();
      final value = await storageManager.readString('test_key');
      
      expect(value, 'test_value');
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureRead');
      expect(methodCalls[0].arguments['key'], 'test_key');
    });

    test('Read non-existent key returns null', () async {
      await storageManager.initialize();
      
      final value = await storageManager.readString('non_existent_key');
      expect(value, isNull);
    });

    test('Save and read map data', () async {
      await storageManager.initialize();
      
      final testMap = {'name': 'test', 'value': 123};
      
      // Save map
      await storageManager.saveMap('json_key', testMap);
      
      // Verify JSON encoding
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureStore');
      expect(methodCalls[0].arguments['key'], 'json_key');
      expect(jsonDecode(methodCalls[0].arguments['value']), testMap);
      
      // Read map
      methodCalls.clear();
      final readMap = await storageManager.readMap('json_key');
      
      expect(readMap, testMap);
    });

    test('Delete key', () async {
      await storageManager.initialize();
      
      final result = await storageManager.delete('test_key');
      
      expect(result, true);
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureDelete');
      expect(methodCalls[0].arguments['key'], 'test_key');
    });

    test('Check if key exists', () async {
      await storageManager.initialize();
      
      // This will use containsKey directly
      final exists = await storageManager.containsKey('test_key');
      
      expect(exists, true);
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureContainsKey');
    });

    test('Clear all storage', () async {
      await storageManager.initialize();
      
      await storageManager.clear();
      
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureDeleteAll');
    });

    test('Get all keys', () async {
      await storageManager.initialize();
      
      final keys = await storageManager.getAllKeys();
      
      expect(keys, {'test_key', 'json_key'});
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'secureGetAllKeys');
    });

    test('Handle platform exceptions gracefully', () async {
      await storageManager.initialize();
      
      // Mock a platform exception
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'STORAGE_ERROR', message: 'Storage failed');
        },
      );
      
      // Should throw MCPException
      expect(
        () => storageManager.saveString('test', 'value'),
        throwsA(isA<MCPException>()),
      );
    });

    test('Multiple initialize calls are safe', () async {
      await storageManager.initialize();
      await storageManager.initialize(); // Should not cause issues
      await storageManager.initialize(); // Should not cause issues
      
      expect(storageManager, isNotNull);
    });
  });
}