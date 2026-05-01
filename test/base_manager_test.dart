import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/core/base_manager.dart';
import 'package:flutter_mcp/src/types/health_types.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

class _TestManager extends BaseManager {
  bool initCalled = false;
  bool disposeCalled = false;
  Object? throwOnInit;

  _TestManager() : super('test_manager');

  @override
  Future<void> onInitialize() async {
    if (throwOnInit != null) throw throwOnInit!;
    initCalled = true;
  }

  @override
  Future<void> onDispose() async {
    disposeCalled = true;
    await super.onDispose();
  }
}

class _ConfigManager extends ConfigBasedManager<int> {
  final int? configValue;
  final bool failLoad;
  bool initCalled = false;

  _ConfigManager({this.configValue, this.failLoad = false})
      : super('config_test');

  @override
  Future<int> loadConfiguration() async {
    if (failLoad) throw StateError('load failure');
    if (configValue == null) {
      throw StateError('intentional null payload');
    }
    return configValue!;
  }

  @override
  void validateConfiguration(int config) {
    if (config < 0) {
      throw MCPConfigurationException('value must be non-negative');
    }
  }

  @override
  Future<void> initializeWithConfig(int config) async {
    initCalled = true;
  }
}

class _PlatformManager extends PlatformSpecificManager {
  final bool supported;

  _PlatformManager({required this.supported})
      : super('platform_test', 'macos');

  @override
  bool isPlatformSupported() => supported;

  @override
  Future<void> initializeForPlatform() async {}
}

class _ResourceManager extends ResourceManagingManager {
  final List<String> disposedKeys = [];

  _ResourceManager() : super('resource_test');

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> disposeResource(String resourceKey) async {
    disposedKeys.add(resourceKey);
  }
}

void main() {
  group('BaseManager — lifecycle', () {
    test('initialize sets isInitialized true and runs onInitialize', () async {
      final m = _TestManager();
      expect(m.isInitialized, isFalse);
      await m.initialize();
      expect(m.isInitialized, isTrue);
      expect(m.initCalled, isTrue);
    });

    test('initialize is a no-op when already initialized', () async {
      final m = _TestManager();
      await m.initialize();
      m.initCalled = false;
      await m.initialize();
      // onInitialize should not run a second time.
      expect(m.initCalled, isFalse);
    });

    test('initialize throws when called on disposed manager', () async {
      final m = _TestManager();
      await m.initialize();
      await m.dispose();
      await expectLater(m.initialize(), throwsA(isA<MCPException>()));
    });

    test('dispose sets isDisposed and clears initialized', () async {
      final m = _TestManager();
      await m.initialize();
      await m.dispose();
      expect(m.isDisposed, isTrue);
      expect(m.isInitialized, isFalse);
      expect(m.disposeCalled, isTrue);
    });

    test('dispose is a no-op when already disposed', () async {
      final m = _TestManager();
      await m.initialize();
      await m.dispose();
      m.disposeCalled = false;
      await m.dispose();
      expect(m.disposeCalled, isFalse);
    });

    test('uptime grows over time', () async {
      final m = _TestManager();
      final t1 = m.uptime;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final t2 = m.uptime;
      expect(t2, greaterThan(t1));
    });

    test('getStatus includes lifecycle fields', () async {
      final m = _TestManager();
      final status = m.getStatus();
      expect(status['managerName'], 'test_manager');
      expect(status, contains('initialized'));
      expect(status, contains('disposed'));
      expect(status, contains('createdAt'));
      expect(status, contains('uptime'));
    });

    test('ensureInitialized throws when not initialized', () {
      final m = _TestManager();
      expect(() => m.ensureInitialized(), throwsA(isA<MCPException>()));
    });

    test('ensureInitialized passes after initialize', () async {
      final m = _TestManager();
      await m.initialize();
      m.ensureInitialized();
    });

    test('restart on a disposed manager surfaces an MCPException', () async {
      // restart() calls dispose() then initialize(); initialize() rejects
      // a disposed manager, so the second leg surfaces an error. This is
      // existing behavior; the test pins it down so any future change to
      // restart's contract is intentional.
      final m = _TestManager();
      await m.initialize();
      await expectLater(m.restart(), throwsA(isA<MCPException>()));
    });
  });

  group('BaseManager — health check', () {
    test('reports unhealthy before initialization', () async {
      final m = _TestManager();
      final r = await m.performHealthCheck();
      expect(r.status, MCPHealthStatus.unhealthy);
      expect(r.message, contains('not initialized'));
    });

    test('reports healthy after initialization', () async {
      final m = _TestManager();
      await m.initialize();
      final r = await m.performHealthCheck();
      expect(r.status, MCPHealthStatus.healthy);
    });

    test('reports unhealthy after disposal', () async {
      // After dispose, _initialized is also reset to false, so the
      // not-initialized branch fires before the disposed-specific check.
      // Either message is acceptable — both signal unhealthy.
      final m = _TestManager();
      await m.initialize();
      await m.dispose();
      final r = await m.performHealthCheck();
      expect(r.status, MCPHealthStatus.unhealthy);
      expect(r.message, anyOf(contains('disposed'), contains('not initialized')));
    });
  });

  group('ManagerLifecycleEvent', () {
    test('eventType + toMap', () {
      final e = ManagerLifecycleEvent(
        managerName: 'm',
        state: 'initialized',
        metadata: {'k': 1},
      );
      expect(e.eventType, 'manager.lifecycle');
      final map = e.toMap();
      expect(map['eventType'], 'manager.lifecycle');
      expect(map['managerName'], 'm');
      expect(map['state'], 'initialized');
      expect(map['metadata'], {'k': 1});
    });
  });

  group('ConfigBasedManager', () {
    test('loads config and reports configured=true in getStatus', () async {
      final m = _ConfigManager(configValue: 42);
      await m.initialize();
      expect(m.config, 42);
      expect(m.isConfigured, isTrue);
      expect(m.initCalled, isTrue);
      expect(m.getStatus()['configured'], isTrue);
    });

    test('throws on configuration validation failure', () async {
      final m = _ConfigManager(configValue: -1);
      await expectLater(
        m.initialize(),
        throwsA(isA<MCPException>()),
      );
    });

    test('throws when loadConfiguration fails', () async {
      final m = _ConfigManager(failLoad: true);
      await expectLater(
        m.initialize(),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('PlatformSpecificManager', () {
    test('initializes when platform is supported', () async {
      final m = _PlatformManager(supported: true);
      await m.initialize();
      expect(m.isInitialized, isTrue);
      final status = m.getStatus();
      expect(status['platformName'], 'macos');
      expect(status['platformSupported'], isTrue);
    });

    test('throws when platform is not supported', () async {
      final m = _PlatformManager(supported: false);
      await expectLater(
        m.initialize(),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('ResourceManagingManager', () {
    test('register/unregister and dispose all on dispose', () async {
      final m = _ResourceManager();
      await m.initialize();
      m.registerManagedResource('a');
      m.registerManagedResource('b');
      expect(m.managedResources, ['a', 'b']);
      m.unregisterManagedResource('a');
      expect(m.managedResources, ['b']);
      await m.dispose();
      // Disposed in reverse order via the manager.
      expect(m.disposedKeys, ['b']);
      expect(m.managedResources, isEmpty);
    });

    test('getStatus reports managedResourceCount', () async {
      final m = _ResourceManager();
      m.registerManagedResource('x');
      expect(m.getStatus()['managedResourceCount'], 1);
      expect(m.getStatus()['managedResources'], ['x']);
    });
  });
}
