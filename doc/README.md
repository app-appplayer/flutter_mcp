# Flutter MCP Documentation

Welcome to the Flutter MCP plugin documentation. This comprehensive guide will help you understand and use the Flutter MCP plugin effectively.

## Quick Start

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

// Initialize Flutter MCP
await FlutterMCP.instance.init(
  MCPConfig(
    appName: 'My App',
    appVersion: '1.0.0',
    autoStart: false,
  ),
);

// Create and connect a client
final clientId = await FlutterMCP.instance.createClient(
  name: 'My Client',
  version: '1.0.0',
  serverUrl: 'http://localhost:8080/sse',
);
await FlutterMCP.instance.connectClient(clientId);
```

## Documentation Structure

### 📚 Guides
- [Getting Started](guides/getting-started.md) - Quick start guide for Flutter MCP
- [Installation Guide](guides/installation.md) - Detailed installation instructions
- [Architecture Overview](guides/architecture.md) - Understanding the manager-based architecture
- [Best Practices](guides/best-practices.md) - Recommended patterns and practices
- [Transport Configuration](guides/transport-configuration.md) - Configure different transport types
- [Performance Monitoring](guides/performance-monitoring-guide.md) - Monitor and optimize performance

### 🖥️ Platform Guides
- [Android Integration](platform/android.md) - Android-specific setup and features
- [iOS Integration](platform/ios.md) - iOS-specific setup and features
- [macOS Support](platform/macos.md) - Desktop support for macOS
- [Windows Support](platform/windows.md) - Desktop support for Windows
- [Linux Support](platform/linux.md) - Desktop support for Linux
- [Web Support](platform/web.md) - Web platform considerations

### 🚀 Examples
- [Simple Connection](examples/simple-connection.md) - Basic MCP client connection
- [Multiple Servers](examples/multiple-servers.md) - Managing multiple MCP servers
- [Background Jobs](examples/background-jobs.md) - Running MCP in background
- [State Management](examples/state-management.md) - Managing state with MCP
- [Real-time Updates](examples/realtime-updates.md) - Handling real-time data
- [Security Examples](examples/security-examples.md) - Implementing secure connections
- [Plugin Development](examples/plugin-development.md) - Creating custom plugins
- [Platform Examples](examples/) - Platform-specific implementation examples

### 🤖 LLM Integrations
- [Anthropic Claude](integrations/anthropic-claude.md) - Integrate with Claude
- [OpenAI GPT](integrations/openai-gpt.md) - Integrate with OpenAI models
- [Google Gemini](integrations/google-gemini.md) - Integrate with Google's Gemini
- [Local LLM](integrations/local-llm.md) - Connect to local language models

### 🔧 Advanced Topics
- [Performance Tuning](advanced/performance-tuning.md) - Optimize for production
- [Memory Management](advanced/memory-management.md) - Handle memory efficiently
- [Error Handling](advanced/error-handling.md) - Robust error handling strategies
- [Security](advanced/security.md) - Security best practices
- [Testing](advanced/testing.md) - Testing MCP integrations

### 🔌 Plugin System
- [Plugin Development](plugins/development.md) - Create custom plugins
- [Plugin Lifecycle](plugins/lifecycle.md) - Understanding plugin lifecycle
- [Plugin Communication](plugins/communication.md) - Inter-plugin communication
- [Plugin Examples](plugins/examples.md) - Example plugin implementations

### 🛠️ Troubleshooting
- [Common Issues](troubleshooting/common-issues.md) - Frequently encountered problems
- [Debug Mode](troubleshooting/debug-mode.md) - Using debug features
- [Error Codes](troubleshooting/error-codes.md) - Error code reference
- [Migration Guide](troubleshooting/migration.md) - Upgrading between versions
- [Performance Issues](troubleshooting/performance.md) - Solving performance problems

### 📝 Contributing
- [Contributing Guidelines](CONTRIBUTING.md) - How to contribute to the project

## Core Concepts

### Manager-Based Architecture

Flutter MCP uses a manager-based architecture with the following core components:

- **`FlutterMCP.instance`** - Singleton instance that provides access to all managers
- **`clientManager`** - Manages MCP client connections
- **`serverManager`** - Manages MCP server instances
- **`llmManager`** - Manages LLM integrations
- **`backgroundService`** - Handles background tasks
- **`scheduler`** - Manages scheduled jobs

### Resource Management

All resources (clients, servers, LLMs) are managed by ID strings:

```dart
// Create resources and get their IDs
final clientId = await FlutterMCP.instance.createClient(...);
final serverId = await FlutterMCP.instance.serverManager.addServer(...);
final llmId = await FlutterMCP.instance.llmManager.addLLM(...);

// Use IDs to interact with resources
await FlutterMCP.instance.connectClient(clientId);
await FlutterMCP.instance.serverManager.startServer(serverId);
await FlutterMCP.instance.llmManager.query(llmId: llmId, ...);
```

## Quick Links

### 🔗 MCP Dart Package Family
- [`mcp_server`](https://pub.dev/packages/mcp_server) - MCP server implementation
- [`mcp_client`](https://pub.dev/packages/mcp_client) - MCP client implementation
- [`mcp_llm`](https://pub.dev/packages/mcp_llm) - LLM integration bridge
- [`flutter_mcp_ui_core`](https://pub.dev/packages/flutter_mcp_ui_core) - UI core utilities
- [`flutter_mcp_ui_runtime`](https://pub.dev/packages/flutter_mcp_ui_runtime) - UI runtime engine
- [`flutter_mcp_ui_generator`](https://pub.dev/packages/flutter_mcp_ui_generator) - UI generation tools

### 📦 Resources
- [GitHub Repository](https://github.com/app-appplayer/flutter_mcp)
- [Issue Tracker](https://github.com/app-appplayer/flutter_mcp/issues)
- [pub.dev Package](https://pub.dev/packages/flutter_mcp)
- [MCP Specification](https://modelcontextprotocol.io/specification)

## Getting Help

If you need help with Flutter MCP:

1. Check the [troubleshooting guide](troubleshooting/common-issues.md)
2. Search [existing issues](https://github.com/app-appplayer/flutter_mcp/issues)
3. Ask in the [discussions](https://github.com/app-appplayer/flutter_mcp/discussions)
4. Report bugs via [issue tracker](https://github.com/app-appplayer/flutter_mcp/issues/new)

## Version

This documentation is for Flutter MCP v1.0.4 and above. For older versions, please refer to the version-specific branches in the repository.