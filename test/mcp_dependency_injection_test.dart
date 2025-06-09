import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/core/dependency_injection.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

// Test classes for dependency injection testing
abstract class TestServiceInterface {
  String getName();
  int getValue();
}

class TestServiceImplementation implements TestServiceInterface {
  final String _name;
  final int _value;
  int _callCount = 0;
  
  TestServiceImplementation(this._name, this._value);
  
  @override
  String getName() {
    _callCount++;
    return _name;
  }
  
  @override
  int getValue() {
    _callCount++;
    return _value;
  }
  
  int get callCount => _callCount;
}

class TestRepository {
  final TestServiceInterface _service;
  
  TestRepository(this._service);
  
  String getServiceName() => _service.getName();
  int getServiceValue() => _service.getValue();
}

class TestController {
  final TestRepository _repository;
  final TestServiceInterface _service;
  
  TestController(this._repository, this._service);
  
  String getInfo() => 'Controller: ${_repository.getServiceName()} - ${_service.getName()}';
  int getTotalValue() => _repository.getServiceValue() + _service.getValue();
}

class DisposableService implements TestServiceInterface {
  bool _disposed = false;
  
  @override
  String getName() => _disposed ? 'disposed' : 'active';
  
  @override
  int getValue() => _disposed ? -1 : 42;
  
  void dispose() {
    _disposed = true;
  }
  
  bool get isDisposed => _disposed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Dependency Injection Container Tests', () {
    late DIContainer container;
    
    setUp(() {
      // Use a fresh container for each test
      container = DIContainer.instance;
      
      // Clear any existing registrations
      container.clear();
    });
    
    tearDown(() {
      container.clear();
    });
    
    group('Basic Registration and Resolution', () {
      test('should register and resolve factory services', () {
        // Register factory
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('factory_service', 100),
        );
        
        // Resolve multiple instances
        final instance1 = container.get<TestServiceInterface>();
        final instance2 = container.get<TestServiceInterface>();
        
        expect(instance1, isNotNull);
        expect(instance2, isNotNull);
        expect(identical(instance1, instance2), isFalse); // Different instances
        expect(instance1.getName(), equals('factory_service'));
        expect(instance2.getValue(), equals(100));
      });
      
      test('should register and resolve singleton services', () {
        // Register singleton
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('singleton_service', 200),
        );
        
        // Resolve multiple times
        final instance1 = container.get<TestServiceInterface>();
        final instance2 = container.get<TestServiceInterface>();
        
        expect(instance1, isNotNull);
        expect(instance2, isNotNull);
        expect(identical(instance1, instance2), isTrue); // Same instance
        expect(instance1.getName(), equals('singleton_service'));
        expect(instance2.getValue(), equals(200));
      });
      
      test('should register and resolve instance services', () {
        final existingInstance = TestServiceImplementation('existing_instance', 300);
        
        // Register existing instance
        container.registerInstance<TestServiceInterface>(existingInstance);
        
        // Resolve service
        final resolved = container.get<TestServiceInterface>();
        
        expect(identical(resolved, existingInstance), isTrue);
        expect(resolved.getName(), equals('existing_instance'));
        expect(resolved.getValue(), equals(300));
      });
    });
    
    group('Named Services', () {
      test('should support named service registration', () {
        // Register multiple implementations with names
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('default_service', 1),
        );
        
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('named_service', 2),
          name: 'special',
        );
        
        // Resolve by name
        final defaultService = container.get<TestServiceInterface>();
        final namedService = container.get<TestServiceInterface>(name: 'special');
        
        expect(defaultService.getName(), equals('default_service'));
        expect(namedService.getName(), equals('named_service'));
        expect(defaultService.getValue(), equals(1));
        expect(namedService.getValue(), equals(2));
      });
      
      test('should maintain separate singleton instances for named services', () {
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('default_singleton', 10),
        );
        
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('named_singleton', 20),
          name: 'named',
        );
        
        final default1 = container.get<TestServiceInterface>();
        final default2 = container.get<TestServiceInterface>();
        final named1 = container.get<TestServiceInterface>(name: 'named');
        final named2 = container.get<TestServiceInterface>(name: 'named');
        
        expect(identical(default1, default2), isTrue);
        expect(identical(named1, named2), isTrue);
        expect(identical(default1, named1), isFalse);
      });
    });
    
    group('Service Dependencies', () {
      test('should resolve dependencies manually', () {
        // Register dependencies
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('dependency_service', 500),
        );
        
        container.registerFactory<TestRepository>(
          () => TestRepository(container.get<TestServiceInterface>()),
        );
        
        // Resolve service with dependency
        final repository = container.get<TestRepository>();
        
        expect(repository, isNotNull);
        expect(repository.getServiceName(), equals('dependency_service'));
        expect(repository.getServiceValue(), equals(500));
      });
      
      test('should handle complex dependency chains', () {
        // Register service
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('chain_service', 999),
        );
        
        // Register repository with service dependency
        container.registerSingleton<TestRepository>(
          () => TestRepository(container.get<TestServiceInterface>()),
        );
        
        // Register controller with repository and service dependencies
        container.registerFactory<TestController>(
          () => TestController(
            container.get<TestRepository>(),
            container.get<TestServiceInterface>(),
          ),
        );
        
        // Resolve complex object
        final controller = container.get<TestController>();
        
        expect(controller, isNotNull);
        expect(controller.getInfo(), contains('chain_service'));
        expect(controller.getTotalValue(), equals(1998)); // 999 + 999
      });
    });
    
    group('Error Handling', () {
      test('should throw exception for unregistered service', () {
        expect(
          () => container.get<TestServiceInterface>(),
          throwsA(isA<MCPException>()),
        );
      });
      
      test('should throw exception for unregistered named service', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('default', 1),
        );
        
        // Default should work
        expect(container.get<TestServiceInterface>(), isNotNull);
        
        // Named should throw
        expect(
          () => container.get<TestServiceInterface>(name: 'missing'),
          throwsA(isA<MCPException>()),
        );
      });
      
      test('should handle factory exceptions gracefully', () {
        container.registerFactory<TestServiceInterface>(
          () => throw Exception('Factory error'),
        );
        
        expect(
          () => container.get<TestServiceInterface>(),
          throwsA(isA<Exception>()),
        );
      });
      
      test('should handle singleton factory exceptions gracefully', () {
        container.registerSingleton<TestServiceInterface>(
          () => throw Exception('Singleton factory error'),
        );
        
        expect(
          () => container.get<TestServiceInterface>(),
          throwsA(isA<Exception>()),
        );
        
        // Second call should also throw (no partial singleton creation)
        expect(
          () => container.get<TestServiceInterface>(),
          throwsA(isA<Exception>()),
        );
      });
    });
    
    group('Service Lifecycle Management', () {
      test('should check if service is registered', () {
        expect(container.isRegistered<TestServiceInterface>(), isFalse);
        
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('test', 1),
        );
        
        expect(container.isRegistered<TestServiceInterface>(), isTrue);
        expect(container.isRegistered<TestServiceInterface>(name: 'other'), isFalse);
      });
      
      test('should unregister services', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('test', 1),
        );
        
        expect(container.isRegistered<TestServiceInterface>(), isTrue);
        
        container.unregister<TestServiceInterface>();
        
        expect(container.isRegistered<TestServiceInterface>(), isFalse);
        expect(
          () => container.get<TestServiceInterface>(),
          throwsA(isA<MCPException>()),
        );
      });
      
      test('should unregister named services', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('default', 1),
        );
        
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('named', 2),
          name: 'special',
        );
        
        expect(container.isRegistered<TestServiceInterface>(), isTrue);
        expect(container.isRegistered<TestServiceInterface>(name: 'special'), isTrue);
        
        container.unregister<TestServiceInterface>(name: 'special');
        
        expect(container.isRegistered<TestServiceInterface>(), isTrue);
        expect(container.isRegistered<TestServiceInterface>(name: 'special'), isFalse);
      });
      
      test('should clear all registrations', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('test1', 1),
        );
        
        container.registerSingleton<TestRepository>(
          () => TestRepository(TestServiceImplementation('test2', 2)),
        );
        
        expect(container.isRegistered<TestServiceInterface>(), isTrue);
        expect(container.isRegistered<TestRepository>(), isTrue);
        
        container.clear();
        
        expect(container.isRegistered<TestServiceInterface>(), isFalse);
        expect(container.isRegistered<TestRepository>(), isFalse);
      });
    });
    
    group('Singleton Behavior Verification', () {
      test('should create singleton only once', () {
        var createCount = 0;
        
        container.registerSingleton<TestServiceInterface>(
          () {
            createCount++;
            return TestServiceImplementation('singleton_$createCount', createCount);
          },
        );
        
        // Multiple gets should only create once
        final instance1 = container.get<TestServiceInterface>();
        final instance2 = container.get<TestServiceInterface>();
        final instance3 = container.get<TestServiceInterface>();
        
        expect(createCount, equals(1));
        expect(identical(instance1, instance2), isTrue);
        expect(identical(instance2, instance3), isTrue);
        expect(instance1.getName(), equals('singleton_1'));
      });
      
      test('should track singleton state correctly', () {
        final disposableService = DisposableService();
        
        container.registerInstance<TestServiceInterface>(disposableService);
        
        final resolved = container.get<TestServiceInterface>();
        expect(identical(resolved, disposableService), isTrue);
        expect((resolved as DisposableService).isDisposed, isFalse);
        
        // Dispose the service
        disposableService.dispose();
        
        // Container should still return the same instance
        final resolvedAfterDispose = container.get<TestServiceInterface>();
        expect(identical(resolvedAfterDispose, disposableService), isTrue);
        expect((resolvedAfterDispose as DisposableService).isDisposed, isTrue);
      });
    });
    
    group('Performance and Load Testing', () {
      test('should handle many service registrations efficiently', () {
        const serviceCount = 100;
        
        // Register many services
        for (int i = 0; i < serviceCount; i++) {
          container.registerFactory<TestServiceInterface>(
            () => TestServiceImplementation('service_$i', i),
            name: 'service_$i',
          );
        }
        
        // Verify all are registered
        for (int i = 0; i < serviceCount; i++) {
          expect(container.isRegistered<TestServiceInterface>(name: 'service_$i'), isTrue);
        }
        
        // Resolve a few to verify they work
        final service0 = container.get<TestServiceInterface>(name: 'service_0');
        final service50 = container.get<TestServiceInterface>(name: 'service_50');
        final service99 = container.get<TestServiceInterface>(name: 'service_99');
        
        expect(service0.getName(), equals('service_0'));
        expect(service50.getValue(), equals(50));
        expect(service99.getName(), equals('service_99'));
      });
      
      test('should handle concurrent access safely', () async {
        container.registerSingleton<TestServiceInterface>(
          () => TestServiceImplementation('concurrent_service', 42),
        );
        
        // Concurrent resolution
        final futures = <Future<TestServiceInterface>>[];
        for (int i = 0; i < 10; i++) {
          futures.add(Future(() => container.get<TestServiceInterface>()));
        }
        
        final results = await Future.wait(futures);
        
        // All should be the same singleton instance
        for (int i = 1; i < results.length; i++) {
          expect(identical(results[i], results[0]), isTrue);
        }
        
        expect(results[0].getName(), equals('concurrent_service'));
      });
      
      test('should handle factory instance creation efficiently', () {
        var createCount = 0;
        
        container.registerFactory<TestServiceInterface>(
          () {
            createCount++;
            return TestServiceImplementation('factory_\$createCount', createCount);
          },
        );
        
        const instanceCount = 50;
        final instances = <TestServiceInterface>[];
        
        // Create many instances
        for (int i = 0; i < instanceCount; i++) {
          instances.add(container.get<TestServiceInterface>());
        }
        
        expect(createCount, equals(instanceCount));
        expect(instances.length, equals(instanceCount));
        
        // All should be different instances
        for (int i = 1; i < instances.length; i++) {
          expect(identical(instances[i], instances[0]), isFalse);
        }
      });
    });
    
    group('Edge Cases and Boundary Conditions', () {
      test('should handle null return from factory', () {
        // Using nullable type for testing null returns
        container.registerFactory<TestServiceInterface?>(
          () => null,
        );
        
        // Should return null
        final result = container.get<TestServiceInterface?>();
        expect(result, isNull);
      });
      
      test('should handle empty string as name', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('empty_name', 1),
          name: '',
        );
        
        final service = container.get<TestServiceInterface>(name: '');
        expect(service.getName(), equals('empty_name'));
      });
      
      test('should differentiate between null name and empty string name', () {
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('no_name', 1),
        );
        
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('empty_name', 2),
          name: '',
        );
        
        final noName = container.get<TestServiceInterface>();
        final emptyName = container.get<TestServiceInterface>(name: '');
        
        expect(noName.getValue(), equals(1));
        expect(emptyName.getValue(), equals(2));
        expect(identical(noName, emptyName), isFalse);
      });
      
      test('should handle service registration replacement', () {
        // Register first service
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('first', 1),
        );
        
        final first = container.get<TestServiceInterface>();
        expect(first.getName(), equals('first'));
        
        // Replace with second service
        container.registerFactory<TestServiceInterface>(
          () => TestServiceImplementation('second', 2),
        );
        
        final second = container.get<TestServiceInterface>();
        expect(second.getName(), equals('second'));
        expect(identical(second, first), isFalse);
      });
    });
  });
}