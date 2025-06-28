# Flutter MCP

## 🙌 Support This Project

If you find this package useful, consider supporting ongoing development on Patreon.

[![Support on Patreon](https://c5.patreon.com/external/logo/become_a_patron_button.png)](https://www.patreon.com/mcpdevstudio)

### 🔗 MCP Dart Package Family

- [`mcp_server`](https://pub.dev/packages/mcp_server): Exposes tools, resources, and prompts to LLMs. Acts as the AI server.
- [`mcp_client`](https://pub.dev/packages/mcp_client): Connects Flutter/Dart apps to MCP servers. Acts as the client interface.
- [`mcp_llm`](https://pub.dev/packages/mcp_llm): Bridges LLMs (Claude, OpenAI, etc.) to MCP clients/servers. Acts as the LLM brain.
- [`flutter_mcp`](https://pub.dev/packages/flutter_mcp): Complete Flutter plugin for MCP integration with platform features.
- [`flutter_mcp_ui_core`](https://pub.dev/packages/flutter_mcp_ui_core): Core models, constants, and utilities for Flutter MCP UI system. 
- [`flutter_mcp_ui_runtime`](https://pub.dev/packages/flutter_mcp_ui_runtime): Comprehensive runtime for building dynamic, reactive UIs through JSON specifications.
- [`flutter_mcp_ui_generator`](https://pub.dev/packages/flutter_mcp_ui_generator): JSON generation toolkit for creating UI definitions with templates and fluent API. 

---

A Flutter plugin for integrating Large Language Models (LLMs) with [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This plugin provides comprehensive integration between MCP components and platform-specific features like background execution, notifications, system tray, and lifecycle management.

## Features

- **MCP Integration**:
  - Built-in MCP client, server, and LLM capabilities (no need for separate packages)
  - Support for multiple simultaneous MCP clients and servers
  - LLM integration with MCP components
  - Enhanced batch processing with priority-based deduplication

- **Platform Features**:
  - Background service execution with task queuing
  - Local notifications with enhanced configuration
  - System tray support with dynamic menu management (desktop platforms)
  - Application lifecycle management with health monitoring
  - Secure storage for credentials and configuration

- **Advanced Capabilities**:
  - **Real-time Health Monitoring**: Component-level health tracking with event-driven updates
  - **Enhanced Error Handling**: Circuit breaker pattern with automatic recovery strategies
  - **Resource Management**: Automatic cleanup with leak detection and memory optimization
  - **Performance Monitoring**: Advanced metrics with aggregation, anomaly detection, and threshold alerts
  - **Plugin System**: Version management, sandboxing, and dependency resolution
  - **Security Features**: Comprehensive audit logging, encryption management, and risk assessment
  - **Type Safety**: Typed platform channels eliminating manual JSON handling
  - **Dynamic Configuration**: Runtime config updates with validation and rollback support
  - Cross-platform support: Android, iOS, macOS, Windows, Linux, Web

## Getting Started

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^1.0.4
```

Or install via command line:

```bash
flutter pub add flutter_mcp
```

### Platform Setup (Optional)

#### Android Configuration
You can configure Android-specific settings in your `pubspec.yaml`:

##### Foreground Service Types
By default, flutter_mcp uses `dataSync` foreground service type which works for most use cases. If you need additional service types (e.g., location, mediaPlayback), add this to your `pubspec.yaml`:

```yaml
flutter_mcp:
  android:
    foreground_service_types:
      - dataSync      # Default - data synchronization
      - location      # For location-based services
      - mediaPlayback # For media playback
      - microphone    # For audio recording
```

##### Additional Permissions (Coming Soon)
In future versions, you'll be able to request additional Android permissions through pubspec.yaml:

```yaml
flutter_mcp:
  android:
    permissions:
      - camera        # For camera access
      - location      # For location services
      - microphone    # For audio recording
      - storage       # For file access
```

These configurations are automatically applied during build time. No manual AndroidManifest.xml changes needed!

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP
  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'My MCP App',
      appVersion: '1.0.0',
      useBackgroundService: true,
      useNotification: true,
      useTray: true,
      autoStart: true,
      enablePerformanceMonitoring: true, // Enable performance monitoring
      highMemoryThresholdMB: 512, // Set memory threshold for automatic cleanup
      // Auto-start server configuration
      autoStartServer: [
        MCPServerConfig(
          name: 'MCP Server',
          version: '1.0.0',
          capabilities: ServerCapabilities(
            tools: true,
            resources: true,
            prompts: true,
          ),
          integrateLlm: MCPLlmIntegration(
            providerName: 'your-provider',
            config: LlmConfiguration(
              apiKey: 'your-api-key',
              model: 'your-model',
            ),
          ),
        ),
      ],
      // Auto-start client configuration
      autoStartClient: [
        MCPClientConfig(
          name: 'MCP Client',
          version: '1.0.0',
          capabilities: ClientCapabilities(
            sampling: true,
            roots: true,
          ),
          integrateLlm: MCPLlmIntegration(
            existingLlmId: 'llm_1',
          ),
        ),
      ],
      // Scheduled tasks
      schedule: [
        MCPJob.every(
          Duration(minutes: 15),
          task: () {
            // This runs every 15 minutes
          },
        ),
      ],
      // System tray configuration
      tray: TrayConfig(
        tooltip: 'My MCP App',
        menuItems: [
          TrayMenuItem(label: 'Show', onTap: () {
            // Show window code
          }),
          TrayMenuItem.separator(),
          TrayMenuItem(label: 'Exit', onTap: () {
            // Exit app code
          }),
        ],
      ),
    ),
  );
  
  runApp(MyApp());
}
```

### Manual Component Creation

You can also manually create and manage MCP components:

```dart
import 'package:logging/logging.dart';

// Create a logger
final logger = Logger('flutter_mcp.example');

// Create a server
final serverId = await FlutterMCP.instance.createServer(
  name: 'MCP Server',
  version: '1.0.0',
  capabilities: ServerCapabilities(
    tools: true,
    resources: true,
    prompts: true,
  ),
);

// Create a client
final clientId = await FlutterMCP.instance.createClient(
  name: 'MCP Client',
  version: '1.0.0',
  transportCommand: 'server',
  transportArgs: ['--port', '8080'],
);

// Create an LLM
final llmId = await FlutterMCP.instance.createLlm(
  providerName: 'openai',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'gpt-4o',
  ),
);

// Connect components
await FlutterMCP.instance.integrateServerWithLlm(
  serverId: serverId,
  llmId: llmId,
);

await FlutterMCP.instance.integrateClientWithLlm(
  clientId: clientId,
  llmId: llmId,
);

// Start components
FlutterMCP.instance.connectServer(serverId);
await FlutterMCP.instance.connectClient(clientId);

// Use components with memory-efficient caching
final response = await FlutterMCP.instance.chat(
  llmId,
  'Hello, how are you today?',
  useCache: true, // Enable caching for repeated questions
);
logger.info('AI: ${response.text}');

// Stream responses from LLM
Stream<LlmResponseChunk> responseStream = FlutterMCP.instance.streamChat(
  llmId,
  'Write me a short story about robots',
);

responseStream.listen((chunk) {
  logger.info(chunk.textChunk); // Process each chunk as it arrives
});

// Clean up when done
await FlutterMCP.instance.shutdown();
```

## Platform Support

| Platform | Background Service | Notifications | System Tray |
|----------|--------------------|---------------|-------------|
| Android  | ✅                 | ✅            | ❌          |
| iOS      | ⚠️ (Limited)       | ✅            | ❌          |
| macOS    | ✅                 | ✅            | ✅          |
| Windows  | ✅                 | ✅            | ✅          |
| Linux    | ✅                 | ✅            | ✅          |

## Transport Configuration

Transport is the core communication mechanism in MCP. Flutter MCP supports three transport types, each with its own configuration options.

### Transport Types

| Transport Type | Description | Use Case |
|---------------|-------------|----------|
| **STDIO** | Standard Input/Output communication | Local process communication, subprocess execution |
| **SSE** | Server-Sent Events over HTTP | Real-time streaming, web-compatible communication |
| **StreamableHTTP** | HTTP with streaming support | REST-like API with streaming capabilities |

### Server Transport Configuration

#### STDIO Server
```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'STDIO Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'STDIO Server',
    version: '1.0.0',
    transportType: 'stdio',  // Required: must be explicitly specified
  ),
);
```

#### SSE Server
```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'SSE Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'SSE Server',
    version: '1.0.0',
    transportType: 'sse',    // Required: must be explicitly specified
    ssePort: 8080,           // Required for SSE
    host: 'localhost',       // Optional: default 'localhost'
    endpoint: '/sse',        // Optional: default '/sse'
    messagesEndpoint: '/message',  // Optional: default '/message'
    fallbackPorts: [8081, 8082],   // Optional: alternative ports
    authToken: 'secret',     // Optional: authentication
    middleware: [],          // Optional: custom middleware
  ),
);
```

#### StreamableHTTP Server
```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'StreamableHTTP Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'StreamableHTTP Server',
    version: '1.0.0',
    transportType: 'streamablehttp',  // Required: must be explicitly specified
    streamableHttpPort: 8080,         // Required for StreamableHTTP
    host: 'localhost',                // Optional: default 'localhost'
    endpoint: '/mcp',                 // Optional: default '/mcp'
    messagesEndpoint: '/message',     // Optional: default '/message'
    fallbackPorts: [8081, 8082],      // Optional: alternative ports
    authToken: 'secret',              // Optional: authentication
    isJsonResponseEnabled: false,     // Optional: false = SSE mode (default), true = JSON mode
    jsonResponseMode: 'sync',         // Optional: 'sync' or 'async' (only for JSON mode)
    maxRequestSize: 4194304,          // Optional: max request size in bytes (default 4MB)
    requestTimeout: Duration(seconds: 30),  // Optional: request timeout
    corsConfig: {                     // Optional: CORS configuration
      'allowOrigin': '*',
      'allowMethods': 'POST, GET, OPTIONS',
      'allowHeaders': 'Content-Type, Authorization',
    },
  ),
);
```

### Client Transport Configuration

#### STDIO Client
```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'STDIO Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'STDIO Client',
    version: '1.0.0',
    transportType: 'stdio',        // Required: must be explicitly specified
    transportCommand: 'python',    // Required for STDIO
    transportArgs: ['server.py', '--mode', 'mcp'],  // Optional: command arguments
  ),
);
```

#### SSE Client
```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'SSE Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'SSE Client',
    version: '1.0.0',
    transportType: 'sse',              // Required: must be explicitly specified
    serverUrl: 'http://localhost:8080', // Required for SSE
    endpoint: '/sse',                  // Optional: will be appended to serverUrl
    authToken: 'secret',               // Optional: authentication
    headers: {                         // Optional: additional headers
      'X-Custom-Header': 'value',
    },
    timeout: Duration(seconds: 30),    // Optional: request timeout
    sseReadTimeout: Duration(minutes: 5),  // Optional: SSE stream timeout
  ),
);
```

#### StreamableHTTP Client
```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'StreamableHTTP Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'StreamableHTTP Client',
    version: '1.0.0',
    transportType: 'streamablehttp',    // Required: must be explicitly specified
    serverUrl: 'http://localhost:8080', // Required for StreamableHTTP (base URL only)
    endpoint: '/mcp',                   // Optional: server should use the same endpoint
    authToken: 'secret',                // Optional: authentication
    headers: {                          // Optional: additional headers
      'X-Custom-Header': 'value',
    },
    timeout: Duration(seconds: 30),     // Optional: request timeout
    maxConcurrentRequests: 10,          // Optional: max concurrent requests
    useHttp2: true,                     // Optional: use HTTP/2 if available
    terminateOnClose: true,             // Optional: terminate session on close
  ),
);
```

### Important Notes

1. **Transport Type is Required**: Starting from v1.0.1, `transportType` must be explicitly specified. Automatic inference has been removed to prevent unexpected behavior.

2. **URL Handling**:
   - For **SSE**: The `endpoint` is appended to `serverUrl` if provided
   - For **StreamableHTTP**: The client connects to the base `serverUrl`, and the server's endpoint configuration must match

3. **Default Endpoints**:
   - SSE Server: `/sse` (messages) and `/message` (commands)
   - StreamableHTTP Server: `/mcp` (all communications)

4. **Authentication**: All transports support bearer token authentication via the `authToken` field

5. **Port Configuration**:
   - Servers can specify `fallbackPorts` for automatic failover
   - Clients connect to the specific port in the `serverUrl`

### Connection Example

```dart
// 1. Create and start a StreamableHTTP server
final serverId = await FlutterMCP.instance.createServer(
  name: 'My Server',
  version: '1.0.0',
  config: MCPServerConfig(
    name: 'My Server',
    version: '1.0.0',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
    endpoint: '/mcp',  // Server listens at http://localhost:8080/mcp
  ),
);
await FlutterMCP.instance.connectServer(serverId);

// 2. Create and connect a client to the server
final clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '1.0.0',
  config: MCPClientConfig(
    name: 'My Client',
    version: '1.0.0',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',  // Base URL only
    endpoint: '/mcp',  // Must match server's endpoint
  ),
);
await FlutterMCP.instance.connectClient(clientId);
```

## Permissions

Flutter MCP automatically requests necessary permissions based on your configuration:

### Automatic Permission Handling
When you enable features in `MCPConfig`, permissions are requested automatically during initialization:
- `useNotification: true` → Requests notification permission
- `useBackgroundService: true` → Requests background execution permissions (Android 13+)

### Manual Permission Management
You can also manage permissions manually:

```dart
// Check specific permission
bool hasNotificationPermission = await FlutterMCP.instance.checkPermission('notification');

// Request specific permission
bool granted = await FlutterMCP.instance.requestPermission('notification');

// Request multiple permissions
Map<String, bool> results = await FlutterMCP.instance.requestPermissions([
  'notification',
  'location',
]);

// Request all required permissions based on current config
Map<String, bool> results = await FlutterMCP.instance.requestRequiredPermissions();
```

### Platform-specific Notes
- **Android**: Permissions are defined in AndroidManifest.xml. Runtime permissions (like notifications on Android 13+) are requested automatically.
- **iOS**: Permissions must be described in Info.plist. Runtime permissions are requested when needed.
- **Desktop**: Most features don't require explicit permissions, except for system tray on some Linux distributions.

## Configuration Options

### MCPConfig Options

```dart
MCPConfig(
  appName: 'My App',
  appVersion: '1.0.0',
  useBackgroundService: true,
  useNotification: true,
  useTray: true,
  secure: true,
  lifecycleManaged: true,
  autoStart: true,
  enablePerformanceMonitoring: true,
  enableMetricsExport: false,
  highMemoryThresholdMB: 512,
  lowBatteryWarningThreshold: 20,
  maxConnectionRetries: 3,
  llmRequestTimeoutMs: 60000,
  background: BackgroundConfig(...),
  notification: NotificationConfig(...),
  tray: TrayConfig(...),
  schedule: [...],
  autoStartServer: [...],
  autoStartClient: [...],
)
```

### Logging Configuration

Flutter MCP uses the standard Dart `logging` package following MCP conventions:

```dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

// Configure logging
FlutterMcpLogging.configure(
  level: Level.INFO,
  enableDebugLogging: true, // Sets level to FINE
);

// Create a logger with MCP naming convention
final Logger logger = Logger('flutter_mcp.my_component');

// Use the logger
logger.info('Information message');
logger.warning('Warning message');
logger.severe('Error message');
logger.fine('Debug message');
logger.finest('Trace message');

// Extension methods for compatibility
logger.debug('Debug message');  // Maps to fine()
logger.error('Error message');  // Maps to severe()
logger.warn('Warning message'); // Maps to warning()
logger.trace('Trace message');  // Maps to finest()
```

### Background Service Configuration

```dart
BackgroundConfig(
  notificationChannelId: 'my_channel',
  notificationChannelName: 'My Channel',
  notificationDescription: 'Background service notification',
  notificationIcon: 'app_icon',
  autoStartOnBoot: true,
  intervalMs: 5000,
  keepAlive: true,
)
```

### Notification Configuration

```dart
NotificationConfig(
  channelId: 'notifications_channel',
  channelName: 'Notifications',
  channelDescription: 'App notifications',
  icon: 'notification_icon',
  enableSound: true,
  enableVibration: true,
  priority: NotificationPriority.high,
)
```

### System Tray Configuration

```dart
TrayConfig(
  iconPath: 'assets/tray_icon.png',
  tooltip: 'My MCP App',
  menuItems: [
    TrayMenuItem(label: 'Show', onTap: showApp),
    TrayMenuItem.separator(),
    TrayMenuItem(label: 'Exit', onTap: exitApp),
  ],
)
```

## Advanced Usage

### Memory-Efficient Processing

```dart
// Process large data in chunks to avoid memory spikes
final documents = [...]; // List of documents
final processedDocs = await FlutterMCP.instance.processDocumentsInChunks(
  documents,
  (doc) async {
    // Process each document
    return processedDocument;
  },
  chunkSize: 10,
  pauseBetweenChunks: Duration(milliseconds: 100),
);
```

### Memory-Aware Caching

```dart
// Chat with memory-aware caching for faster responses
// The cache will automatically reduce in size during high memory conditions
final response = await FlutterMCP.instance.chat(
  llmId,
  userMessage,
  useCache: true,
);
```

### Performance Monitoring

```dart
import 'package:logging/logging.dart';

final logger = Logger('flutter_mcp.example');

// Get system performance metrics
final status = FlutterMCP.instance.getSystemStatus();
logger.info('Memory usage: ${status['performanceMetrics']['resources']['memory.usageMB']['current']}MB');
logger.info('LLM response time: ${status['performanceMetrics']['timers']['llm.chat']['avg_ms']}ms');
```

### Secure Storage

```dart
// Store values securely
await FlutterMCP.instance.secureStore('api_key', 'your-secret-api-key');

// Retrieve values
final apiKey = await FlutterMCP.instance.secureRead('api_key');
```

### Task Scheduling

```dart
// Add scheduled tasks
final jobId = FlutterMCP.instance.addScheduledJob(
  MCPJob.every(
    Duration(hours: 1),
    task: () {
      // Perform regular task
    },
  ),
);

// Schedule one-time tasks
FlutterMCP.instance.addScheduledJob(
  MCPJob.once(
    Duration(minutes: 5),
    task: () {
      // Will execute only once after 5 minutes
    },
  ),
);

// Remove scheduled tasks
FlutterMCP.instance.removeScheduledJob(jobId);
```

### System Status

```dart
import 'package:logging/logging.dart';

final logger = Logger('flutter_mcp.example');

// Get system status
final status = FlutterMCP.instance.getSystemStatus();
logger.info('Clients: ${status['clients']}');
logger.info('Servers: ${status['servers']}');
logger.info('LLMs: ${status['llms']}');
logger.info('Platform: ${status['platformName']}');
logger.info('Memory: ${status['performanceMetrics']['resources']['memory.usageMB']['current']}MB');
```

### Plugin Registration

```dart
// Register custom plugins
await FlutterMCP.instance.registerPlugin(
  MyCustomPlugin(),
  {'config_key': 'value'},
);

// Execute custom tool plugins
final result = await FlutterMCP.instance.executeToolPlugin(
  'my_tool_plugin',
  {'param1': 'value1'},
);
```

## Examples

Check out the [example](https://github.com/app-appplayer/flutter_mcp/tree/main/example) directory for a complete sample application.

### Configuration Examples

#### Scheduled Tasks Configuration
```json
{
  "schedule": [
    {
      "id": "health_check",
      "name": "System Health Check",
      "intervalMinutes": 15,
      "taskType": "healthcheck",
      "taskConfig": {
        "checks": ["memory", "connectivity", "services"]
      }
    },
    {
      "id": "cleanup_task",
      "name": "Cleanup Temporary Files",
      "intervalHours": 6,
      "taskType": "cleanup",
      "taskConfig": {
        "targets": ["temp", "cache", "logs"]
      }
    },
    {
      "id": "memory_monitor",
      "name": "Memory Usage Check",
      "intervalMinutes": 5,
      "taskType": "memory_check",
      "taskConfig": {
        "thresholdMB": 512
      }
    }
  ]
}
```

#### Platform Version Checking
```dart
// Check platform compatibility
if (await PlatformUtils.isAndroidAtLeast(31)) {
  // Use Android 12+ features
}

if (await PlatformUtils.isIOSAtLeast('15.0')) {
  // Use iOS 15+ features
}

// Create a logger
final logger = Logger('flutter_mcp.example');

// Get detailed platform info
final platformInfo = await PlatformUtils.getPlatformVersionInfo();
logger.info('Platform: ${platformInfo['platform']}');
logger.info('OS Version: ${platformInfo['operatingSystemVersion']}');
```

#### Web Memory Monitoring
```dart
// Enhanced web memory monitoring
final webMonitor = WebMemoryMonitor.instance;

// Start monitoring with improved accuracy
webMonitor.startMonitoring();

// Create a logger
final logger = Logger('flutter_mcp.example');

// Get real-time memory statistics
final stats = webMonitor.getStatistics();
logger.info('Memory Usage: ${stats['currentUsageMB']}MB');
logger.info('Source: ${stats['source']}'); // performance.memory, performance_observer, etc.

// Export detailed memory data
final exportData = webMonitor.exportData();
```

## Architecture

For a detailed understanding of the Flutter MCP architecture, please refer to [ARCHITECTURE.md](ARCHITECTURE.md).

### Key Architectural Features

- **Modular Design**: Clean separation between MCP components and platform services
- **Cross-Platform**: Native implementations for all supported platforms
- **Plugin System**: Extensible architecture for custom functionality
- **Performance Optimized**: Memory management and real-time monitoring
- **Configuration-Driven**: YAML/JSON configuration with task automation

## Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
flutter test

# Run specific test suites
flutter test test/config_task_execution_test.dart
flutter test test/platform_version_test.dart
flutter test test/web_memory_monitor_test.dart
```

### Test Coverage Areas

- **Configuration Task Execution**: Automated task scheduling and execution
- **Platform Version Detection**: Cross-platform version compatibility
- **Web Memory Monitoring**: Enhanced browser memory tracking
- **Integration Tests**: End-to-end functionality validation

## Performance Monitoring

Flutter MCP includes advanced performance monitoring capabilities:

### Real-time Metrics
- Memory usage tracking with platform-specific APIs
- CPU utilization monitoring
- Network request tracking
- Error rate monitoring

### Automated Optimization
- Memory-aware caching with automatic eviction
- Background task throttling based on system resources
- Circuit breaker pattern for error recovery
- Performance-based configuration adjustments

## Troubleshooting

### Common Issues

#### Memory Issues
```dart
// Enable aggressive memory monitoring
await FlutterMCP.instance.init(MCPConfig(
  highMemoryThresholdMB: 256, // Lower threshold for stricter monitoring
  enablePerformanceMonitoring: true,
));
```

#### Platform Compatibility
```dart
// Check platform support before using features
if (PlatformUtils.supportsNotifications) {
  await FlutterMCP.instance.showNotification(
    title: 'Test',
    body: 'Platform supports notifications',
  );
}
```

#### Configuration Issues
```dart
// Validate configuration before initialization
try {
  final config = await ConfigLoader.loadFromJsonFile('assets/mcp_config.json');
  await FlutterMCP.instance.init(config);
} catch (e) {
  final logger = Logger('flutter_mcp.example');
  logger.error('Configuration error: $e');
  // Fallback to default configuration
  await FlutterMCP.instance.init(MCPConfig.defaultConfig());
}
```

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/flutter_mcp/issues).

## Architecture

### MCP Core Integration
Flutter MCP includes built-in MCP protocol support:

- **MCP Client**: Built-in client implementation with transport layer support
- **MCP Server**: Built-in server implementation with capability management  
- **MCP LLM**: Built-in LLM integration layer for MCP protocol communication

These capabilities are included in the flutter_mcp package - no additional dependencies needed!

### Native Platform Implementation
Version 1.0.0 implements platform-specific features using native code instead of external Flutter packages:

- **Background Services**: Native Android (Kotlin), iOS (Swift), Windows (C++), Linux (C++), and macOS (Swift) implementations
- **Notifications**: Platform-native notification systems with full customization support
- **System Tray**: Native system tray integration for desktop platforms (Windows, macOS, Linux)
- **Secure Storage**: Direct integration with platform keychain/credential systems
- **File System**: Uses `path_provider`: ^2.1.5 for cross-platform file access

This native approach provides better performance, reduced dependencies, and platform-optimized user experiences.

## Documentation

Comprehensive documentation is available in the [doc](https://github.com/app-appplayer/flutter_mcp/tree/main/doc) directory:

### 📚 Getting Started
- [Installation Guide](doc/guides/installation.md) - Step-by-step installation instructions
- [Getting Started](doc/guides/getting-started.md) - Quick start guide
- [Architecture Overview](doc/guides/architecture.md) - System architecture and design patterns
- [Best Practices](doc/guides/best-practices.md) - Recommended patterns and practices

### 🔧 API Reference
- [Core API](doc/api/core.md) - Main FlutterMCP class and initialization
- [Client Manager](doc/api/client-manager.md) - MCP client management
- [Server Manager](doc/api/server-manager.md) - MCP server management
- [LLM Manager](doc/api/llm-manager.md) - LLM integration and management
- [Plugin System](doc/api/plugin-system.md) - Plugin development and integration
- [Platform Services](doc/api/platform-services.md) - Platform-specific features
- [Background Service](doc/api/background-service.md) - Background task management
- [Security API](doc/api/security-api.md) - Security and encryption features
- [Utilities](doc/api/utilities.md) - Helper functions and utilities

### 💡 Examples
- [Simple Connection](doc/examples/simple-connection.md) - Basic MCP connection example
- [Multiple Servers](doc/examples/multiple-servers.md) - Managing multiple MCP servers
- [Plugin Development](doc/examples/plugin-development.md) - Creating custom plugins
- [Background Jobs](doc/examples/background-jobs.md) - Scheduling background tasks
- [Real-time Updates](doc/examples/realtime-updates.md) - Implementing real-time features
- [State Management](doc/examples/state-management.md) - Managing application state
- [Security Examples](doc/examples/security-examples.md) - Implementing security features

### 🚀 Platform Integration
- [Android Integration](doc/examples/android-integration.md) - Android-specific features
- [iOS Integration](doc/examples/ios-integration.md) - iOS-specific features
- [Desktop Applications](doc/examples/desktop-applications.md) - Windows, macOS, Linux features
- [Web Applications](doc/examples/web-applications.md) - Web platform features

### 🤖 LLM Integrations
- [Anthropic Claude](doc/integrations/anthropic-claude.md) - Claude integration guide
- [OpenAI GPT](doc/integrations/openai-gpt.md) - GPT integration guide
- [Google Gemini](doc/integrations/google-gemini.md) - Gemini integration guide
- [Local LLM](doc/integrations/local-llm.md) - Local LLM deployment guide

### 🛠️ Advanced Topics
- [Error Handling](doc/advanced/error-handling.md) - Comprehensive error handling
- [Memory Management](doc/advanced/memory-management.md) - Memory optimization techniques
- [Performance Tuning](doc/advanced/performance-tuning.md) - Performance optimization
- [Security](doc/advanced/security.md) - Security best practices
- [Testing](doc/advanced/testing.md) - Testing strategies and examples

### 🔍 Troubleshooting
- [Common Issues](doc/troubleshooting/common-issues.md) - Solutions to common problems
- [Debug Mode](doc/troubleshooting/debug-mode.md) - Debugging techniques
- [Error Codes](doc/troubleshooting/error-codes.md) - Error code reference
- [Performance Issues](doc/troubleshooting/performance.md) - Performance troubleshooting
- [Migration Guide](doc/troubleshooting/migration.md) - Version migration guide

### 🧩 Plugin Development
- [Plugin Lifecycle](doc/plugins/lifecycle.md) - Understanding plugin lifecycle
- [Plugin Communication](doc/plugins/communication.md) - Inter-plugin communication
- [Plugin Development Guide](doc/plugins/development.md) - Creating custom plugins
- [Plugin Examples](doc/plugins/examples.md) - Sample plugin implementations

### 📱 Platform Guides
- [Android](doc/platform/android.md) - Android platform guide
- [iOS](doc/platform/ios.md) - iOS platform guide
- [Windows](doc/platform/windows.md) - Windows platform guide
- [macOS](doc/platform/macos.md) - macOS platform guide
- [Linux](doc/platform/linux.md) - Linux platform guide
- [Web](doc/platform/web.md) - Web platform guide

### 🤝 Contributing
- [Contributing Guide](doc/CONTRIBUTING.md) - How to contribute to the project

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.