// Coverage tests for MethodChannelFlutterMcp event-handling paths —
// the native→Flutter dispatch in _handleMethodCall and the
// eventStream broadcast.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelFlutterMcp impl;

  setUp(() {
    impl = MethodChannelFlutterMcp();
  });

  group('MethodChannelFlutterMcp — _handleMethodCall', () {
    test('onBackgroundServiceStateChanged updates isRunning + emits event',
        () async {
      final futureEvent = impl.eventStream.first;

      // Simulate native sending the call to flutter.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        impl.methodChannel.name,
        impl.methodChannel.codec.encodeMethodCall(
          const MethodCall(
            'onBackgroundServiceStateChanged',
            {'isRunning': true},
          ),
        ),
        (_) {},
      );

      expect(impl.isBackgroundServiceRunning, isTrue);
      final event = await futureEvent;
      expect(event['type'], 'backgroundServiceStateChanged');
      expect((event['data'] as Map)['isRunning'], isTrue);
    });

    test('onBackgroundTaskResult emits matching event', () async {
      final futureEvent = impl.eventStream.first;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        impl.methodChannel.name,
        impl.methodChannel.codec.encodeMethodCall(
          const MethodCall(
            'onBackgroundTaskResult',
            {'taskId': 't1', 'result': 'ok'},
          ),
        ),
        (_) {},
      );

      final event = await futureEvent;
      expect(event['type'], 'backgroundTaskResult');
      expect((event['data'] as Map)['taskId'], 't1');
    });

    test('onNotificationReceived emits matching event', () async {
      final futureEvent = impl.eventStream.first;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        impl.methodChannel.name,
        impl.methodChannel.codec.encodeMethodCall(
          const MethodCall(
            'onNotificationReceived',
            {'id': 'n1', 'action': 'click'},
          ),
        ),
        (_) {},
      );

      final event = await futureEvent;
      expect(event['type'], 'notificationReceived');
      expect((event['data'] as Map)['id'], 'n1');
    });

    test('onTrayEvent emits matching event', () async {
      final futureEvent = impl.eventStream.first;

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        impl.methodChannel.name,
        impl.methodChannel.codec.encodeMethodCall(
          const MethodCall(
            'onTrayEvent',
            {'click': 'left'},
          ),
        ),
        (_) {},
      );

      final event = await futureEvent;
      expect(event['type'], 'trayEvent');
      expect((event['data'] as Map)['click'], 'left');
    });

  });
}
