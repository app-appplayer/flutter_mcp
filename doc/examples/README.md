# Flutter MCP Examples

This directory contains example applications demonstrating various Flutter MCP features.

## Examples Overview

### Basic Examples

1. **[Simple Connection](./simple-connection.md)**
   - Basic server connection
   - Simple method execution
   - Error handling

2. **[Multiple Servers](./multiple-servers.md)**
   - Connecting to multiple servers
   - Server switching
   - Load balancing

3. **[Background Jobs](./background-jobs.md)**
   - Background task scheduling
   - Periodic updates
   - Platform-specific implementations

### Advanced Examples

4. **[Plugin Development](./plugin-development.md)**
   - Creating custom plugins
   - Tool implementation
   - Resource management

5. **[State Management](./state-management.md)**
   - Integration with Provider
   - Integration with Riverpod
   - Integration with Bloc

6. **[Real-time Updates](./realtime-updates.md)**
   - WebSocket subscriptions
   - Event streaming
   - Live data synchronization

### Platform-Specific Examples

7. **[Android Integration](./android-integration.md)**
   - Android-specific features
   - Background services
   - Notifications

8. **[iOS Integration](./ios-integration.md)**
   - iOS-specific features
   - Background fetch
   - Push notifications

9. **[Desktop Applications](./desktop-applications.md)**
   - System tray integration
   - File system access
   - Native menus

10. **[Web Applications](./web-applications.md)**
    - Web Worker integration
    - Service Worker setup
    - Browser storage

## Running Examples

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/flutter_mcp.git
   cd flutter_mcp/examples
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run an example:
   ```bash
   cd simple_connection
   flutter run
   ```

## Example Structure

Each example follows a standard structure:

```
example_name/
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── mcp_config.dart
│   ├── models/
│   │   └── data_model.dart
│   ├── screens/
│   │   └── home_screen.dart
│   └── services/
│       └── mcp_service.dart
├── test/
│   └── widget_test.dart
├── pubspec.yaml
└── README.md
```

## Common Patterns

### Configuration

All examples use a common configuration pattern:

```dart
final config = MCPConfig(
  servers: {
    'example-server': ServerConfig(
      uri: 'ws://localhost:3000',
      auth: AuthConfig(
        type: 'token',
        token: 'your-token',
      ),
    ),
  },
);
```

### Error Handling

Standard error handling pattern used across examples:

```dart
try {
  final result = await server.execute('method', params);
  // Handle success
} on MCPException catch (e) {
  // Handle MCP-specific errors
} catch (e) {
  // Handle general errors
}
```

### State Management

Examples demonstrate different state management approaches:

```dart
// Provider
final mcpProvider = Provider<MCPService>((ref) => MCPService());

// Riverpod
final mcpProvider = Provider<MCPService>((ref) => MCPService());

// Bloc
class MCPBloc extends Bloc<MCPEvent, MCPState> {
  // Implementation
}
```

## Testing Examples

Each example includes tests:

```bash
cd example_name
flutter test
```

## Contributing

To add a new example:

1. Create a new directory under `examples/`
2. Implement the example following the standard structure
3. Add documentation to this README
4. Include comprehensive tests
5. Submit a pull request

## License

See the main project LICENSE file.