export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';

import 'dart:async';
import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

import 'src/config/mcp_config.dart';
import 'src/core/client_manager.dart';
import 'src/core/server_manager.dart';
import 'src/core/llm_manager.dart';
import 'src/core/scheduler.dart';
import 'src/platform/platform_services.dart';
import 'src/utils/logger.dart';
import 'src/utils/exceptions.dart';

/// Flutter MCP - Integrated MCP Management System
///
/// A package that integrates MCP components (mcp_client, mcp_server, mcp_llm)
/// and adds various platform features (background execution, notifications, system tray)
/// for Flutter environments.
class FlutterMCP {
  // Singleton instance
  static final FlutterMCP _instance = FlutterMCP._();

  /// Singleton instance accessor
  static FlutterMCP get instance => _instance;

  // Private constructor
  FlutterMCP._();

  // MCP core managers
  final MCPClientManager _clientManager = MCPClientManager();
  final MCPServerManager _serverManager = MCPServerManager();
  final MCPLlmManager _llmManager = MCPLlmManager();

  // Platform services
  final PlatformServices _platformServices = PlatformServices();

  // Task scheduler
  final MCPScheduler _scheduler = MCPScheduler();

  // Plugin state
  bool _initialized = false;
  MCPConfig? _config;

  // Integrated logger
  static final MCPLogger _logger = MCPLogger('flutter_mcp');

  /// Whether the plugin is initialized
  bool get initialized => _initialized;

  /// Initialize the plugin
  ///
  /// [config] specifies the configuration for necessary components.
  Future<void> init(MCPConfig config) async {
    if (_initialized) {
      _logger.warning('Flutter MCP is already initialized');
      return;
    }

    _config = config;

    // Initialize logging setup
    if (config.loggingLevel != null) {
      MCPLogger.setDefaultLevel(config.loggingLevel!);
    }

    _logger.info('Flutter MCP initialization started');

    // Initialize platform services
    await _platformServices.initialize(config);

    // Initialize managers
    await _clientManager.initialize();
    await _serverManager.initialize();
    await _llmManager.initialize();

    // Initialize scheduler
    if (config.schedule != null && config.schedule!.isNotEmpty) {
      _scheduler.initialize();
      for (final job in config.schedule!) {
        _scheduler.addJob(job);
      }
      _scheduler.start();
    }

    // Auto-start configuration
    if (config.autoStart) {
      _logger.info('Starting services based on auto-start configuration');
      await startServices();
    }

    _initialized = true;
    _logger.info('Flutter MCP initialization completed');
  }

  /// Start services
  Future<void> startServices() async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Start background service
    if (_config!.useBackgroundService) {
      await _platformServices.startBackgroundService();
    }

    // Show notification
    if (_config!.useNotification) {
      await _platformServices.showNotification(
        title: '${_config!.appName} Running',
        body: 'MCP service is running',
      );
    }

    // Start configured components
    await _startConfiguredComponents();
  }

  /// Start configured components
  Future<void> _startConfiguredComponents() async {
    final config = _config!;

    // Start auto-start servers
    if (config.autoStartServer != null && config.autoStartServer!.isNotEmpty) {
      for (final serverConfig in config.autoStartServer!) {
        try {
          final serverId = await createServer(
            name: serverConfig.name,
            version: serverConfig.version,
            capabilities: serverConfig.capabilities,
            useStdioTransport: serverConfig.useStdioTransport,
            ssePort: serverConfig.ssePort,
          );

          // Integrate with LLM if configured
          if (serverConfig.integrateLlm != null) {
            String llmId;

            if (serverConfig.integrateLlm!.existingLlmId != null) {
              llmId = serverConfig.integrateLlm!.existingLlmId!;
            } else {
              llmId = await createLlm(
                providerName: serverConfig.integrateLlm!.providerName!,
                config: serverConfig.integrateLlm!.config!,
              );
            }

            await integrateServerWithLlm(
              serverId: serverId,
              llmId: llmId,
            );
          }

          // Connect server
          connectServer(serverId);
        } catch (e) {
          _logger.error('Failed to start server: ${serverConfig.name}', e);
          // Continue with other servers even if one fails
        }
      }
    }

    // Start auto-start clients
    if (config.autoStartClient != null && config.autoStartClient!.isNotEmpty) {
      for (final clientConfig in config.autoStartClient!) {
        try {
          final clientId = await createClient(
            name: clientConfig.name,
            version: clientConfig.version,
            capabilities: clientConfig.capabilities,
            transportCommand: clientConfig.transportCommand,
            transportArgs: clientConfig.transportArgs,
            serverUrl: clientConfig.serverUrl,
          );

          // Integrate with LLM if configured
          if (clientConfig.integrateLlm != null) {
            String llmId;

            if (clientConfig.integrateLlm!.existingLlmId != null) {
              llmId = clientConfig.integrateLlm!.existingLlmId!;
            } else {
              llmId = await createLlm(
                providerName: clientConfig.integrateLlm!.providerName!,
                config: clientConfig.integrateLlm!.config!,
              );
            }

            await integrateClientWithLlm(
              clientId: clientId,
              llmId: llmId,
            );
          }

          // Connect client
          await connectClient(clientId);
        } catch (e) {
          _logger.error('Failed to start client: ${clientConfig.name}', e);
          // Continue with other clients even if one fails
        }
      }
    }
  }

  /// Create MCP client
  ///
  /// [name]: Client name
  /// [version]: Client version
  /// [capabilities]: Client capabilities
  /// [transportCommand]: Command for stdio transport
  /// [transportArgs]: Arguments for stdio transport
  /// [serverUrl]: URL for SSE transport
  ///
  /// Returns ID of the created client
  Future<String> createClient({
    required String name,
    required String version,
    ClientCapabilities? capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    String? serverUrl,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP client: $name');

    // Create client
    final clientId = _clientManager.generateId();
    final client = McpClient.createClient(
      name: name,
      version: version,
      capabilities: capabilities ?? ClientCapabilities(),
    );

    // Create transport
    ClientTransport? transport;
    if (transportCommand != null) {
      transport = await McpClient.createStdioTransport(
        command: transportCommand,
        arguments: transportArgs ?? [],
      );
    } else if (serverUrl != null) {
      transport = await McpClient.createSseTransport(
        serverUrl: serverUrl,
      );
    }

    // Register client
    await _clientManager.registerClient(clientId, client, transport);

    return clientId;
  }

  /// Create MCP server
  ///
  /// [name]: Server name
  /// [version]: Server version
  /// [capabilities]: Server capabilities
  /// [useStdioTransport]: Whether to use stdio transport
  /// [ssePort]: Port for SSE transport
  ///
  /// Returns ID of the created server
  Future<String> createServer({
    required String name,
    required String version,
    ServerCapabilities? capabilities,
    bool useStdioTransport = true,
    int? ssePort,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP server: $name');

    // Create server
    final serverId = _serverManager.generateId();
    final server = McpServer.createServer(
      name: name,
      version: version,
      capabilities: capabilities ?? ServerCapabilities(),
    );

    // Create transport
    ServerTransport? transport;
    if (useStdioTransport) {
      transport = McpServer.createStdioTransport();
    } else if (ssePort != null) {
      transport = McpServer.createSseTransport(
        endpoint: '/sse',
        messagesEndpoint: '/messages',
        port: ssePort,
      );
    }

    // Register server
    _serverManager.registerServer(serverId, server, transport);

    return serverId;
  }

  /// Create MCP LLM
  ///
  /// [providerName]: LLM provider name
  /// [config]: LLM configuration
  ///
  /// Returns ID of the created LLM
  Future<String> createLlm({
    required String providerName,
    required LlmConfiguration config,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP LLM: $providerName');

    // Get LLM instance
    final mcpLlm = MCPLlm.instance;

    // Create LLM client
    final llmClient = await mcpLlm.createClient(
      providerName: providerName,
      config: config,
    );

    // Generate and register LLM ID
    final llmId = _llmManager.generateId();
    _llmManager.registerLlm(llmId, mcpLlm, llmClient);

    return llmId;
  }

  /// Integrate server with LLM
  ///
  /// [serverId]: Server ID
  /// [llmId]: LLM ID
  Future<void> integrateServerWithLlm({
    required String serverId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating server with LLM: $serverId + $llmId');

    final server = _serverManager.getServer(serverId);
    if (server == null) {
      throw MCPException('Server not found: $serverId');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    // Create LLM server
    final llmServer = LlmServer(
      llmProvider: llmInfo.client.getLlmProvider(),
      mcpServer: server,
    );

    // Register LLM tools
    await llmServer.registerLlmTools();

    // Register LLM server
    _serverManager.setLlmServer(serverId, llmServer);
  }

  /// Integrate client with LLM
  ///
  /// [clientId]: Client ID
  /// [llmId]: LLM ID
  Future<void> integrateClientWithLlm({
    required String clientId,
    required String llmId,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Integrating client with LLM: $clientId + $llmId');

    final client = _clientManager.getClient(clientId);
    if (client == null) {
      throw MCPException('Client not found: $clientId');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    // Register client with LLM
    await _llmManager.addClientToLlm(llmId, client);
  }

  /// Connect client
  ///
  /// [clientId]: Client ID
  Future<void> connectClient(String clientId) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting client: $clientId');

    final clientInfo = _clientManager.getClientInfo(clientId);
    if (clientInfo == null) {
      throw MCPException('Client not found: $clientId');
    }

    if (clientInfo.transport == null) {
      throw MCPException('Client has no transport configured: $clientId');
    }

    await clientInfo.client.connect(clientInfo.transport!);
    clientInfo.connected = true;
  }

  /// Connect server
  ///
  /// [serverId]: Server ID
  void connectServer(String serverId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Connecting server: $serverId');

    final serverInfo = _serverManager.getServerInfo(serverId);
    if (serverInfo == null) {
      throw MCPException('Server not found: $serverId');
    }

    if (serverInfo.transport == null) {
      throw MCPException('Server has no transport configured: $serverId');
    }

    serverInfo.server.connect(serverInfo.transport!);
    serverInfo.running = true;
  }

  /// Call tool with client
  ///
  /// [clientId]: Client ID
  /// [toolName]: Tool name
  /// [arguments]: Tool arguments
  Future<CallToolResult> callTool(
      String clientId,
      String toolName,
      Map<String, dynamic> arguments,
      ) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final clientInfo = _clientManager.getClientInfo(clientId);
    if (clientInfo == null) {
      throw MCPException('Client not found: $clientId');
    }

    return await clientInfo.client.callTool(toolName, arguments);
  }

  /// Chat with LLM
  ///
  /// [llmId]: LLM ID
  /// [message]: Message content
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  Future<LlmResponse> chat(
      String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic>? parameters,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    return await llmInfo.client.chat(
      message,
      enableTools: enableTools,
      parameters: parameters,
    );
  }

  /// Add scheduled job
  ///
  /// [job]: Job to add
  ///
  /// Returns ID of the created job
  String addScheduledJob(MCPJob job) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return _scheduler.addJob(job);
  }

  /// Remove scheduled job
  ///
  /// [jobId]: Job ID to remove
  void removeScheduledJob(String jobId) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _scheduler.removeJob(jobId);
  }

  /// Store value securely
  ///
  /// [key]: Key to store value under
  /// [value]: Value to store
  Future<void> secureStore(String key, String value) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _platformServices.secureStore(key, value);
  }

  /// Read value from secure storage
  ///
  /// [key]: Key to read
  Future<String?> secureRead(String key) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    return await _platformServices.secureRead(key);
  }

  /// Shutdown all services
  Future<void> shutdown() async {
    if (!_initialized) return;

    _logger.info('Flutter MCP shutdown started');

    // Stop scheduler
    _scheduler.stop();

    // Close managers
    await Future.wait([
      _clientManager.closeAll(),
      _serverManager.closeAll(),
      _llmManager.closeAll(),
    ]);

    // Shutdown platform services
    await _platformServices.shutdown();

    _initialized = false;
    _logger.info('Flutter MCP shutdown completed');
  }

  /// ID access methods
  List<String> get allClientIds => _clientManager.getAllClientIds();
  List<String> get allServerIds => _serverManager.getAllServerIds();
  List<String> get allLlmIds => _llmManager.getAllLlmIds();

  /// Object access methods
  Client? getClient(String clientId) => _clientManager.getClient(clientId);
  Server? getServer(String serverId) => _serverManager.getServer(serverId);
  LlmClient? getLlm(String llmId) => _llmManager.getLlm(llmId);

  /// Get system status
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _initialized,
      'clients': _clientManager.getAllClientIds().length,
      'servers': _serverManager.getAllServerIds().length,
      'llms': _llmManager.getAllLlmIds().length,
      'backgroundServiceRunning': _platformServices.isBackgroundServiceRunning,
      'schedulerRunning': _scheduler.isRunning,
      'clientsStatus': _clientManager.getStatus(),
      'serversStatus': _serverManager.getStatus(),
      'llmsStatus': _llmManager.getStatus(),
    };
  }
}