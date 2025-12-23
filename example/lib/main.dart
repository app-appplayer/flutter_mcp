import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'v1_features_demo.dart';
import 'native_features_demo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initMCP();
  } catch (e) {
    debugPrint('Failed to initialize MCP: $e');
  }

  runApp(const MCPDemoApp());
}

/// Initialize MCP with v1.0.0 configuration and native features
Future<void> initMCP() async {
  // Configure logging
  FlutterMcpLogging.configure(level: Level.FINE, enableDebugLogging: true);
  final logger = Logger('flutter_mcp.demo_app');

  logger.info('Initializing MCP v1.0.0 with native features...');

  try {
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'MCP Demo',
        appVersion: '1.0.0',
        autoStart: false,
        enablePerformanceMonitoring: true, // v1.0.0 feature
        highMemoryThresholdMB: 512, // v1.0.0 memory management

        // Native platform features
        useBackgroundService: true,
        useNotification: true,
        useTray: _isDesktopPlatform(),
        secure: true,

        // Background configuration
        background: BackgroundConfig(
          notificationChannelId: 'mcp_demo_background',
          notificationChannelName: 'MCP Demo Background Service',
          notificationDescription: 'Keeps MCP services running',
          intervalMs: 60000, // 1 minute
          keepAlive: true,
        ),

        // Notification configuration
        notification: NotificationConfig(
          channelId: 'mcp_demo_notifications',
          channelName: 'MCP Demo Notifications',
          channelDescription: 'Notifications from MCP Demo',
          enableSound: true,
          enableVibration: true,
          priority: NotificationPriority.high,
        ),

        // Tray configuration (desktop only)
        tray: TrayConfig(
          iconPath: 'assets/icons/tray_icon.png',
          tooltip: 'MCP Demo Application',
          menuItems: [
            TrayMenuItem(label: 'Show Window'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Quit'),
          ],
        ),
      ),
    );
    logger.info('MCP initialized successfully with native features');
  } catch (e, stackTrace) {
    logger.error('Failed to initialize MCP: $e\nStack trace: $stackTrace');
    rethrow;
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

bool _isDesktopPlatform() {
  try {
    // Check if running on desktop using Platform class
    return Theme.of(navigatorKey.currentContext ?? NavigatorState().context)
                .platform ==
            TargetPlatform.macOS ||
        Theme.of(navigatorKey.currentContext ?? NavigatorState().context)
                .platform ==
            TargetPlatform.windows ||
        Theme.of(navigatorKey.currentContext ?? NavigatorState().context)
                .platform ==
            TargetPlatform.linux;
  } catch (e) {
    return false;
  }
}

class MCPDemoApp extends StatelessWidget {
  const MCPDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP v1.0.0 Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      navigatorKey: navigatorKey,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Logger _logger = Logger('flutter_mcp.home_page');

  // Service IDs
  String? _serverId;
  String? _clientId;
  String? _llmId;
  String? _llmServerId;

  // State
  bool _isRunning = false;
  String _status = 'Ready';

  // Platform Services State
  bool _backgroundServiceRunning = false;
  bool _notificationPermissionGranted = false;
  bool _trayIconVisible = false;

  // Chat
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];

  // API key
  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedProvider = 'openai';

  // MCP Mode configuration
  String _mcpMode = 'server'; // 'server' or 'client'
  
  // Transport configuration
  String _transportType = 'stdio';
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _ssePortController = TextEditingController();
  final TextEditingController _httpPortController = TextEditingController();
  final TextEditingController _transportCommandController = TextEditingController();
  final TextEditingController _transportArgsController = TextEditingController();
  final TextEditingController _authTokenController = TextEditingController();
  final TextEditingController _sseEndpointController = TextEditingController();
  final TextEditingController _httpEndpointController = TextEditingController();

  // Health monitoring
  StreamSubscription? _healthSubscription;

  // Validation errors
  String? _serverUrlError;
  String? _ssePortError;
  String? _httpPortError;
  String? _transportCommandError;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _subscribeToHealth();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _apiKeyController.dispose();
    _serverUrlController.dispose();
    _ssePortController.dispose();
    _httpPortController.dispose();
    _transportCommandController.dispose();
    _transportArgsController.dispose();
    _authTokenController.dispose();
    _sseEndpointController.dispose();
    _httpEndpointController.dispose();
    _healthSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToHealth() {
    try {
      _healthSubscription = FlutterMCP.instance.healthStream.listen(
        (health) {
          if (health.status == MCPHealthStatus.unhealthy) {
            _updateStatus('⚠️ Health warning: ${health.message}');
          }
        },
        onError: (error) {
          _logger.debug('Health monitoring not available: $error');
        },
      );
    } catch (e) {
      _logger.debug('Health monitoring setup failed: $e');
    }

    // Check platform service status
    _checkPlatformServices();
  }

  Future<void> _checkPlatformServices() async {
    try {
      // Check platform service status
      final status = FlutterMCP.instance.platformServicesStatus;
      setState(() {
        _backgroundServiceRunning = status['backgroundServiceRunning'] ?? false;
      });
    } catch (e) {
      _logger.debug('Platform service check failed: $e');
    }
  }

  Future<void> _loadApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _apiKeyController.text = prefs.getString('api_key') ?? '';
        _selectedProvider = prefs.getString('provider') ?? 'openai';
        _mcpMode = prefs.getString('mcp_mode') ?? 'server';
        _transportType = prefs.getString('transport_type') ?? 'stdio';
        _serverUrlController.text = prefs.getString('server_url') ?? 'http://localhost';
        _ssePortController.text = prefs.getString('sse_port') ?? '8080';
        _httpPortController.text = prefs.getString('http_port') ?? '8081';
        _transportCommandController.text = prefs.getString('transport_command') ?? 'echo';
        _transportArgsController.text = prefs.getString('transport_args') ?? '';
        _authTokenController.text = prefs.getString('auth_token') ?? '';
        _sseEndpointController.text = prefs.getString('sse_endpoint') ?? '/sse';
        _httpEndpointController.text = prefs.getString('http_endpoint') ?? '/mcp';
      });
    } catch (e) {
      _updateStatus('Failed to load settings');
    }
  }

  Future<void> _saveApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_key', _apiKeyController.text);
      await prefs.setString('provider', _selectedProvider);
      await prefs.setString('mcp_mode', _mcpMode);
      await prefs.setString('transport_type', _transportType);
      await prefs.setString('server_url', _serverUrlController.text);
      await prefs.setString('sse_port', _ssePortController.text);
      await prefs.setString('http_port', _httpPortController.text);
      await prefs.setString('transport_command', _transportCommandController.text);
      await prefs.setString('transport_args', _transportArgsController.text);
      await prefs.setString('auth_token', _authTokenController.text);
      await prefs.setString('sse_endpoint', _sseEndpointController.text);
      await prefs.setString('http_endpoint', _httpEndpointController.text);
      _updateStatus('Settings saved');
    } catch (e) {
      _updateStatus('Failed to save settings');
    }
  }

  void _updateStatus(String status) {
    setState(() {
      _status = status;
    });
  }

  // Validation methods
  bool _validateServerUrl(String? url) {
    if (url == null || url.isEmpty) {
      // Empty is allowed, will use default localhost
      setState(() => _serverUrlError = null);
      return true;
    }
    
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        setState(() => _serverUrlError = 'Invalid URL format. Must start with http:// or https://');
        return false;
      }
      setState(() => _serverUrlError = null);
      return true;
    } catch (e) {
      setState(() => _serverUrlError = 'Invalid URL format');
      return false;
    }
  }

  bool _validatePort(String? portStr, String portType) {
    if (portStr == null || portStr.isEmpty) {
      // Will use default port
      if (portType == 'sse') {
        setState(() => _ssePortError = null);
      } else {
        setState(() => _httpPortError = null);
      }
      return true;
    }
    
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      final error = 'Port must be between 1 and 65535';
      if (portType == 'sse') {
        setState(() => _ssePortError = error);
      } else {
        setState(() => _httpPortError = error);
      }
      return false;
    }
    
    if (portType == 'sse') {
      setState(() => _ssePortError = null);
    } else {
      setState(() => _httpPortError = null);
    }
    return true;
  }

  bool _validateTransportCommand(String? command) {
    if (command == null || command.isEmpty) {
      setState(() => _transportCommandError = 'Transport command is required for STDIO');
      return false;
    }
    setState(() => _transportCommandError = null);
    return true;
  }

  bool _validateTransportSettings() {
    if (_transportType == 'stdio') {
      return _validateTransportCommand(_transportCommandController.text);
    } else if (_transportType == 'sse') {
      return _validateServerUrl(_serverUrlController.text) & 
             _validatePort(_ssePortController.text, 'sse');
    } else if (_transportType == 'streamablehttp') {
      return _validateServerUrl(_serverUrlController.text) & 
             _validatePort(_httpPortController.text, 'http');
    }
    return true;
  }

  String _buildEndpointUrl() {
    final baseUrl = _serverUrlController.text.isEmpty 
        ? 'http://localhost' 
        : _serverUrlController.text;
    
    if (_transportType == 'sse') {
      final port = _ssePortController.text.isEmpty ? '8080' : _ssePortController.text;
      final endpoint = _sseEndpointController.text.isEmpty ? '/sse' : _sseEndpointController.text;
      return '$baseUrl:$port$endpoint';
    } else if (_transportType == 'streamablehttp') {
      final port = _httpPortController.text.isEmpty ? '8081' : _httpPortController.text;
      // Streamable HTTP doesn't use endpoint paths - it's handled internally by the transport
      return '$baseUrl:$port';
    }
    return '';
  }

  Future<void> _startServices() async {
    // Validate transport settings first
    if (!_validateTransportSettings()) {
      setState(() => _isRunning = false);
      _updateStatus('❌ Please fix validation errors');
      return;
    }

    _updateStatus('Starting ${_mcpMode}...');

    try {
      if (_mcpMode == 'server') {
        // SERVER MODE - Create and start MCP server
        MCPServerConfig? serverConfig;
        if (_transportType == 'sse') {
          serverConfig = MCPServerConfig(
            name: 'Demo Server',
            version: '1.0.0',
            transportType: 'sse',
            ssePort: int.tryParse(_ssePortController.text) ?? 8080,
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        } else if (_transportType == 'streamablehttp') {
          serverConfig = MCPServerConfig(
            name: 'Demo Server',
            version: '1.0.0',
            transportType: 'streamablehttp',
            streamableHttpPort: int.tryParse(_httpPortController.text) ?? 8081,
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        } else {
          // STDIO transport (default)
          serverConfig = MCPServerConfig(
            name: 'Demo Server',
            version: '1.0.0',
            transportType: 'stdio',
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        }

        // Create server with transport configuration
        _serverId = await FlutterMCP.instance.createServer(
          name: 'Demo Server',
          version: '1.0.0',
          capabilities: ServerCapabilities.simple(
            tools: true,
            resources: true,
            prompts: true,
            sampling: true,
          ),
          config: serverConfig,
        );

        // Connect server
        if (_serverId != null) {
          FlutterMCP.instance.connectServer(_serverId!);
        }

        // Display server endpoint information
        String endpointInfo = '';
        if (_transportType == 'stdio') {
          endpointInfo = 'STDIO mode - Server ready for subprocess execution';
          // In STDIO mode, the server doesn't listen on a network port
          // It communicates through standard input/output when executed as a subprocess
        } else if (_transportType == 'sse') {
          final baseUrl = _serverUrlController.text.isEmpty ? 'http://localhost' : _serverUrlController.text;
          final port = _ssePortController.text.isEmpty ? '8080' : _ssePortController.text;
          final endpoint = _sseEndpointController.text.isEmpty ? '/sse' : _sseEndpointController.text;
          endpointInfo = 'SSE server listening at $baseUrl:$port$endpoint';
        } else if (_transportType == 'streamablehttp') {
          final baseUrl = _serverUrlController.text.isEmpty ? 'http://localhost' : _serverUrlController.text;
          final port = _httpPortController.text.isEmpty ? '8081' : _httpPortController.text;
          final endpoint = _httpEndpointController.text.isEmpty ? '/mcp' : _httpEndpointController.text;
          endpointInfo = 'HTTP server listening at $baseUrl:$port$endpoint';
        }

        setState(() => _isRunning = true);
        _updateStatus('✅ MCP Server running - $endpointInfo');

      } else {
        // CLIENT MODE - Create and connect MCP client
        MCPClientConfig? clientConfig;
        String? transportCommand;
        List<String>? transportArgs;
        String? serverUrl;

        if (_transportType == 'stdio') {
          transportCommand = _transportCommandController.text.isNotEmpty 
              ? _transportCommandController.text 
              : 'echo';
          if (_transportArgsController.text.isNotEmpty) {
            transportArgs = _transportArgsController.text.split(' ');
          }
          clientConfig = MCPClientConfig(
            name: 'Demo Client',
            version: '1.0.0',
            transportType: 'stdio',
            transportCommand: transportCommand,
            transportArgs: transportArgs,
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        } else if (_transportType == 'sse') {
          serverUrl = _buildEndpointUrl();
          clientConfig = MCPClientConfig(
            name: 'Demo Client',
            version: '1.0.0',
            transportType: 'sse',
            serverUrl: serverUrl,
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        } else if (_transportType == 'streamablehttp') {
          // For streamable HTTP, we need the base URL with port
          final baseUrl = _serverUrlController.text.isEmpty ? 'http://localhost' : _serverUrlController.text;
          final port = _httpPortController.text.isEmpty ? '8081' : _httpPortController.text;
          serverUrl = '$baseUrl:$port';
          clientConfig = MCPClientConfig(
            name: 'Demo Client',
            version: '1.0.0',
            transportType: 'streamablehttp',
            serverUrl: serverUrl,
            endpoint: _httpEndpointController.text.isEmpty ? '/mcp' : _httpEndpointController.text,
            authToken: _authTokenController.text.isNotEmpty ? _authTokenController.text : null,
          );
        }

        // Create client with transport configuration
        _clientId = await FlutterMCP.instance.createClient(
          name: 'Demo Client',
          version: '1.0.0',
          capabilities: const ClientCapabilities(),
          config: clientConfig,
        );

        // Display connection information before connecting
        String connectionInfo = '';
        if (_transportType == 'stdio') {
          connectionInfo = 'STDIO: $transportCommand';
        } else {
          connectionInfo = serverUrl ?? 'Unknown URL';
        }

        _logger.info('Attempting to connect client to: $connectionInfo');
        _updateStatus('🔄 Connecting to $connectionInfo...');

        // Connect client
        if (_clientId != null) {
          await FlutterMCP.instance.connectClient(_clientId!);
          
          // Validate connection by checking client info
          try {
            final clientInfo = FlutterMCP.instance.getClientDetails(_clientId!);
            if (clientInfo.isEmpty || clientInfo['connected'] != true) {
              throw Exception('Client connected but not ready');
            }
            
            setState(() => _isRunning = true);
            _updateStatus('✅ MCP Client connected - $connectionInfo');
          } catch (validationError) {
            _logger.error('Connection validation failed: $validationError');
            // Clean up the failed connection
            await FlutterMCP.instance.clientManager.closeClient(_clientId!);
            throw Exception('Connection validation failed: $validationError');
          }
        }
      }

      // Create LLM if API key provided (for both server and client modes)
      if (_apiKeyController.text.isNotEmpty && _mcpMode == 'server') {
        final result = await FlutterMCP.instance.createLlmServer(
          providerName: _selectedProvider,
          config: LlmConfiguration(
            apiKey: _apiKeyController.text,
            model: _selectedProvider == 'openai'
                ? 'gpt-3.5-turbo'
                : 'claude-3-sonnet-20240229',
          ),
        );
        _llmId = result.$1;
        _llmServerId = result.$2;

        // Connect server to LLM
        if (_serverId != null && _llmServerId != null) {
          await FlutterMCP.instance.addMcpServerToLlmServer(
            mcpServerId: _serverId!,
            llmServerId: _llmServerId!,
          );
        }
      }

    } catch (e) {
      _logger.error('Failed to start $_mcpMode: $e');
      _updateStatus('❌ Error: ${e.toString()}');
      setState(() {
        _isRunning = false;
        // Clean up any created resources
        if (_clientId != null) {
          _clientId = null;
        }
        if (_serverId != null) {
          _serverId = null;
        }
      });
    }
  }

  Future<void> _stopServices() async {
    setState(() => _isRunning = false);
    _updateStatus('Stopping services...');

    setState(() {
      _serverId = null;
      _clientId = null;
      _llmId = null;
      _llmServerId = null;
    });

    _updateStatus('Services stopped');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _llmId == null) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messageController.clear();
    });

    try {
      final response = await FlutterMCP.instance.chat(
        _llmId!,
        text,
        enableTools: true,
      );

      setState(() {
        _messages.add(ChatMessage(text: response.text, isUser: false));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: ${e.toString()}',
          isUser: false,
          isError: true,
        ));
      });
    }
  }

  Future<void> _showStatus() async {
    try {
      final status = FlutterMCP.instance.getSystemStatus();
      final health = await FlutterMCP.instance.getSystemHealth();
      final batchStats = FlutterMCP.instance.getBatchStatistics();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('System Status'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Initialized: ${status['initialized'] ?? false}'),
                Text('Clients: ${status['clients'] ?? 0}'),
                Text('Servers: ${status['servers'] ?? 0}'),
                Text('LLMs: ${status['llms'] ?? 0}'),
                const Divider(),
                const Text('Health Status:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Status: ${health['status'] ?? 'unknown'}'),
                Text('Message: ${health['message'] ?? 'N/A'}'),
                const Divider(),
                const Text('Batch Processing:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Total: ${batchStats['totalBatches'] ?? 0}'),
                Text(
                    'Success Rate: ${(batchStats['successRate'] ?? 0).toStringAsFixed(1)}%'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _updateStatus('Failed to get status');
    }
  }

  Future<void> _testBatchProcessing() async {
    if (_llmId == null) {
      _updateStatus('Start services with API key first');
      return;
    }

    _updateStatus('Testing batch processing...');

    try {
      final results = await FlutterMCP.instance.processBatch(
        llmId: _llmId!,
        requests: [
          () async => '1 + 1 = ?',
          () async => 'Capital of France?',
          () async => 'Color of sky?',
        ],
      );

      _updateStatus('✅ Batch completed: ${results.length} results');
    } catch (e) {
      _updateStatus('❌ Batch failed: $e');
    }
  }

  // Native Platform Feature Methods

  Future<void> _startBackgroundService() async {
    try {
      final started =
          await FlutterMCP.instance.platformServices.startBackgroundService();
      if (started) {
        setState(() {
          _backgroundServiceRunning = true;
        });
        _updateStatus('✅ Background service started');
      } else {
        _updateStatus('❌ Failed to start background service');
      }
    } catch (e) {
      _updateStatus('❌ Background service error: $e');
    }
  }

  Future<void> _stopBackgroundService() async {
    try {
      final stopped =
          await FlutterMCP.instance.platformServices.stopBackgroundService();
      if (stopped) {
        setState(() {
          _backgroundServiceRunning = false;
        });
        _updateStatus('✅ Background service stopped');
      } else {
        _updateStatus('❌ Failed to stop background service');
      }
    } catch (e) {
      _updateStatus('❌ Background service error: $e');
    }
  }

  Future<void> _showTestNotification() async {
    try {
      // Request permission first if not granted
      if (!_notificationPermissionGranted) {
        // On mobile platforms, permission is handled by the native side
        setState(() {
          _notificationPermissionGranted = true;
        });
      }

      await FlutterMCP.instance.platformServices.showNotification(
        title: 'MCP Demo Notification',
        body:
            'This is a test notification from Flutter MCP using native channels!',
        id: 'test_notification_${DateTime.now().millisecondsSinceEpoch}',
      );

      _updateStatus('✅ Notification shown');
    } catch (e) {
      _updateStatus('❌ Notification error: $e');
    }
  }

  Future<void> _showTrayIcon() async {
    try {
      await FlutterMCP.instance.platformServices
          .setTrayIcon('assets/icons/tray_icon.png');
      await FlutterMCP.instance.platformServices
          .setTrayTooltip('MCP Demo - Click for menu');

      // Update tray menu with actions
      await FlutterMCP.instance.platformServices.setTrayMenu([
        TrayMenuItem(
          label: 'Show Window',
          onTap: () {
            _logger.info('Show window clicked');
            // In a real app, this would bring the window to front
          },
        ),
        TrayMenuItem(
          label: 'Status: ${_isRunning ? "Running" : "Stopped"}',
          disabled: true,
        ),
        TrayMenuItem.separator(),
        TrayMenuItem(
          label: 'Quit',
          onTap: () {
            _logger.info('Quit clicked');
            // In a real app, this would quit the application
          },
        ),
      ]);

      setState(() {
        _trayIconVisible = true;
      });
      _updateStatus('✅ Tray icon shown');
    } catch (e) {
      _updateStatus('❌ Tray icon error: $e');
    }
  }

  Future<void> _hideTrayIcon() async {
    try {
      // For now, we'll just update the state
      // In a full implementation, we'd have a hideTrayIcon method
      setState(() {
        _trayIconVisible = false;
      });
      _updateStatus('✅ Tray icon hidden');
    } catch (e) {
      _updateStatus('❌ Tray icon error: $e');
    }
  }

  Future<void> _testSecureStorage() async {
    try {
      // Store test data
      await FlutterMCP.instance.platformServices
          .secureStore('test_key', 'This is a secure value!');

      // Read it back
      final value =
          await FlutterMCP.instance.platformServices.secureRead('test_key');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Secure Storage Test'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Stored value:'),
              const SizedBox(height: 8),
              Text(
                value ?? 'No value found',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              const Text(
                'This value was stored using native secure storage:\n'
                '• Android: EncryptedSharedPreferences\n'
                '• iOS: Keychain\n'
                '• Desktop: OS-specific secure storage',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      _updateStatus('✅ Secure storage test completed');
    } catch (e) {
      _updateStatus('❌ Secure storage error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter MCP v1.0.0'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.batch_prediction),
            onPressed: _testBatchProcessing,
            tooltip: 'Test Batch Processing',
          ),
          IconButton(
            icon: const Icon(Icons.phone_android),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const NativeFeaturesDemo()),
              );
            },
            tooltip: 'Native Features',
          ),
          IconButton(
            icon: const Icon(Icons.science),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const V1FeaturesDemo()),
              );
            },
            tooltip: 'v1.0.0 Features',
          ),
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: _showStatus,
            tooltip: 'System Status',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: _isRunning ? Colors.green[100] : Colors.grey[200],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isRunning ? Colors.green[800] : Colors.grey[800],
                  ),
                ),
                if (_isRunning && _mcpMode == 'server' && (_transportType == 'sse' || _transportType == 'streamablehttp')) ...[
                  const SizedBox(height: 4),
                  Text(
                    'To run another instance: flutter run -d macos',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Configuration
                  ExpansionTile(
                    title: const Text('Configuration'),
                    initiallyExpanded: !_isRunning,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Provider Selection
                            Row(
                      children: [
                        const Text('Provider: '),
                        Radio<String>(
                          value: 'openai',
                          groupValue: _selectedProvider,
                          onChanged: (value) =>
                              setState(() => _selectedProvider = value!),
                        ),
                        const Text('OpenAI'),
                        Radio<String>(
                          value: 'claude',
                          groupValue: _selectedProvider,
                          onChanged: (value) =>
                              setState(() => _selectedProvider = value!),
                        ),
                        const Text('Claude'),
                      ],
                    ),
                    // API Key
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        border: OutlineInputBorder(),
                        helperText: 'Required for chat functionality',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Transport Configuration Section
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'MCP Transport Configuration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // MCP Mode Selection
                    Row(
                      children: [
                        const Text('MCP Mode: '),
                        Radio<String>(
                          value: 'server',
                          groupValue: _mcpMode,
                          onChanged: (value) => setState(() => _mcpMode = value!),
                        ),
                        const Text('Server'),
                        const SizedBox(width: 20),
                        Radio<String>(
                          value: 'client',
                          groupValue: _mcpMode,
                          onChanged: (value) => setState(() => _mcpMode = value!),
                        ),
                        const Text('Client'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Mode explanation
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _mcpMode == 'server' 
                              ? '🖥️ Server Mode: This app will act as an MCP server, accepting connections from clients'
                              : '📱 Client Mode: This app will connect to an existing MCP server',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (_mcpMode == 'client') ...[
                            const SizedBox(height: 8),
                            const Text(
                              '⚠️ Note: Make sure a server is running before connecting!',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Steps: 1) Run another instance 2) Start as Server 3) Connect as Client',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '💡 Recommended: Use SSE transport for easier testing',
                              style: TextStyle(fontSize: 11, color: Colors.blue),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Transport Type Selection
                    DropdownButtonFormField<String>(
                      value: _transportType,
                      decoration: const InputDecoration(
                        labelText: 'Transport Type',
                        border: OutlineInputBorder(),
                        helperText: 'Select the MCP transport protocol',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'stdio',
                          child: Text('STDIO (Standard I/O)'),
                        ),
                        DropdownMenuItem(
                          value: 'sse',
                          child: Text('SSE (Server-Sent Events)'),
                        ),
                        DropdownMenuItem(
                          value: 'streamablehttp',
                          child: Text('Streamable HTTP'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _transportType = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Conditional fields based on mode and transport type
                    if (_mcpMode == 'server') ...[
                      // Server mode - only show port and endpoint configuration
                      if (_transportType == 'stdio') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'STDIO Server Configuration',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'In STDIO mode, the MCP server runs as a subprocess. Clients will execute this server using a command.',
                                style: TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Note: STDIO servers don\'t listen on network ports.',
                                style: TextStyle(fontSize: 12, color: Colors.orange),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '💡 Tip: For testing server-client connection, try SSE transport instead of Streamable HTTP',
                                  style: TextStyle(fontSize: 12, color: Colors.orange),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'To connect a client to this server, use:',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'flutter run',
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Or provide the path to your compiled executable',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_transportType == 'sse') ...[
                        TextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: 'Base URL',
                            border: const OutlineInputBorder(),
                            helperText: 'Base URL for the server (e.g., http://localhost)',
                            errorText: _serverUrlError,
                          ),
                          onChanged: (_) => _validateServerUrl(_serverUrlController.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ssePortController,
                          decoration: InputDecoration(
                            labelText: 'SSE Port',
                            border: const OutlineInputBorder(),
                            helperText: 'Port to listen on for SSE connections (e.g., 8080)',
                            errorText: _ssePortError,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _validatePort(_ssePortController.text, 'sse'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _sseEndpointController,
                          decoration: const InputDecoration(
                            labelText: 'SSE Endpoint Path',
                            border: OutlineInputBorder(),
                            helperText: 'Endpoint path for SSE (e.g., /sse, /events)',
                          ),
                        ),
                      ] else if (_transportType == 'streamablehttp') ...[
                        TextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: 'Base URL',
                            border: const OutlineInputBorder(),
                            helperText: 'Base URL for the server (e.g., http://localhost)',
                            errorText: _serverUrlError,
                          ),
                          onChanged: (_) => _validateServerUrl(_serverUrlController.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _httpPortController,
                          decoration: InputDecoration(
                            labelText: 'HTTP Port',
                            border: const OutlineInputBorder(),
                            helperText: 'Port to listen on for HTTP connections (e.g., 8081)',
                            errorText: _httpPortError,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _validatePort(_httpPortController.text, 'http'),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'Note: Streamable HTTP uses SSE protocol internally.\nNo endpoint path configuration needed.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ] else ...[
                      // Client mode - show connection configuration
                      if (_transportType == 'stdio') ...[
                        TextField(
                          controller: _transportCommandController,
                          decoration: InputDecoration(
                            labelText: 'Transport Command',
                            border: const OutlineInputBorder(),
                            helperText: 'Command to run for STDIO transport (e.g., python server.py)',
                            errorText: _transportCommandError,
                          ),
                          onChanged: (_) => _validateTransportCommand(_transportCommandController.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _transportArgsController,
                          decoration: const InputDecoration(
                            labelText: 'Transport Arguments (optional)',
                            border: OutlineInputBorder(),
                            helperText: 'Space-separated arguments for the command',
                          ),
                        ),
                      ] else if (_transportType == 'sse') ...[
                        TextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: 'Server URL',
                            border: const OutlineInputBorder(),
                            helperText: 'SSE server URL to connect to (e.g., http://localhost)',
                            errorText: _serverUrlError,
                          ),
                          onChanged: (_) => _validateServerUrl(_serverUrlController.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ssePortController,
                          decoration: InputDecoration(
                            labelText: 'SSE Port',
                            border: const OutlineInputBorder(),
                            helperText: 'Port for SSE connection (e.g., 8080)',
                            errorText: _ssePortError,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _validatePort(_ssePortController.text, 'sse'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _sseEndpointController,
                          decoration: const InputDecoration(
                            labelText: 'SSE Endpoint Path',
                            border: OutlineInputBorder(),
                            helperText: 'Endpoint path for SSE (e.g., /sse, /events)',
                          ),
                        ),
                      ] else if (_transportType == 'streamablehttp') ...[
                        TextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: 'Server URL',
                            border: const OutlineInputBorder(),
                            helperText: 'HTTP server URL to connect to (e.g., http://localhost)',
                            errorText: _serverUrlError,
                          ),
                          onChanged: (_) => _validateServerUrl(_serverUrlController.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _httpPortController,
                          decoration: InputDecoration(
                            labelText: 'HTTP Port',
                            border: const OutlineInputBorder(),
                            helperText: 'Port for HTTP connection (e.g., 8081)',
                            errorText: _httpPortError,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _validatePort(_httpPortController.text, 'http'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _httpEndpointController,
                          decoration: const InputDecoration(
                            labelText: 'HTTP Endpoint',
                            border: OutlineInputBorder(),
                            helperText: 'Endpoint path for HTTP connection (e.g., /mcp)',
                          ),
                        ),
                      ],
                    ],
                    
                    // Auth Token (common for all transport types)
                    const SizedBox(height: 8),
                    TextField(
                      controller: _authTokenController,
                      decoration: const InputDecoration(
                        labelText: 'Authentication Token (optional)',
                        border: OutlineInputBorder(),
                        helperText: 'Optional auth token for secure connections',
                      ),
                      obscureText: true,
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saveApiKey,
                          child: const Text('Save'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed:
                              _isRunning ? _stopServices : _startServices,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isRunning ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_isRunning ? 'Stop' : 'Start'),
                        ),
                      ],
                            ),
                          ],
                        ),
                      ),
                    ],
          ),

          // Native Platform Features
          ExpansionTile(
                    title: const Text('Native Platform Features'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Background Service
                            ListTile(
                      title: const Text('Background Service'),
                      subtitle: Text(
                          _backgroundServiceRunning ? 'Running' : 'Stopped'),
                      trailing: Switch(
                        value: _backgroundServiceRunning,
                        onChanged: _isRunning
                            ? (value) async {
                                if (value) {
                                  await _startBackgroundService();
                                } else {
                                  await _stopBackgroundService();
                                }
                              }
                            : null,
                      ),
                    ),

                    // Notifications
                    ListTile(
                      title: const Text('Test Notification'),
                      subtitle: Text(_notificationPermissionGranted
                          ? 'Permission granted'
                          : 'Permission needed'),
                      trailing: ElevatedButton(
                        onPressed: _isRunning ? _showTestNotification : null,
                        child: const Text('Show'),
                      ),
                    ),

                    // System Tray (Desktop only)
                    if (_isDesktopPlatform()) ...[
                      ListTile(
                        title: const Text('System Tray'),
                        subtitle: Text(_trayIconVisible ? 'Visible' : 'Hidden'),
                        trailing: Switch(
                          value: _trayIconVisible,
                          onChanged: _isRunning
                              ? (value) async {
                                  if (value) {
                                    await _showTrayIcon();
                                  } else {
                                    await _hideTrayIcon();
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],

                    // Secure Storage Demo
                    ListTile(
                      title: const Text('Secure Storage'),
                      subtitle: const Text('Store API keys securely'),
                      trailing: ElevatedButton(
                        onPressed: _isRunning ? _testSecureStorage : null,
                        child: const Text('Test'),
                      ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Chat Interface Section
                  Container(
                    height: 400, // Fixed height for chat
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
              children: [
                // Messages
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isError
                                ? Colors.red[100]
                                : msg.isUser
                                    ? Colors.blue[100]
                                    : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(msg.text),
                        ),
                      );
                    },
                  ),
                ),

                // Input
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border(top: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          enabled: _isRunning && _llmId != null,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed:
                            _isRunning && _llmId != null ? _sendMessage : null,
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                ),
              ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });
}
