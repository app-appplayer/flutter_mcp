import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/enhanced_resource_cleanup.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';
import 'package:flutter_mcp/src/utils/enhanced_error_handler.dart';

// WeakReference rejects primitives (string/int/bool/etc), so the registered
// resource type must be a proper Object instance.
class _Holder {
  final String value;
  _Holder(this.value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    EnhancedErrorHandler.instance.initialize();
    EnhancedResourceCleanup.instance.initialize();
  });

  // EnhancedResourceCleanup is a singleton. Clean every test by disposing
  // anything we registered in this test (best-effort).
  Future<void> cleanAll() async {
    final keys = EnhancedResourceCleanup.instance
        .getResourceDetails()
        .map((m) => m['key'] as String)
        .toList();
    for (final key in keys) {
      try {
        await EnhancedResourceCleanup.instance.disposeResource(key);
      } catch (_) {
        // best-effort cleanup
      }
    }
  }

  setUp(() async => cleanAll());
  tearDown(() async => cleanAll());

  group('EnhancedResourceAllocation', () {
    test('starts in allocated state and transitions through markActive/markDisposed/markFailed',
        () {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 5,
        allocatedAt: DateTime.now(),
        allocationStackTrace: StackTrace.current,
      );
      expect(a.id, 'r');
      expect(a.type, 'test');
      expect(a.memorySizeMB, 5);
      expect(a.state, ResourceState.registered);

      a.markActive();
      expect(a.state, ResourceState.active);

      a.markDisposed();
      expect(a.state, ResourceState.disposed);
    });

    test('markFailed transitions to failed', () {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 0,
        allocatedAt: DateTime.now(),
        allocationStackTrace: StackTrace.current,
      );
      a.markFailed();
      expect(a.state, ResourceState.failed);
    });

    test('isLeaked returns true when age exceeds threshold and not disposed',
        () {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 0,
        allocatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        allocationStackTrace: StackTrace.current,
      );
      a.markActive();
      expect(a.isLeaked(const Duration(minutes: 1)), isTrue);
    });

    test('isLeaked returns false when within threshold', () {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 0,
        allocatedAt: DateTime.now(),
        allocationStackTrace: StackTrace.current,
      );
      a.markActive();
      expect(a.isLeaked(const Duration(hours: 1)), isFalse);
    });

    test('isLeaked is false when already disposed', () {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 0,
        allocatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        allocationStackTrace: StackTrace.current,
      );
      a.markDisposed();
      expect(a.isLeaked(const Duration(minutes: 1)), isFalse);
    });

    test('age grows over time', () async {
      final a = EnhancedResourceAllocation(
        id: 'r',
        type: 'test',
        memorySizeMB: 0,
        allocatedAt: DateTime.now(),
        allocationStackTrace: StackTrace.current,
      );
      final t1 = a.age;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final t2 = a.age;
      expect(t2, greaterThan(t1));
    });
  });

  group('EnhancedDisposableResource', () {
    test('dispose runs the disposeFunction once', () async {
      var disposed = 0;
      final res = EnhancedDisposableResource<_Holder>(
        key: 'k',
        resource: _Holder('value'),
        disposeFunction: (v) async {
          disposed++;
        },
        priority: 100,
        allocation: EnhancedResourceAllocation(
          id: 'k',
          type: 'string',
          memorySizeMB: 0,
          allocatedAt: DateTime.now(),
          allocationStackTrace: StackTrace.current,
        ),
      );
      expect(res.isDisposed, isFalse);
      await res.dispose();
      expect(res.isDisposed, isTrue);
      // Second call is a no-op.
      await res.dispose();
      expect(disposed, 1);
    });
  });

  group('EnhancedResourceCleanup — register / dispose', () {
    test('registerResource adds an entry visible in details', () {
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'k1',
        resource: _Holder('value'),
        disposeFunction: (_) async {},
        type: 'string',
        priority: 100,
      );
      final details = EnhancedResourceCleanup.instance.getResourceDetails();
      expect(details.any((m) => m['key'] == 'k1'), isTrue);
    });

    test('disposeResource removes the entry', () async {
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'k2',
        resource: _Holder('1'),
        disposeFunction: (_) async {},
        type: 'int',
      );
      await EnhancedResourceCleanup.instance.disposeResource('k2');
      final details = EnhancedResourceCleanup.instance.getResourceDetails();
      expect(details.any((m) => m['key'] == 'k2'), isFalse);
    });

    test('disposeResource on unknown key is a no-op', () async {
      // Should not throw.
      await EnhancedResourceCleanup.instance.disposeResource('absent');
    });

    test('register with duplicate key disposes previous', () async {
      var firstDisposed = false;
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'dup',
        resource: _Holder('a'),
        disposeFunction: (_) async {
          firstDisposed = true;
        },
        type: 'string',
      );
      // Replacing with same key.
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'dup',
        resource: _Holder('b'),
        disposeFunction: (_) async {},
        type: 'string',
      );
      // Allow async fire-and-forget disposal to settle.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(firstDisposed, isTrue);
    });
  });

  group('EnhancedResourceCleanup — dependencies', () {
    test('dependent is disposed before dependency', () async {
      final order = <String>[];
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'parent',
        resource: _Holder('p'),
        disposeFunction: (_) async {
          order.add('parent');
        },
        type: 'parent',
      );
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'child',
        resource: _Holder('c'),
        disposeFunction: (_) async {
          order.add('child');
        },
        type: 'child',
        dependencies: const ['parent'],
      );

      await EnhancedResourceCleanup.instance.disposeResource('parent');
      // Disposing parent triggers child disposal first.
      expect(order.first, 'child');
    });

    test('circular dependency is rejected', () {
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'a',
        resource: _Holder('a'),
        disposeFunction: (_) async {},
        type: 't',
      );
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'b',
        resource: _Holder('b'),
        disposeFunction: (_) async {},
        type: 't',
        dependencies: const ['a'],
      );
      // Trying to make 'a' depend on 'b' would close a cycle.
      expect(
        () => EnhancedResourceCleanup.instance.registerResource<_Holder>(
          key: 'a',
          resource: _Holder('a'),
          disposeFunction: (_) async {},
          type: 't',
          dependencies: const ['b'],
        ),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('EnhancedResourceCleanup — disposeAll', () {
    test('disposes everything and reports zero registered after', () async {
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'd1',
        resource: _Holder('1'),
        disposeFunction: (_) async {},
        type: 't',
        priority: 50,
      );
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 'd2',
        resource: _Holder('2'),
        disposeFunction: (_) async {},
        type: 't',
        priority: 200,
      );
      await EnhancedResourceCleanup.instance.disposeAll();
      expect(
        EnhancedResourceCleanup.instance.getResourceDetails(),
        isEmpty,
      );
    });
  });

  group('EnhancedResourceCleanup — statistics + leak detection', () {
    test('getStatistics returns expected keys', () {
      EnhancedResourceCleanup.instance.registerResource<_Holder>(
        key: 's1',
        resource: _Holder('1'),
        disposeFunction: (_) async {},
        type: 'tcp',
      );
      final stats = EnhancedResourceCleanup.instance.getStatistics();
      expect(stats, contains('totalRegistered'));
      expect(stats, contains('currentActive'));
      expect(stats, contains('failedDisposals'));
      expect(stats, contains('leaksDetected'));
      expect(stats, contains('resourcesByType'));
      expect(stats, contains('resourcesByPriority'));
    });

    test('checkForLeaks does not throw and is idempotent', () {
      // Even with no resources, the method should run cleanly.
      EnhancedResourceCleanup.instance.checkForLeaks();
      EnhancedResourceCleanup.instance.checkForLeaks();
    });
  });

  group('ResourceGuard', () {
    test('use(callback) returns the callback result', () async {
      final guard = ResourceGuard<_Holder>(
        key: 'guarded',
        resource: _Holder('hello'),
        disposeFunction: (_) async {},
        type: 't',
      );
      final length = await guard.use((h) async => h.value.length);
      expect(length, 5);
      await guard.dispose();
    });

    test('use after dispose throws', () async {
      final guard = ResourceGuard<_Holder>(
        key: 'guarded2',
        resource: _Holder('1'),
        disposeFunction: (_) async {},
        type: 't',
      );
      await guard.dispose();
      await expectLater(
        guard.use((v) async => v),
        throwsA(isA<MCPException>()),
      );
    });

    test('dispose is idempotent', () async {
      final guard = ResourceGuard<_Holder>(
        key: 'guarded3',
        resource: _Holder('1'),
        disposeFunction: (_) async {},
        type: 't',
      );
      await guard.dispose();
      await guard.dispose();
    });
  });
}
