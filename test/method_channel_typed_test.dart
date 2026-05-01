// Coverage tests for the typed methods on MethodChannelFlutterMcp:
// showNotificationTyped, executeBackgroundTaskTyped, requestPermissionTyped,
// getSystemInfoTyped — each routes through TypedPlatformChannel.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp_method_channel.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart' show MCPException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_mcp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelFlutterMcp impl;
  late List<MethodCall> calls;

  setUp(() {
    impl = MethodChannelFlutterMcp();
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelFlutterMcp.showNotificationTyped', () {
    test('forwards id/title/body and resolves on success-like response',
        () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        // Returning null becomes SuccessResponse via fromPlatformResponse.
        return null;
      });
      await impl.showNotificationTyped(
        id: 'n1',
        title: 't',
        body: 'b',
      );
      final call = calls.firstWhere((c) => c.method == 'showNotification');
      expect((call.arguments as Map)['id'], 'n1');
      expect((call.arguments as Map)['title'], 't');
      expect((call.arguments as Map)['body'], 'b');
    });

    test('PlatformException on the channel surfaces as MCPPlatformException',
        () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'BOOM', message: 'no');
      });
      await expectLater(
        impl.showNotificationTyped(id: 'n2', title: 't', body: 'b'),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('MethodChannelFlutterMcp.executeBackgroundTaskTyped', () {
    test('forwards taskId + data on success', () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return null;
      });
      await impl.executeBackgroundTaskTyped(
        taskId: 'task-1',
        data: {'k': 'v'},
      );
      final call =
          calls.firstWhere((c) => c.method == 'executeBackgroundTask');
      expect((call.arguments as Map)['taskId'], 'task-1');
      expect((call.arguments as Map)['data'], {'k': 'v'});
    });

    test('PlatformException on the channel surfaces as MCPPlatformException',
        () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'TASK_ERROR', message: 'failed');
      });
      await expectLater(
        impl.executeBackgroundTaskTyped(taskId: 't', data: {}),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('MethodChannelFlutterMcp.requestPermissionTyped', () {
    // The MethodChannel codec yields Map<Object?, Object?>, so
    // PlatformResponse.fromPlatformResponse falls through to SuccessResponse
    // and the typed wrapper raises MCPPlatformException(INVALID_RESPONSE).
    // Verify the throw branch + that the call still goes out.

    test('throws MCPPlatformException for non-PermissionResponse maps',
        () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return {
          'permission': 'notif',
          'granted': true,
        };
      });
      await expectLater(
        impl.requestPermissionTyped('notif'),
        throwsA(isA<MCPException>()),
      );
      expect(
        calls.any((c) => c.method == 'requestPermission'),
        isTrue,
      );
    });

    test('forwards optional rationale arg even when throwing', () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return {'permission': 'mic', 'granted': true};
      });
      try {
        await impl.requestPermissionTyped('mic', rationale: 'need it');
      } on MCPPlatformException {/* expected */}
      final call = calls.firstWhere((c) => c.method == 'requestPermission');
      expect((call.arguments as Map)['rationale'], 'need it');
    });
  });

  group('MethodChannelFlutterMcp.getSystemInfoTyped', () {
    test('throws MCPPlatformException for non-SystemInfoResponse maps',
        () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        return {
          'platform': 'ios',
          'version': '17',
          'capabilities': {'a': true},
        };
      });
      await expectLater(
        impl.getSystemInfoTyped(),
        throwsA(isA<MCPException>()),
      );
    });
  });
}
