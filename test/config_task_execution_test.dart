import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/config_loader.dart';
import 'package:flutter_mcp/src/utils/logger.dart';

void main() {
  group('Configuration Task Execution Tests', () {
    setUpAll(() {
      FlutterMcpLogging.configure(level: Level.FINE, enableDebugLogging: true);
    });

    test('Parse schedule with various task types', () {
      final scheduleJson = [
        {
          'id': 'log_task',
          'name': 'Log Task',
          'intervalMinutes': 5,
          'taskType': 'log',
          'taskConfig': {'message': 'Test log message', 'level': 'info'}
        },
        {
          'id': 'health_check',
          'name': 'Health Check',
          'intervalMinutes': 15,
          'taskType': 'healthcheck',
          'taskConfig': {
            'checks': ['memory', 'connectivity']
          }
        },
        {
          'id': 'cleanup_task',
          'name': 'Cleanup Task',
          'intervalHours': 6,
          'taskType': 'cleanup',
          'taskConfig': {
            'targets': ['temp', 'cache']
          }
        },
        {
          'id': 'custom_task',
          'name': 'Custom Task',
          'intervalMinutes': 30,
          'taskType': 'custom',
          'taskConfig': {
            'command': 'data_sync',
            'parameters': {'endpoint': '/api/sync'}
          }
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(jobs!.length, equals(4));

      // Test log task
      expect(jobs[0].id, equals('log_task'));
      expect(jobs[0].name, equals('Log Task'));
      expect(jobs[0].interval, equals(Duration(minutes: 5)));

      // Test health check task
      expect(jobs[1].id, equals('health_check'));
      expect(jobs[1].interval, equals(Duration(minutes: 15)));

      // Test cleanup task
      expect(jobs[2].id, equals('cleanup_task'));
      expect(jobs[2].interval, equals(Duration(hours: 6)));

      // Test custom task
      expect(jobs[3].id, equals('custom_task'));
      expect(jobs[3].interval, equals(Duration(minutes: 30)));
    });

    test('Task execution without errors', () async {
      final scheduleJson = [
        {
          'id': 'test_log',
          'taskType': 'log',
          'taskConfig': {'message': 'Test execution', 'level': 'debug'}
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(jobs!.length, equals(1));

      // Execute task - should not throw
      expect(() => jobs[0].task(), returnsNormally);
    });

    test('Task execution with missing taskType', () async {
      final scheduleJson = [
        {
          'id': 'incomplete_task',
          'name': 'Incomplete Task',
          'intervalMinutes': 5
          // Missing taskType
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App", 
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(jobs!.length, equals(1));

      // Execute task - should handle missing taskType gracefully
      expect(() => jobs[0].task(), returnsNormally);
    });

    test('Health check task execution', () async {
      final scheduleJson = [
        {
          'id': 'health_test',
          'taskType': 'healthcheck',
          'taskConfig': {
            'checks': ['memory', 'connectivity', 'services']
          }
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0", 
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Cleanup task execution', () async {
      final scheduleJson = [
        {
          'id': 'cleanup_test',
          'taskType': 'cleanup',
          'taskConfig': {
            'targets': ['temp', 'cache', 'logs']
          }
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Notification task execution', () async {
      final scheduleJson = [
        {
          'id': 'notification_test',
          'taskType': 'notification',
          'taskConfig': {
            'title': 'Test Notification',
            'message': 'This is a test notification'
          }
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Memory check task execution', () async {
      final scheduleJson = [
        {
          'id': 'memory_test',
          'taskType': 'memory_check',
          'taskConfig': {'thresholdMB': 512}
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Performance report task execution', () async {
      final scheduleJson = [
        {
          'id': 'performance_test',
          'taskType': 'performance_report',
          'taskConfig': {'includeMemory': true, 'includeNetwork': false}
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Custom task execution', () async {
      final scheduleJson = [
        {
          'id': 'custom_test',
          'taskType': 'custom',
          'taskConfig': {
            'command': 'test_command',
            'parameters': {'param1': 'value1', 'param2': 42}
          }
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      expect(() => jobs![0].task(), returnsNormally);
    });

    test('Unknown task type fallback', () async {
      final scheduleJson = [
        {
          'id': 'unknown_test',
          'taskType': 'unknown_task_type',
          'taskConfig': {'someConfig': 'value'}
        }
      ];

      final jobs = ConfigLoader.loadFromString('''
{
  "appName": "Test App",
  "appVersion": "1.0.0",
  "schedule": ${jsonEncode(scheduleJson)}
}
''').schedule;

      expect(jobs, isNotNull);
      // Should fallback to custom task execution
      expect(() => jobs![0].task(), returnsNormally);
    });
  });
}
