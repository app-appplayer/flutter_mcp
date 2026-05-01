import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/background_job.dart';

void main() {
  group('Job', () {
    test('constructs with required fields and defaults', () {
      final job = Job(name: 'daily-cleanup', cronExpression: '0 0 * * *');
      expect(job.name, 'daily-cleanup');
      expect(job.cronExpression, '0 0 * * *');
      expect(job.enabled, isTrue);
      expect(job.priority, isNull);
      expect(job.runOnBoot, isFalse);
      expect(job.maxExecutionTime, isNull);
      expect(job.retryOnFailure, isTrue);
      expect(job.maxRetries, 3);
      expect(job.metadata, isNull);
    });

    test('constructs with all fields', () {
      final job = Job(
        name: 'sync',
        cronExpression: '*/5 * * * *',
        enabled: false,
        priority: 'high',
        runOnBoot: true,
        maxExecutionTime: const Duration(minutes: 10),
        retryOnFailure: false,
        maxRetries: 5,
        metadata: {'owner': 'platform'},
      );
      expect(job.enabled, isFalse);
      expect(job.priority, 'high');
      expect(job.runOnBoot, isTrue);
      expect(job.maxExecutionTime, const Duration(minutes: 10));
      expect(job.retryOnFailure, isFalse);
      expect(job.maxRetries, 5);
      expect(job.metadata, {'owner': 'platform'});
    });

    group('toJson', () {
      test('serializes minimal job', () {
        final job = Job(name: 'x', cronExpression: '* * * * *');
        final json = job.toJson();
        expect(json['name'], 'x');
        expect(json['cronExpression'], '* * * * *');
        expect(json['enabled'], isTrue);
        expect(json['priority'], isNull);
        expect(json['runOnBoot'], isFalse);
        expect(json['maxExecutionTimeMs'], isNull);
        expect(json['retryOnFailure'], isTrue);
        expect(json['maxRetries'], 3);
        expect(json['metadata'], isNull);
      });

      test('serializes job with all fields', () {
        final job = Job(
          name: 'full',
          cronExpression: '0 12 * * 1',
          enabled: false,
          priority: 'low',
          runOnBoot: true,
          maxExecutionTime: const Duration(seconds: 30),
          retryOnFailure: false,
          maxRetries: 0,
          metadata: {'k': 'v'},
        );
        final json = job.toJson();
        expect(json['enabled'], isFalse);
        expect(json['priority'], 'low');
        expect(json['runOnBoot'], isTrue);
        expect(json['maxExecutionTimeMs'], 30000);
        expect(json['retryOnFailure'], isFalse);
        expect(json['maxRetries'], 0);
        expect(json['metadata'], {'k': 'v'});
      });
    });

    group('fromJson', () {
      test('parses minimal payload using defaults', () {
        final job = Job.fromJson({
          'name': 'x',
          'cronExpression': '* * * * *',
        });
        expect(job.name, 'x');
        expect(job.cronExpression, '* * * * *');
        expect(job.enabled, isTrue);
        expect(job.priority, isNull);
        expect(job.runOnBoot, isFalse);
        expect(job.maxExecutionTime, isNull);
        expect(job.retryOnFailure, isTrue);
        expect(job.maxRetries, 3);
        expect(job.metadata, isNull);
      });

      test('parses full payload', () {
        final job = Job.fromJson({
          'name': 'full',
          'cronExpression': '0 12 * * 1',
          'enabled': false,
          'priority': 'low',
          'runOnBoot': true,
          'maxExecutionTimeMs': 60000,
          'retryOnFailure': false,
          'maxRetries': 7,
          'metadata': {'a': 1},
        });
        expect(job.enabled, isFalse);
        expect(job.priority, 'low');
        expect(job.runOnBoot, isTrue);
        expect(job.maxExecutionTime, const Duration(milliseconds: 60000));
        expect(job.retryOnFailure, isFalse);
        expect(job.maxRetries, 7);
        expect(job.metadata, {'a': 1});
      });

      test('roundtrips toJson → fromJson', () {
        final original = Job(
          name: 'rt',
          cronExpression: '* * * * *',
          priority: 'normal',
          runOnBoot: true,
          maxExecutionTime: const Duration(seconds: 5),
          metadata: const {'tag': 'r'},
        );
        final restored = Job.fromJson(original.toJson());
        expect(restored.name, original.name);
        expect(restored.cronExpression, original.cronExpression);
        expect(restored.enabled, original.enabled);
        expect(restored.priority, original.priority);
        expect(restored.runOnBoot, original.runOnBoot);
        expect(restored.maxExecutionTime, original.maxExecutionTime);
        expect(restored.retryOnFailure, original.retryOnFailure);
        expect(restored.maxRetries, original.maxRetries);
        expect(restored.metadata, original.metadata);
      });
    });

    group('validate', () {
      test('returns true for a valid job', () {
        expect(Job(name: 'ok', cronExpression: '* * * * *').validate(), isTrue);
      });

      test('returns false when name is empty', () {
        expect(Job(name: '', cronExpression: '* * * * *').validate(), isFalse);
      });

      test('returns false when cronExpression is empty', () {
        expect(Job(name: 'ok', cronExpression: '').validate(), isFalse);
      });

      test('returns false when maxRetries is negative', () {
        expect(
          Job(name: 'ok', cronExpression: '* * * * *', maxRetries: -1)
              .validate(),
          isFalse,
        );
      });

      test('returns true when maxRetries is zero', () {
        expect(
          Job(name: 'ok', cronExpression: '* * * * *', maxRetries: 0).validate(),
          isTrue,
        );
      });
    });
  });
}
