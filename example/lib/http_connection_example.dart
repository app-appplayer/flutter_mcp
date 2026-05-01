import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

/// Flutter MCP HTTP connection example.
///
/// Demonstrates the supported way to talk to an MCP server over HTTP.
/// Each `MCPClientConfig` must declare its `transportType` explicitly —
/// the runtime never infers it from the URL.
final _log = Logger('flutter_mcp.http_connection_example');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterMcpLogging.configure(level: Level.INFO);

  try {
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'HTTP Connection Example',
        appVersion: '1.0.0',
        autoStart: false,
        useBackgroundService: false,
        useNotification: false,
        useTray: false,
      ),
    );
    _log.info('Flutter MCP initialized successfully');
  } catch (e) {
    _log.severe('Failed to initialize Flutter MCP: $e');
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP HTTP Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HttpConnectionExample(),
    );
  }
}

class HttpConnectionExample extends StatefulWidget {
  const HttpConnectionExample({Key? key}) : super(key: key);

  @override
  State<HttpConnectionExample> createState() => _HttpConnectionExampleState();
}

class _HttpConnectionExampleState extends State<HttpConnectionExample> {
  String? _clientId;
  String _status = 'Not connected';
  final TextEditingController _urlController = TextEditingController(
    text: 'http://localhost:8080/sse',
  );

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Connect with a fully-described `MCPClientConfig`. The transport
  /// type is picked by inspecting the path the user typed; you would
  /// normally know which transport you're targeting and hard-code it.
  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = 'URL is empty');
      return;
    }

    setState(() => _status = 'Connecting...');

    try {
      // Pick a transport based on the URL convention. In production
      // pick this once for your deployment, not at runtime.
      String transportType;
      String? endpoint;
      String serverUrl = url;
      if (url.contains('/sse')) {
        transportType = 'sse';
        // Strip the path so MCPClientConfig can re-append `endpoint`.
        final uri = Uri.parse(url);
        serverUrl = uri.replace(path: '').toString();
        endpoint = uri.path;
      } else if (url.contains('/mcp')) {
        transportType = 'streamablehttp';
        final uri = Uri.parse(url);
        serverUrl = uri.replace(path: '').toString();
        endpoint = uri.path;
      } else {
        transportType = 'sse';
      }

      final config = MCPClientConfig(
        name: 'HTTP Client',
        version: '1.0.0',
        transportType: transportType,
        serverUrl: serverUrl,
        endpoint: endpoint,
      );

      _clientId = await FlutterMCP.instance.createClient(
        name: config.name,
        version: config.version,
        config: config,
      );

      await FlutterMCP.instance.connectClient(_clientId!);

      setState(() => _status =
          'Connected via $transportType to $serverUrl${endpoint ?? ''}');
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
      setState(() => _status = 'Disconnect error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter MCP HTTP Connection'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection status.
            Card(
              color: _clientId != null ? Colors.green[50] : Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Status: $_status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_clientId != null) ...[
                      const SizedBox(height: 8),
                      Text('Client ID: $_clientId'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // URL input.
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://localhost:8080/sse',
                border: OutlineInputBorder(),
                helperText:
                    'SSE: /sse endpoint, StreamableHTTP: /mcp endpoint',
              ),
            ),
            const SizedBox(height: 20),

            // Help.
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Note: transportType must be specified',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                        '• MCPClientConfig requires transportType (no auto-inference).'),
                    Text(
                        '• Pick transportType once for your deployment, not from the URL.'),
                    SizedBox(height: 8),
                    Text('Transport types:'),
                    Text('  - sse: Server-Sent Events'),
                    Text('  - streamablehttp: Streamable HTTP'),
                    Text('  - stdio: Standard I/O (local subprocess)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons.
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clientId == null ? _connect : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clientId != null ? _disconnect : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
