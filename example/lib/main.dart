import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Flutter MCP system
  await initMCP();

  runApp(const MCPIntegrationApp());
}

/// Initialize MCP with configuration
Future<void> initMCP() async {
  // Set up logging
  MCPLogger.setDefaultLevel(LogLevel.debug);
  final logger = MCPLogger('integration_app');

  logger.info('Initializing MCP...');

  try {
    // Load API keys securely
    final prefs = await SharedPreferences.getInstance();
    final openaiApiKey = prefs.getString('openai_api_key') ?? '';
    final claudeApiKey = prefs.getString('claude_api_key') ?? '';

    // Configure the MCP system
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'MCP Integration Demo',
        appVersion: '1.0.0',
        useBackgroundService: true,
        useNotification: true,
        useTray: true,
        autoStart: false, // We'll start services manually
        loggingLevel: LogLevel.debug,
        enablePerformanceMonitoring: true, // Enable performance monitoring
        highMemoryThresholdMB: 512, // Set memory threshold for automatic cleanup
        background: BackgroundConfig(
          notificationChannelId: 'mcp_demo_channel',
          notificationChannelName: 'MCP Demo Service',
          notificationDescription: 'Running MCP Demo Service',
          autoStartOnBoot: false,
          intervalMs: 5000,
        ),
        notification: NotificationConfig(
          channelId: 'mcp_demo_channel',
          channelName: 'MCP Demo',
          channelDescription: 'MCP Demo Notifications',
          priority: NotificationPriority.normal,
        ),
        tray: TrayConfig(
          tooltip: 'MCP Integration Demo',
          menuItems: [
            TrayMenuItem(label: 'Show', onTap: () {
              // Code to show app window
              logger.debug('Show app from tray');
            }),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Exit', onTap: () {
              // Code to exit app
              logger.debug('Exit app from tray');
            }),
          ],
        ),
        // We'll set up components programmatically instead of auto-start
      ),
    );

    logger.info('MCP initialized successfully');
  } catch (e, stackTrace) {
    logger.error('Failed to initialize MCP', e, stackTrace);
    // In a real app, you might want to show an error dialog
  }
}

class MCPIntegrationApp extends StatelessWidget {
  const MCPIntegrationApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Integration Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final MCPLogger _logger = MCPLogger('integration_app.home_page');

  // Services state
  bool _servicesRunning = false;

  // Component IDs
  String? _serverId;
  String? _clientId;
  String? _llmId;

  // Chat
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _chatMessages = [];

  // API keys
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _claudeKeyController = TextEditingController();

  // Stored file path
  String? _filePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApiKeys();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _openaiKeyController.dispose();
    _claudeKeyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _logger.debug('App paused, saving state');
      _saveApiKeys();
    }
  }

  // Load API keys from storage
  Future<void> _loadApiKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _openaiKeyController.text = prefs.getString('openai_api_key') ?? '';
        _claudeKeyController.text = prefs.getString('claude_api_key') ?? '';
      });
    } catch (e) {
      _logger.error('Failed to load API keys', e);
    }
  }

  // Save API keys to storage
  Future<void> _saveApiKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('openai_api_key', _openaiKeyController.text);
      await prefs.setString('claude_api_key', _claudeKeyController.text);
    } catch (e) {
      _logger.error('Failed to save API keys', e);
    }
  }

  // Helper method to check if MCP is ready
  bool isReady() {
    try {
      // If getSystemStatus doesn't throw an exception, it's ready
      FlutterMCP.instance.getSystemStatus();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Start MCP services
  Future<void> _startServices() async {
    if (!isReady()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MCP is not initialized')),
      );
      return;
    }

    setState(() => _servicesRunning = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Starting MCP services...')),
    );

    try {
      // Create MCP server
      _serverId = await FlutterMCP.instance.createServer(
        name: 'Demo Server',
        version: '1.0.0',
        capabilities: const ServerCapabilities(
          tools: true,
          toolsListChanged: true,
          resources: true,
          resourcesListChanged: true,
          prompts: true,
          promptsListChanged: true,
          sampling: true,
        ),
      );

      // Create LLM client
      _llmId = await _createLlm();

      // Integrate server with LLM
      if (_serverId != null && _llmId != null) {
        await FlutterMCP.instance.integrateServerWithLlm(
          serverId: _serverId!,
          llmId: _llmId!,
        );
      }

      // Connect server
      if (_serverId != null) {
        FlutterMCP.instance.connectServer(_serverId!);
      }

      // Create MCP client
      _clientId = await FlutterMCP.instance.createClient(
        name: 'Demo Client',
        version: '1.0.0',
        capabilities: const ClientCapabilities(
          sampling: true,
          roots: true,
          rootsListChanged: true,
        ),
        transportCommand: 'localhost', // Simplified for demo
      );

      // Connect client
      if (_clientId != null) {
        await FlutterMCP.instance.connectClient(_clientId!);
      }

      // Integrate client with LLM
      if (_clientId != null && _llmId != null) {
        await FlutterMCP.instance.integrateClientWithLlm(
          clientId: _clientId!,
          llmId: _llmId!,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MCP services started successfully')),
      );
    } catch (e) {
      _logger.error('Failed to start services', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
      setState(() => _servicesRunning = false);
    }
  }

  // Stop MCP services
  Future<void> _stopServices() async {
    setState(() => _servicesRunning = false);

    try {
      await FlutterMCP.instance.shutdown();

      setState(() {
        _serverId = null;
        _clientId = null;
        _llmId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MCP services stopped')),
      );
    } catch (e) {
      _logger.error('Failed to stop services', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  // Create LLM client
  Future<String> _createLlm() async {
    // Determine which API key to use - prefer Claude if available
    if (_claudeKeyController.text.isNotEmpty) {
      return await FlutterMCP.instance.createLlm(
        providerName: 'claude',
        config: LlmConfiguration(
          apiKey: _claudeKeyController.text,
          model: 'claude-3-sonnet-20240229',
        ),
      );
    } else if (_openaiKeyController.text.isNotEmpty) {
      return await FlutterMCP.instance.createLlm(
        providerName: 'openai',
        config: LlmConfiguration(
          apiKey: _openaiKeyController.text,
          model: 'gpt-4o',
        ),
      );
    } else {
      throw Exception('No API key provided for LLM');
    }
  }

  // Send message to LLM
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _llmId == null) return;

    setState(() {
      _chatMessages.add(ChatMessage(
        text: message,
        isUser: true,
      ));
      _messageController.clear();
    });

    try {
      // Use memory-efficient chat method with caching enabled
      final response = await FlutterMCP.instance.chat(
        _llmId!,
        message,
        enableTools: true,
        useCache: true, // Enable caching for faster subsequent responses
      );

      setState(() {
        _chatMessages.add(ChatMessage(
          text: response.text,
          isUser: false,
        ));
      });
    } catch (e) {
      _logger.error('Failed to send message', e);
      setState(() {
        _chatMessages.add(ChatMessage(
          text: 'Error: ${e.toString()}',
          isUser: false,
          isError: true,
        ));
      });
    }
  }

  // Check service status
  Future<void> _checkStatus() async {
    try {
      final status = FlutterMCP.instance.getSystemStatus();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('MCP Status'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Initialized: ${status['initialized']}'),
                Text('Clients: ${status['clients']}'),
                Text('Servers: ${status['servers']}'),
                Text('LLMs: ${status['llms']}'),
                Text('Background Service: ${status['backgroundServiceRunning']}'),
                Text('Scheduler: ${status['schedulerRunning']}'),
                Text('Platform: ${status['platformName']}'),
                const Divider(),
                const Text('Memory Usage:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (status['performanceMetrics'] != null &&
                    status['performanceMetrics']['resources'] != null &&
                    status['performanceMetrics']['resources']['memory.usageMB'] != null)
                  Text('Current: ${status['performanceMetrics']['resources']['memory.usageMB']['current']}MB'),
                const Divider(),
                const Text('Client Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(status['clientsStatus'].toString()),
                const Divider(),
                const Text('Server Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(status['serversStatus'].toString()),
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
      _logger.error('Failed to get status', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Integration Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _checkStatus,
            tooltip: 'Check Status',
          ),
        ],
      ),
      body: Column(
        children: [
          // Services control
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'MCP Services: ${_servicesRunning ? 'Running' : 'Stopped'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: _servicesRunning ? _stopServices : _startServices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _servicesRunning ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_servicesRunning ? 'Stop' : 'Start'),
                ),
              ],
            ),
          ),

          // API Key setup
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('API Keys', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _openaiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'OpenAI API Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _claudeKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Claude API Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _saveApiKeys,
                  child: const Text('Save API Keys'),
                ),
              ],
            ),
          ),

          // Chat interface
          Expanded(
            child: Column(
              children: [
                // Chat messages
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final message = _chatMessages[index];
                      return ChatBubble(message: message);
                    },
                  ),
                ),

                // Message input
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Enter message...',
                            border: OutlineInputBorder(),
                          ),
                          enabled: _servicesRunning && _llmId != null,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _servicesRunning && _llmId != null
                            ? _sendMessage
                            : null,
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

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: message.isError
              ? Colors.red[100]
              : message.isUser
              ? Colors.blue[100]
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message.text),
      ),
    );
  }
}