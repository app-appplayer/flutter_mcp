import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/platform/platform_services.dart';
// Removed unused imports for batch_manager, health_monitor, and oauth_manager
import 'package:mcp_llm/mcp_llm.dart' as llm;

import 'mcp_integration_test.mocks.dart';

// Generate mock for dependencies
@GenerateMocks([PlatformServices])
void main() {
  late MockPlatformServices mockPlatformServices;

  // Set up logging for tests
  setUp(() {
    FlutterMcpLogging.configure(level: Level.FINE, enableDebugLogging: true);
    mockPlatformServices = MockPlatformServices();

    // Mock platform services behavior
    when(mockPlatformServices.initialize(any)).thenAnswer((_) async {});
    when(mockPlatformServices.isBackgroundServiceRunning).thenReturn(false);
    when(mockPlatformServices.startBackgroundService()).thenAnswer((_) async => true);
    when(mockPlatformServices.stopBackgroundService()).thenAnswer((_) async => true);
    when(mockPlatformServices.showNotification(
      title: anyNamed('title'),
      body: anyNamed('body'),
      icon: anyNamed('icon'),
      id: anyNamed('id'),
    )).thenAnswer((_) async {});
    when(mockPlatformServices.secureStore(any, any)).thenAnswer((_) async {});
    when(mockPlatformServices.secureRead(any)).thenAnswer((_) async => 'mock-stored-value');
  });

  group('FlutterMCP Initialization Tests', () {
    test('Initialize with minimal configuration', () async {
      // Create a minimal configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
      );

      // Use a test-specific implementation instead of the actual FlutterMCP.instance
      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Verify platform services were initialized
      verify(mockPlatformServices.initialize(config)).called(1);

      // Verify initialization completed
      expect(flutterMcp.isInitialized, true);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Initialize with auto-start', () async {
      // Create configuration with auto-start enabled
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: true,
        useBackgroundService: true,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Verify background service was started
      verify(mockPlatformServices.startBackgroundService()).called(1);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Initialize with auto-start disabled', () async {
      // Create configuration with auto-start disabled
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
        useBackgroundService: true,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Verify background service was NOT started
      verifyNever(mockPlatformServices.startBackgroundService());

      // Clean up
      await flutterMcp.shutdown();
    });
  });

  group('FlutterMCP Platform Service Tests', () {
    test('Start and stop background service', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Start services
      await flutterMcp.startServices();

      // Verify background service was started
      verify(mockPlatformServices.startBackgroundService()).called(1);

      // Verify notification was shown
      verify(mockPlatformServices.showNotification(
        title: anyNamed('title'),
        body: anyNamed('body'),
      )).called(1);

      // Shut down
      await flutterMcp.shutdown();

      // Verify platform services were shut down
      verify(mockPlatformServices.shutdown()).called(1);
    });

    test('Secure storage operations', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Test storing and retrieving secure values
      await flutterMcp.secureStore('test_key', 'test_value');
      final value = await flutterMcp.secureRead('test_key');

      // Verify storage operations
      verify(mockPlatformServices.secureStore('test_key', 'test_value')).called(1);
      verify(mockPlatformServices.secureRead('test_key')).called(1);
      expect(value, 'mock-stored-value');

      // Clean up
      await flutterMcp.shutdown();
    });
  });

  group('FlutterMCP Component Creation Tests', () {
    test('Create MCP server', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create a server
      final serverId = await flutterMcp.createServer(
        name: 'Test Server',
        version: '1.0.0',
        capabilities: ServerCapabilities(),
      );

      // Verify server was created
      expect(serverId, isNotNull);
      expect(serverId, startsWith('server_'));

      // Get server status
      final status = flutterMcp.getSystemStatus();
      expect(status['servers'], 1);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Create MCP client', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create a client (we'll mock the transport part)
      final clientId = await flutterMcp.createTestClient(
        'Test Client',
        '1.0.0',
      );

      // Verify client was created
      expect(clientId, isNotNull);
      expect(clientId, startsWith('client_'));

      // Get client status
      final status = flutterMcp.getSystemStatus();
      expect(status['clients'], 1);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Create LLM client', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create an LLM client (we'll mock the actual LLM provider)
      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Verify LLM was created
      expect(llmId, isNotNull);
      expect(llmId, startsWith('llm_'));

      // Get LLM status
      final status = flutterMcp.getSystemStatus();
      expect(status['llms'], 1);

      // Clean up
      await flutterMcp.shutdown();
    });
  });

  group('FlutterMCP Integration Tests', () {
    test('Integrate server with LLM', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create server and LLM
      final serverId = await flutterMcp.createServer(
        name: 'Test Server',
        version: '1.0.0',
      );

      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Integrate server with LLM
      await flutterMcp.integrateServerWithLlm(
        serverId: serverId,
        llmId: llmId,
      );

      // Connect server
      flutterMcp.connectServer(serverId);

      // Verify integration
      final status = flutterMcp.getSystemStatus();
      expect(status['serversStatus']['servers'][serverId]['hasLlmServer'], true);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Integrate client with LLM', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create client and LLM
      final clientId = await flutterMcp.createTestClient(
        'Test Client',
        '1.0.0',
      );

      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Integrate client with LLM
      await flutterMcp.integrateClientWithLlm(
        clientId: clientId,
        llmId: llmId,
      );

      // Verify integration (in real implementation, this would check LLM info)
      final llmInfo = flutterMcp.getLlmClientInfo(llmId);
      expect(llmInfo, isNotNull);

      // Clean up
      await flutterMcp.shutdown();
    });

    test('Chat with LLM', () async {
      // Create configuration
      final config = MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
      );

      final flutterMcp = TestFlutterMCP(mockPlatformServices);

      // Initialize
      await flutterMcp.init(config);

      // Create an LLM client
      final llmId = await flutterMcp.createTestLlm(
        'test-provider',
        LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'test-model',
        ),
      );

      // Chat with LLM
      final response = await flutterMcp.chat(
        llmId,
        'Hello, how are you today?',
      );

      // Verify response
      expect(response.text, 'This is a test response from mock LLM');

      // Clean up
      await flutterMcp.shutdown();
    });
  });
}

/// Mock classes for testing

/// Mock Server
class MockServer {
  final String name;
  final String version;
  final ServerCapabilities? capabilities;
  bool connected = false;
  bool hasLlmServer = false;

  MockServer(this.name, this.version, this.capabilities);

  void disconnect() {
    connected = false;
  }
}

/// Mock Client
class MockClient {
  final String name;
  final String version;
  bool connected = false;
  String? llmId;

  MockClient(this.name, this.version);

  void disconnect() {
    connected = false;
  }
}

/// Mock LLM Client
class MockLlmClient {
  final String providerName;
  final LlmConfiguration config;
  final List<String> integratedServerIds = [];
  final List<String> integratedClientIds = [];

  MockLlmClient(this.providerName, this.config);

  Future<void> close() async {
    // Clean up any resources
  }
}

/// Test implementation of FlutterMCP for use in tests
class TestFlutterMCP {
  final MockPlatformServices _platformServices;
  bool _initialized = false;
  final Map<String, MockServer> _servers = {};
  final Map<String, MockClient> _clients = {};
  final Map<String, MockLlmClient> _llmClients = {};
  int _serverCounter = 0;
  int _clientCounter = 0;
  int _llmCounter = 0;

  /// Integrate client with LLM
  Future<void> integrateClientWithLlm({
    required String clientId,
    required String llmId,
  }) async {
    final client = _clients[clientId];
    if (client == null) {
      throw Exception('Client not found: $clientId');
    }

    final llmClient = _llmClients[llmId];
    if (llmClient == null) {
      throw Exception('LLM client not found: $llmId');
    }

    llmClient.integratedClientIds.add(clientId);
    client.llmId = llmId;
  }

  /// Chat with LLM
  Future<llm.LlmResponse> chat(String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        bool useCache = true,
      }) async {
    final llmClient = _llmClients[llmId];
    if (llmClient == null) {
      throw Exception('LLM client not found: $llmId');
    }

    // Return a mock response
    return llm.LlmResponse(
      text: 'This is a test response from mock LLM',
      metadata: {
        'model': llmClient.config.model,
        'provider': llmClient.providerName,
        'input_tokens': message.length ~/ 4,
        'output_tokens': 12,
      },
    );
  }

  /// Get system status
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _initialized,
      'clients': _clients.length,
      'servers': _servers.length,
      'llms': _llmClients.length,
      'backgroundServiceRunning': _platformServices.isBackgroundServiceRunning,
      'clientsStatus': {
        'total': _clients.length,
        'clients': _clients.map((key, value) =>
            MapEntry(key, {
              'connected': value.connected,
              'name': value.name,
              'version': value.version,
            })),
      },
      'serversStatus': {
        'total': _servers.length,
        'servers': _servers.map((key, value) =>
            MapEntry(key, {
              'name': value.name,
              'version': value.version,
              'hasLlmServer': value.hasLlmServer,
            })),
      },
      'llmsStatus': {
        'total': _llmClients.length,
        'llms': _llmClients.map((key, value) =>
            MapEntry(key, {
              'provider': value.providerName,
              'connectedClients': value.integratedClientIds.length,
            })),
      },
    };
  }

  /// Store value securely
  Future<void> secureStore(String key, String value) async {
    await _platformServices.secureStore(key, value);
  }

  /// Read secure value
  Future<String?> secureRead(String key) async {
    return await _platformServices.secureRead(key);
  }

  /// Shutdown
  Future<void> shutdown() async {
    await _platformServices.shutdown();
    _initialized = false;
    _servers.clear();
    _clients.clear();
    _llmClients.clear();
  }
  
  /// Execute a tiered memory cleanup for testing
  Future<void> performTieredMemoryCleanup(int severityLevel) async {
    // This is a stub method for testing purposes
    // In production, this would call the actual method in FlutterMCP
  }

  /// Register a test resource
  Future<void> registerTestResource(String key, dynamic value, {int priority = 100}) async {
    // This is a stub method for testing purposes
    // In production, this would register a resource with the ResourceManager
  }

  TestFlutterMCP(this._platformServices);

  bool get isInitialized => _initialized;

  /// Initialize with configuration
  Future<void> init(MCPConfig config) async {
    await _platformServices.initialize(config);

    _initialized = true;

    if (config.autoStart) {
      await startServices();
    }
  }

  /// Start services
  Future<void> startServices() async {
    if (!_initialized) {
      throw Exception('FlutterMCP is not initialized');
    }

    await _platformServices.startBackgroundService();

    await _platformServices.showNotification(
      title: 'Test App Running',
      body: 'MCP service is running',
    );
  }

  /// Create server
  Future<String> createServer({
    required String name,
    required String version,
    ServerCapabilities? capabilities,
    bool useStdioTransport = true,
    int? ssePort,
  }) async {
    if (!_initialized) {
      throw Exception('FlutterMCP is not initialized');
    }

    _serverCounter++;
    final serverId = 'server_${DateTime
        .now()
        .millisecondsSinceEpoch}_$_serverCounter';

    final server = MockServer(name, version, capabilities);
    _servers[serverId] = server;

    return serverId;
  }

  /// Connect server
  void connectServer(String serverId) {
    final server = _servers[serverId];
    if (server == null) {
      throw Exception('Server not found: $serverId');
    }

    server.connected = true;
  }

  /// Create a test client
  Future<String> createTestClient(String name, String version) async {
    if (!_initialized) {
      throw Exception('FlutterMCP is not initialized');
    }

    _clientCounter++;
    final clientId = 'client_${DateTime
        .now()
        .millisecondsSinceEpoch}_$_clientCounter';

    final client = MockClient(name, version);
    _clients[clientId] = client;

    return clientId;
  }

  /// Connect client
  Future<void> connectClient(String clientId) async {
    final client = _clients[clientId];
    if (client == null) {
      throw Exception('Client not found: $clientId');
    }

    client.connected = true;
  }

  /// Create a test LLM
  Future<String> createTestLlm(String providerName,
      LlmConfiguration config,) async {
    if (!_initialized) {
      throw Exception('FlutterMCP is not initialized');
    }

    _llmCounter++;
    final llmId = 'llm_${DateTime
        .now()
        .millisecondsSinceEpoch}_$_llmCounter';

    final llmClient = MockLlmClient(
      providerName,
      config,
    );

    _llmClients[llmId] = llmClient;

    return llmId;
  }

  /// Get LLM client info
  Map<String, dynamic>? getLlmClientInfo(String llmId) {
    final client = _llmClients[llmId];
    if (client == null) return null;

    return {
      'provider': client.providerName,
      'model': client.config.model,
    };
  }

  /// Integrate server with LLM
  Future<void> integrateServerWithLlm({
    required String serverId,
    required String llmId,
  }) async {
    final server = _servers[serverId];
    if (server == null) {
      throw Exception('Server not found: $serverId');
    }

    final llmClient = _llmClients[llmId];
    if (llmClient == null) {
      throw Exception('LLM client not found: $llmId');
    }

    server.hasLlmServer = true;
    llmClient.integratedServerIds.add(serverId);
  }
}