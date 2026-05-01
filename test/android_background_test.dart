// Smoke coverage for AndroidBackgroundService — class is host-agnostic;
// every public method runs once the channel is mocked.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/background/android_background.dart';
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

  group('AndroidBackgroundService — initialize / configure', () {
    test('initialize without config uses defaults', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      expect(calls.map((c) => c.method), contains('initialize'));
      s.dispose();
    });

    test('configure forwards channel + interval + keepAlive', () async {
      final s = AndroidBackgroundService();
      await s.initialize(BackgroundConfig(
        intervalMs: 60000,
        notificationChannelId: 'cid',
        notificationChannelName: 'cn',
        autoStartOnBoot: true,
        keepAlive: true,
      ));
      calls.clear();
      await s.configure(
        onStart: () {},
        onRepeat: (_) {},
        onDestroy: () {},
        onEvent: (_) {},
      );
      final cfg = calls
          .firstWhere((c) => c.method == 'configureBackgroundService')
          .arguments as Map;
      expect(cfg['intervalMs'], 60000);
      expect(cfg['channelId'], 'cid');
      expect(cfg['channelName'], 'cn');
      expect(cfg['autoStartOnBoot'], true);
      expect(cfg['keepAlive'], true);
      s.dispose();
    });
  });

  group('AndroidBackgroundService — start / stop', () {
    test('start updates isRunning to true on success', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      expect(await s.start(), isTrue);
      expect(s.isRunning, isTrue);
      s.dispose();
    });

    test('start returns false when native throws', () async {
      failStart = true;
      final s = AndroidBackgroundService();
      await s.initialize(null);
      expect(await s.start(), isFalse);
      s.dispose();
    });

    test('stop returns true and clears isRunning', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      await s.start();
      expect(await s.stop(), isTrue);
      expect(s.isRunning, isFalse);
      s.dispose();
    });

    test('stop returns false when native throws', () async {
      failStop = true;
      final s = AndroidBackgroundService();
      await s.initialize(null);
      expect(await s.stop(), isFalse);
      s.dispose();
    });
  });

  group('AndroidBackgroundService — task scheduling', () {
    test('scheduleTask routes to native', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      calls.clear();
      await s.scheduleTask('t1', const Duration(seconds: 5), () {});
      final cfg = calls
          .firstWhere((c) => c.method == 'scheduleBackgroundTask')
          .arguments as Map;
      expect(cfg['taskId'], 't1');
      expect(cfg['delayMillis'], 5000);
      s.dispose();
    });

    test('scheduleTask swallows native errors', () async {
      failSchedule = true;
      final s = AndroidBackgroundService();
      await s.initialize(null);
      await s.scheduleTask('t-bad', const Duration(seconds: 1), () {});
      s.dispose();
    });

    test('cancelTask routes to native', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      await s.scheduleTask('t2', const Duration(seconds: 5), () {});
      calls.clear();
      await s.cancelTask('t2');
      final cfg = calls
          .firstWhere((c) => c.method == 'cancelBackgroundTask')
          .arguments as Map;
      expect(cfg['taskId'], 't2');
      s.dispose();
    });

    test('cancelTask swallows native errors', () async {
      failCancel = true;
      final s = AndroidBackgroundService();
      await s.initialize(null);
      await s.cancelTask('absent');
      s.dispose();
    });
  });

  group('AndroidBackgroundService — dispose', () {
    test('dispose is idempotent', () async {
      final s = AndroidBackgroundService();
      await s.initialize(null);
      s.dispose();
      s.dispose();
    });
  });
}
