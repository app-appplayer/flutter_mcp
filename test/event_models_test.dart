import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('MemoryEvent', () {
    test('eventType is memory.high', () {
      final e = MemoryEvent(currentMB: 100, thresholdMB: 200, peakMB: 150);
      expect(e.eventType, 'memory.high');
    });

    test('toMap → fromMap roundtrip', () {
      final ts = DateTime(2026, 5, 1, 12);
      final e = MemoryEvent(
        currentMB: 100,
        thresholdMB: 200,
        peakMB: 150,
        timestamp: ts,
      );
      final restored = MemoryEvent.fromMap(e.toMap());
      expect(restored.currentMB, 100);
      expect(restored.thresholdMB, 200);
      expect(restored.peakMB, 150);
      expect(restored.timestamp, ts);
    });
  });

  group('ServerEvent', () {
    test('eventType and toMap fields', () {
      final ts = DateTime(2026);
      final e = ServerEvent(
        serverId: 's1',
        status: ServerStatus.running,
        message: 'up',
        timestamp: ts,
        metadata: {'k': 'v'},
      );
      expect(e.eventType, 'server.status');
      final map = e.toMap();
      expect(map['serverId'], 's1');
      expect(map['status'], 'running');
      expect(map['message'], 'up');
      expect(map['metadata'], {'k': 'v'});
    });

    test('fromMap roundtrip', () {
      final ts = DateTime(2026);
      final original = ServerEvent(
        serverId: 's1',
        status: ServerStatus.starting,
        timestamp: ts,
      );
      final restored = ServerEvent.fromMap(original.toMap());
      expect(restored.serverId, 's1');
      expect(restored.status, ServerStatus.starting);
      expect(restored.message, isNull);
      expect(restored.timestamp, ts);
    });

    test('all ServerStatus enum values', () {
      expect(ServerStatus.values, hasLength(5));
      for (final status in ServerStatus.values) {
        final e = ServerEvent(serverId: 's', status: status);
        expect(e.toMap()['status'], status.name);
      }
    });
  });

  group('ClientEvent', () {
    test('eventType and roundtrip', () {
      final ts = DateTime(2026);
      final e = ClientEvent(
        clientId: 'c1',
        status: ClientStatus.connected,
        message: 'connected',
        serverUrl: 'http://example.com',
        timestamp: ts,
      );
      expect(e.eventType, 'client.status');
      final restored = ClientEvent.fromMap(e.toMap());
      expect(restored.clientId, 'c1');
      expect(restored.status, ClientStatus.connected);
      expect(restored.message, 'connected');
      expect(restored.serverUrl, 'http://example.com');
      expect(restored.timestamp, ts);
    });

    test('all ClientStatus enum values', () {
      expect(ClientStatus.values, hasLength(5));
    });
  });

  group('PerformanceEvent', () {
    test('eventType and roundtrip with capacity', () {
      final ts = DateTime(2026);
      final e = PerformanceEvent(
        metricName: 'cpu',
        value: 75.5,
        capacity: 100,
        type: MetricType.gauge,
        unit: '%',
        timestamp: ts,
      );
      expect(e.eventType, 'performance.metric');
      final restored = PerformanceEvent.fromMap(e.toMap());
      expect(restored.metricName, 'cpu');
      expect(restored.value, 75.5);
      expect(restored.capacity, 100);
      expect(restored.type, MetricType.gauge);
      expect(restored.unit, '%');
      expect(restored.timestamp, ts);
    });

    test('roundtrip without capacity', () {
      final e = PerformanceEvent(
        metricName: 'requests',
        value: 1.0,
        type: MetricType.counter,
      );
      final restored = PerformanceEvent.fromMap(e.toMap());
      expect(restored.capacity, isNull);
      expect(restored.unit, isNull);
    });

    test('all MetricType enum values', () {
      expect(MetricType.values, hasLength(4));
    });
  });

  group('ErrorEvent', () {
    test('eventType and full-field roundtrip', () {
      final ts = DateTime(2026);
      final e = ErrorEvent(
        errorCode: 'E001',
        message: 'oops',
        component: 'core',
        severity: ErrorSeverity.high,
        stackTrace: 'frame1\nframe2',
        context: {'arg': 1},
        timestamp: ts,
      );
      expect(e.eventType, 'error.occurred');
      final restored = ErrorEvent.fromMap(e.toMap());
      expect(restored.errorCode, 'E001');
      expect(restored.message, 'oops');
      expect(restored.component, 'core');
      expect(restored.severity, ErrorSeverity.high);
      expect(restored.stackTrace, 'frame1\nframe2');
      expect(restored.context, {'arg': 1});
      expect(restored.timestamp, ts);
    });

    test('roundtrip with optional fields null', () {
      final e = ErrorEvent(
        errorCode: 'E000',
        message: 'empty',
        severity: ErrorSeverity.low,
      );
      final restored = ErrorEvent.fromMap(e.toMap());
      expect(restored.component, isNull);
      expect(restored.stackTrace, isNull);
      expect(restored.context, isNull);
    });

    test('all ErrorSeverity enum values', () {
      expect(ErrorSeverity.values, hasLength(4));
    });

    test('all AlertSeverity enum values', () {
      expect(AlertSeverity.values, hasLength(5));
    });
  });

  group('SecurityEvent', () {
    test('eventType and roundtrip', () {
      final ts = DateTime(2026);
      final e = SecurityEvent(
        eventType_: 'login_failure',
        severity: AlertSeverity.medium,
        message: 'bad password',
        userId: 'u1',
        details: {'attempts': 3},
        timestamp: ts,
      );
      expect(e.eventType, 'security.event');
      final restored = SecurityEvent.fromMap(e.toMap());
      expect(restored.eventType_, 'login_failure');
      expect(restored.severity, AlertSeverity.medium);
      expect(restored.message, 'bad password');
      expect(restored.userId, 'u1');
      expect(restored.details, {'attempts': 3});
      expect(restored.timestamp, ts);
    });

    test('details defaults to empty map', () {
      final e = SecurityEvent(
        eventType_: 'x',
        severity: AlertSeverity.info,
        message: '',
      );
      expect(e.details, isEmpty);
    });

    test('fromMap with missing details treats as empty', () {
      final e = SecurityEvent(
        eventType_: 'x',
        severity: AlertSeverity.info,
        message: 'm',
      );
      final map = e.toMap();
      map.remove('details');
      // Even when serialised then re-loaded with details missing, fromMap
      // should normalise to empty map.
      final restored = SecurityEvent.fromMap(map);
      expect(restored.details, isEmpty);
    });
  });

  group('SecurityAlert', () {
    test('eventType and roundtrip', () {
      final e = SecurityAlert(
        severity: AlertSeverity.critical,
        title: 'breach',
        message: 'pwned',
        details: {'ip': '1.2.3.4'},
      );
      expect(e.eventType, 'security.alert');
      final restored = SecurityAlert.fromMap(e.toMap());
      expect(restored.severity, AlertSeverity.critical);
      expect(restored.title, 'breach');
      expect(restored.message, 'pwned');
      expect(restored.details, {'ip': '1.2.3.4'});
    });

    test('details defaults to empty map', () {
      final e = SecurityAlert(
        severity: AlertSeverity.info,
        title: 't',
        message: 'm',
      );
      expect(e.details, isEmpty);
    });
  });

  group('PluginEvent', () {
    test('eventType and roundtrip', () {
      final ts = DateTime(2026);
      final e = PluginEvent(
        pluginId: 'p1',
        version: '1.0',
        state: PluginLifecycleState.running,
        message: 'started',
        pluginMetadata: {'capabilities': ['x']},
        metadata: {'ext': 1},
        timestamp: ts,
      );
      expect(e.eventType, 'plugin.lifecycle');
      final restored = PluginEvent.fromMap(e.toMap());
      expect(restored.pluginId, 'p1');
      expect(restored.version, '1.0');
      expect(restored.state, PluginLifecycleState.running);
      expect(restored.message, 'started');
      expect(restored.pluginMetadata, {'capabilities': ['x']});
      expect(restored.metadata, {'ext': 1});
      expect(restored.timestamp, ts);
    });

    test('all PluginLifecycleState values', () {
      expect(PluginLifecycleState.values, hasLength(8));
      // round-trip every state
      for (final s in PluginLifecycleState.values) {
        final e = PluginEvent(pluginId: 'p', state: s);
        final restored = PluginEvent.fromMap(e.toMap());
        expect(restored.state, s);
      }
    });
  });

  group('BackgroundTaskEvent', () {
    test('eventType and roundtrip with all fields', () {
      final ts = DateTime(2026);
      final e = BackgroundTaskEvent(
        taskId: 't1',
        taskType: 'sync',
        status: TaskStatus.completed,
        message: 'done',
        duration: const Duration(milliseconds: 500),
        result: {'count': 10},
        timestamp: ts,
      );
      expect(e.eventType, 'background.task');
      final restored = BackgroundTaskEvent.fromMap(e.toMap());
      expect(restored.taskId, 't1');
      expect(restored.taskType, 'sync');
      expect(restored.status, TaskStatus.completed);
      expect(restored.message, 'done');
      expect(restored.duration, const Duration(milliseconds: 500));
      expect(restored.result, {'count': 10});
      expect(restored.timestamp, ts);
    });

    test('roundtrip without duration / result', () {
      final e = BackgroundTaskEvent(
        taskId: 't2',
        taskType: 'cleanup',
        status: TaskStatus.queued,
      );
      final restored = BackgroundTaskEvent.fromMap(e.toMap());
      expect(restored.duration, isNull);
      expect(restored.result, isNull);
      expect(restored.message, isNull);
    });

    test('all TaskStatus enum values', () {
      expect(TaskStatus.values, hasLength(5));
    });
  });

  group('AuthEvent', () {
    test('eventType and full roundtrip', () {
      final ts = DateTime(2026);
      final e = AuthEvent(
        userId: 'u1',
        action: AuthAction.login,
        success: true,
        reason: 'creds ok',
        ipAddress: '1.2.3.4',
        userAgent: 'tester',
        timestamp: ts,
      );
      expect(e.eventType, 'auth.event');
      final restored = AuthEvent.fromMap(e.toMap());
      expect(restored.userId, 'u1');
      expect(restored.action, AuthAction.login);
      expect(restored.success, isTrue);
      expect(restored.reason, 'creds ok');
      expect(restored.ipAddress, '1.2.3.4');
      expect(restored.userAgent, 'tester');
      expect(restored.timestamp, ts);
    });

    test('roundtrip with optional fields null', () {
      final e = AuthEvent(
        userId: 'u',
        action: AuthAction.logout,
        success: true,
      );
      final restored = AuthEvent.fromMap(e.toMap());
      expect(restored.reason, isNull);
      expect(restored.ipAddress, isNull);
      expect(restored.userAgent, isNull);
    });

    test('all AuthAction enum values', () {
      expect(AuthAction.values, hasLength(5));
      for (final a in AuthAction.values) {
        final e = AuthEvent(userId: 'u', action: a, success: false);
        final restored = AuthEvent.fromMap(e.toMap());
        expect(restored.action, a);
      }
    });
  });
}
