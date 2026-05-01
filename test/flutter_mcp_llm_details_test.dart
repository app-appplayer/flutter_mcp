// Coverage tests for FlutterMCP's LLM-detail methods —
// getLlmEnhancedDetails, getAllLlmDetails, removeLlmClient/removeLlmServer
// happy paths and error paths. These need a registered LlmInfo so we
// access the manager via FlutterMCP.instance.llmManager and inject fakes.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_llm/mcp_llm.dart' as llm;

class _FakeProvider implements llm.LlmProvider {
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

llm.LlmClient _newClient() => llm.LlmClient(llmProvider: _FakeProvider());
llm.LlmServer _newServer() => llm.LlmServer(
      llmProvider: _FakeProvider(),
      pluginManager: llm.PluginManager(),
    );

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

  group('FlutterMCP LLM detail methods (uninitialized)', () {
    setUp(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
    });

    test('getLlmEnhancedDetails throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.getLlmEnhancedDetails('any'),
        throwsA(isA<MCPException>()),
      );
    });

    test('getAllLlmDetails throws when not initialized', () {
      expect(
        () => FlutterMCP.instance.getAllLlmDetails(),
        throwsA(isA<MCPException>()),
      );
    });
  });

  group('FlutterMCP LLM detail methods (initialized)', () {
    setUpAll(() async {
      _installMethodChannelMock();
      if (!FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.init(
          MCPConfig(appName: 'llm-details-test', appVersion: '0.0.1'),
        );
      }
    });

    tearDownAll(() async {
      if (FlutterMCP.instance.isInitialized) {
        await FlutterMCP.instance.shutdown();
      }
      _removeMethodChannelMock();
    });

    test('getLlmEnhancedDetails throws MCPResourceNotFound for unknown llm',
        () {
      expect(
        () => FlutterMCP.instance.getLlmEnhancedDetails('absent-llm'),
        throwsA(isA<MCPResourceNotFoundException>()),
      );
    });

    test('getAllLlmDetails returns paginated shape with no llms', () {
      final result = FlutterMCP.instance.getAllLlmDetails();
      expect(result['total'], isA<int>());
      expect(result['offset'], 0);
      expect(result['limit'], 50);
      expect(result['returned'], isA<int>());
      expect(result['llms'], isA<Map>());
    });

    test('getAllLlmDetails respects offset and limit', () {
      final result =
          FlutterMCP.instance.getAllLlmDetails(offset: 10, limit: 5);
      expect(result['offset'], 10);
      expect(result['limit'], 5);
    });

    test('removeLlmClient throws MCPOperationFailed for unknown llmId',
        () async {
      // The outer try/catch wraps MCPResourceNotFoundException.
      await expectLater(
        FlutterMCP.instance.removeLlmClient('absent', 'cid'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    test('removeLlmServer throws MCPOperationFailed for unknown llmId',
        () async {
      await expectLater(
        FlutterMCP.instance.removeLlmServer('absent', 'sid'),
        throwsA(anyOf(
          isA<MCPResourceNotFoundException>(),
          isA<MCPOperationFailedException>(),
        )),
      );
    });

    group('with a registered LLM', () {
      setUp(() {
        // Register a fresh LLM with a client + server for each test.
        FlutterMCP.instance.llmManager.registerLlm(
          'test-llm-id',
          llm.MCPLlm(),
          initialClient: _newClient(),
          initialServer: _newServer(),
        );
      });

      tearDown(() async {
        await FlutterMCP.instance.llmManager.closeLlm('test-llm-id');
      });

      test('getLlmEnhancedDetails returns full nested shape', () {
        final details =
            FlutterMCP.instance.getLlmEnhancedDetails('test-llm-id');
        expect(details['id'], 'test-llm-id');
        expect(details['hasClients'], isTrue);
        expect(details['hasServers'], isTrue);
        expect(details['clientCount'], 1);
        expect(details['serverCount'], 1);
        expect(details['clients'], isA<Map>());
        expect(details['servers'], isA<Map>());
        expect(details['associatedMcpClients'], isA<List>());
        expect(details['associatedMcpServers'], isA<List>());
      });

      test('getAllLlmDetails(includeDetails: false) emits compact entries',
          () {
        final result = FlutterMCP.instance.getAllLlmDetails();
        expect(result['returned'], greaterThanOrEqualTo(1));
        final llms = result['llms'] as Map;
        expect(llms.containsKey('test-llm-id'), isTrue);
        final entry = llms['test-llm-id'] as Map;
        expect(entry['hasClients'], isTrue);
        expect(entry['clientCount'], 1);
      });

      test('getAllLlmDetails(includeDetails: true) embeds full details', () {
        final result =
            FlutterMCP.instance.getAllLlmDetails(includeDetails: true);
        final llms = result['llms'] as Map;
        final entry = llms['test-llm-id'] as Map;
        expect(entry['id'], 'test-llm-id');
        expect(entry.containsKey('clients'), isTrue);
      });
    });
  });
}
