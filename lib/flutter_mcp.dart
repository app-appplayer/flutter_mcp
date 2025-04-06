export 'src/config/mcp_config.dart';
export 'src/config/background_config.dart';
export 'src/config/notification_config.dart';
export 'src/config/tray_config.dart';
export 'src/config/job.dart';
export 'src/utils/exceptions.dart';

import 'dart:async';
import 'package:mcp_client/mcp_client.dart' hide ServerCapabilities;
import 'package:mcp_server/mcp_server.dart' hide CallToolResult;
import 'package:mcp_llm/mcp_llm.dart';

import 'src/config/mcp_config.dart';
import 'src/config/job.dart';
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

  // MCP core components
  final MCPClientManager _clientManager = MCPClientManager();
  final MCPServerManager _serverManager = MCPServerManager();
  final MCPLlmManager _llmManager = MCPLlmManager();

  // Multiple MCP LLM instances
  final Map<String, MCPLlm> _mcpLlmInstances = {};

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

    // Create default MCP LLM instance
    final defaultLlm = MCPLlm();
    _mcpLlmInstances['default'] = defaultLlm;

    // Register default LLM providers on the default instance
    _registerDefaultProviders(defaultLlm);

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

  /// Register default LLM providers
  void _registerDefaultProviders(MCPLlm mcpLlm) {
    try {
      mcpLlm.registerProvider('openai', OpenAiProviderFactory());
      _logger.debug('Registered OpenAI provider');
    } catch (e) {
      _logger.warning('Failed to register OpenAI provider: $e');
    }

    try {
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());
      _logger.debug('Registered Claude provider');
    } catch (e) {
      _logger.warning('Failed to register Claude provider: $e');
    }

    try {
      mcpLlm.registerProvider('together', TogetherProviderFactory());
      _logger.debug('Registered Together provider');
    } catch (e) {
      _logger.warning('Failed to register Together provider: $e');
    }

    // Register other providers as needed
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

    // Create client using McpClient factory
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
    _clientManager.registerClient(clientId, client, transport);

    return clientId;
  }

  /// Create MCP server
  ///
  /// [name]: Server name
  /// [version]: Server version
  /// [capabilities]: Server capabilities
  /// [useStdioTransport]: Whether to use stdio transport
  /// [ssePort]: Port for SSE transport
  /// [fallbackPorts]: Fallback ports if primary port is unavailable
  /// [authToken]: Authentication token for SSE transport
  ///
  /// Returns ID of the created server
  Future<String> createServer({
    required String name,
    required String version,
    ServerCapabilities? capabilities,
    bool useStdioTransport = true,
    int? ssePort,
    List<int>? fallbackPorts,
    String? authToken,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    _logger.info('Creating MCP server: $name');

    // Create server using McpServer factory
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
        fallbackPorts: fallbackPorts,
        authToken: authToken,
      );
    }

    // Register server
    _serverManager.registerServer(serverId, server, transport);

    return serverId;
  }

  /// Create a new MCPLlm instance with custom ID
  ///
  /// [instanceId]: ID for the new instance
  /// [registerDefaultProviders]: Whether to register default providers
  ///
  /// Returns the newly created MCPLlm instance
  MCPLlm createMcpLlmInstance(String instanceId, {bool registerDefaultProviders = true}) {
    if (_mcpLlmInstances.containsKey(instanceId)) {
      _logger.warning('MCPLlm instance with ID $instanceId already exists');
      return _mcpLlmInstances[instanceId]!;
    }

    final mcpLlm = MCPLlm();
    _mcpLlmInstances[instanceId] = mcpLlm;

    if (registerDefaultProviders) {
      _registerDefaultProviders(mcpLlm);
    }

    return mcpLlm;
  }

  /// Get an existing MCPLlm instance by ID
  ///
  /// [instanceId]: ID of the instance to get
  ///
  /// Returns the requested MCPLlm instance or null if not found
  MCPLlm? getMcpLlmInstance(String instanceId) {
    return _mcpLlmInstances[instanceId];
  }

  /// Create MCP LLM
  ///
  /// [providerName]: LLM provider name
  /// [config]: LLM configuration
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  /// [storageManager]: Optional storage manager for the LLM
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  ///
  /// Returns ID of the created LLM
  Future<String> createLlm({
    required String providerName,
    required LlmConfiguration config,
    String mcpLlmInstanceId = 'default',
    StorageManager? storageManager,
    RetrievalManager? retrievalManager,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    // Get MCPLlm instance, create if doesn't exist
    MCPLlm mcpLlm;
    if (!_mcpLlmInstances.containsKey(mcpLlmInstanceId)) {
      _logger.debug('Creating new MCPLlm instance: $mcpLlmInstanceId');
      mcpLlm = createMcpLlmInstance(mcpLlmInstanceId);
    } else {
      mcpLlm = _mcpLlmInstances[mcpLlmInstanceId]!;
    }

    _logger.info('Creating MCP LLM: $providerName on instance $mcpLlmInstanceId');

    // Create LLM client using specified MCP LLM instance and its factory method
    final llmClient = await mcpLlm.createClient(
      providerName: providerName,
      config: config,
      storageManager: storageManager,
      retrievalManager: retrievalManager,
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
  /// [storageManager]: Optional storage manager
  /// [retrievalManager]: Optional retrieval manager for RAG capabilities
  Future<void> integrateServerWithLlm({
    required String serverId,
    required String llmId,
    StorageManager? storageManager,
    RetrievalManager? retrievalManager,
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

    // Create LLM server using MCPLlm's createServer method
    final llmServer = await llmInfo.mcpLlm.createServer(
      providerName: llmInfo.mcpLlm.getProviderCapabilities().keys.first, // Get first available provider
      config: null, // Using null as the LLM client is already configured
      mcpServer: server,
      storageManager: storageManager,
      retrievalManager: retrievalManager,
    );

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
        Map<String, dynamic> parameters = const {},
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

  /// Stream chat with LLM
  ///
  /// [llmId]: LLM ID
  /// [message]: Message content
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  Stream<LlmResponseChunk> streamChat(
      String llmId,
      String message, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
      }) async* {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    await for (final chunk in llmInfo.client.streamChat(
      message,
      enableTools: enableTools,
      parameters: parameters,
    )) {
      yield chunk;
    }
  }

  /// Add document to LLM for retrieval
  ///
  /// [llmId]: LLM ID
  /// [document]: Document to add
  Future<String> addDocument(String llmId, Document document) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    return await llmInfo.client.addDocument(document);
  }

  /// Retrieve relevant documents for a query
  ///
  /// [llmId]: LLM ID
  /// [query]: Query text
  /// [topK]: Number of results to return
  Future<List<Document>> retrieveRelevantDocuments(
      String llmId,
      String query, {
        int topK = 5,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    return await llmInfo.client.retrieveRelevantDocuments(
      query,
      topK: topK,
    );
  }

  /// Generate embeddings
  ///
  /// [llmId]: LLM ID
  /// [text]: Text to embed
  Future<List<double>> generateEmbeddings(String llmId, String text) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    return await llmInfo.client.generateEmbeddings(text);
  }

  /// Select client for a query
  ///
  /// [query]: Query text
  /// [properties]: Properties to match
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  LlmClient? selectClient(
      String query, {
        Map<String, dynamic>? properties,
        String mcpLlmInstanceId = 'default',
      }) {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    return mcpLlm.selectClient(query, properties: properties);
  }

  /// Fan out query to multiple clients
  ///
  /// [query]: Query text
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  Future<Map<String, LlmResponse>> fanOutQuery(
      String query, {
        bool enableTools = false,
        Map<String, dynamic> parameters = const {},
        String mcpLlmInstanceId = 'default',
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    return await mcpLlm.fanOutQuery(
      query,
      enableTools: enableTools,
      parameters: parameters,
    );
  }

  /// Execute parallel query across multiple providers
  ///
  /// [query]: Query text
  /// [providers]: List of provider names
  /// [enableTools]: Whether to enable tools
  /// [parameters]: Additional parameters
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to use (defaults to 'default')
  Future<LlmResponse> executeParallel(
      String query, {
        List<String>? providerNames,
        ResultAggregator? aggregator,
        Map<String, dynamic> parameters = const {},
        LlmConfiguration? config,
        String mcpLlmInstanceId = 'default',
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    return await mcpLlm.executeParallel(
      query,
      providerNames: providerNames,
      aggregator: aggregator,
      parameters: parameters,
      config: config,
    );
  }

  /// Helper method to get MCPLlm instance or throw if not found
  MCPLlm _getMcpLlmInstanceOrThrow(String instanceId) {
    final mcpLlm = _mcpLlmInstances[instanceId];
    if (mcpLlm == null) {
      throw MCPException('MCPLlm instance not found: $instanceId');
    }
    return mcpLlm;
  }

  /// Create chat session
  ///
  /// [llmId]: LLM ID
  /// [sessionId]: Optional session ID
  /// [title]: Optional session title
  /// [storageManager]: Optional storage manager for persisting chat history
  Future<ChatSession> createChatSession(
      String llmId, {
        String? sessionId,
        String? title,
        StorageManager? storageManager,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    // Create a new chat session with storage
    final storage = storageManager ?? MemoryStorage();

    return ChatSession(
      llmProvider: llmInfo.client.llmProvider,
      storageManager: storage,
      id: sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Chat Session',
    );
  }

  /// Create a conversation with multiple sessions
  ///
  /// [llmId]: LLM ID
  /// [title]: Optional conversation title
  /// [topics]: Optional topics for the conversation
  /// [storageManager]: Optional storage manager for persisting conversation
  Future<Conversation> createConversation(
      String llmId, {
        String? title,
        List<String>? topics,
        StorageManager? storageManager,
      }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    final llmInfo = _llmManager.getLlmInfo(llmId);
    if (llmInfo == null) {
      throw MCPException('LLM not found: $llmId');
    }

    // Create a new conversation
    final storage = storageManager ?? MemoryStorage();

    return Conversation(
      id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Conversation',
      llmProvider: llmInfo.client.llmProvider,
      topics: topics ?? [],
      storageManager: storage,
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

  /// Show notification
  ///
  /// [title]: Notification title
  /// [body]: Notification body
  /// [icon]: Optional icon
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
  }) async {
    if (!_initialized) {
      throw MCPException('Flutter MCP is not initialized');
    }

    await _platformServices.showNotification(
      title: title,
      body: body,
      icon: icon,
    );
  }

  /// Register LLM provider
  ///
  /// [name]: Provider name
  /// [factory]: Provider factory
  /// [mcpLlmInstanceId]: ID of the MCPLlm instance to register on (defaults to 'default')
  void registerLlmProvider(
      String name,
      LlmProviderFactory factory, {
        String mcpLlmInstanceId = 'default',
      }) {
    final mcpLlm = _getMcpLlmInstanceOrThrow(mcpLlmInstanceId);
    mcpLlm.registerProvider(name, factory);
  }

  /// List all registered MCPLlm instances
  List<String> getAllMcpLlmInstanceIds() {
    return _mcpLlmInstances.keys.toList();
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