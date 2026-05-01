import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/platform_factory.dart';
import 'package:flutter_mcp/src/platform/background/background_service.dart';
import 'package:flutter_mcp/src/platform/notification/notification_manager.dart';
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart';
import 'package:flutter_mcp/src/platform/storage/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final factory = PlatformFactory();

  group('PlatformFactory — create*', () {
    test('createBackgroundService returns a BackgroundService', () {
      final svc = factory.createBackgroundService();
      expect(svc, isA<BackgroundService>());
    });

    test('createNotificationManager returns a NotificationManager', () {
      final m = factory.createNotificationManager();
      expect(m, isA<NotificationManager>());
    });

    test('createTrayManager returns a TrayManager', () {
      final t = factory.createTrayManager();
      expect(t, isA<TrayManager>());
    });

    test('createStorageManager returns a SecureStorageManager', () {
      final s = factory.createStorageManager();
      expect(s, isA<SecureStorageManager>());
    });
  });

  group('PlatformFactory — supportsFeature', () {
    test('exhaustive over PlatformFeature values', () {
      for (final f in PlatformFeature.values) {
        // Each call exercises a switch case; we don't assert specific
        // bools because they depend on the host platform.
        expect(factory.supportsFeature(f), isA<bool>());
      }
    });

    test('secureStorage is universally supported', () {
      expect(factory.supportsFeature(PlatformFeature.secureStorage), isTrue);
    });

    test('PlatformFeature enum has 4 values', () {
      expect(PlatformFeature.values, hasLength(4));
    });
  });

  group('PlatformFactory — platformName', () {
    test('returns a non-empty platform name', () {
      expect(factory.platformName, isNotEmpty);
      // On any supported test host the name is one of the documented set
      // (or "Unknown" as fallback).
      expect(
        ['Web', 'Android', 'iOS', 'Windows', 'macOS', 'Linux', 'Unknown'],
        contains(factory.platformName),
      );
    });
  });
}
