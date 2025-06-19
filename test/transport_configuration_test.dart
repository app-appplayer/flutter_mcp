import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterMCP mcp;

  setUp(() async {
    FlutterMcpLogging.configure(level: Level.FINE, enableDebugLogging: true);

    // Set up method channel mock handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_mcp'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'initialize':
            return null;
          case 'startBackgroundService':
            return true;
          case 'stopBackgroundService':
            return true;
          case 'showNotification':
            return null;
          case 'cancelAllNotifications':
            return null;
          case 'shutdown':
            return null;
          case 'getPlatformVersion':
            return 'Test Platform 1.0';
          default:
            return null;
        }
      },
    );

    mcp = FlutterMCP.instance;

    // Initialize if not already initialized
    if (!mcp.isInitialized) {
      await mcp.init(MCPConfig(
        appName: 'Transport Config Test',
        appVersion: '1.0.0',
      ));
    }
  });

  tearDownAll(() async {
    try {
      await mcp.shutdown();
    } catch (_) {
      // Ignore shutdown errors
    }

    // Clear method channel mock
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_mcp'),
      null,
    );
  });

  group('Transport Type Configuration', () {
    test('transportType is required in MCPServerConfig', () {
      expect(
        () => MCPServerConfig(
          name: 'Test Server',
          version: '1.0.0',
          // Missing transportType - should throw
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('transportType is required in MCPClientConfig', () {
      expect(
        () => MCPClientConfig(
          name: 'Test Client',
          version: '1.0.0',
          // Missing transportType - should throw
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Valid transport types are accepted', () {
      // STDIO
      expect(
        () => MCPServerConfig(
          name: 'Test Server',
          version: '1.0.0',
          transportType: 'stdio',
        ),
        returnsNormally,
      );

      // SSE
      expect(
        () => MCPServerConfig(
          name: 'Test Server',
          version: '1.0.0',
          transportType: 'sse',
          ssePort: 8080,
        ),
        returnsNormally,
      );

      // StreamableHTTP
      expect(
        () => MCPServerConfig(
          name: 'Test Server',
          version: '1.0.0',
          transportType: 'streamablehttp',
          streamableHttpPort: 8080,
        ),
        returnsNormally,
      );
    });
  });

  group('STDIO Transport Configuration', () {
    test('STDIO server configuration', () async {
      final serverId = await mcp.createServer(
        name: 'STDIO Server',
        version: '1.0.0',
        config: MCPServerConfig(
          name: 'STDIO Server',
          version: '1.0.0',
          transportType: 'stdio',
          authToken: 'test-token',
        ),
      );

      expect(serverId, isNotNull);
      expect(serverId, startsWith('server_'));
    });

    test('STDIO client configuration', () async {
      final clientId = await mcp.createClient(
        name: 'STDIO Client',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'STDIO Client',
          version: '1.0.0',
          transportType: 'stdio',
          transportCommand: 'echo',
          transportArgs: ['--test'],
          authToken: 'test-token',
        ),
      );

      expect(clientId, isNotNull);
      expect(clientId, startsWith('client_'));
    });

    test('STDIO client requires transportCommand', () async {
      try {
        await mcp.createClient(
          name: 'STDIO Client',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'STDIO Client',
            version: '1.0.0',
            transportType: 'stdio',
            // Missing transportCommand
          ),
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        // The validation error might be wrapped in MCPOperationFailedException
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), contains('transportCommand is required'));
      }
    });
  });

  group('SSE Transport Configuration', () {
    test('SSE server with all configuration options', () async {
      final serverId = await mcp.createServer(
        name: 'SSE Server',
        version: '1.0.0',
        config: MCPServerConfig(
          name: 'SSE Server',
          version: '1.0.0',
          transportType: 'sse',
          ssePort: 0, // Dynamic port
          host: 'localhost',
          endpoint: '/custom-sse',
          messagesEndpoint: '/custom-message',
          fallbackPorts: [8081, 8082, 8083],
          authToken: 'secret-token',
          middleware: <shelf.Middleware>[],
        ),
      );

      expect(serverId, isNotNull);
      expect(serverId, startsWith('server_'));
    });

    test('SSE server requires ssePort', () async {
      try {
        await mcp.createServer(
          name: 'SSE Server',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'SSE Server',
            version: '1.0.0',
            transportType: 'sse',
            // Missing ssePort
          ),
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        // The validation error might be wrapped in MCPOperationFailedException
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), contains('ssePort is required'));
      }
    });

    test('SSE client with all configuration options', () async {
      final clientId = await mcp.createClient(
        name: 'SSE Client',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'SSE Client',
          version: '1.0.0',
          transportType: 'sse',
          serverUrl: 'http://localhost:8080',
          endpoint: '/custom-sse',
          authToken: 'secret-token',
          headers: {
            'X-Custom-Header': 'value',
            'User-Agent': 'Test/1.0',
          },
          timeout: Duration(seconds: 30),
          sseReadTimeout: Duration(minutes: 5),
        ),
      );

      expect(clientId, isNotNull);
      expect(clientId, startsWith('client_'));
    });

    test('SSE client requires serverUrl', () async {
      try {
        await mcp.createClient(
          name: 'SSE Client',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'SSE Client',
            version: '1.0.0',
            transportType: 'sse',
            // Missing serverUrl
          ),
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        // The validation error might be wrapped in MCPOperationFailedException
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), anyOf(
          contains('serverUrl is required'),
          contains('Either transportCommand or serverUrl must be provided')
        ));
      }
    });
  });

  group('StreamableHTTP Transport Configuration', () {
    test('StreamableHTTP server with all configuration options', () async {
      final serverId = await mcp.createServer(
        name: 'StreamableHTTP Server',
        version: '1.0.0',
        config: MCPServerConfig(
          name: 'StreamableHTTP Server',
          version: '1.0.0',
          transportType: 'streamablehttp',
          streamableHttpPort: 0, // Dynamic port
          host: '0.0.0.0',
          endpoint: '/api/mcp',
          messagesEndpoint: '/api/message',
          fallbackPorts: [9001, 9002, 9003],
          authToken: 'api-key',
          isJsonResponseEnabled: false, // SSE mode
          jsonResponseMode: 'sync',
          maxRequestSize: 8388608, // 8MB
          requestTimeout: Duration(seconds: 60),
          corsConfig: {
            'allowOrigin': 'https://example.com',
            'allowMethods': 'POST, GET, OPTIONS, DELETE',
            'allowHeaders': 'Content-Type, Authorization, mcp-session-id',
            'maxAge': 86400,
          },
        ),
      );

      expect(serverId, isNotNull);
      expect(serverId, startsWith('server_'));
    });

    test('StreamableHTTP server requires streamableHttpPort', () async {
      try {
        await mcp.createServer(
          name: 'StreamableHTTP Server',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'StreamableHTTP Server',
            version: '1.0.0',
            transportType: 'streamablehttp',
            // Missing streamableHttpPort
          ),
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        // The validation error might be wrapped in MCPOperationFailedException
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), contains('streamableHttpPort or ssePort is required'));
      }
    });

    test('StreamableHTTP client with all configuration options', () async {
      final clientId = await mcp.createClient(
        name: 'StreamableHTTP Client',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'StreamableHTTP Client',
          version: '1.0.0',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:8080',
          endpoint: '/api/mcp',
          authToken: 'api-key',
          headers: {
            'X-API-Version': '2.0',
            'Accept': 'application/json',
          },
          timeout: Duration(seconds: 60),
          maxConcurrentRequests: 20,
          useHttp2: true,
          terminateOnClose: true,
        ),
      );

      expect(clientId, isNotNull);
      expect(clientId, startsWith('client_'));
    });

    test('StreamableHTTP client requires serverUrl', () async {
      try {
        await mcp.createClient(
          name: 'StreamableHTTP Client',
          version: '1.0.0',
          config: MCPClientConfig(
            name: 'StreamableHTTP Client',
            version: '1.0.0',
            transportType: 'streamablehttp',
            // Missing serverUrl
          ),
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        // The validation error might be wrapped in MCPOperationFailedException
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), anyOf(
          contains('serverUrl is required'),
          contains('Either transportCommand or serverUrl must be provided')
        ));
      }
    });

    test('StreamableHTTP JSON response modes', () {
      // Test sync mode
      final syncConfig = MCPServerConfig(
        name: 'Sync Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
        isJsonResponseEnabled: true,
        jsonResponseMode: 'sync',
      );
      expect(syncConfig.jsonResponseMode, equals('sync'));

      // Test async mode
      final asyncConfig = MCPServerConfig(
        name: 'Async Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
        isJsonResponseEnabled: true,
        jsonResponseMode: 'async',
      );
      expect(asyncConfig.jsonResponseMode, equals('async'));
    });
  });

  group('Transport Configuration Serialization', () {
    test('MCPServerConfig toJson includes all fields', () {
      final config = MCPServerConfig(
        name: 'Test Server',
        version: '1.0.0',
        transportType: 'streamablehttp',
        streamableHttpPort: 8080,
        host: 'example.com',
        endpoint: '/mcp',
        messagesEndpoint: '/msg',
        fallbackPorts: [8081, 8082],
        authToken: 'token',
        isJsonResponseEnabled: true,
        jsonResponseMode: 'async',
        maxRequestSize: 1048576,
        requestTimeout: Duration(seconds: 30),
        corsConfig: {'allowOrigin': '*'},
      );

      final json = config.toJson();
      expect(json['name'], equals('Test Server'));
      expect(json['version'], equals('1.0.0'));
      expect(json['transportType'], equals('streamablehttp'));
      expect(json['streamableHttpPort'], equals(8080));
      expect(json['host'], equals('example.com'));
      expect(json['endpoint'], equals('/mcp'));
      expect(json['messagesEndpoint'], equals('/msg'));
      expect(json['fallbackPorts'], equals([8081, 8082]));
      expect(json['authToken'], equals('token'));
      expect(json['isJsonResponseEnabled'], equals(true));
      expect(json['jsonResponseMode'], equals('async'));
      expect(json['maxRequestSize'], equals(1048576));
      expect(json['requestTimeout'], equals(30000)); // milliseconds
      expect(json['corsConfig'], equals({'allowOrigin': '*'}));
    });

    test('MCPClientConfig toJson includes all fields', () {
      final config = MCPClientConfig(
        name: 'Test Client',
        version: '1.0.0',
        transportType: 'sse',
        serverUrl: 'https://api.example.com',
        endpoint: '/events',
        transportCommand: 'node',
        transportArgs: ['server.js'],
        authToken: 'bearer-token',
        timeout: Duration(seconds: 45),
        sseReadTimeout: Duration(minutes: 10),
        maxConcurrentRequests: 15,
        useHttp2: true,
        terminateOnClose: false,
        headers: {'Authorization': 'Bearer token'},
      );

      final json = config.toJson();
      expect(json['name'], equals('Test Client'));
      expect(json['version'], equals('1.0.0'));
      expect(json['transportType'], equals('sse'));
      expect(json['serverUrl'], equals('https://api.example.com'));
      expect(json['endpoint'], equals('/events'));
      expect(json['transportCommand'], equals('node'));
      expect(json['transportArgs'], equals(['server.js']));
      expect(json['authToken'], equals('bearer-token'));
      expect(json['timeout'], equals(45000)); // milliseconds
      expect(json['sseReadTimeout'], equals(600000)); // milliseconds
      expect(json['maxConcurrentRequests'], equals(15));
      expect(json['useHttp2'], equals(true));
      expect(json['terminateOnClose'], equals(false));
      expect(json['headers'], equals({'Authorization': 'Bearer token'}));
    });
  });

  group('Transport Validation', () {
    test('Invalid transport type throws validation error', () async {
      try {
        await mcp.createServer(
          name: 'Invalid Server',
          version: '1.0.0',
          config: MCPServerConfig(
            name: 'Invalid Server',
            version: '1.0.0',
            transportType: 'websocket', // Invalid type
          ),
        );
        fail('Should have thrown MCPOperationFailedException');
      } catch (e) {
        expect(e, isA<MCPOperationFailedException>());
        expect(e.toString(), contains('Invalid transport type'));
      }
    });

    test('Transport configuration matches between server and client', () async {
      // Create server with specific endpoint
      final serverId = await mcp.createServer(
        name: 'Endpoint Server',
        version: '1.0.0',
        config: MCPServerConfig(
          name: 'Endpoint Server',
          version: '1.0.0',
          transportType: 'streamablehttp',
          streamableHttpPort: 0,
          endpoint: '/custom/mcp',
        ),
      );

      // Client should use matching endpoint
      final clientConfig = MCPClientConfig(
        name: 'Endpoint Client',
        version: '1.0.0',
        transportType: 'streamablehttp',
        serverUrl: 'http://localhost:8080',
        endpoint: '/custom/mcp', // Must match server
      );

      expect(clientConfig.endpoint, equals('/custom/mcp'));
    });

    test('Authentication token configuration', () {
      final serverConfig = MCPServerConfig(
        name: 'Auth Server',
        version: '1.0.0',
        transportType: 'sse',
        ssePort: 8080,
        authToken: 'server-secret',
      );

      final clientConfig = MCPClientConfig(
        name: 'Auth Client',
        version: '1.0.0',
        transportType: 'sse',
        serverUrl: 'http://localhost:8080',
        authToken: 'server-secret', // Must match server
      );

      expect(serverConfig.authToken, equals(clientConfig.authToken));
    });
  });

  group('Transport Type Requirement', () {
    test('Client without config requires transportType', () async {
      try {
        await mcp.createClient(
          name: 'No Config Client',
          version: '1.0.0',
          transportCommand: 'echo',
          // No config provided, so transportType is missing
        );
        fail('Should have thrown MCPValidationException');
      } catch (e) {
        expect(e, anyOf(isA<MCPValidationException>(), isA<MCPOperationFailedException>()));
        expect(e.toString(), contains('transportType must be specified'));
      }
    });

    test('Server with legacy useStdioTransport still works', () async {
      // Server has backward compatibility for useStdioTransport
      final serverId = await mcp.createServer(
        name: 'Legacy Server',
        version: '1.0.0',
        useStdioTransport: true,
      );

      expect(serverId, isNotNull);
    });

    test('Server with SSE port but no explicit transport still works', () async {
      // Server can infer SSE transport from ssePort
      final serverId = await mcp.createServer(
        name: 'Legacy SSE Server',
        version: '1.0.0',
        useStdioTransport: false,
        ssePort: 0,
      );

      expect(serverId, isNotNull);
    });
  });
}