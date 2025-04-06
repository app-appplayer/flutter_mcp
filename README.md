# Flutter MCP

A Flutter plugin for integrating Large Language Models (LLMs) with [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This plugin provides comprehensive integration between MCP components and platform-specific features like background execution, notifications, system tray, and lifecycle management.

## Features

- **MCP Integration**:
  - Seamless integration with `mcp_client`, `mcp_server`, and `mcp_llm`
  - Support for multiple simultaneous MCP clients and servers
  - LLM integration with MCP components

- **Platform Features**:
  - Background service execution
  - Local notifications
  - System tray support (on desktop platforms)
  - Application lifecycle management
  - Secure storage for credentials and configuration

- **Advanced Capabilities**:
  - Task scheduling
  - Configurable logging
  - Cross-platform support: Android, iOS, macOS, Windows, Linux

## Getting Started

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^0.0.1
```

Or install via command line:

```bash
flutter pub add flutter_mcp
```

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:mcp_client/mcp_client.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:mcp_llm/mcp_llm.dart';

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
            log('This runs every 15 minutes');
          },
        ),
      ],
    ),
  );
  
  runApp(MyApp());
}
```

### Manual Component Creation

You can also manually create and manage MCP components:

```dart
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
    model: 'gpt-4',
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

// Use components
final response = await FlutterMCP.instance.chat(
  llmId,
  'Hello, how are you today?',
);
log('AI: ${response.text}');

// Clean up when done
await FlutterMCP.instance.shutdown();
```

## Platform Support

| Platform | Background Service | Notifications | System Tray |
|----------|-------------------|---------------|------------|
| Android  | ✅                | ✅             | ❌          |
| iOS      | ⚠️ (Limited)      | ✅             | ❌          |
| macOS    | ✅                | ✅             | ✅          |
| Windows  | ✅                | ✅             | ✅          |
| Linux    | ✅                | ✅             | ✅          |

## Configuration Options

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

// Remove scheduled tasks
FlutterMCP.instance.removeScheduledJob(jobId);
```

### System Status

```dart
// Get system status
final status = FlutterMCP.instance.getSystemStatus();
log('Clients: ${status['clients']}');
log('Servers: ${status['servers']}');
log('LLMs: ${status['llms']}');
```

## Examples

Check out the [example](https://github.com/app-appplayer/flutter_mcp/tree/main/example) directory for a complete sample application.

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/flutter_mcp/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
