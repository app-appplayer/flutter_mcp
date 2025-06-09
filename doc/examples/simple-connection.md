# Simple Connection Example

This example demonstrates basic MCP server connection and method execution.

## Overview

This example shows how to:
- Initialize Flutter MCP
- Connect to a single server
- Execute remote methods
- Handle errors

## Code Example

### Configuration

```dart
// lib/config/mcp_config.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class AppConfig {
  static MCPConfig get mcpConfig => MCPConfig(
    servers: {
      'demo-server': ServerConfig(
        uri: 'ws://localhost:3000',
        auth: AuthConfig(
          type: 'token',
          token: 'demo-token',
        ),
      ),
    },
  );
}
```

### Main Application

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'config/mcp_config.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP
  await FlutterMCP.initialize(AppConfig.mcpConfig);
  
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
  MCPServer? _server;
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
      _server = await FlutterMCP.connect('demo-server');
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
    if (_server == null) {
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
      final result = await _server!.execute('echo', {
        'message': 'Hello from Flutter!',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
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
    if (_server == null) return;
    
    setState(() {
      _loading = true;
    });
    
    try {
      await _server!.disconnect();
      setState(() {
        _server = null;
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
              onPressed: _loading || _server == null ? null : _disconnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text('Disconnect'),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading || _server != null ? null : _connectToServer,
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

### MCP Service

```dart
// lib/services/mcp_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class MCPService {
  MCPServer? _server;
  
  Future<void> connect() async {
    _server = await FlutterMCP.connect('demo-server');
  }
  
  Future<void> disconnect() async {
    await _server?.disconnect();
    _server = null;
  }
  
  bool get isConnected => _server?.isConnected ?? false;
  
  Future<Map<String, dynamic>> echo(String message) async {
    if (_server == null) {
      throw MCPException('Not connected');
    }
    
    return await _server!.execute('echo', {
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  Future<Map<String, dynamic>> getData() async {
    if (_server == null) {
      throw MCPException('Not connected');
    }
    
    return await _server!.execute('getData', {});
  }
}
```

## Testing

```dart
// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp_test/flutter_mcp_test.dart';

import 'package:simple_connection/main.dart';

void main() {
  testWidgets('Simple connection test', (WidgetTester tester) async {
    // Mock the server
    MCPTestEnvironment.mockServer('demo-server', {
      'echo': (params) => params,
      'getData': (params) => {'data': 'test data'},
    });
    
    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();
    
    // Verify initial state
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Execute Method'), findsOneWidget);
    
    // Tap the execute button
    await tester.tap(find.text('Execute Method'));
    await tester.pumpAndSettle();
    
    // Verify result
    expect(find.textContaining('Result:'), findsOneWidget);
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

### Error Handling

The example demonstrates proper error handling:

```dart
try {
  final result = await server.execute('method', params);
  // Handle success
} on ConnectionException catch (e) {
  // Handle connection errors
} on AuthenticationException catch (e) {
  // Handle auth errors
} on MCPException catch (e) {
  // Handle general MCP errors
} catch (e) {
  // Handle unexpected errors
}
```

### Connection Management

The example shows how to:
- Maintain connection state
- Handle disconnections
- Implement reconnection logic

### UI State Management

The example uses `setState` for simplicity but can be adapted to use:
- Provider
- Riverpod
- Bloc
- GetX

## Next Steps

- Try the [Multiple Servers](./multiple-servers.md) example
- Explore [Background Jobs](./background-jobs.md)
- Learn about [Plugin Development](./plugin-development.md)