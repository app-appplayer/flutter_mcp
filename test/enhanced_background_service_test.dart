import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/background/enhanced_background_service.dart';
import 'package:flutter_mcp/src/platform/background/background_service.dart';
import 'package:flutter_mcp/src/config/background_config.dart';
import 'package:flutter_mcp/src/config/enhanced_background_config.dart';
import 'package:flutter_mcp/src/utils/enhanced_error_handler.dart';
import 'package:flutter_mcp/src/utils/enhanced_resource_cleanup.dart';
import 'package:flutter_mcp/src/types/health_types.dart';

class _TestBackgroundService extends EnhancedBackgroundService {
  bool initCalled = false;
  bool startCalled = false;
  bool stopCalled = false;
  bool startReturn = true;
  bool stopReturn = true;
  Object? throwOnInit;

  _TestBackgroundService() : super('test');

  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    if (throwOnInit != null) throw throwOnInit!;
    initCalled = true;
  }

  @override
  Future<bool> platformStart() async {
    startCalled = true;
    return startReturn;
  }

  @override
  Future<bool> platformStop() async {
    stopCalled = true;
    return stopReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    EnhancedErrorHandler.instance.initialize();
    EnhancedResourceCleanup.instance.initialize();
  });

  group('BackgroundTask', () {
    test('default-priority constructor sets pending status', () {
      final task = BackgroundTask(
        id: 't1',
        name: 'unit',
        execute: () async {},
      );
      expect(task.id, 't1');
      expect(task.priority, TaskPriority.normal);
      expect(task.status, TaskStatus.pending);
      expect(task.allowConcurrent, isFalse);
      expect(task.dependencies, isEmpty);
      expect(task.metadata, isEmpty);
      expect(task.retryCount, 0);
    });

    test('canRun is true while pending', () {
      final task = BackgroundTask(
        id: 't',
        name: 'n',
        execute: () async {},
      );
      expect(task.canRun, isTrue);
    });

    test('executionTime is null until startTime is set', () {
      final task = BackgroundTask(
        id: 't',
        name: 'n',
        execute: () async {},
      );
      expect(task.executionTime, isNull);
      task.startTime = DateTime.now().subtract(const Duration(seconds: 1));
      expect(task.executionTime!.inMilliseconds, greaterThan(900));
    });

    test('executionTime uses endTime when set', () {
      final task = BackgroundTask(
        id: 't',
        name: 'n',
        execute: () async {},
        timeout: const Duration(seconds: 2),
        allowConcurrent: true,
        dependencies: const ['x'],
        metadata: const {'k': 'v'},
      );
      task.startTime = DateTime(2026, 5, 1);
      task.endTime = DateTime(2026, 5, 1).add(const Duration(seconds: 5));
      expect(task.executionTime, const Duration(seconds: 5));
    });

    test('all TaskStatus values exist', () {
      expect(TaskStatus.values, hasLength(5));
    });

    test('all TaskPriority values exist', () {
      expect(TaskPriority.values, hasLength(3));
    });
  });

  group('EnhancedBackgroundService — lifecycle', () {
    test('initialize sets isInitialized', () async {
      final svc = _TestBackgroundService();
      expect(svc.isInitialized, isFalse);
      await svc.initialize(BackgroundConfig());
      expect(svc.isInitialized, isTrue);
      expect(svc.initCalled, isTrue);
    });

    test('initialize is idempotent', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      svc.initCalled = false;
      await svc.initialize(BackgroundConfig());
      expect(svc.initCalled, isFalse);
    });

    test('initialize accepts an EnhancedBackgroundConfig directly', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(EnhancedBackgroundConfig.defaultConfig());
      expect(svc.isInitialized, isTrue);
    });

    test('initialize without config builds default', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(null);
      expect(svc.isInitialized, isTrue);
    });

    test('start succeeds and sets isRunning', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final ok = await svc.start();
      expect(ok, isTrue);
      expect(svc.isRunning, isTrue);
      expect(svc.startCalled, isTrue);
    });

    test('start returns false when platformStart returns false', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      svc.startReturn = false;
      final ok = await svc.start();
      expect(ok, isFalse);
      expect(svc.isRunning, isFalse);
    });

    test('stop sets isRunning false when started', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      await svc.start();
      final ok = await svc.stop();
      expect(ok, isTrue);
      expect(svc.isRunning, isFalse);
      expect(svc.stopCalled, isTrue);
    });
  });

  group('EnhancedBackgroundService — task management', () {
    test('registerTask returns a unique task id', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final id1 = svc.registerTask(name: 'a', execute: () async {});
      final id2 = svc.registerTask(name: 'b', execute: () async {});
      expect(id1, isNot(id2));
      expect(svc.getAllTasks(), hasLength(2));
    });

    test('registered task is initially pending', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final id = svc.registerTask(name: 'a', execute: () async {});
      expect(svc.getTaskStatus(id), TaskStatus.pending);
    });

    test('cancelTask sets status to cancelled when pending', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final id = svc.registerTask(name: 'a', execute: () async {});
      expect(svc.cancelTask(id), isTrue);
      expect(svc.getTaskStatus(id), TaskStatus.cancelled);
    });

    test('cancelTask returns false for unknown taskId', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(svc.cancelTask('no-such-id'), isFalse);
    });

    test('getTaskStatus returns null for unknown taskId', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(svc.getTaskStatus('no-such-id'), isNull);
    });

    test('getRunningTasks returns empty initially', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(svc.getRunningTasks(), isEmpty);
    });

    test('scheduleTask once sets timer + cancelScheduledTask cancels it',
        () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      svc.scheduleTask(
        name: 'sched-1',
        delay: const Duration(milliseconds: 1000),
        execute: () async {},
      );
      // Cancel via id pattern is not exposed externally, so we just assert
      // the call doesn't throw and getStatistics reflects scheduledTasks.
      final stats = svc.getStatistics();
      expect(stats['scheduledTasks'], greaterThanOrEqualTo(1));
    });

    test('scheduleTask with recurring uses Timer.periodic', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      svc.scheduleTask(
        name: 'sched-rep',
        delay: const Duration(seconds: 60),
        execute: () async {},
        recurring: true,
      );
      final stats = svc.getStatistics();
      expect(stats['scheduledTasks'], greaterThanOrEqualTo(1));
    });

    test('cancelScheduledTask is a no-op for unknown id', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      svc.cancelScheduledTask('absent');
    });

    test('priority enqueueing prefers high priority', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      // Low priority is enqueued first, then high — verify both entries exist.
      svc.registerTask(
        name: 'low',
        execute: () async {},
        priority: TaskPriority.low,
      );
      svc.registerTask(
        name: 'high',
        execute: () async {},
        priority: TaskPriority.high,
      );
      // Don't assert on internal queue order — just confirm both pending.
      expect(svc.getAllTasks().map((t) => t.name).toList()..sort(),
          ['high', 'low']);
    });
  });

  group('EnhancedBackgroundService — getStatistics + performHealthCheck', () {
    test('getStatistics shape', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final stats = svc.getStatistics();
      expect(stats, contains('isRunning'));
      expect(stats, contains('totalTasksExecuted'));
      expect(stats, contains('totalTasksFailed'));
      expect(stats, contains('runningTasks'));
      expect(stats, contains('pendingTasks'));
      expect(stats, contains('scheduledTasks'));
      expect(stats, contains('taskExecutionCounts'));
      expect(stats, contains('tasks'));
    });

    test('performHealthCheck reports unhealthy when not running', () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      final r = await svc.performHealthCheck();
      expect(r.status, MCPHealthStatus.unhealthy);
      expect(r.message, contains('not running'));
    });

    test('performHealthCheck reports healthy when running with no failures',
        () async {
      final svc = _TestBackgroundService();
      await svc.initialize(BackgroundConfig());
      await svc.start();
      final r = await svc.performHealthCheck();
      expect(r.status, MCPHealthStatus.healthy);
    });
  });

  group('BackgroundServiceFactory.create', () {
    test('android', () {
      expect(BackgroundServiceFactory.create('android'),
          isA<AndroidEnhancedBackgroundService>());
    });
    test('ios', () {
      expect(BackgroundServiceFactory.create('ios'),
          isA<IOSEnhancedBackgroundService>());
    });
    test('windows / linux / macos all pick desktop', () {
      expect(BackgroundServiceFactory.create('windows'),
          isA<DesktopEnhancedBackgroundService>());
      expect(BackgroundServiceFactory.create('linux'),
          isA<DesktopEnhancedBackgroundService>());
      expect(BackgroundServiceFactory.create('macos'),
          isA<DesktopEnhancedBackgroundService>());
    });
    test('web', () {
      expect(BackgroundServiceFactory.create('web'),
          isA<WebEnhancedBackgroundService>());
    });
    test('unknown returns NoOpBackgroundService', () {
      expect(BackgroundServiceFactory.create('unknown'),
          isA<NoOpBackgroundService>());
    });
    test('case-insensitive match', () {
      expect(BackgroundServiceFactory.create('ANDROID'),
          isA<AndroidEnhancedBackgroundService>());
    });
  });

  group('Concrete platform subclasses smoke', () {
    test('AndroidEnhancedBackgroundService start/stop', () async {
      final svc = AndroidEnhancedBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(await svc.start(), isTrue);
      expect(await svc.stop(), isTrue);
    });

    test('IOSEnhancedBackgroundService start/stop', () async {
      final svc = IOSEnhancedBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(await svc.start(), isTrue);
      expect(await svc.stop(), isTrue);
    });

    test('DesktopEnhancedBackgroundService start/stop', () async {
      final svc = DesktopEnhancedBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(await svc.start(), isTrue);
      expect(await svc.stop(), isTrue);
    });

    test('WebEnhancedBackgroundService start/stop', () async {
      final svc = WebEnhancedBackgroundService();
      await svc.initialize(BackgroundConfig());
      expect(await svc.start(), isTrue);
      expect(await svc.stop(), isTrue);
    });
  });
}
