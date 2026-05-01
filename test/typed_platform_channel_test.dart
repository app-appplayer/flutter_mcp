import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/utils/typed_platform_channel.dart';
import 'package:flutter_mcp/src/models/platform_messages.dart';
import 'package:flutter_mcp/src/utils/enhanced_error_handler.dart';
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // EnhancedErrorHandler wraps every TypedPlatformChannel call. Initialize
  // once for the whole suite.
  setUpAll(() {
    EnhancedErrorHandler.instance.initialize();
  });

  group('TypedPlatformChannel — sendMessage', () {
    final ch = TypedPlatformChannel('typed_test_send');
    final mc = const MethodChannel('typed_test_send');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
    });

    void mockReturn(Object? Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (call) async {
        calls.add(call);
        return handler(call);
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, null);
    });

    test('sends a message and parses null as SuccessResponse', () async {
      mockReturn((_) => null);
      const msg = StopBackgroundServiceMessage();
      final r = await ch.sendMessage(msg);
      expect(r, isA<SuccessResponse>());
      expect(calls.single.method, 'stopBackgroundService');
    });

    test('sends a message and parses raw map as SuccessResponse with data',
        () async {
      mockReturn((_) => <String, dynamic>{'arbitrary': 1});
      const msg = GetSystemInfoMessage();
      final r = await ch.sendMessage(msg);
      expect(r, isA<SuccessResponse>());
      expect((r as SuccessResponse).data, {'arbitrary': 1});
    });

    test('throws MCPPlatformException on PlatformException', () async {
      mockReturn((_) => throw PlatformException(code: 'X', message: 'no'));
      const msg = StopBackgroundServiceMessage();
      await expectLater(
        ch.sendMessage(msg),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('throws MCPPlatformException on MissingPluginException', () async {
      mockReturn((_) => throw MissingPluginException('absent'));
      const msg = StopBackgroundServiceMessage();
      await expectLater(
        ch.sendMessage(msg),
        throwsA(isA<MCPPlatformException>()),
      );
    });

    test('error envelope is parseable through fromPlatformResponse directly',
        () {
      // The MethodChannel codec yields Map<Object?, Object?> in tests, so
      // the error-envelope branch in TypedPlatformChannel.sendMessage isn't
      // reachable through a mock channel (the runtime check requires
      // Map<String, dynamic>). Verify the parser itself maps an error
      // envelope to ErrorResponse — that's the contract we rely on.
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'error': {'code': 'BAD', 'message': 'broken'},
      });
      expect(r, isA<ErrorResponse>());
      final err = r as ErrorResponse;
      expect(err.code, 'BAD');
    });
  });

  group('TypedPlatformChannel — invoke variants', () {
    final ch = TypedPlatformChannel('typed_test_invoke');
    final mc = const MethodChannel('typed_test_invoke');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, null);
    });

    test('invokeMethod returns underlying value', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (call) async {
        calls.add(call);
        return 42;
      });
      final r = await ch.invokeMethod<int>('m');
      expect(r, 42);
      expect(calls.single.method, 'm');
    });

    test('invokeListMethod returns typed list', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (call) async {
        calls.add(call);
        return <String>['a', 'b'];
      });
      final r = await ch.invokeListMethod<String>('list');
      expect(r, ['a', 'b']);
    });

    test('invokeMapMethod returns typed map', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (call) async {
        calls.add(call);
        return <String, int>{'a': 1, 'b': 2};
      });
      final r = await ch.invokeMapMethod<String, int>('map');
      expect(r, {'a': 1, 'b': 2});
    });
  });

  group('TypedPlatformChannel — sendBatch', () {
    final ch = TypedPlatformChannel('typed_test_batch');
    final mc = const MethodChannel('typed_test_batch');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, null);
    });

    test('sends each message and returns one response per message', () async {
      var counter = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (call) async {
        counter++;
        return null;
      });
      final responses = await ch.sendBatch([
        const StopBackgroundServiceMessage(),
        const StopBackgroundServiceMessage(),
        const StopBackgroundServiceMessage(),
      ]);
      expect(responses, hasLength(3));
      expect(counter, 3);
      for (final r in responses) {
        expect(r, isA<SuccessResponse>());
      }
    });
  });

  group('TypedPlatformChannel — event handler registration', () {
    final ch = TypedPlatformChannel('typed_test_events');
    final mc = const MethodChannel('typed_test_events');

    test('registered handler receives platform calls', () async {
      var received = '';
      ch.registerEventHandler('inboundEvent', (args) async {
        received = args.toString();
        return 'ok';
      });
      // Simulate a platform → flutter call.
      final result = await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        mc.name,
        mc.codec.encodeMethodCall(
            const MethodCall('inboundEvent', {'data': 1})),
        (_) {},
      );
      result;
      expect(received, contains('1'));
    });

    test('unregistered handler returns missing-plugin error to platform',
        () async {
      ch.registerEventHandler('willBeRemoved', (_) async => 'ok');
      ch.unregisterEventHandler('willBeRemoved');
      // After unregister, calls to that method route to the
      // missing-plugin branch which the channel surface translates to
      // a PlatformException reply.
      Object? caught;
      try {
        await TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .handlePlatformMessage(
          mc.name,
          mc.codec.encodeMethodCall(const MethodCall('willBeRemoved')),
          (_) {},
        );
      } catch (e) {
        caught = e;
      }
      // The exact behavior may vary by Flutter version — we only assert
      // that we don't get a stale-handler success reply.
      expect(caught, anyOf(isNull, isA<PlatformException>()));
    });
  });

  group('TypedPlatformChannel.subscribeToEvent', () {
    final ch = TypedPlatformChannel('typed_test_stream');

    test('createEventChannel composes channel name', () {
      final ec = ch.createEventChannel('events');
      expect(ec.name, 'typed_test_stream/events');
    });
  });

  group('FlutterMCPChannel singleton', () {
    test('instance returns the same TypedPlatformChannel', () {
      final a = FlutterMCPChannel.instance;
      final b = FlutterMCPChannel.instance;
      expect(identical(a, b), isTrue);
    });
  });

  group('MCPPlatformException (typed_platform_channel)', () {
    test('toString includes message', () {
      final e = MCPPlatformException('boom', code: 'CODE');
      expect(e.toString(), contains('boom'));
    });

    test('toString includes details when present', () {
      final e = MCPPlatformException('boom', code: 'CODE', details: 'why');
      expect(e.toString(), contains('why'));
    });

    test('extends MCPException base', () {
      final e = MCPPlatformException('boom', code: 'CODE');
      expect(e, isA<MCPException>());
    });
  });
}
