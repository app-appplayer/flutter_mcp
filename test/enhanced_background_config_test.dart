import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/config/enhanced_background_config.dart';
import 'package:flutter_mcp/src/config/background_config.dart';
import 'package:flutter_mcp/src/config/background_job.dart';

void main() {
  group('EnhancedBackgroundConfig — defaults', () {
    test('default constructor uses documented defaults', () {
      final c = EnhancedBackgroundConfig();
      expect(c.maxRetries, 3);
      expect(c.schedule, isNull);
      expect(c.requestBatteryOptimization, isFalse);
      expect(c.minBatteryLevel, 20);
      expect(c.requireCharging, isFalse);
      expect(c.requireWifi, isFalse);
      expect(c.taskTimeout, const Duration(minutes: 5));
      expect(c.enableCrashRecovery, isTrue);
      expect(c.enableTaskPersistence, isTrue);
    });

    test('defaultConfig factory yields a fully-populated config', () {
      final c = EnhancedBackgroundConfig.defaultConfig();
      expect(c.notificationChannelId, 'flutter_mcp_enhanced');
      expect(c.notificationChannelName, 'MCP Enhanced Service');
      expect(c.notificationTitle, 'MCP Service Running');
      expect(c.taskTimeout, const Duration(minutes: 5));
    });

    test('fromBase preserves base fields and uses Enhanced defaults for the rest',
        () {
      final base = BackgroundConfig(
        notificationChannelId: 'ch',
        notificationChannelName: 'name',
        notificationIcon: 'i',
        autoStartOnBoot: true,
        intervalMs: 12345,
        keepAlive: false,
      );
      final c = EnhancedBackgroundConfig.fromBase(base);
      expect(c.notificationChannelId, 'ch');
      expect(c.notificationChannelName, 'name');
      expect(c.notificationIcon, 'i');
      expect(c.autoStartOnBoot, isTrue);
      expect(c.intervalMs, 12345);
      expect(c.keepAlive, isFalse);
      // Defaults for new fields.
      expect(c.maxRetries, 3);
      expect(c.minBatteryLevel, 20);
    });
  });

  group('EnhancedBackgroundConfig.toJson', () {
    test('covers all extended fields', () {
      final c = EnhancedBackgroundConfig(
        maxRetries: 5,
        schedule: [
          Job(name: 'j', cronExpression: '* * * * *'),
        ],
        requestBatteryOptimization: true,
        minBatteryLevel: 50,
        requireCharging: true,
        requireWifi: true,
        taskTimeout: const Duration(seconds: 30),
        enableCrashRecovery: false,
        enableTaskPersistence: false,
      );
      final json = c.toJson();
      expect(json['maxRetries'], 5);
      expect(json['schedule'], hasLength(1));
      expect(json['requestBatteryOptimization'], isTrue);
      expect(json['minBatteryLevel'], 50);
      expect(json['requireCharging'], isTrue);
      expect(json['requireWifi'], isTrue);
      expect(json['taskTimeoutMs'], 30000);
      expect(json['enableCrashRecovery'], isFalse);
      expect(json['enableTaskPersistence'], isFalse);
    });

    test('schedule serialises to null when omitted', () {
      final c = EnhancedBackgroundConfig();
      expect(c.toJson()['schedule'], isNull);
    });
  });

  group('EnhancedBackgroundConfig.validate', () {
    test('returns true for sane defaults', () {
      expect(EnhancedBackgroundConfig().validate(), isTrue);
    });

    test('returns false when minBatteryLevel is below 0', () {
      expect(
        EnhancedBackgroundConfig(minBatteryLevel: -1).validate(),
        isFalse,
      );
    });

    test('returns false when minBatteryLevel is above 100', () {
      expect(
        EnhancedBackgroundConfig(minBatteryLevel: 101).validate(),
        isFalse,
      );
    });

    test('returns false when foreground service has no notification title',
        () {
      final c = EnhancedBackgroundConfig(enableForegroundService: true);
      expect(c.validate(), isFalse);
    });

    test('returns true when foreground service has a notification title', () {
      final c = EnhancedBackgroundConfig(
        enableForegroundService: true,
        notificationTitle: 'Running',
      );
      expect(c.validate(), isTrue);
    });

    test('returns false when an embedded job is invalid', () {
      final c = EnhancedBackgroundConfig(schedule: [
        Job(name: '', cronExpression: '* * * * *'), // empty name → invalid
      ]);
      expect(c.validate(), isFalse);
    });

    test('returns true when all embedded jobs are valid', () {
      final c = EnhancedBackgroundConfig(schedule: [
        Job(name: 'a', cronExpression: '* * * * *'),
        Job(name: 'b', cronExpression: '0 0 * * *'),
      ]);
      expect(c.validate(), isTrue);
    });
  });
}
