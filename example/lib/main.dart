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

  // Health monitoring
  StreamSubscription? _healthSubscription;

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

  Future<void> _startServices() async {
    setState(() => _isRunning = true);
    _updateStatus('Starting services...');

    try {
      // Create server
      _serverId = await FlutterMCP.instance.createServer(
        name: 'Demo Server',
        version: '1.0.0',
        capabilities: ServerCapabilities.simple(
          tools: true,
          resources: true,
          prompts: true,
          sampling: true,
        ),
      );

      // Create LLM if API key provided
      if (_apiKeyController.text.isNotEmpty) {
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

      // Create client
      _clientId = await FlutterMCP.instance.createClient(
        name: 'Demo Client',
        version: '1.0.0',
        capabilities: const ClientCapabilities(),
        transportCommand: 'echo',
      );

      // Connect services
      if (_serverId != null) {
        FlutterMCP.instance.connectServer(_serverId!);
      }

      if (_clientId != null) {
        await FlutterMCP.instance.connectClient(_clientId!);
      }

      _updateStatus('✅ Services running');
    } catch (e) {
      _logger.error('Failed to start services: $e');
      _updateStatus('❌ Error: ${e.toString()}');
      setState(() => _isRunning = false);
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
            child: Text(
              _status,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _isRunning ? Colors.green[800] : Colors.grey[800],
              ),
            ),
          ),

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
                    const SizedBox(height: 8),
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

          // Chat Interface
          Expanded(
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
