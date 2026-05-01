import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

/// Minimal Flutter MCP initialisation example.
///
/// Initialises the MCP runtime without any platform-specific features
/// (no background service, no notifications, no tray, no secure
/// storage). Useful when troubleshooting "Flutter MCP is not
/// initialized" failures triggered by platform-permission flows.
final _log = Logger('flutter_mcp.simple_init_example');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterMcpLogging.configure(level: Level.INFO);

  // Minimal config — every platform integration is disabled.
  try {
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'Simple MCP Example',
        appVersion: '1.0.0',
        autoStart: false,
        useBackgroundService: false,
        useNotification: false,
        useTray: false,
        secure: false,
        enablePerformanceMonitoring: false,
      ),
    );
    _log.info('Flutter MCP initialized successfully');
  } catch (e) {
    _log.severe('Failed to initialize Flutter MCP: $e');
    // Bail out instead of running an app on top of a broken runtime.
    return;
  }

  runApp(const SimpleApp());
}

class SimpleApp extends StatelessWidget {
  const SimpleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Flutter MCP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SimpleExample(),
    );
  }
}

class SimpleExample extends StatefulWidget {
  const SimpleExample({Key? key}) : super(key: key);

  @override
  State<SimpleExample> createState() => _SimpleExampleState();
}

class _SimpleExampleState extends State<SimpleExample> {
  String? _clientId;
  String _status = 'Ready';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkInitialization();
  }

  void _checkInitialization() {
    setState(() {
      _isInitialized = FlutterMCP.instance.isInitialized;
      _status = _isInitialized ? 'MCP Initialized' : 'MCP Not Initialized';
    });
  }

  Future<void> _testConnection() async {
    if (!_isInitialized) {
      setState(() => _status = 'MCP not initialized!');
      return;
    }

    setState(() => _status = 'Testing connection...');

    try {
      // Create a client through the public API. transportType must be
      // declared explicitly via MCPClientConfig — there is no auto-
      // inference.
      _clientId = await FlutterMCP.instance.createClient(
        name: 'Test Client',
        version: '1.0.0',
        config: MCPClientConfig(
          name: 'Test Client',
          version: '1.0.0',
          transportType: 'sse',
          serverUrl: 'http://localhost:8080',
          endpoint: '/sse',
        ),
      );

      setState(() => _status = 'Client created: $_clientId');

      await FlutterMCP.instance.connectClient(_clientId!);
      setState(() => _status = 'Connected successfully!');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_clientId == null) return;

    try {
      await FlutterMCP.instance.clientManager.closeClient(_clientId!);
      setState(() {
        _clientId = null;
        _status = 'Disconnected';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Flutter MCP Test'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Initialisation state.
              Card(
                color: _isInitialized ? Colors.green[100] : Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        _isInitialized ? Icons.check_circle : Icons.error,
                        size: 48,
                        color: _isInitialized ? Colors.green : Colors.red,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Flutter MCP: ${_isInitialized ? "Initialized" : "Not Initialized"}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Status text.
              Text(
                _status,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Action buttons.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _isInitialized && _clientId == null
                        ? _testConnection
                        : null,
                    child: const Text('Test Connection'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _clientId != null ? _disconnect : null,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Help text.
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Troubleshooting:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('1. If MCP is not initialized:'),
                      Text('   - Disable platform features (as in this example)'),
                      Text('   - Check runtime permission grants'),
                      SizedBox(height: 8),
                      Text('2. If the connection fails:'),
                      Text('   - Confirm the server is running'),
                      Text('   - Verify the URL and port'),
                      Text('   - Set transportType explicitly in MCPClientConfig'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
