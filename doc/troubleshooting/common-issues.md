# Common Issues

A comprehensive guide to troubleshooting common issues with Flutter MCP.

## Installation Issues

### Package Resolution Errors

**Problem**: Flutter cannot resolve the flutter_mcp package dependencies.

```
Because flutter_mcp depends on mcp_client ^1.0.0 which depends on...
```

**Solution**:
1. Clear pub cache:
   ```bash
   flutter pub cache clean
   ```

2. Update dependencies:
   ```bash
   flutter pub upgrade
   ```

3. If using a specific version, check compatibility:
   ```yaml
   dependencies:
     flutter_mcp: ^1.0.4
     mcp_client: ^1.0.0  # Ensure compatible versions
   ```

### Platform-Specific Build Errors

**Problem**: Build fails on Android/iOS with native code errors.

**Android Solution**:
```gradle
// android/app/build.gradle
android {
    compileSdkVersion 33
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 33
    }
}
```

**iOS Solution**:
```ruby
# ios/Podfile
platform :ios, '13.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

## Initialization Issues

### "Flutter MCP is not initialized" Error

**Problem**: Getting error when trying to use MCP features.

```
MCPException: Flutter MCP is not initialized
```

**Solution**:

1. Always initialize before use:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     
     // Initialize MCP first
     await FlutterMCP.instance.init(
       MCPConfig(
         appName: 'My App',
         appVersion: '1.0.0',
         autoStart: false,
       ),
     );
     
     runApp(MyApp());
   }
   ```

2. Check initialization status:
   ```dart
   if (FlutterMCP.instance.isInitialized) {
     // Safe to use MCP features
     final clientId = await FlutterMCP.instance.createClient(...);
   } else {
     // Handle not initialized state
   }
   ```

3. For widgets, ensure initialization in initState:
   ```dart
   @override
   void initState() {
     super.initState();
     _initializeMCP();
   }
   
   Future<void> _initializeMCP() async {
     if (!FlutterMCP.instance.isInitialized) {
       await FlutterMCP.instance.init(MCPConfig(...));
     }
   }
   ```

## Connection Issues

### MCP Client Connection Failed

**Problem**: Cannot connect to MCP server.

```dart
MCPConnectionException: Failed to connect to server
```

**Solution**:

1. Verify server is running:
   ```bash
   # Check if server process is running
   ps aux | grep mcp-server
   
   # Check port availability
   lsof -i :8080
   ```

2. Use correct transport type:
   ```dart
   // Explicitly specify transport type
   final clientId = await FlutterMCP.instance.createClient(
     name: 'My Client',
     version: '1.0.0',
     serverUrl: 'http://localhost:8080/sse',
     transportType: 'sse',  // Must match server
   );
   ```

3. Handle connection errors:
   ```dart
   try {
     await FlutterMCP.instance.connectClient(clientId);
   } on MCPConnectionException catch (e) {
     print('Connection failed: ${e.message}');
     // Implement retry logic
   }
   ```

### Transport Type Mismatch

**Problem**: Client and server use different transport types.

**Solution**:

1. For SSE servers:
   ```dart
   final clientId = await FlutterMCP.instance.createClient(
     name: 'SSE Client',
     version: '1.0.0',
     serverUrl: 'http://localhost:8080/sse',
     transportType: 'sse',
   );
   ```

2. For StreamableHttp servers:
   ```dart
   final clientId = await FlutterMCP.instance.createClient(
     name: 'StreamableHttp Client',
     version: '1.0.0',
     serverUrl: 'http://localhost:8080/mcp',
     transportType: 'streamablehttp',
   );
   ```

3. For stdio servers:
   ```dart
   final clientId = await FlutterMCP.instance.clientManager.createClient(
     MCPClientConfig(
       name: 'Stdio Client',
       version: '1.0.0',
       transportType: 'stdio',
       transportCommand: 'node',
       transportArgs: ['server.js'],
     ),
   );
   ```

## Runtime Errors

### Resource Not Found

**Problem**: Cannot find client/server/LLM by ID.

```dart
MCPException: Client with ID 'xxx' not found
```

**Solution**:

1. Store IDs properly:
   ```dart
   class MCPService {
     String? _clientId;
     
     Future<void> connect() async {
       _clientId = await FlutterMCP.instance.createClient(...);
       await FlutterMCP.instance.connectClient(_clientId!);
     }
     
     Future<void> callTool(String tool, Map<String, dynamic> args) async {
       if (_clientId == null) {
         throw MCPException('Not connected');
       }
       return await FlutterMCP.instance.clientManager.callTool(
         _clientId!,
         tool,
         args,
       );
     }
   }
   ```

2. Check resource existence:
   ```dart
   final clientInfo = FlutterMCP.instance.clientManager.getClientInfo(clientId);
   if (clientInfo == null) {
     print('Client not found');
     return;
   }
   ```

### Memory Leaks

**Problem**: App memory usage keeps growing.

**Solution**:

1. Always clean up resources:
   ```dart
   @override
   void dispose() {
     if (_clientId != null) {
       FlutterMCP.instance.clientManager.closeClient(_clientId!);
     }
     super.dispose();
   }
   ```

2. Enable memory monitoring:
   ```dart
   await FlutterMCP.instance.init(
     MCPConfig(
       appName: 'My App',
       appVersion: '1.0.0',
       highMemoryThresholdMB: 512,
       enablePerformanceMonitoring: true,
     ),
   );
   ```

### Timeout Errors

**Problem**: Operations timeout before completion.

```
MCPTimeoutException: Operation timed out after 30 seconds
```

**Solution**:

1. Adjust timeout in client config:
   ```dart
   final clientId = await FlutterMCP.instance.clientManager.createClient(
     MCPClientConfig(
       name: 'Client',
       version: '1.0.0',
       transportType: 'sse',
       serverUrl: 'http://localhost:8080/sse',
       timeout: Duration(seconds: 60),
       sseReadTimeout: Duration(minutes: 5),
     ),
   );
   ```

2. Implement retry logic:
   ```dart
   Future<T> retryOperation<T>(
     Future<T> Function() operation, {
     int maxAttempts = 3,
     Duration delay = const Duration(seconds: 1),
   }) async {
     for (int i = 0; i < maxAttempts; i++) {
       try {
         return await operation();
       } on MCPTimeoutException {
         if (i == maxAttempts - 1) rethrow;
         await Future.delayed(delay * (i + 1));
       }
     }
     throw Exception('Should not reach here');
   }
   ```

## Platform-Specific Issues

### Android

#### Background Execution Restrictions

**Problem**: Background tasks stop working on Android 12+.

**Solution**:

1. Update manifest permissions:
   ```xml
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.WAKE_LOCK" />
   ```

2. Configure background service properly:
   ```dart
   await FlutterMCP.instance.init(
     MCPConfig(
       appName: 'My App',
       appVersion: '1.0.0',
       useBackgroundService: true,
       background: BackgroundConfig(
         notificationChannelId: 'mcp_background',
         notificationChannelName: 'MCP Background Service',
         notificationDescription: 'Keeps MCP running',
         keepAlive: true,
       ),
     ),
   );
   ```

### iOS

#### App Transport Security

**Problem**: Network requests blocked on iOS.

**Solution**:

1. For development - allow arbitrary loads:
   ```xml
   <!-- ios/Runner/Info.plist -->
   <key>NSAppTransportSecurity</key>
   <dict>
     <key>NSAllowsArbitraryLoads</key>
     <true/>
   </dict>
   ```

2. For production - whitelist domains:
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
     <key>NSExceptionDomains</key>
     <dict>
       <key>your-api-domain.com</key>
       <dict>
         <key>NSIncludesSubdomains</key>
         <true/>
         <key>NSExceptionAllowsInsecureHTTPLoads</key>
         <false/>
       </dict>
     </dict>
   </dict>
   ```

### Desktop

#### System Tray Issues

**Problem**: System tray icon not showing on desktop.

**Solution**:

1. Enable tray in configuration:
   ```dart
   await FlutterMCP.instance.init(
     MCPConfig(
       appName: 'Desktop App',
       appVersion: '1.0.0',
       useTray: true,
       tray: TrayConfig(
         iconPath: 'assets/icons/tray_icon.png',
         tooltip: 'My MCP App',
         menuItems: [
           TrayMenuItem(label: 'Show Window'),
           TrayMenuItem.separator(),
           TrayMenuItem(label: 'Quit'),
         ],
       ),
     ),
   );
   ```

2. Ensure icon asset is included:
   ```yaml
   # pubspec.yaml
   flutter:
     assets:
       - assets/icons/tray_icon.png
   ```

## Performance Issues

### Slow Client Creation

**Problem**: Creating clients takes too long.

**Solution**:

1. Use simplified client creation for common cases:
   ```dart
   // Fast creation with defaults
   final clientId = await FlutterMCP.instance.createClient(
     name: 'Quick Client',
     version: '1.0.0',
     serverUrl: 'http://localhost:8080/sse',
   );
   ```

2. Pre-create clients during initialization:
   ```dart
   class MCPService {
     final Map<String, String> _clientPool = {};
     
     Future<void> initialize() async {
       // Pre-create clients
       for (int i = 0; i < 5; i++) {
         final clientId = await FlutterMCP.instance.createClient(...);
         _clientPool['client_$i'] = clientId;
       }
     }
     
     String getAvailableClient() {
       return _clientPool.values.first;
     }
   }
   ```

### UI Freezing

**Problem**: UI becomes unresponsive during MCP operations.

**Solution**:

1. Use proper state management:
   ```dart
   class MCPViewModel extends ChangeNotifier {
     bool _isLoading = false;
     String? _error;
     dynamic _result;
     
     bool get isLoading => _isLoading;
     String? get error => _error;
     dynamic get result => _result;
     
     Future<void> executeOperation() async {
       _isLoading = true;
       _error = null;
       notifyListeners();
       
       try {
         _result = await FlutterMCP.instance.clientManager.callTool(...);
       } catch (e) {
         _error = e.toString();
       } finally {
         _isLoading = false;
         notifyListeners();
       }
     }
   }
   ```

2. Show loading indicators:
   ```dart
   @override
   Widget build(BuildContext context) {
     return Consumer<MCPViewModel>(
       builder: (context, viewModel, child) {
         if (viewModel.isLoading) {
           return CircularProgressIndicator();
         }
         if (viewModel.error != null) {
           return Text('Error: ${viewModel.error}');
         }
         return Text('Result: ${viewModel.result}');
       },
     );
   }
   ```

## Debugging Tips

### Enable Verbose Logging

```dart
void main() {
  // Configure logging
  FlutterMcpLogging.configure(
    level: Level.FINE,
    enableDebugLogging: true,
  );
  
  runApp(MyApp());
}
```

### Get Diagnostic Information

```dart
// Get overall status
final status = FlutterMCP.instance.getStatus();
print('Status: $status');

// Get specific manager status
final clientStatus = FlutterMCP.instance.clientManagerStatus;
final serverStatus = FlutterMCP.instance.serverManagerStatus;
final llmStatus = FlutterMCP.instance.llmManagerStatus;

// Get detailed resource info
final clientDetails = FlutterMCP.instance.getClientDetails(clientId);
final serverDetails = FlutterMCP.instance.getServerDetails(serverId);
final llmDetails = FlutterMCP.instance.getLlmDetails(llmId);
```

### Monitor Events

```dart
// Monitor client events
FlutterMCP.instance.clientManager.clientStream.listen((clients) {
  print('Active clients: ${clients.length}');
  for (final client in clients) {
    print('Client ${client.id}: ${client.status}');
  }
});

// Monitor server events
FlutterMCP.instance.serverManager.serverStream.listen((servers) {
  print('Active servers: ${servers.length}');
  for (final server in servers) {
    print('Server ${server.id}: ${server.status}');
  }
});
```

## Getting Help

### Collecting Diagnostic Information

When reporting issues, include:

1. **Flutter MCP version**:
   ```dart
   print('Flutter MCP version: ${FlutterMCP.version}');
   ```

2. **Configuration**:
   ```dart
   final config = FlutterMCP.instance.config;
   print('Config: ${config?.toJson()}');
   ```

3. **Error logs** with stack traces

4. **Minimal reproducible example**

### Community Resources

- GitHub Issues: [github.com/app-appplayer/flutter_mcp/issues](https://github.com/app-appplayer/flutter_mcp/issues)
- Documentation: [flutter-mcp.dev](https://flutter-mcp.dev)
- pub.dev: [pub.dev/packages/flutter_mcp](https://pub.dev/packages/flutter_mcp)

## See Also

- [Debug Mode](debug-mode.md)
- [Error Codes Reference](error-codes.md)
- [Performance Tuning](performance.md)
- [Migration Guide](migration.md)