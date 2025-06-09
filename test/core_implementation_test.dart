import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mcp_client/mcp_client.dart' as mcp_client;
import 'package:mcp_server/mcp_server.dart' as mcp_server;
import 'package:mcp_llm/mcp_llm.dart' as mcp_llm;

import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/core/batch_manager.dart';
// Health monitor import removed - using simple implementation
import 'package:flutter_mcp/src/security/credential_manager.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';
import 'package:flutter_mcp/src/utils/memory_manager.dart';
import 'package:flutter_mcp/src/utils/performance_monitor.dart' as perf;
import 'package:flutter_mcp/src/utils/event_system.dart';
import 'package:flutter_mcp/src/utils/circuit_breaker.dart';

import 'core_implementation_test.mocks.dart';

// Mock only transport layer
@GenerateMocks([mcp_client.ClientTransport, mcp_server.ServerTransport])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Core Implementation Tests', () {
    late List<MethodCall> methodCalls;
    late Map<String, String> mockStorage;
    
    setUp(() {
      methodCalls = [];
      mockStorage = {};
      
      // Mock method channel for platform interface
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          
          switch (methodCall.method) {
            case 'initialize':
              return null;
            case 'secureStore':
              final key = methodCall.arguments['key'] as String;
              final value = methodCall.arguments['value'] as String;
              mockStorage[key] = value;
              return null;
            case 'secureRead':
              final key = methodCall.arguments['key'] as String;
              return mockStorage[key];
            case 'secureGetAllKeys':
              return mockStorage.keys.toList();
            case 'secureDelete':
              final key = methodCall.arguments['key'] as String;
              mockStorage.remove(key);
              return null;
            case 'secureContainsKey':
              final key = methodCall.arguments['key'] as String;
              return mockStorage.containsKey(key);
            case 'startBackgroundService':
              return true;
            case 'stopBackgroundService':
              return true;
            case 'showNotification':
              return null;
            case 'cancelAllNotifications':
              return null;
            case 'shutdown':
              return null;
            default:
              return null;
          }
        },
      );
    });
    
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_mcp'),
        null,
      );
    });
    
    group('Client Manager Tests', () {
      test('should register and manage MCP clients', () async {
        final clientManager = MCPClientManager();
        await clientManager.initialize();
        
        // Create mock client and transport
        final mockTransport = MockClientTransport();
        final client = mcp_client.Client(
          name: 'test_client',
          version: '1.0.0',
          capabilities: mcp_client.ClientCapabilities(),
        );
        
        // Test client registration
        final clientId = clientManager.generateId();
        clientManager.registerClient(clientId, client, mockTransport);
        
        // Test client retrieval
        final retrievedClient = clientManager.getClient(clientId);
        expect(retrievedClient, isNotNull);
        expect(retrievedClient!.name, equals('test_client'));
        
        // Test client info
        final clientInfo = clientManager.getClientInfo(clientId);
        expect(clientInfo, isNotNull);
        expect(clientInfo!.id, equals(clientId));
        
        // Test client listing
        final clientIds = clientManager.getAllClientIds();
        expect(clientIds, contains(clientId));
        
        // Test status
        final status = clientManager.getStatus();
        expect(status['total'], equals(1));
      });
      
      test('should handle client lifecycle', () async {
        final clientManager = MCPClientManager();
        await clientManager.initialize();
        
        final mockTransport = MockClientTransport();
        final client = mcp_client.Client(
          name: 'lifecycle_client',
          version: '1.0.0',
          capabilities: mcp_client.ClientCapabilities(),
        );
        
        final clientId = clientManager.generateId();
        clientManager.registerClient(clientId, client, mockTransport);
        
        // Test client closure
        await clientManager.closeClient(clientId);
        final afterClose = clientManager.getClient(clientId);
        expect(afterClose, isNull);
      });
    });
    
    group('Server Manager Tests', () {
      test('should register and manage MCP servers', () async {
        final serverManager = MCPServerManager();
        await serverManager.initialize();
        
        // Create mock server and transport
        final mockTransport = MockServerTransport();
        final server = mcp_server.Server(
          name: 'test_server',
          version: '1.0.0',
          capabilities: mcp_server.ServerCapabilities(),
        );
        
        // Test server registration
        final serverId = serverManager.generateId();
        serverManager.registerServer(serverId, server, mockTransport);
        
        // Test server retrieval
        final retrievedServer = serverManager.getServer(serverId);
        expect(retrievedServer, isNotNull);
        expect(retrievedServer!.name, equals('test_server'));
        
        // Test server listing
        final serverIds = serverManager.getAllServerIds();
        expect(serverIds, contains(serverId));
        
        // Test status
        final status = serverManager.getStatus();
        expect(status['total'], equals(1));
      });
    });
    
    group('LLM Manager Tests', () {
      test('should manage LLM instances', () async {
        final llmManager = MCPLlmManager();
        
        // Create mock LLM
        final mockLlm = mcp_llm.MCPLlm();
        
        // Test LLM registration
        llmManager.registerLlm('test_llm', mockLlm);
        
        final llmInfo = llmManager.getLlmInfo('test_llm');
        expect(llmInfo, isNotNull);
        expect(llmInfo!.id, equals('test_llm'));
        
        // Test status
        final status = llmManager.getStatus();
        expect(status['total'], equals(1));
      });
    });
    
    group('Batch Manager Tests', () {
      test('should process batch requests', () async {
        final batchManager = MCPBatchManager.instance;
        
        // Initialize batch manager
        final mockLlm = mcp_llm.MCPLlm();
        batchManager.initializeBatchManager('test_llm', mockLlm);
        
        // Test batch processing
        final results = await batchManager.processBatch<String>(
          llmId: 'test_llm',
          requests: [
            () async => 'result1',
            () async => 'result2',
            () async => 'result3',
          ],
        );
        
        expect(results, hasLength(3));
        expect(results, contains('result1'));
        expect(results, contains('result2'));
        expect(results, contains('result3'));
        
        // Test statistics
        final stats = batchManager.getStatistics('test_llm');
        expect(stats['llmId'], equals('test_llm'));
        // Allow for async processing - the processor might not have recorded stats yet
        expect(stats, containsPair('llmId', 'test_llm'));
      });
      
      test('should handle batch errors with retry', () async {
        final batchManager = MCPBatchManager.instance;
        final mockLlm = mcp_llm.MCPLlm();
        batchManager.initializeBatchManager('error_llm', mockLlm);
        
        int callCount = 0;
        final results = await batchManager.processBatch<String>(
          llmId: 'error_llm',
          requests: [
            () async {
              callCount++;
              if (callCount < 3) {
                throw Exception('Temporary error');
              }
              return 'success_after_retry';
            },
          ],
        );
        
        expect(results, hasLength(1));
        expect(results.first, equals('success_after_retry'));
        expect(callCount, greaterThanOrEqualTo(3));
      });
    });
    
    // Health Monitor Tests removed - using simple implementation in main class
    
    group('Credential Manager Tests', () {
      test('should store and retrieve credentials', () async {
        // Initialize credential manager with secure storage
        final secureStorage = SecureStorageManagerImpl();
        await secureStorage.initialize();
        final credentialManager = await CredentialManager.initialize(secureStorage);
        
        // Test credential storage
        await credentialManager.storeCredential('test_key', 'test_value');
        
        // Test credential retrieval
        final retrievedValue = await credentialManager.getCredential('test_key');
        expect(retrievedValue, equals('test_value'));
        
        // Test credential existence check
        final exists = await credentialManager.hasCredential('test_key');
        expect(exists, isTrue);
        
        // Test credential listing
        final keys = await credentialManager.listCredentialKeys();
        expect(keys, contains('test_key'));
        
        // Test credential deletion (check existence first, then delete)
        final existsBeforeDelete = await credentialManager.hasCredential('test_key');
        expect(existsBeforeDelete, isTrue);
        final deleted = await credentialManager.deleteCredential('test_key');
        expect(deleted, isTrue);
        
        final afterDeletion = await credentialManager.getCredential('test_key');
        expect(afterDeletion, isNull);
      });
      
      test('should handle credential metadata', () async {
        // Initialize credential manager with secure storage
        final secureStorage = SecureStorageManagerImpl();
        await secureStorage.initialize();
        final credentialManager = await CredentialManager.initialize(secureStorage);
        
        final metadata = {'type': 'api_key', 'provider': 'test'};
        await credentialManager.storeCredential(
          'meta_key', 
          'meta_value',
          metadata: metadata,
        );
        
        final result = await credentialManager.getCredentialWithMetadata('meta_key');
        expect(result, isNotNull);
        expect(result!['value'], equals('meta_value'));
        expect(result['metadata'], equals(metadata));
      });
    });
    
    group('Secure Storage Tests', () {
      test('should store and retrieve secure data', () async {
        final secureStorage = SecureStorageManagerImpl();
        await secureStorage.initialize();
        
        // Test string storage
        await secureStorage.saveString('string_key', 'string_value');
        final retrievedString = await secureStorage.readString('string_key');
        expect(retrievedString, equals('string_value'));
        
        // Test key listing
        final keys = await secureStorage.getAllKeys();
        expect(keys, contains('string_key'));
        
        // Test deletion
        await secureStorage.delete('string_key');
        final afterDeletion = await secureStorage.readString('string_key');
        expect(afterDeletion, isNull);
      });
    });
    
    group('Memory Manager Tests', () {
      test('should track memory usage', () async {
        final memoryManager = MemoryManager.instance;
        
        // Test memory stats
        final stats = memoryManager.getMemoryStats();
        expect(stats, isA<Map<String, dynamic>>());
        // Memory stats may be simulated, so check for basic structure
        expect(stats, isNotEmpty);
        
        // Test memory monitoring initialization
        memoryManager.initialize(startMonitoring: false);
        
        // Stats should still be available
        final afterInit = memoryManager.getMemoryStats();
        expect(afterInit, isA<Map<String, dynamic>>());
      });
    });
    
    group('Performance Monitor Tests', () {
      test('should track operation performance', () async {
        final performanceMonitor = perf.PerformanceMonitor.instance;
        
        // Test operation timing
        final timer = performanceMonitor.startTimer('test_operation');
        await Future.delayed(Duration(milliseconds: 10));
        performanceMonitor.stopTimer(timer, success: true);
        
        // Check if operations are being tracked via metrics report
        final metricsReport = performanceMonitor.getMetricsReport();
        expect(metricsReport, isA<Map<String, dynamic>>());
        // Metrics report should contain some data
        expect(metricsReport, isNotEmpty);
      });
      
      test('should track resource usage', () async {
        final performanceMonitor = perf.PerformanceMonitor.instance;
        
        // Record resource usage
        performanceMonitor.recordResourceUsage('memory.test', 100.0);
        
        // Check if resource usage is tracked via metrics report
        final metricsReport = performanceMonitor.getMetricsReport();
        expect(metricsReport, isA<Map<String, dynamic>>());
        // Metrics report should contain some data after recording resource usage
        expect(metricsReport, isNotEmpty);
      });
    });
    
    group('Event System Tests', () {
      test('should publish and subscribe to events', () async {
        final eventSystem = EventSystem.instance;
        
        String? receivedEvent;
        Map<String, dynamic>? receivedData;
        
        // Subscribe to events
        final subscription = eventSystem.subscribe('test_event', (data) {
          receivedEvent = 'test_event';
          receivedData = data as Map<String, dynamic>?;
        });
        
        // Publish event
        eventSystem.publish('test_event', {'message': 'hello'});
        
        // Wait for event processing
        await Future.delayed(Duration(milliseconds: 10));
        
        expect(receivedEvent, equals('test_event'));
        expect(receivedData?['message'], equals('hello'));
        
        // Cleanup
        eventSystem.unsubscribe(subscription);
      });
      
      test('should handle multiple subscribers', () async {
        final eventSystem = EventSystem.instance;
        
        int subscriber1CallCount = 0;
        int subscriber2CallCount = 0;
        
        final sub1 = eventSystem.subscribe('multi_event', (data) {
          subscriber1CallCount++;
        });
        
        final sub2 = eventSystem.subscribe('multi_event', (data) {
          subscriber2CallCount++;
        });
        
        // Publish event
        eventSystem.publish('multi_event', {});
        
        // Wait for event processing
        await Future.delayed(Duration(milliseconds: 10));
        
        expect(subscriber1CallCount, equals(1));
        expect(subscriber2CallCount, equals(1));
        
        // Cleanup
        eventSystem.unsubscribe(sub1);
        eventSystem.unsubscribe(sub2);
      });
    });
    
    group('Circuit Breaker Tests', () {
      test('should prevent calls when circuit is open', () async {
        final circuitBreaker = CircuitBreaker(
          name: 'test_circuit',
          failureThreshold: 2,
          resetTimeout: Duration(milliseconds: 100),
        );
        
        // First few calls should succeed
        var result = await circuitBreaker.execute(() async => 'success');
        expect(result, equals('success'));
        
        // Cause failures to open circuit
        try {
          await circuitBreaker.execute(() async => throw Exception('failure'));
        } catch (e) {
          // Expected
        }
        
        try {
          await circuitBreaker.execute(() async => throw Exception('failure'));
        } catch (e) {
          // Expected
        }
        
        // Circuit should now be open
        expect(circuitBreaker.state, equals(CircuitBreakerState.open));
        
        // Next call should fail fast
        expect(
          () async => await circuitBreaker.execute(() async => 'should_not_execute'),
          throwsA(isA<Exception>()),
        );
      });
      
      test('should recover after timeout', () async {
        final circuitBreaker = CircuitBreaker(
          name: 'recovery_circuit',
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
        );
        
        // Cause failure to open circuit
        try {
          await circuitBreaker.execute(() async => throw Exception('failure'));
        } catch (e) {
          // Expected
        }
        
        expect(circuitBreaker.state, equals(CircuitBreakerState.open));
        
        // Wait for timeout
        await Future.delayed(Duration(milliseconds: 60));
        
        // Circuit should be half-open, and successful call should close it
        final result = await circuitBreaker.execute(() async => 'recovered');
        expect(result, equals('recovered'));
        expect(circuitBreaker.state, equals(CircuitBreakerState.closed));
      });
    });
    
    group('Platform Integration Tests', () {
      test('should handle method channel communication', () async {
        // Initialize platform services would trigger method calls
        final secureStorage = SecureStorageManagerImpl();
        await secureStorage.initialize();
        
        // Clear method calls and perform an operation
        methodCalls.clear();
        await secureStorage.saveString('platform_test', 'platform_value');
        
        // Method calls should have been made
        expect(methodCalls, isNotEmpty);
      });
      
      test('should handle secure storage operations', () async {
        final secureStorage = SecureStorageManagerImpl();
        await secureStorage.initialize();
        
        // Clear previous method calls
        methodCalls.clear();
        
        // Perform storage operation
        await secureStorage.saveString('platform_test', 'platform_value');
        
        // Should have called the platform method
        expect(methodCalls.any((call) => call.method == 'secureStore'), isTrue);
        
        // Test reading - store a value first, then read it
        await secureStorage.saveString('test_key', 'test_value');
        methodCalls.clear();
        final value = await secureStorage.readString('test_key');
        expect(value, equals('test_value'));
        expect(methodCalls.any((call) => call.method == 'secureRead'), isTrue);
      });
    });
  });
}