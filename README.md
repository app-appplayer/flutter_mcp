# Flutter MCP

A Flutter plugin that integrates [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) clients, servers, and Large Language Model (LLM) providers into a single agent runtime, plus the platform plumbing (background execution, notifications, system tray, lifecycle, secure storage, scheduling) that turns it into a deployable cross-platform app.

Built on `mcp_client`, `mcp_server`, and `mcp_llm` 2.x.

## Features

### MCP integration
- Multiple simultaneous MCP **clients** and **servers** managed by ID
- Multi-revision MCP support — `2024-11-05`, `2025-03-26`, `2025-06-18`, `2025-11-25` (negotiated automatically per session)
- Built-in **LLM provider layer** with multi-provider routing
- **Sampling** — server-initiated `sampling/createMessage` auto-bridged to the host LLM
- **Elicitation** (`2025-06-18+`) — server-initiated user-input requests with a pluggable handler
- **Roots** — typed roots configuration; server-initiated `roots/list` answered by the client
- **Completion** — `completion/complete` handlers with `context` field (previously-resolved arguments)
- **OAuth Resource Server** (RFC 9728) — `/.well-known/oauth-protected-resource` from `MCPServerConfig.protectedResource`
- **Structured tool output** — `Tool.outputSchema` + `CallToolResult.structuredContent`, plus `ResourceLinkContent`

### Platform features
- Background service execution with task queuing
- Local notifications with platform-native rendering
- System tray (desktop) with dynamic menus
- Lifecycle hooks and health monitoring
- Secure storage backed by platform keychain / credential manager
- Job scheduler (interval + cron)

### Operational
- Real-time health monitoring with event-driven updates
- Circuit breaker pattern with automatic recovery
- Resource manager with leak detection
- Performance monitor with aggregation, thresholds, and anomaly detection
- Plugin system with version management, sandboxing, dependency resolution
- Security audit log + encryption manager
- Typed platform channels (no manual JSON handling)
- Dynamic configuration with validation and rollback
- Cross-platform: Android, iOS, macOS, Windows, Linux, Web

## Protocol Versions

Flutter MCP supports the four MCP specification revisions exposed by
`mcp_client` and `mcp_server` 2.x. Negotiation is automatic — the
session ends up on the highest version both peers understand.

| Version | Notes |
|---|---|
| `2024-11-05` | Original; JSON-RPC batching available |
| `2025-03-26` | Earlier 2025 revision; JSON-RPC batching available |
| `2025-06-18` | Adds elicitation, structured tool output, resource links, OAuth Resource Server, MCP-Protocol-Version header. Removes JSON-RPC batching |
| `2025-11-25` | Adds icons, sampling tool calling (`tools` / `toolChoice`), URL-mode elicitation, OIDC Discovery, Client ID Metadata Documents |

## Getting Started

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

These configurations are applied automatically at build time — no
manual `AndroidManifest.xml` edits required.

### Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterMCP.instance.init(
    MCPConfig(
      appName: 'My MCP App',
      appVersion: '<your.app.version>',
      useBackgroundService: true,
      useNotification: true,
      useTray: true,
      autoStart: true,
      // Optional: declare LLM clients/servers + MCP clients/servers up front.
      autoStartLlmClient: [
        MCPLlmClientConfig(
          providerName: 'openai',
          config: LlmConfiguration(
            apiKey: 'your-api-key',
            model: 'gpt-4o',
          ),
          isDefault: true,
        ),
      ],
      autoStartClient: [
        MCPClientConfig(
          name: 'My Client',
          version: '<your.client.version>',
          transportType: 'streamablehttp',
          serverUrl: 'http://localhost:8080',
          endpoint: '/mcp',
          // autoBridgeSampling defaults to true — incoming
          // sampling/createMessage requests will be answered by the host
          // LLM registered above.
        ),
      ],
      schedule: [
        MCPJob.every(Duration(minutes: 15), task: () {
          // runs every 15 minutes
        }),
      ],
      tray: TrayConfig(
        tooltip: 'My MCP App',
        menuItems: [
          TrayMenuItem(label: 'Show', onTap: () { /* show window */ }),
          TrayMenuItem.separator(),
          TrayMenuItem(label: 'Exit', onTap: () { /* exit */ }),
        ],
      ),
    ),
  );

  runApp(MyApp());
}
```

### Manual Component Creation

For finer-grained control, create and wire components yourself:

```dart
import 'package:logging/logging.dart';

// Create a logger
final logger = Logger('flutter_mcp.example');

// Create a server (Streamable HTTP transport)
final serverId = await FlutterMCP.instance.createServer(
  name: 'MCP Server',
  version: '<your.version>',
  capabilities: ServerCapabilities(
    tools: ToolsCapability(),
    resources: ResourcesCapability(),
    prompts: PromptsCapability(),
  ),
  config: MCPServerConfig(
    name: 'MCP Server',
    version: '<your.version>',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
  ),
);

// Create a client (Streamable HTTP transport)
final clientId = await FlutterMCP.instance.createClient(
  name: 'MCP Client',
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'MCP Client',
    version: '<your.version>',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',
    endpoint: '/mcp',
  ),
);

// Create LLM client and LLM server (each returns (llmId, role-specific id))
final (llmId, llmClientId) = await FlutterMCP.instance.createLlmClient(
  providerName: 'openai',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'gpt-4o',
  ),
);

final (_, llmServerId) = await FlutterMCP.instance.createLlmServer(
  providerName: 'openai',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'gpt-4o',
  ),
);

// Wire MCP components into the LLM
await FlutterMCP.instance.addMcpServerToLlmServer(
  llmServerId: llmServerId,
  mcpServerId: serverId,
);

await FlutterMCP.instance.addMcpClientToLlmClient(
  llmClientId: llmClientId,
  mcpClientId: clientId,
);

// Start components
FlutterMCP.instance.connectServer(serverId);
await FlutterMCP.instance.connectClient(clientId);

// Use components
final response = await FlutterMCP.instance.chat(
  llmId,
  'Hello, how are you today?',
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

## Spec Capabilities

### Sampling — server-initiated, host-LLM bridge

`MCPClientConfig.autoBridgeSampling` defaults to `true`: any
`sampling/createMessage` request from the server is fulfilled by the
default LLM client registered through `createLlmClient`. Override per
client by setting `autoBridgeSampling: false` or by passing an explicit
`ClientCapabilities()` without the `sampling` flag.

To call sampling from a server tool handler:

```dart
final result = await FlutterMCP.instance.requestClientSampling(
  serverId: serverId,
  sessionId: sessionId,
  params: {
    'messages': [
      {'role': 'user', 'content': {'type': 'text', 'text': 'summarise X'}},
    ],
    'systemPrompt': 'You are a concise summariser.',
  },
);
```

### Elicitation — server requests user input (`2025-06-18+`)

```dart
// Client side: register a handler.
FlutterMCP.instance.setElicitationHandler((params) async {
  final result = await showElicitationDialog(params);
  return result.cancelled
      ? {'action': 'cancel'}
      : {'action': 'accept', 'content': result.values};
});

// Server side: ask the connected client.
final answer = await FlutterMCP.instance.requestClientElicitation(
  serverId: serverId,
  sessionId: sessionId,
  params: {
    'message': 'Confirm overwrite?',
    'requestedSchema': {
      'type': 'object',
      'properties': {'confirm': {'type': 'boolean'}},
      'required': ['confirm'],
    },
  },
);
```

### Roots

```dart
final clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'My Client',
    version: '<your.version>',
    transportType: 'streamablehttp',
    serverUrl: 'http://localhost:8080',
    initialRoots: const [
      Root(uri: 'file:///workspace/project', name: 'project'),
    ],
  ),
);
FlutterMCP.instance.addClientRoot(clientId, Root(uri: 'file:///tmp', name: 'tmp'));

// Server side
final roots = await FlutterMCP.instance.requestClientRoots(
  serverId: serverId,
  sessionId: sessionId,
);
```

### Completion

```dart
FlutterMCP.instance.addServerCompletion(
  serverId: serverId,
  refType: 'prompt',
  refKey: 'analyze',
  handler: (ref, argument, context) async => {
    'values': suggestionsFor(argument['value'] as String),
  },
);
```

### OAuth Resource Server (RFC 9728)

```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'My Server',
  version: '<your.version>',
  config: MCPServerConfig(
    name: 'My Server',
    version: '<your.version>',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
    protectedResource: const MCPProtectedResourceConfig(
      resource: 'https://api.example.com/mcp',
      authorizationServers: ['https://auth.example.com'],
      scopesSupported: ['mcp:read', 'mcp:tools'],
      bearerMethodsSupported: ['header'],
    ),
  ),
);
```

`/.well-known/oauth-protected-resource` is served automatically.

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
  version: '<your.version>',
  config: MCPServerConfig(
    name: 'STDIO Server',
    version: '<your.version>',
    transportType: 'stdio',  // Required: must be explicitly specified
  ),
);
```

#### SSE Server
```dart
final serverId = await FlutterMCP.instance.createServer(
  name: 'SSE Server',
  version: '<your.version>',
  config: MCPServerConfig(
    name: 'SSE Server',
    version: '<your.version>',
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
  version: '<your.version>',
  config: MCPServerConfig(
    name: 'StreamableHTTP Server',
    version: '<your.version>',
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
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'STDIO Client',
    version: '<your.version>',
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
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'SSE Client',
    version: '<your.version>',
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
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'StreamableHTTP Client',
    version: '<your.version>',
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

1. **Transport Type is Required**: `transportType` must be explicitly specified. Automatic inference has been removed to prevent unexpected behavior.

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
  version: '<your.version>',
  config: MCPServerConfig(
    name: 'My Server',
    version: '<your.version>',
    transportType: 'streamablehttp',
    streamableHttpPort: 8080,
    endpoint: '/mcp',  // Server listens at http://localhost:8080/mcp
  ),
);
await FlutterMCP.instance.connectServer(serverId);

// 2. Create and connect a client to the server
final clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '<your.version>',
  config: MCPClientConfig(
    name: 'My Client',
    version: '<your.version>',
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
  appVersion: '<your.app.version>',
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
final response = await FlutterMCP.instance.chat(
  llmId,
  userMessage,
);
```

### Performance Monitoring

```dart
import 'package:logging/logging.dart';

final logger = Logger('flutter_mcp.example');

// Get system performance metrics. Only available when
// MCPConfig(enablePerformanceMonitoring: true) was passed to init().
final status = FlutterMCP.instance.getSystemStatus();
final metrics = status['performanceMetrics'] as Map<String, dynamic>?;
final memory = metrics?['resources']?['memory.usageMB']?['current'];
if (memory != null) logger.info('Memory usage: ${memory}MB');

// Per-operation timers are keyed by the call site (`operation.<context>`)
// — inspect the map to discover what's been recorded.
final timers = metrics?['timers'] as Map<String, dynamic>?;
timers?.forEach((name, stats) =>
    logger.info('$name: avg=${stats['avg_ms']}ms count=${stats['count']}'));
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

Flutter MCP wraps `mcp_client`, `mcp_server`, and `mcp_llm` 2.x in a
manager-based runtime and adds native platform integration.

### MCP core
- **MCP Client / Server / LLM** — protocol implementations and provider
  layer; no separate package installation required.
- **Multi-revision negotiation** — `2024-11-05` through `2025-11-25`,
  selected per session.
- **Spec request handlers** — sampling, elicitation, roots, completion,
  cancellation, progress.

### Native platform layer
- **Background services** — Kotlin (Android), Swift (iOS / macOS), C++
  (Windows / Linux).
- **Notifications** — platform-native notification systems.
- **System tray** — desktop platforms (Windows, macOS, Linux).
- **Secure storage** — direct integration with platform keychain /
  credential systems.
- **File system** — `path_provider` for cross-platform file access.

### Operational layer
- Modular separation of MCP components and platform services
- Plugin system with version management, sandboxing, dependency
  resolution
- Performance monitor with aggregation, thresholds, anomaly detection
- Configuration-driven (YAML/JSON) with validation and rollback

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
  await FlutterMCP.instance.platformServices.showNotification(
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
  // Fallback to a minimal configuration with platform features disabled.
  await FlutterMCP.instance.init(MCPConfig(
    appName: 'My App',
    appVersion: '1.0.0',
    useBackgroundService: false,
    useNotification: false,
    useTray: false,
  ));
}
```

## Resources

- [In-package documentation](doc/) — architecture, transports, spec features, plugins, platform services, observability, migration
- [`mcp_client`](https://pub.dev/packages/mcp_client), [`mcp_server`](https://pub.dev/packages/mcp_server), [`mcp_llm`](https://pub.dev/packages/mcp_llm) — underlying MCP packages
- [CHANGELOG](CHANGELOG.md) — including breaking changes when upgrading from 1.x

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/flutter_mcp/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.