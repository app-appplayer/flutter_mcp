import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/job.dart';

void main() {
  group('MCPJob — constructor + copyWith', () {
    test('default constructor sets fields', () {
      final j = MCPJob(
        id: 'j1',
        interval: const Duration(seconds: 1),
        task: () {},
      );
      expect(j.id, 'j1');
      expect(j.interval, const Duration(seconds: 1));
      expect(j.runOnce, isFalse);
      expect(j.paused, isFalse);
      expect(j.name, isNull);
      expect(j.description, isNull);
      expect(j.lastRun, isNull);
    });

    test('copyWith updates only specified fields', () {
      final j1 = MCPJob(
        interval: const Duration(seconds: 1),
        task: () {},
        name: 'orig',
      );
      final j2 = j1.copyWith(
        name: 'new',
        paused: true,
        runOnce: true,
        lastRun: DateTime(2026),
        description: 'd',
        id: 'id',
      );
      expect(j2.name, 'new');
      expect(j2.paused, isTrue);
      expect(j2.runOnce, isTrue);
      expect(j2.description, 'd');
      expect(j2.id, 'id');
      expect(j2.lastRun, DateTime(2026));
      expect(j2.interval, j1.interval);
    });

    test('copyWith with no args returns equivalent job', () {
      final j = MCPJob(
        interval: const Duration(seconds: 1),
        task: () {},
      );
      final c = j.copyWith();
      expect(c.interval, j.interval);
      expect(c.runOnce, j.runOnce);
    });

    test('toMap serializes the public state', () {
      final j = MCPJob(
        id: 'j1',
        interval: const Duration(seconds: 30),
        task: () {},
        name: 'n',
        description: 'd',
        runOnce: true,
        paused: true,
        lastRun: DateTime(2026, 5, 1),
      );
      final m = j.toMap();
      expect(m['id'], 'j1');
      expect(m['interval_ms'], 30000);
      expect(m['run_once'], isTrue);
      expect(m['paused'], isTrue);
      expect(m['name'], 'n');
      expect(m['description'], 'd');
      expect(m['last_run'], DateTime(2026, 5, 1).toIso8601String());
    });
  });

  group('MCPJob.every', () {
    test('runOnce is false', () {
      final j = MCPJob.every(
        const Duration(minutes: 5),
        task: () {},
        name: 'periodic',
      );
      expect(j.runOnce, isFalse);
      expect(j.interval, const Duration(minutes: 5));
      expect(j.name, 'periodic');
    });
  });

  group('MCPJob.once', () {
    test('runOnce is true', () {
      final j = MCPJob.once(
        const Duration(seconds: 10),
        task: () {},
      );
      expect(j.runOnce, isTrue);
    });
  });

  group('MCPJob.delayed', () {
    test('task and onComplete both fire when invoked', () {
      var taskRan = false;
      var completed = false;
      final j = MCPJob.delayed(
        const Duration(seconds: 1),
        task: () => taskRan = true,
        onComplete: () => completed = true,
      );
      j.task();
      expect(taskRan, isTrue);
      expect(completed, isTrue);
      expect(j.runOnce, isTrue);
    });

    test('works without onComplete', () {
      var taskRan = false;
      final j = MCPJob.delayed(
        const Duration(seconds: 1),
        task: () => taskRan = true,
      );
      j.task();
      expect(taskRan, isTrue);
    });
  });

  group('MCPJob.conditional', () {
    test('task runs when condition returns true', () {
      var taskRan = false;
      final j = MCPJob.conditional(
        const Duration(seconds: 1),
        task: () => taskRan = true,
        condition: () => true,
      );
      j.task();
      expect(taskRan, isTrue);
    });

    test('task is skipped when condition returns false', () {
      var taskRan = false;
      final j = MCPJob.conditional(
        const Duration(seconds: 1),
        task: () => taskRan = true,
        condition: () => false,
      );
      j.task();
      expect(taskRan, isFalse);
    });
  });
}
