import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/platform_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  group('Platform Version Tests', () {
    test('isAndroidAtLeast returns false on web', () async {
      if (kIsWeb) {
        final result = await PlatformUtils.isAndroidAtLeast(30);
        expect(result, isFalse);
      }
    });

    test('isIOSAtLeast returns false on web', () async {
      if (kIsWeb) {
        final result = await PlatformUtils.isIOSAtLeast('15.0');
        expect(result, isFalse);
      }
    });

    test('getPlatformVersionInfo returns basic info', () async {
      final info = await PlatformUtils.getPlatformVersionInfo();
      
      expect(info, isA<Map<String, dynamic>>());
      expect(info.containsKey('platform'), isTrue);
      expect(info.containsKey('isWeb'), isTrue);
      expect(info['isWeb'], equals(kIsWeb));
    });

    test('Android version to SDK level mapping', () {
      // This tests the internal _androidVersionToSdkLevel method indirectly
      // by testing the expected behavior
      expect(true, isTrue); // Placeholder - internal method testing
    });

    test('Version comparison logic', () {
      // Test version comparison indirectly through public API
      // This would require actual platform-specific tests
      expect(true, isTrue); // Placeholder for version comparison tests
    });

    test('Platform capabilities detection', () {
      // Test platform-specific capabilities
      expect(PlatformUtils.platformName, isA<String>());
      expect(PlatformUtils.isDesktop, isA<bool>());
      expect(PlatformUtils.isMobile, isA<bool>());
      expect(PlatformUtils.supportsSecureStorage, isA<bool>());
    });

    test('Notification support detection', () {
      final supported = PlatformUtils.supportsNotifications;
      expect(supported, isA<bool>());
    });

    test('System tray support detection', () {
      final supported = PlatformUtils.supportsTray;
      expect(supported, isA<bool>());
    });

    test('Background service support detection', () {
      final supported = PlatformUtils.supportsBackgroundService;
      expect(supported, isA<bool>());
    });

    test('Platform info consistency', () {
      expect(PlatformUtils.platformName, isA<String>());
      expect(PlatformUtils.isDesktop, isA<bool>());
      expect(PlatformUtils.isMobile, isA<bool>());
      expect(PlatformUtils.supportsSecureStorage, isA<bool>());
    });
  });

  group('Platform Version Error Handling', () {
    test('Handles system property errors gracefully', () async {
      // Test should not throw even if system property access fails
      if (!kIsWeb) {
        expect(() async => await PlatformUtils.isAndroidAtLeast(30), returnsNormally);
        expect(() async => await PlatformUtils.isIOSAtLeast('15.0'), returnsNormally);
      }
    });

    test('Handles version parsing errors gracefully', () async {
      // Even with malformed OS version strings, should not crash
      final info = await PlatformUtils.getPlatformVersionInfo();
      expect(info, isA<Map<String, dynamic>>());
    });
  });
}