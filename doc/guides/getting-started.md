# Getting Started

Get started with the Flutter MCP plugin and create your first MCP client.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^0.1.0
```

## Basic Setup

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load MCP configuration
  final config = await MCPConfig.fromFile('assets/mcp_config.json');
  
  // Initialize Flutter MCP
  final mcp = FlutterMCP();
  await mcp.initialize(
    config: config,
    enablePerformanceMonitoring: true,
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
  final mcp = FlutterMCP();
  MCPClient? client;
  
  @override
  void initState() {
    super.initState();
    _initializeClient();
  }
  
  Future<void> _initializeClient() async {
    // Create client
    client = await mcp.clientManager.createClient(
      clientConfig: ClientConfig(
        id: 'my_client',
        serverUrl: 'http://localhost:3000',
        retryPolicy: RetryPolicy(
          maxRetries: 3,
          retryDelay: Duration(seconds: 1),
        ),
      ),
    );
    
    // Connect to server
    await client?.connect();
  }
  
  Future<void> _sendMessage() async {
    final response = await client?.send(
      method: 'chat',
      params: {
        'message': 'Hello, MCP Server!',
      },
    );
    
    print('Response: ${response?.data}');
  }
  
  @override
  void dispose() {
    client?.disconnect();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MCP Client')),
      body: Center(
        child: ElevatedButton(
          onPressed: _sendMessage,
          child: Text('Send Message'),
        ),
      ),
    );
  }
}
```

## Server Management

```dart
// Monitor server status
mcp.serverManager.serverStream.listen((servers) {
  print('Active servers: ${servers.length}');
  for (final server in servers) {
    print('Server ${server.id}: ${server.status}');
  }
});

// Add server
await mcp.serverManager.addServer(
  ServerConfig(
    id: 'my_server',
    name: 'My MCP Server',
    command: 'node',
    args: ['server.js'],
    env: {'NODE_ENV': 'development'},
  ),
);

// Start server
await mcp.serverManager.startServer('my_server');
```

## LLM Integration

```dart
// Add LLM
await mcp.llmManager.addLLM(
  LLMConfig(
    id: 'openai',
    provider: 'openai',
    model: 'gpt-4',
    apiKey: 'your-api-key',
  ),
);

// Use LLM
final response = await mcp.llmManager.query(
  llmId: 'openai',
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
// Configure background service
await mcp.backgroundService.configure(
  BackgroundConfig(
    enableSync: true,
    syncInterval: Duration(minutes: 15),
    enableNotifications: true,
  ),
);

// Register task
await mcp.backgroundService.registerTask(
  taskId: 'sync_data',
  handler: () async {
    // Data sync logic
    print('Syncing data in background...');
  },
);
```

## Next Steps

- [Transport Configuration](transport-configuration.md) - Learn about different transport types and their configuration
- [Architecture](architecture.md) - Understand the plugin's internal structure
- [Plugin System](../plugins/development.md) - Develop custom plugins
- [Platform Guides](../platform/README.md) - Platform-specific optimizations

## Example Project

Check out the full example in the [GitHub repository](https://github.com/your-org/flutter_mcp/tree/main/example).