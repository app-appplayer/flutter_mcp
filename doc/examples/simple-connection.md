# Simple Connection Example

This example demonstrates basic MCP client connection and method execution.

## Overview

This example shows how to:
- Initialize Flutter MCP
- Connect to a single MCP server
- Execute remote methods
- Handle errors

## Code Example

### Main Application

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP with minimal configuration
  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'MCP Simple Connection',
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

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Simple Connection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
    );
  }
}
```

### Home Screen

```dart
// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _clientId;
  String _status = 'Disconnected';
  String _result = '';
  bool _loading = false;
  
  @override
  void initState() {
    super.initState();
    _connectToServer();
  }
  
  Future<void> _connectToServer() async {
    setState(() {
      _loading = true;
      _status = 'Connecting...';
    });
    
    try {
      // Create client
      _clientId = await FlutterMCP.instance.createClient(
        name: 'Demo Client',
        version: '1.0.0',
        serverUrl: 'http://localhost:3000/sse',
        transportType: 'sse',
      );
      
      // Connect to server
      await FlutterMCP.instance.connectClient(_clientId!);
      
      setState(() {
        _status = 'Connected';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
  
  Future<void> _executeMethod() async {
    if (_clientId == null) {
      setState(() {
        _result = 'Not connected';
      });
      return;
    }
    
    setState(() {
      _loading = true;
      _result = 'Executing...';
    });
    
    try {
      // Call a tool on the server
      final result = await FlutterMCP.instance.clientManager.callTool(
        _clientId!,
        'echo',
        {
          'message': 'Hello from Flutter!',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      setState(() {
        _result = 'Result: ${result.toString()}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
  
  Future<void> _disconnect() async {
    if (_clientId == null) return;
    
    setState(() {
      _loading = true;
    });
    
    try {
      await FlutterMCP.instance.clientManager.closeClient(_clientId!);
      setState(() {
        _clientId = null;
        _status = 'Disconnected';
        _result = '';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loading = false;
      });
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
      appBar: AppBar(
        title: Text('Simple Connection Example'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Status',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _status.startsWith('Connected')
                            ? Colors.green
                            : _status.startsWith('Error')
                                ? Colors.red
                                : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Method Result',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: 8),
                    Text(_result.isEmpty ? 'No result yet' : _result),
                  ],
                ),
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _executeMethod,
              child: Text('Execute Method'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading || _clientId == null ? null : _disconnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text('Disconnect'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading || _clientId != null ? null : _connectToServer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: Text('Reconnect'),
            ),
            if (_loading)
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

### MCP Service (Optional)

```dart
// lib/services/mcp_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPService {
  String? _clientId;
  
  Future<void> connect() async {
    _clientId = await FlutterMCP.instance.createClient(
      name: 'Demo Client',
      version: '1.0.0',
      serverUrl: 'http://localhost:3000/sse',
      transportType: 'sse',
    );
    await FlutterMCP.instance.connectClient(_clientId!);
  }
  
  Future<void> disconnect() async {
    if (_clientId != null) {
      await FlutterMCP.instance.clientManager.closeClient(_clientId!);
      _clientId = null;
    }
  }
  
  bool get isConnected => _clientId != null;
  
  Future<Map<String, dynamic>> echo(String message) async {
    if (_clientId == null) {
      throw MCPException('Not connected');
    }
    
    return await FlutterMCP.instance.clientManager.callTool(
      _clientId!,
      'echo',
      {
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
  
  Future<Map<String, dynamic>> getData() async {
    if (_clientId == null) {
      throw MCPException('Not connected');
    }
    
    return await FlutterMCP.instance.clientManager.callTool(
      _clientId!,
      'getData',
      {},
    );
  }
}
```

## Advanced Configuration

### Using MCPClientConfig

```dart
// Create client with detailed configuration
final clientId = await FlutterMCP.instance.clientManager.createClient(
  MCPClientConfig(
    name: 'Advanced Client',
    version: '1.0.0',
    transportType: 'sse',
    serverUrl: 'http://localhost:3000/sse',
    authToken: 'your-auth-token',
    timeout: Duration(seconds: 30),
    sseReadTimeout: Duration(minutes: 5),
    headers: {
      'X-API-Key': 'your-api-key',
    },
    capabilities: ClientCapabilities(
      roots: {'file:///workspace': {}},
      sampling: {},
    ),
  ),
);
```

### Monitoring Connection Status

```dart
// Get client info
final clientInfo = FlutterMCP.instance.clientManager.getClientInfo(clientId);
if (clientInfo != null) {
  print('Client connected: ${clientInfo.client.isConnected}');
}

// Monitor all clients
FlutterMCP.instance.clientManager.clientStream.listen((clients) {
  for (final client in clients) {
    print('Client ${client.id}: ${client.status}');
  }
});
```

## Error Handling

The example demonstrates proper error handling patterns:

```dart
try {
  final result = await FlutterMCP.instance.clientManager.callTool(
    clientId, 'method', params);
  // Handle success
} on MCPConnectionException catch (e) {
  // Handle connection errors
  print('Connection error: ${e.message}');
} on MCPAuthenticationException catch (e) {
  // Handle auth errors
  print('Authentication error: ${e.message}');
} on MCPException catch (e) {
  // Handle general MCP errors
  print('MCP error: ${e.message}');
} catch (e) {
  // Handle unexpected errors
  print('Unexpected error: $e');
}
```

## Testing

```dart
// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:simple_connection/main.dart';

void main() {
  setUp(() async {
    // Initialize MCP for tests
    await FlutterMCP.instance.init(
      MCPConfig(
        appName: 'Test App',
        appVersion: '1.0.0',
        autoStart: false,
        useBackgroundService: false,
        useNotification: false,
        useTray: false,
      ),
    );
  });

  testWidgets('Simple connection test', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();
    
    // Verify initial state
    expect(find.text('Connection Status'), findsOneWidget);
    expect(find.text('Execute Method'), findsOneWidget);
    
    // Tap the execute button (should be disabled initially)
    await tester.tap(find.text('Execute Method'));
    await tester.pump();
    
    // Verify error message
    expect(find.text('Not connected'), findsOneWidget);
  });
}
```

## Running the Example

1. Start the demo MCP server:
   ```bash
   cd server
   npm install
   npm start
   ```

2. Run the Flutter app:
   ```bash
   cd simple_connection
   flutter run
   ```

## Key Concepts

### Connection Management

The example shows how to:
- Create clients using ID-based management
- Maintain connection state
- Handle disconnections
- Implement reconnection logic

### UI State Management

The example uses `setState` for simplicity but can be adapted to use:
- Provider
- Riverpod
- Bloc
- GetX

### Resource Cleanup

Always clean up resources in `dispose()`:

```dart
@override
void dispose() {
  if (_clientId != null) {
    FlutterMCP.instance.clientManager.closeClient(_clientId!);
  }
  super.dispose();
}
```

## Next Steps

- Try the [Multiple Servers](./multiple-servers.md) example
- Explore [Background Jobs](./background-jobs.md)
- Learn about [Plugin Development](./plugin-development.md)