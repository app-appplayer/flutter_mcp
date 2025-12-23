# Getting Started

Get started with the Flutter MCP plugin and create your first MCP client.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^1.0.4
```

## Basic Setup

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP with minimal configuration
  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'My MCP App',
      appVersion: '1.0.0',
      autoStart: false,
      // Disable platform features for simplicity
      useBackgroundService: false,
      useNotification: false,
      useTray: false,
      secure: false,
    ),
  );
  
  runApp(MyApp());
}
```

## Your First MCP Client

```dart
class MyMCPClient extends StatefulWidget {
  @override
  _MyMCPClientState createState() => _MyMCPClientState();
}

class _MyMCPClientState extends State<MyMCPClient> {
  String? _clientId;
  bool _isConnected = false;
  
  @override
  void initState() {
    super.initState();
    _initializeClient();
  }
  
  Future<void> _initializeClient() async {
    try {
      // Create client with simple configuration
      _clientId = await FlutterMCP.instance.createClient(
        name: 'My Client',
        version: '1.0.0',
        serverUrl: 'http://localhost:8080/sse',
        // Optional: specify transport type explicitly
        transportType: 'sse',
      );
      
      // Connect to server
      await FlutterMCP.instance.connectClient(_clientId!);
      
      setState(() {
        _isConnected = true;
      });
    } catch (e) {
      print('Failed to connect: $e');
    }
  }
  
  Future<void> _sendMessage() async {
    if (_clientId == null || !_isConnected) return;
    
    try {
      // Call a tool on the server
      final result = await FlutterMCP.instance.clientManager
          .callTool(_clientId!, 'echo', {
        'message': 'Hello, MCP Server!',
      });
      
      print('Response: $result');
    } catch (e) {
      print('Error sending message: $e');
    }
  }
  
  @override
  void dispose() {
    // Clean up client connection
    if (_clientId != null) {
      FlutterMCP.instance.clientManager.closeClient(_clientId!);
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MCP Client')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isConnected ? 'Connected' : 'Disconnected'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isConnected ? _sendMessage : null,
              child: Text('Send Message'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Advanced Client Configuration

For more control over the client connection, use `MCPClientConfig`:

```dart
// Create client with detailed configuration
final clientId = await FlutterMCP.instance.clientManager.createClient(
  MCPClientConfig(
    name: 'Advanced Client',
    version: '1.0.0',
    transportType: 'sse',
    serverUrl: 'http://localhost:8080/sse',
    authToken: 'your-auth-token',
    timeout: Duration(seconds: 30),
    sseReadTimeout: Duration(minutes: 5),
    headers: {
      'X-Custom-Header': 'value',
    },
    capabilities: ClientCapabilities(
      roots: {'file:///workspace': {}},
      sampling: {},
    ),
  ),
);
```

## Server Management

```dart
// Add a server configuration
final serverId = await FlutterMCP.instance.serverManager.addServer(
  MCPServerConfig(
    name: 'My Server',
    version: '1.0.0',
    transportType: 'stdio',
    transportCommand: 'node',
    transportArgs: ['server.js'],
    env: {'NODE_ENV': 'development'},
  ),
);

// Start the server
await FlutterMCP.instance.serverManager.startServer(serverId);

// Monitor server status
FlutterMCP.instance.serverManager.serverStream.listen((servers) {
  for (final server in servers) {
    print('Server ${server.id}: ${server.status}');
  }
});
```

## LLM Integration

```dart
// Add LLM configuration
final llmId = await FlutterMCP.instance.llmManager.addLLM(
  LLMConfig(
    id: 'openai',
    provider: 'openai',
    model: 'gpt-4',
    apiKey: 'your-api-key',
  ),
);

// Use LLM for queries
final response = await FlutterMCP.instance.llmManager.query(
  llmId: llmId,
  prompt: 'Translate to Korean: Hello, world!',
  options: QueryOptions(
    temperature: 0.7,
    maxTokens: 100,
  ),
);

print('Translation: ${response.text}');
```

## Background Tasks

```dart
// Configure background service (requires platform features enabled)
await FlutterMCP.instance.init(
  MCPConfig(
    appName: 'MCP Background Example',
    appVersion: '1.0.0',
    useBackgroundService: true,
    background: BackgroundConfig(
      notificationChannelId: 'mcp_background',
      notificationChannelName: 'MCP Background Service',
      notificationDescription: 'Keeps MCP running in background',
      intervalMs: 60000, // 1 minute
      keepAlive: true,
    ),
  ),
);

// Register background task
await FlutterMCP.instance.backgroundService.registerTask(
  taskId: 'sync_data',
  handler: () async {
    print('Running background sync...');
    // Your background logic here
  },
);
```

## Error Handling

```dart
try {
  await FlutterMCP.instance.connectClient(clientId);
} on MCPConnectionException catch (e) {
  // Handle connection errors
  print('Connection failed: ${e.message}');
} on MCPException catch (e) {
  // Handle general MCP errors
  print('MCP error: ${e.message}');
} catch (e) {
  // Handle unexpected errors
  print('Unexpected error: $e');
}
```

## Status Monitoring

```dart
// Check initialization status
if (FlutterMCP.instance.isInitialized) {
  print('MCP is initialized');
}

// Get detailed status
final status = FlutterMCP.instance.getStatus();
print('Clients: ${status['clientCount']}');
print('Servers: ${status['serverCount']}');
print('LLMs: ${status['llmCount']}');

// Get manager-specific status
final clientStatus = FlutterMCP.instance.clientManagerStatus;
final serverStatus = FlutterMCP.instance.serverManagerStatus;
final llmStatus = FlutterMCP.instance.llmManagerStatus;
```

## Next Steps

- [Transport Configuration](transport-configuration.md) - Learn about different transport types and their configuration
- [Architecture](architecture.md) - Understand the plugin's internal structure
- [Plugin System](../plugins/development.md) - Develop custom plugins
- [Platform Guides](../platform/README.md) - Platform-specific optimizations

## Example Project

Check out the full example in the [GitHub repository](https://github.com/app-appplayer/flutter_mcp/tree/main/example).

## Common Issues

### "Flutter MCP is not initialized" Error

This error occurs when trying to use MCP features before initialization. Make sure to:

1. Call `FlutterMCP.instance.init()` before using any MCP features
2. Wait for the initialization to complete (it's asynchronous)
3. Check `FlutterMCP.instance.isInitialized` before making calls

### Transport Type Issues

If you're having connection issues, explicitly specify the transport type:

```dart
// For SSE connections
_clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '1.0.0',
  serverUrl: 'http://localhost:8080/sse',
  transportType: 'sse', // Explicitly specify transport
);

// For StreamableHttp connections
_clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '1.0.0',
  serverUrl: 'http://localhost:8080/mcp',
  transportType: 'streamablehttp',
);
```