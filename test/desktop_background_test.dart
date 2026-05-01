// Smoke coverage for DesktopBackgroundService — exercises initialize,
// configure, start/stop, scheduleTask/cancelTask, registerTaskHandler,
// updateConfig, getStatistics, dispose.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/background/desktop_background.dart';
import 'package:flutter_mcp/src/config/background_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return;
  }

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool failStart;
  late bool failStop;

  setUp(() {
    calls = [];
    failStart = false;
    failStop = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'configureBackgroundService':
        case 'scheduleBackgroundTask':
        case 'cancelBackgroundTask':
          return true;
        case 'startBackgroundService':
          if (failStart) throw PlatformException(code: 's');
          return true;
        case 'stopBackgroundService':
          if (failStop) throw PlatformException(code: 'st');
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('DesktopBackgroundService — initialize / configure', () {
    test('initialize without config uses defaults + fires native init', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      expect(calls.map((c) => c.method), contains('initialize'));
      s.dispose();
    });

    test('configure stores callbacks + native config', () async {
      final s = DesktopBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 30000, keepAlive: false));
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
      expect(cfg['intervalMs'], 30000);
      expect(cfg['keepAlive'], false);
      s.dispose();
    });
  });

  group('DesktopBackgroundService — start / stop', () {
    test('start returns true and updates isRunning', () async {
      final s = DesktopBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 60000));
      expect(await s.start(), isTrue);
      expect(s.isRunning, isTrue);
      // Stop to clean up the periodic Timer.
      await s.stop();
      s.dispose();
    });

    test('start when already running returns false (warns)', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      await s.start();
      expect(await s.start(), isFalse);
      await s.stop();
      s.dispose();
    });

    test('start returns false when native throws', () async {
      failStart = true;
      final s = DesktopBackgroundService();
      await s.initialize(null);
      expect(await s.start(), isFalse);
      s.dispose();
    });

    test('stop when not running returns false', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      expect(await s.stop(), isFalse);
      s.dispose();
    });

    test('stop returns false when native throws', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      await s.start();
      failStop = true;
      expect(await s.stop(), isFalse);
      s.dispose();
    });
  });

  group('DesktopBackgroundService — task handler + scheduling', () {
    test('registerTaskHandler stores handler', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      s.registerTaskHandler(() async {});
      s.dispose();
    });

    test('scheduleTask routes to native', () async {
      final s = DesktopBackgroundService();
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

    test('cancelTask routes to native', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      await s.scheduleTask('t2', const Duration(hours: 1), () {});
      calls.clear();
      await s.cancelTask('t2');
      final cfg = calls
          .firstWhere((c) => c.method == 'cancelBackgroundTask')
          .arguments as Map;
      expect(cfg['taskId'], 't2');
      s.dispose();
    });
  });

  group('DesktopBackgroundService — updateConfig + getStatistics', () {
    test('updateConfig replaces config without restart when not running',
        () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      await s.updateConfig(BackgroundConfig(intervalMs: 12345));
      // No restart expected because service isn't running.
      s.dispose();
    });

    test('getStatistics returns running flag + counters', () async {
      final s = DesktopBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 60000));
      final stats = s.getStatistics();
      expect(stats['platform'], 'desktop');
      expect(stats['isRunning'], isFalse);
      expect(stats['taskExecutionCount'], 0);
      expect(stats['errorCount'], 0);
      s.dispose();
    });
  });

  group('DesktopBackgroundService — dispose', () {
    test('dispose is idempotent', () async {
      final s = DesktopBackgroundService();
      await s.initialize(null);
      s.dispose();
      s.dispose();
    });
  });
}
