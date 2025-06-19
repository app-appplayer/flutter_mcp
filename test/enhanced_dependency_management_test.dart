import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/core/enhanced_dependency_injection.dart';
import 'package:flutter_mcp/src/utils/enhanced_resource_manager.dart';
import 'package:flutter_mcp/src/events/event_system.dart';
import 'dart:async';

void main() {
  group('Enhanced Dependency Management Tests', () {
    late EnhancedDIContainer diContainer;
    late EnhancedResourceManager resourceManager;

    setUp(() {
      diContainer = EnhancedDIContainer.instance;
      resourceManager = EnhancedResourceManager.instance;
    });

    tearDown(() async {
      await diContainer.clear();
      await resourceManager.shutdown();
    });

    group('Enhanced DI Container', () {
      test('should register and resolve services with dependencies', () async {
        // Register services with dependencies
        diContainer.register<DatabaseService>(
          factory: () => DatabaseService(),
          dependencies: [],
          onInitialize: (service) => service.connect(),
          onDispose: (service) => service.disconnect(),
        );

        diContainer.register<UserRepository>(
          factory: () => UserRepository(),
          dependencies: [DatabaseService],
          onInitialize: (repo) => repo.initialize(),
        );

        diContainer.register<UserService>(
          factory: () => UserService(),
          dependencies: [UserRepository],
          isSingleton: true,
        );

        // Get service - should initialize dependencies automatically
        final userService = await diContainer.get<UserService>();
        expect(userService, isNotNull);
        expect(userService, isA<UserService>());

        // Verify dependencies are initialized
        expect(diContainer.isInitialized<DatabaseService>(), isTrue);
        expect(diContainer.isInitialized<UserRepository>(), isTrue);
        expect(diContainer.isInitialized<UserService>(), isTrue);

        // Getting same service should return same instance (singleton)
        final userService2 = await diContainer.get<UserService>();
        expect(identical(userService, userService2), isTrue);
      });

      test('should detect circular dependencies', () {
        diContainer.register<ServiceA>(
          factory: () => ServiceA(),
          dependencies: [ServiceB],
        );

        expect(
          () => diContainer.register<ServiceB>(
            factory: () => ServiceB(),
            dependencies: [ServiceA],
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('should initialize all services in dependency order', () async {
        final initOrder = <String>[];

        diContainer.register<DatabaseService>(
          factory: () => DatabaseService(),
          onInitialize: (service) async {
            initOrder.add('DatabaseService');
            await service.connect();
          },
        );

        diContainer.register<UserRepository>(
          factory: () => UserRepository(),
          dependencies: [DatabaseService],
          onInitialize: (repo) async {
            initOrder.add('UserRepository');
            await repo.initialize();
          },
        );

        diContainer.register<UserService>(
          factory: () => UserService(),
          dependencies: [UserRepository],
          onInitialize: (service) async {
            initOrder.add('UserService');
          },
        );

        await diContainer.initializeAll();

        // Dependencies should be initialized before dependents
        expect(initOrder.indexOf('DatabaseService'),
            lessThan(initOrder.indexOf('UserRepository')));
        expect(initOrder.indexOf('UserRepository'),
            lessThan(initOrder.indexOf('UserService')));
      });

      test('should dispose all services in reverse dependency order', () async {
        final disposeOrder = <String>[];

        diContainer.register<DatabaseService>(
          factory: () => DatabaseService(),
          onDispose: (service) async {
            disposeOrder.add('DatabaseService');
            await service.disconnect();
          },
        );

        diContainer.register<UserRepository>(
          factory: () => UserRepository(),
          dependencies: [DatabaseService],
          onDispose: (repo) async {
            disposeOrder.add('UserRepository');
          },
        );

        diContainer.register<UserService>(
          factory: () => UserService(),
          dependencies: [UserRepository],
          onDispose: (service) async {
            disposeOrder.add('UserService');
          },
        );

        await diContainer.initializeAll();
        await diContainer.disposeAll();

        // Dependents should be disposed before dependencies
        expect(disposeOrder.indexOf('UserService'),
            lessThan(disposeOrder.indexOf('UserRepository')));
        expect(disposeOrder.indexOf('UserRepository'),
            lessThan(disposeOrder.indexOf('DatabaseService')));
      });

      test('should publish lifecycle events', () async {
        final lifecycleEvents = <ServiceLifecycleEvent>[];

        // Subscribe before any operations
        EventSystem.instance.subscribe<ServiceLifecycleEvent>((event) {
          // Only capture events for TestService
          if (event.serviceKey.contains('TestService')) {
            print(
                'Received lifecycle event: ${event.serviceKey} ${event.oldState} -> ${event.newState}');
            lifecycleEvents.add(event);
          }
        });

        // Wait a bit for subscription to be active
        await Future.delayed(Duration(milliseconds: 50));

        diContainer.register<TestService>(
          factory: () => TestService(),
          onInitialize: (service) => service.initialize(),
          onDispose: (service) => service.dispose(),
        );

        await diContainer.get<TestService>();
        await diContainer.disposeAll();

        // Allow more time for events to propagate
        await Future.delayed(Duration(milliseconds: 200));

        print('Total lifecycle events received: ${lifecycleEvents.length}');
        expect(lifecycleEvents.length, greaterThanOrEqualTo(2));

        final initializingEvent = lifecycleEvents.firstWhere(
          (e) => e.newState == ServiceLifecycle.initializing,
        );
        expect(initializingEvent.serviceKey, contains('TestService'));

        final initializedEvent = lifecycleEvents.firstWhere(
          (e) => e.newState == ServiceLifecycle.initialized,
        );
        expect(initializedEvent.serviceKey, contains('TestService'));
      });

      test('should provide comprehensive statistics', () async {
        diContainer.register<TestService>(factory: () => TestService());
        diContainer.register<AnotherService>(
            factory: () => AnotherService(), isSingleton: true);

        await diContainer.get<TestService>();
        await diContainer.get<AnotherService>();

        final stats = diContainer.getStatistics();

        expect(stats['registeredServices'], equals(2));
        expect(stats['initializedServices'], equals(2));
        expect(stats['singletonServices'], equals(1));
        expect(stats['circularDependencies'], equals(0));
      });
    });

    group('Enhanced Resource Manager', () {
      test('should register and dispose resources with dependencies', () async {
        var dbConnected = false;
        var repoInitialized = false;

        // Register database connection
        resourceManager.register<MockDatabase>(
          key: 'database',
          resource: MockDatabase(),
          initializeFunction: (db) async {
            await db.connect();
            dbConnected = true;
          },
          disposeFunction: (db) async {
            await db.disconnect();
            dbConnected = false;
          },
          type: ResourceType.database,
          priority: ResourcePriority.high,
        );

        // Register repository that depends on database
        resourceManager.register<MockRepository>(
          key: 'repository',
          resource: MockRepository(),
          dependencies: ['database'],
          initializeFunction: (repo) async {
            await repo.initialize();
            repoInitialized = true;
          },
          disposeFunction: (repo) async {
            await repo.cleanup();
            repoInitialized = false;
          },
          type: ResourceType.service,
        );

        await resourceManager.initialize('repository');

        expect(dbConnected, isTrue);
        expect(repoInitialized, isTrue);

        await resourceManager.dispose('repository');

        expect(repoInitialized, isFalse);
        expect(dbConnected,
            isTrue); // Database remains since it wasn't explicitly disposed

        // Now dispose the database explicitly
        await resourceManager.dispose('database');
        expect(dbConnected, isFalse);
      });

      test('should register stream subscriptions', () async {
        final controller = StreamController<int>();
        final receivedValues = <int>[];

        resourceManager.registerStream<int>(
          'test_stream',
          controller.stream,
          (value) => receivedValues.add(value),
          priority: ResourcePriority.normal,
          tags: ['stream', 'test'],
        );

        // Send some data
        controller.add(1);
        controller.add(2);
        controller.add(3);

        await Future.delayed(Duration(milliseconds: 10));

        expect(receivedValues, equals([1, 2, 3]));

        // Dispose should cancel subscription
        await resourceManager.dispose('test_stream');

        controller.add(4); // Should not be received
        await Future.delayed(Duration(milliseconds: 10));

        expect(receivedValues, equals([1, 2, 3]));

        await controller.close();
      });

      test('should register timers', () async {
        var timerFired = false;

        resourceManager.registerTimer(
          'test_timer',
          Duration(milliseconds: 50),
          () => timerFired = true,
          priority: ResourcePriority.low,
          tags: ['timer'],
        );

        // Wait for timer to fire
        await Future.delayed(Duration(milliseconds: 100));
        expect(timerFired, isTrue);

        await resourceManager.dispose('test_timer');
      });

      test('should dispose resources by group', () async {
        var disposed1 = false;
        var disposed2 = false;
        var disposed3 = false;

        resourceManager.register(
          key: 'resource1',
          resource: MockResource(),
          disposeFunction: (r) async => disposed1 = true,
          group: 'test_group',
        );

        resourceManager.register(
          key: 'resource2',
          resource: MockResource(),
          disposeFunction: (r) async => disposed2 = true,
          group: 'test_group',
        );

        resourceManager.register(
          key: 'resource3',
          resource: MockResource(),
          disposeFunction: (r) async => disposed3 = true,
          group: 'other_group',
        );

        await resourceManager.disposeGroup('test_group');

        expect(disposed1, isTrue);
        expect(disposed2, isTrue);
        expect(disposed3, isFalse);
      });

      test('should dispose resources by tag', () async {
        var disposed1 = false;
        var disposed2 = false;
        var disposed3 = false;

        resourceManager.register(
          key: 'resource1',
          resource: MockResource(),
          disposeFunction: (r) async => disposed1 = true,
          tags: ['cache', 'memory'],
        );

        resourceManager.register(
          key: 'resource2',
          resource: MockResource(),
          disposeFunction: (r) async => disposed2 = true,
          tags: ['cache', 'disk'],
        );

        resourceManager.register(
          key: 'resource3',
          resource: MockResource(),
          disposeFunction: (r) async => disposed3 = true,
          tags: ['network'],
        );

        await resourceManager.disposeTag('cache');

        expect(disposed1, isTrue);
        expect(disposed2, isTrue);
        expect(disposed3, isFalse);
      });

      test('should handle resource expiration', () async {
        resourceManager.register(
          key: 'expiring_resource',
          resource: MockResource(),
          maxLifetime: Duration(milliseconds: 100),
          autoDispose: true,
        );

        await resourceManager.initialize('expiring_resource');

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 150));

        // Auto-cleanup should have disposed the resource
        // Note: Auto-cleanup runs every 5 minutes in real usage,
        // but we test the logic directly
        final registration =
            resourceManager.getRegistration('expiring_resource');
        expect(registration?.isExpired, isTrue);
      });

      test('should publish resource lifecycle events', () async {
        final lifecycleEvents = <ResourceLifecycleEvent>[];

        EventSystem.instance.subscribe<ResourceLifecycleEvent>((event) {
          // Only capture events for our test resource
          if (event.resourceKey == 'test_resource') {
            lifecycleEvents.add(event);
          }
        });

        resourceManager.register<MockResource>(
          key: 'test_resource',
          resource: MockResource(),
          initializeFunction: (r) => r.initialize(),
          disposeFunction: (r) => r.cleanup(),
          type: ResourceType.service,
        );

        await resourceManager.initialize('test_resource');
        await resourceManager.dispose('test_resource');

        // Allow events to propagate
        await Future.delayed(Duration(milliseconds: 10));

        expect(lifecycleEvents.length, greaterThanOrEqualTo(3));

        final initializingEvent = lifecycleEvents.firstWhere(
          (e) => e.newState == ResourceLifecycle.initializing,
        );
        expect(initializingEvent.resourceKey, equals('test_resource'));
        expect(initializingEvent.resourceType, equals(ResourceType.service));
      });

      test('should provide comprehensive statistics', () async {
        // Ensure clean state
        await resourceManager.shutdown();

        resourceManager.register(
          key: 'resource1',
          resource: MockResource(),
          type: ResourceType.service,
          priority: ResourcePriority.high,
        );

        resourceManager.register(
          key: 'resource2',
          resource: MockDatabase(),
          type: ResourceType.database,
          priority: ResourcePriority.critical,
        );

        final stats = resourceManager.getStatistics();

        expect(stats['totalRegistered'], equals(2));
        expect(stats['currentCount'], equals(2));
        expect(stats['typeStats']['service'], equals(1));
        expect(stats['typeStats']['database'], equals(1));
        expect(stats['lifecycleStats']['registered'], equals(2));
      });
    });

    group('Integration Tests', () {
      test('should integrate DI container with resource manager', () async {
        // Register service in DI container that creates resources
        diContainer.register<ResourceCreatingService>(
          factory: () => ResourceCreatingService(resourceManager),
          onInitialize: (service) => service.createResources(),
          onDispose: (service) => service.cleanupResources(),
        );

        await diContainer.get<ResourceCreatingService>();

        // Service should have created resources
        expect(resourceManager.has('service_timer'), isTrue);
        expect(resourceManager.has('service_stream'), isTrue);

        // Dispose DI container should also clean up resources
        await diContainer.disposeAll();

        expect(resourceManager.has('service_timer'), isFalse);
        expect(resourceManager.has('service_stream'), isFalse);
      });
    });
  });
}

// Test services and resources
class TestService {
  bool initialized = false;
  bool disposed = false;

  Future<void> initialize() async {
    initialized = true;
  }

  Future<void> dispose() async {
    disposed = true;
  }
}

class AnotherService {
  bool initialized = false;
}

class DatabaseService {
  bool connected = false;

  Future<void> connect() async {
    connected = true;
  }

  Future<void> disconnect() async {
    connected = false;
  }
}

class UserRepository {
  bool initialized = false;

  Future<void> initialize() async {
    initialized = true;
  }
}

class UserService {
  bool initialized = false;
}

class ServiceA {
  bool initialized = false;
}

class ServiceB {
  bool initialized = false;
}

class MockResource {
  bool initialized = false;
  bool cleaned = false;

  Future<void> initialize() async {
    initialized = true;
  }

  Future<void> cleanup() async {
    cleaned = true;
  }
}

class MockDatabase {
  bool connected = false;

  Future<void> connect() async {
    connected = true;
  }

  Future<void> disconnect() async {
    connected = false;
  }
}

class MockRepository {
  bool initialized = false;

  Future<void> initialize() async {
    initialized = true;
  }

  Future<void> cleanup() async {
    initialized = false;
  }
}

class ResourceCreatingService {
  final EnhancedResourceManager _resourceManager;

  ResourceCreatingService(this._resourceManager);

  Future<void> createResources() async {
    // Create a timer resource
    _resourceManager.registerTimer(
      'service_timer',
      Duration(seconds: 1),
      () => {}, // Timer callback
      group: 'service_resources',
    );

    // Create a stream resource
    final controller = StreamController<String>();
    _resourceManager.registerStream<String>(
      'service_stream',
      controller.stream,
      (data) => {}, // Stream data handler
      group: 'service_resources',
    );
  }

  Future<void> cleanupResources() async {
    await _resourceManager.disposeGroup('service_resources');
  }
}
