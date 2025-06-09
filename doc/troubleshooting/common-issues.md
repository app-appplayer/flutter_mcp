# Common Issues

A comprehensive guide to troubleshooting common issues with Flutter MCP.

## Installation Issues

### Package Resolution Errors

**Problem**: Flutter cannot resolve the flutter_mcp package dependencies.

```
Because flutter_mcp depends on http ^1.0.0 which depends on...
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
     flutter_mcp: ^1.0.0
     http: ^1.0.0  # Ensure compatible versions
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

## Connection Issues

### MCP Server Connection Failed

**Problem**: Cannot connect to MCP server.

```dart
MCPException: Failed to connect to server at localhost:8080
```

**Solution**:

1. Verify server is running:
   ```bash
   # Check if server process is running
   ps aux | grep mcp-server
   
   # Check port availability
   lsof -i :8080
   ```

2. Check server configuration:
   ```dart
   final config = McpConfig(
     servers: [
       ServerConfig(
         id: 'main-server',
         url: 'ws://localhost:8080',  // Ensure correct protocol
         reconnectDelay: Duration(seconds: 5),
         maxReconnectAttempts: 3,
       ),
     ],
   );
   ```

3. Handle connection errors:
   ```dart
   try {
     await mcp.initialize(config: config);
   } on MCPConnectionException catch (e) {
     print('Connection failed: ${e.message}');
     // Implement fallback or retry logic
   }
   ```

### SSL/TLS Certificate Issues

**Problem**: SSL handshake fails with self-signed certificates.

**Solution**:

1. For development only - bypass certificate validation:
   ```dart
   // WARNING: Only for development!
   import 'dart:io';
   
   class MyHttpOverrides extends HttpOverrides {
     @override
     HttpClient createHttpClient(SecurityContext? context) {
       return super.createHttpClient(context)
         ..badCertificateCallback = (cert, host, port) => true;
     }
   }
   
   void main() {
     HttpOverrides.global = MyHttpOverrides();
     runApp(MyApp());
   }
   ```

2. For production - add trusted certificates:
   ```dart
   final securityContext = SecurityContext()
     ..setTrustedCertificates('path/to/ca-cert.pem');
   
   final config = McpConfig(
     securityContext: securityContext,
   );
   ```

## Runtime Errors

### Out of Memory

**Problem**: App crashes with out of memory error.

```
E/flutter: [ERROR:flutter/runtime/dart_vm_initializer.cc(41)] 
Unhandled Exception: Out of Memory
```

**Solution**:

1. Implement proper resource cleanup:
   ```dart
   class _MyWidgetState extends State<MyWidget> {
     FlutterMCP? _mcp;
     
     @override
     void dispose() {
       _mcp?.dispose();  // Always dispose MCP instances
       super.dispose();
     }
   }
   ```

2. Limit concurrent operations:
   ```dart
   final mcp = FlutterMCP(
     config: McpConfig(
       maxConcurrentOperations: 5,
       memoryLimit: 100 * 1024 * 1024, // 100MB
     ),
   );
   ```

3. Use memory monitoring:
   ```dart
   mcp.monitoring.onMemoryWarning.listen((usage) {
     if (usage > 0.8) {  // 80% usage
       _cleanupResources();
     }
   });
   ```

### Timeout Errors

**Problem**: Operations timeout before completion.

```
MCPTimeoutException: Operation timed out after 30 seconds
```

**Solution**:

1. Adjust timeout settings:
   ```dart
   final config = McpConfig(
     requestTimeout: Duration(seconds: 60),
     servers: [
       ServerConfig(
         id: 'server',
         url: 'ws://localhost:8080',
         connectionTimeout: Duration(seconds: 10),
       ),
     ],
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

### Serialization Errors

**Problem**: JSON serialization/deserialization fails.

```
FormatException: Unexpected character (at character 1)
```

**Solution**:

1. Validate JSON structure:
   ```dart
   try {
     final result = await mcp.client.callTool(
       serverId: 'server',
       name: 'tool',
       arguments: {'data': jsonData},
     );
   } on FormatException catch (e) {
     print('Invalid JSON: $e');
     // Log the actual response for debugging
   }
   ```

2. Use proper type conversions:
   ```dart
   class MyModel {
     final String name;
     final int? age;  // Nullable for optional fields
     
     factory MyModel.fromJson(Map<String, dynamic> json) {
       return MyModel(
         name: json['name'] as String,
         age: json['age'] as int?,  // Safe cast
       );
     }
   }
   ```

## Platform-Specific Issues

### Android

#### Background Execution Restrictions

**Problem**: Background tasks stop working on Android 12+.

**Solution**:

1. Update manifest permissions:
   ```xml
   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
   <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
   ```

2. Handle battery optimizations:
   ```dart
   import 'package:battery_optimization/battery_optimization.dart';
   
   Future<void> requestBatteryOptimizationExemption() async {
     final isIgnoring = await BatteryOptimization.isIgnoringBatteryOptimizations();
     if (!isIgnoring) {
       await BatteryOptimization.openBatteryOptimizationSettings();
     }
   }
   ```

#### ProGuard Issues

**Problem**: App crashes in release mode due to code obfuscation.

**Solution**:

Add ProGuard rules:
```proguard
# Keep Flutter MCP classes
-keep class com.example.flutter_mcp.** { *; }
-keep class io.flutter.plugin.** { *; }

# Keep JSON serialization
-keepattributes *Annotation*
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
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
         <true/>
       </dict>
     </dict>
   </dict>
   ```

#### Background Task Limitations

**Problem**: Background tasks terminate after 30 seconds on iOS.

**Solution**:

1. Use background task API properly:
   ```swift
   // ios/Runner/AppDelegate.swift
   import BackgroundTasks
   
   @UIApplicationMain
   @objc class AppDelegate: FlutterAppDelegate {
     override func application(
       _ application: UIApplication,
       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
     ) -> Bool {
       BGTaskScheduler.shared.register(
         forTaskWithIdentifier: "com.example.mcp.refresh",
         using: nil
       ) { task in
         self.handleAppRefresh(task: task as! BGAppRefreshTask)
       }
       return super.application(application, didFinishLaunchingWithOptions: launchOptions)
     }
   }
   ```

### Desktop

#### Permission Issues

**Problem**: Cannot access files or network on desktop platforms.

**Solution**:

1. macOS - add entitlements:
   ```xml
   <!-- macos/Runner/DebugProfile.entitlements -->
   <key>com.apple.security.network.client</key>
   <true/>
   <key>com.apple.security.files.user-selected.read-write</key>
   <true/>
   ```

2. Linux - check AppArmor/SELinux policies:
   ```bash
   # Check if AppArmor is blocking
   sudo aa-status
   
   # Temporarily disable for testing
   sudo aa-complain /path/to/your/app
   ```

3. Windows - run as administrator or adjust permissions:
   ```dart
   // Check for admin rights
   import 'dart:io';
   
   bool isRunningAsAdmin() {
     if (!Platform.isWindows) return true;
     
     try {
       // Try to access a protected directory
       Directory('C:\\Windows\\System32\\config').listSync();
       return true;
     } catch (e) {
       return false;
     }
   }
   ```

## Performance Issues

### Slow Server Responses

**Problem**: Server takes too long to respond.

**Solution**:

1. Implement request caching:
   ```dart
   class CachedMCPClient {
     final FlutterMCP mcp;
     final Map<String, CacheEntry> _cache = {};
     final Duration cacheDuration;
     
     CachedMCPClient({
       required this.mcp,
       this.cacheDuration = const Duration(minutes: 5),
     });
     
     Future<ToolResult> callTool({
       required String serverId,
       required String name,
       required Map<String, dynamic> arguments,
     }) async {
       final key = '$serverId:$name:${jsonEncode(arguments)}';
       final cached = _cache[key];
       
       if (cached != null && !cached.isExpired) {
         return cached.result;
       }
       
       final result = await mcp.client.callTool(
         serverId: serverId,
         name: name,
         arguments: arguments,
       );
       
       _cache[key] = CacheEntry(
         result: result,
         timestamp: DateTime.now(),
         duration: cacheDuration,
       );
       
       return result;
     }
   }
   ```

2. Use connection pooling:
   ```dart
   final config = McpConfig(
     connectionPool: ConnectionPoolConfig(
       maxConnections: 5,
       maxIdleTime: Duration(minutes: 5),
       connectionTimeout: Duration(seconds: 10),
     ),
   );
   ```

### UI Freezing

**Problem**: UI becomes unresponsive during MCP operations.

**Solution**:

1. Use isolates for heavy operations:
   ```dart
   import 'dart:isolate';
   
   Future<String> processInIsolate(String data) async {
     final receivePort = ReceivePort();
     
     await Isolate.spawn((SendPort sendPort) {
       // Heavy processing here
       final result = processData(data);
       sendPort.send(result);
     }, receivePort.sendPort);
     
     return await receivePort.first as String;
   }
   ```

2. Implement proper state management:
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
         _result = await mcp.client.callTool(...);
       } catch (e) {
         _error = e.toString();
       } finally {
         _isLoading = false;
         notifyListeners();
       }
     }
   }
   ```

## Debugging Tips

### Enable Verbose Logging

```dart
void main() {
  // Enable debug logging
  FlutterMCP.enableDebugLogging = true;
  
  // Set log level
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  
  runApp(MyApp());
}
```

### Use Development Tools

```dart
// Enable development mode
final config = McpConfig(
  developmentMode: true,
  debugOptions: DebugOptions(
    logNetworkTraffic: true,
    logPerformanceMetrics: true,
    enableInspector: true,
  ),
);

// Access debug information
mcp.debug.getNetworkLogs().then((logs) {
  logs.forEach(print);
});
```

### Implement Error Boundaries

```dart
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  
  const ErrorBoundary({Key? key, required this.child}) : super(key: key);
  
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool hasError = false;
  String? errorMessage;
  
  @override
  void initState() {
    super.initState();
    
    // Catch Flutter errors
    FlutterError.onError = (FlutterErrorDetails details) {
      setState(() {
        hasError = true;
        errorMessage = details.exception.toString();
      });
    };
  }
  
  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Center(
        child: Text('Error: $errorMessage'),
      );
    }
    
    return widget.child;
  }
}
```

## Getting Help

### Diagnostic Information

When reporting issues, include:

1. **System Information**:
   ```dart
   Future<Map<String, dynamic>> collectDiagnostics() async {
     return {
       'platform': Platform.operatingSystem,
       'dart_version': Platform.version,
       'flutter_version': await getFlutterVersion(),
       'mcp_version': FlutterMCP.version,
       'config': mcp.config.toJson(),
       'server_status': await mcp.getServerStatus(),
     };
   }
   ```

2. **Error Logs**:
   ```dart
   // Capture and save error logs
   FlutterError.onError = (details) {
     File('error_log.txt').writeAsStringSync(
       '${DateTime.now()}: ${details.exception}\n${details.stack}\n',
       mode: FileMode.append,
     );
   };
   ```

3. **Network Traces**:
   ```dart
   // Enable network logging
   mcp.client.onRequest.listen((request) {
     print('Request: ${request.toJson()}');
   });
   
   mcp.client.onResponse.listen((response) {
     print('Response: ${response.toJson()}');
   });
   ```

### Community Resources

- GitHub Issues: [github.com/flutter-mcp/issues](https://github.com/flutter-mcp/issues)
- Discord Community: [discord.gg/flutter-mcp](https://discord.gg/flutter-mcp)
- Stack Overflow: Tag with `flutter-mcp`
- Documentation: [flutter-mcp.dev](https://flutter-mcp.dev)

## See Also

- [Debug Mode](/doc/troubleshooting/debug-mode.md)
- [Error Codes Reference](/doc/troubleshooting/error-codes.md)
- [Performance Tuning](/doc/troubleshooting/performance.md)
- [Migration Guide](/doc/troubleshooting/migration.md)