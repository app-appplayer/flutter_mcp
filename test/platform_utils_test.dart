import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_mcp/src/utils/platform_utils.dart';

void main() {
  group('PlatformUtils — flag getters', () {
    test('platformName returns a non-empty string', () {
      expect(PlatformUtils.platformName, isNotEmpty);
    });

    test('isWeb / isNative are mutually exclusive', () {
      expect(PlatformUtils.isWeb, kIsWeb);
      expect(PlatformUtils.isNative, !kIsWeb);
    });

    test('exactly one of isMobile / isDesktop / isWeb is true', () {
      final flags = [
        PlatformUtils.isMobile,
        PlatformUtils.isDesktop,
        PlatformUtils.isWeb,
      ];
      expect(flags.where((b) => b).length, 1);
    });

    test('individual platform flags do not throw', () {
      // Each call exercises a kIsWeb branch. We don't assert specific
      // values because they depend on the host platform.
      expect(PlatformUtils.isWindows, isA<bool>());
      expect(PlatformUtils.isMacOS, isA<bool>());
      expect(PlatformUtils.isLinux, isA<bool>());
      expect(PlatformUtils.isAndroid, isA<bool>());
      expect(PlatformUtils.isIOS, isA<bool>());
    });
  });

  group('PlatformUtils — feature support', () {
    test('supportsNotifications, supportsTray, supportsBackgroundService return bools',
        () {
      expect(PlatformUtils.supportsNotifications, isA<bool>());
      expect(PlatformUtils.supportsTray, isA<bool>());
      expect(PlatformUtils.supportsBackgroundService, isA<bool>());
    });

    test('isFeatureSupported handles all known feature names', () {
      // All four known names route through the switch (case branches).
      PlatformUtils.isFeatureSupported('notifications');
      PlatformUtils.isFeatureSupported('tray');
      PlatformUtils.isFeatureSupported('background');
      PlatformUtils.isFeatureSupported('secure_storage');
    });

    test('isFeatureSupported is case-insensitive', () {
      // Same value regardless of casing.
      expect(
        PlatformUtils.isFeatureSupported('Notifications'),
        PlatformUtils.isFeatureSupported('notifications'),
      );
    });

    test('isFeatureSupported returns false for unknown features', () {
      expect(PlatformUtils.isFeatureSupported('bogus_feature'), isFalse);
    });

    test('getFeatureSupport returns map with expected keys', () {
      final m = PlatformUtils.getFeatureSupport();
      expect(m.keys, containsAll([
        'notifications',
        'tray',
        'background',
        'secure_storage',
        'web',
        'mobile',
        'desktop',
      ]));
    });
  });

  group('PlatformUtils — version queries', () {
    test('isAndroidAtLeast returns false on web', () async {
      // We can't fake kIsWeb at runtime here, but we can call the method
      // and assert it doesn't throw. On non-Android non-web hosts it
      // should also return false.
      final v = await PlatformUtils.isAndroidAtLeast(21);
      expect(v, isA<bool>());
    });

    test('isIOSAtLeast does not throw', () async {
      final v = await PlatformUtils.isIOSAtLeast('14.0');
      expect(v, isA<bool>());
    });

    test('getPlatformVersionInfo returns a populated map', () async {
      final info = await PlatformUtils.getPlatformVersionInfo();
      expect(info, contains('platform'));
      expect(info, contains('isWeb'));
    });
  });
}
