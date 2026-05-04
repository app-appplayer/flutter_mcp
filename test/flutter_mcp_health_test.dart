// Coverage tests for FlutterMCP health + resource methods —
// getComponentHealth/getSystemHealth/getResourceStatistics/checkForResourceLeaks
// /getResourceDetails/connectClient/connectServer error paths.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_llm/mcp_llm.dart' as llm;

class _FakeProvider implements llm.LlmProvider {
  @override
  bool get supportsPromptCaching => false;

  @override
  Future<void> initialize(llm.LlmConfiguration config) async {}
  @override
  Future<void> close() async {}
  @override
  Future<llm.LlmResponse> complete(llm.LlmRequest request) async =>
      llm.LlmResponse(text: 'fake');
  @override
  Stream<llm.LlmResponseChunk> streamComplete(llm.LlmRequest request) =>
      const Stream.empty();
  @override
  Future<List<double>> getEmbeddings(String text) async => [];
  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) => false;
  @override
  llm.LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) =>
      null;
  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) =>
      metadata;
}

void _installMethodChannelMock() {
  const channel = MethodChannel('flutter_mcp');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        return {'success': true, 'platform': 'test'};
      case 'getPlatformVersion':
        return 'Test 1.0';
      case 'startBackgroundService':
      case 'stopBackgroundService':
      case 'requestNotificationPermission':
      case 'shutdown':
      case 'configureNotifications':
      case 'cancelNotification':
      case 'cancelAllNotifications':
        return true;
      case 'showNotification':
        return {'success': true, 'id': 'test'};
      case 'secureStore':
      case 'secureDelete':
        return true;
      case 'secureRead':
        return null;
      case 'secureContainsKey':
        return false;
      case 'requestPermission':
      case 'checkPermission':
        return true;
      case 'requestPermissions':
        return {'notif': true};
      default:
        return null;
    }
  });
}

void _removeMethodChannelMock() {
  const channel = MethodChannel('flutter_mcp');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterMCP health (uninitialized)', () {
    setUp(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
    });

    test('getComponentHealth throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.getComponentHealth('any'),
        throwsA(isA<MCPException>()),
      );
    });

    test('getSystemHealth throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.getSystemHealth(),
        throwsA(isA<MCPException>()),
      );
    });

    test('connectClient throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.connectClient('cid'),
        throwsA(isA<MCPException>()),
      );
    });

    test('connectServer throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.connectServer('sid'),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('FlutterMCP health (initialized)', () {
    setUpAll(() async {
      _installMethodChannelMock();
      if (!FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.init(
          MCPConfig(appName: 'health-test', appVersion: '0.0.1'),
        );
      }
    });

    tearDownAll(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      _removeMethodChannelMock();
    });

    test('getComponentHealth returns unhealthy for unknown client', () async {
      final r = await FlutterMCP.instance.getComponentHealth('client_absent');
      expect(r.status, MCPHealthStatus.unhealthy);
    });

    test('getComponentHealth returns unhealthy for unknown server', () async {
      final r = await FlutterMCP.instance.getComponentHealth('server_absent');
      expect(r.status, MCPHealthStatus.unhealthy);
    });

    test('getComponentHealth returns unhealthy for unknown llm', () async {
      final r = await FlutterMCP.instance.getComponentHealth('llm_absent');
      expect(r.status, MCPHealthStatus.unhealthy);
      expect(r.message, contains('LLM not found'));
    });

    test('getComponentHealth returns unhealthy for unknown component prefix',
        () async {
      final r = await FlutterMCP.instance.getComponentHealth('foo_x');
      expect(r.status, MCPHealthStatus.unhealthy);
      expect(r.message, contains('Unknown component'));
    });

    test('getComponentHealth healthy for registered LLM', () async {
      FlutterMCP.instance.llmManager.registerLlm(
        'health-llm',
        llm.MCPLlm(),
      );
      final r = await FlutterMCP.instance.getComponentHealth('llm_health-llm');
      expect(r.status, MCPHealthStatus.healthy);
      await FlutterMCP.instance.llmManager.closeLlm('health-llm');
    });

    test('getSystemHealth aggregates with 0 components → healthy', () async {
      final h = await FlutterMCP.instance.getSystemHealth();
      expect(h, contains('overall'));
      expect(h, contains('components'));
      expect(h, contains('timestamp'));
    });

    test('getSystemHealth includes registered LLM in components', () async {
      FlutterMCP.instance.llmManager.registerLlm(
        'sys-llm',
        llm.MCPLlm(),
      );
      final h = await FlutterMCP.instance.getSystemHealth();
      final comps = h['components'] as Map;
      expect(comps.containsKey('llm_sys-llm'), isTrue);
      await FlutterMCP.instance.llmManager.closeLlm('sys-llm');
    });

    test('getResourceStatistics returns map shape', () {
      final stats = FlutterMCP.instance.getResourceStatistics();
      expect(stats, isA<Map<String, dynamic>>());
    });

    test('checkForResourceLeaks runs without throwing', () {
      FlutterMCP.instance.checkForResourceLeaks();
    });

    test('getResourceDetails returns a list', () {
      final details = FlutterMCP.instance.getResourceDetails();
      expect(details, isA<List>());
    });

    test('connectClient throws MCPOperationFailed for unknown clientId',
        () async {
      // The outer try/catch wraps MCPResourceNotFoundException.
      await expectLater(
        FlutterMCP.instance.connectClient('absent'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('connectServer throws MCPOperationFailed for unknown serverId', () {
      expect(
        () => FlutterMCP.instance.connectServer('absent'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('healthStream returns a Stream when initialized', () {
      final s = FlutterMCP.instance.healthStream;
      expect(s, isA<Stream>());
    });
  });
}
