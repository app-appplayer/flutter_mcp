import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp_platform_interface.dart';
import 'package:flutter_mcp/flutter_mcp_method_channel.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

// Concrete subclass that does NOT override any methods — used to drive
// the base-class UnimplementedError branches for coverage.
class _StubPlatform extends FlutterMcpPlatform {
  // No overrides: every base-class method should still throw
  // UnimplementedError. The only thing we need to do is call super() with
  // the platform-interface token by inheriting the default constructor.
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FlutterMcpPlatform is sticky — once set in this isolate it stays. We
  // capture and restore the existing instance so this test doesn't
  // permanently swap it out for any later tests in the same isolate.
  late FlutterMcpPlatform original;

  setUp(() {
    try {
      original = FlutterMcpPlatform.instance;
    } catch (_) {
      // Not initialized in this isolate yet — record a fresh impl so we
      // can restore deterministically.
      FlutterMcpPlatform.instance = MethodChannelFlutterMcp();
      original = FlutterMcpPlatform.instance;
    }
  });

  tearDown(() {
    FlutterMcpPlatform.instance = original;
  });

  test('setting and reading instance roundtrips a registered impl', () {
    final impl = MethodChannelFlutterMcp();
    FlutterMcpPlatform.instance = impl;
    expect(FlutterMcpPlatform.instance, same(impl));
  });

  group('base-class default implementations throw UnimplementedError', () {
    final stub = _StubPlatform();

    test('getPlatformVersion', () {
      expect(() => stub.getPlatformVersion(), throwsUnimplementedError);
    });

    test('initialize', () {
      expect(
        () => stub.initialize(MCPConfig(appName: 'a', appVersion: '0.0.1')),
        throwsUnimplementedError,
      );
    });

    test('startBackgroundService', () {
      expect(
        () => stub.startBackgroundService(),
        throwsUnimplementedError,
      );
    });

    test('stopBackgroundService', () {
      expect(
        () => stub.stopBackgroundService(),
        throwsUnimplementedError,
      );
    });

    test('isBackgroundServiceRunning', () {
      expect(
        () => stub.isBackgroundServiceRunning,
        throwsUnimplementedError,
      );
    });

    test('showNotification', () {
      expect(
        () => stub.showNotification(title: 'T', body: 'B'),
        throwsUnimplementedError,
      );
    });

    test('secureStore', () {
      expect(
        () => stub.secureStore('k', 'v'),
        throwsUnimplementedError,
      );
    });

    test('secureRead', () {
      expect(
        () => stub.secureRead('k'),
        throwsUnimplementedError,
      );
    });

    test('shutdown', () {
      expect(() => stub.shutdown(), throwsUnimplementedError);
    });

    test('checkPermission', () {
      expect(
        () => stub.checkPermission('p'),
        throwsUnimplementedError,
      );
    });

    test('requestPermission', () {
      expect(
        () => stub.requestPermission('p'),
        throwsUnimplementedError,
      );
    });

    test('requestPermissions', () {
      expect(
        () => stub.requestPermissions(['p']),
        throwsUnimplementedError,
      );
    });

    test('cancelAllNotifications', () {
      expect(
        () => stub.cancelAllNotifications(),
        throwsUnimplementedError,
      );
    });
  });
}
