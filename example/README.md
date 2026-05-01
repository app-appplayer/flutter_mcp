# Flutter MCP Example App

A demo application that exercises the Flutter MCP runtime end-to-end —
spec-conforming MCP client/server creation, LLM integration, native
platform features, and the diagnostic surface.

## Features demonstrated

- MCP client and server creation with multiple transport types
- LLM provider integration (OpenAI / Claude) and chat / streamChat
- Native platform features:
  - Background service (with foreground notification on Android)
  - Local notifications via the platform notification system
  - Secure storage backed by platform keychain / credential store
  - System tray on Windows, macOS, Linux
- Diagnostics — `getSystemStatus`, `getSystemHealth`, performance metrics
- Cross-platform: Android, iOS, macOS, Windows, Linux, Web

## Getting Started

### Prerequisites

- Flutter SDK 3.0.0 or higher
- An OpenAI or Claude API key

### Run

From this `example/` directory:

```bash
flutter pub get

# Pick a target
flutter run -d macos
flutter run -d ios
flutter run -d android
flutter run -d windows
flutter run -d linux
flutter run -d chrome
```

Optional Android-specific configuration goes in `pubspec.yaml`:

```yaml
flutter_mcp:
  android:
    foreground_service_types:
      - dataSync
      - location
```

## Source layout

```
example/
├── lib/
│   ├── main.dart                 # Main demo app
│   ├── simple_init_example.dart  # Minimal init walkthrough
│   ├── http_connection_example.dart  # Streamable HTTP transport demo
│   ├── native_features_demo.dart # Native platform features (BG / tray / notifications / secure storage)
│   └── v1_features_demo.dart     # Health monitor, performance metrics, OAuth demo
├── integration_test/
│   └── plugin_integration_test.dart  # E2E smoke against the host platform
├── mcp_config.json               # Example JSON config for ConfigLoader
├── mcp_config.yaml               # Same config, YAML form
└── pubspec.yaml
```

## Common flows

### Logging

```dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

FlutterMcpLogging.configure(
  level: Level.FINE,
  enableDebugLogging: true,
);

final logger = Logger('flutter_mcp.demo_app');
logger.info('Starting services...');
logger.warning('Low memory detected');
logger.severe('Failed to connect: $error');
```

### Loading config from a file

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

final config = await ConfigLoader.loadFromJsonFile('assets/mcp_config.json');
// or YAML:
// final config = await ConfigLoader.loadFromYamlFile('assets/mcp_config.yaml');

await FlutterMCP.instance.init(config);
```

### Native platform features

```dart
// Start the platform background service
await FlutterMCP.instance.platformServices.startBackgroundService();

// Show a notification
await FlutterMCP.instance.platformServices.showNotification(
  title: 'MCP Demo',
  body: 'Background task completed',
  id: 'task_complete',
);

// Secure storage
await FlutterMCP.instance.platformServices.secureStore('api_key', 'secret');
final apiKey = await FlutterMCP.instance.platformServices.secureRead('api_key');
```

### Integration test

```bash
flutter test integration_test/plugin_integration_test.dart -d macos
```

The integration test boots `FlutterMCP`, exercises the diagnostic getters,
creates a stdio client (`/usr/bin/true`), and tears everything down.
Mobile hosts skip the createClient assertion because `/usr/bin/true`
isn't reachable there.

## Troubleshooting

- **`Flutter MCP is not initialized`** — make sure `FlutterMCP.instance.init(...)`
  has resolved before any other API call. `simple_init_example.dart`
  shows the minimum config needed.
- **Notification permission denied** — Android 13+ requires runtime
  permission; the demo app requests it on start. iOS requires
  `Info.plist` entries.
- **Tray icon missing on desktop** — set `iconPath` in `TrayConfig` to
  an asset bundled with the app. Linux additionally needs an
  AppIndicator-compatible session.

## License

MIT — see the package's [LICENSE](../LICENSE) file.
