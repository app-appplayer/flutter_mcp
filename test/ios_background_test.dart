// Smoke coverage for IOSBackgroundService — class doesn't gate on
// Platform.isIOS, so all paths run from a macOS host once the channel
// is mocked.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/background/ios_background.dart';
import 'package:flutter_mcp/src/config/background_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool failStart;
  late bool failStop;
  late bool failSchedule;
  late bool failCancel;

  setUp(() {
    calls = [];
    failStart = false;
    failStop = false;
    failSchedule = false;
    failCancel = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'configureBackgroundService':
          return true;
        case 'startBackgroundService':
          if (failStart) throw PlatformException(code: 's');
          return true;
        case 'stopBackgroundService':
          if (failStop) throw PlatformException(code: 'st');
          return true;
        case 'scheduleBackgroundTask':
          if (failSchedule) throw PlatformException(code: 'sch');
          return true;
        case 'cancelBackgroundTask':
          if (failCancel) throw PlatformException(code: 'cn');
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('IOSBackgroundService — initialize / configure', () {
    test('initialize without config uses defaults', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      expect(calls.map((c) => c.method), contains('initialize'));
      s.dispose();
    });

    test('initialize warns about minimum interval', () async {
      final s = IOSBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 5000));
      // Just verify it doesn't throw and fires the native init.
      expect(calls.map((c) => c.method), contains('initialize'));
      s.dispose();
    });

    test('configure adjusts <15min interval up to 15min', () async {
      final s = IOSBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 5000));
      calls.clear();
      await s.configure();
      final cfg = calls
          .firstWhere((c) => c.method == 'configureBackgroundService')
          .arguments as Map;
      expect(cfg['intervalMs'], 900000); // bumped up to 15 minutes
      s.dispose();
    });

    test('configure preserves >=15min interval', () async {
      final s = IOSBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1800000));
      calls.clear();
      await s.configure();
      final cfg = calls
          .firstWhere((c) => c.method == 'configureBackgroundService')
          .arguments as Map;
      expect(cfg['intervalMs'], 1800000);
      s.dispose();
    });
  });

  group('IOSBackgroundService — start / stop', () {
    test('start returns true and updates isRunning', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      final r = await s.start();
      expect(r, isTrue);
      expect(s.isRunning, isTrue);
      s.dispose();
    });

    test('start returns false when native throws', () async {
      failStart = true;
      final s = IOSBackgroundService();
      await s.initialize(null);
      expect(await s.start(), isFalse);
      s.dispose();
    });

    test('stop clears isRunning', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      await s.start();
      expect(s.isRunning, isTrue);
      final r = await s.stop();
      expect(r, isTrue);
      expect(s.isRunning, isFalse);
      s.dispose();
    });

    test('stop returns false when native throws', () async {
      failStop = true;
      final s = IOSBackgroundService();
      await s.initialize(null);
      expect(await s.stop(), isFalse);
      s.dispose();
    });
  });

  group('IOSBackgroundService — task scheduling', () {
    test('scheduleTask adjusts <15min delay up to 15min', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      calls.clear();
      await s.scheduleTask('t1', const Duration(seconds: 30), () {});
      final cfg = calls
          .firstWhere((c) => c.method == 'scheduleBackgroundTask')
          .arguments as Map;
      expect(cfg['taskId'], 't1');
      expect(cfg['delayMillis'], 900000); // 15 minutes
      s.dispose();
    });

    test('scheduleTask preserves >=15min delay', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      calls.clear();
      await s.scheduleTask('t2', const Duration(minutes: 30), () {});
      final cfg = calls
          .firstWhere((c) => c.method == 'scheduleBackgroundTask')
          .arguments as Map;
      expect(cfg['delayMillis'], 30 * 60 * 1000);
      s.dispose();
    });

    test('scheduleTask swallows native errors', () async {
      failSchedule = true;
      final s = IOSBackgroundService();
      await s.initialize(null);
      // Should not throw — error is logged.
      await s.scheduleTask('t3', const Duration(minutes: 20), () {});
      s.dispose();
    });

    test('cancelTask routes to native', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      await s.scheduleTask('cn1', const Duration(minutes: 20), () {});
      calls.clear();
      await s.cancelTask('cn1');
      final cfg = calls
          .firstWhere((c) => c.method == 'cancelBackgroundTask')
          .arguments as Map;
      expect(cfg['taskId'], 'cn1');
      s.dispose();
    });

    test('cancelTask swallows native errors', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      failCancel = true;
      await s.cancelTask('cn-bad'); // should not throw
      s.dispose();
    });
  });

  group('IOSBackgroundService — dispose', () {
    test('dispose is idempotent', () async {
      final s = IOSBackgroundService();
      await s.initialize(null);
      s.dispose();
      s.dispose(); // should not throw
    });
  });
}
