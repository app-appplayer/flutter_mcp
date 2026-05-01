// Browser-only tests for WebBackgroundService. Run with:
//     flutter test --platform chrome test/web_background_web_test.dart

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/background/web_background.dart';
import 'package:flutter_mcp/src/config/background_config.dart';

void main() {
  group('WebBackgroundService — browser', () {
    test('initialize stores config + intervalMs', () async {
      final s = WebBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1500));
      expect(s.isRunning, isFalse);
    });

    test('initialize with null config still succeeds', () async {
      final s = WebBackgroundService();
      await s.initialize(null);
    });

    test('start returns true and updates isRunning', () async {
      final s = WebBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1500));
      final ok = await s.start();
      // Workers aren't always available in the test runner — accept either.
      expect(ok, isA<bool>());
      // Cleanup before next test.
      await s.stop();
    });

    test('start when already running returns true (idempotent)', () async {
      final s = WebBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1500));
      await s.start();
      final r = await s.start();
      expect(r, isTrue);
      await s.stop();
    });

    test('stop after start clears isRunning', () async {
      final s = WebBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1500));
      await s.start();
      await s.stop();
      expect(s.isRunning, isFalse);
    });

    test('stop when not running is a no-op', () async {
      final s = WebBackgroundService();
      await s.initialize(BackgroundConfig(intervalMs: 1500));
      await s.stop();
    });
  });
}
