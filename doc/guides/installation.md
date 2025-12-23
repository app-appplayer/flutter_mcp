# Installation Guide

This guide covers the installation process for Flutter MCP across different platforms.

## Prerequisites

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Platform-specific requirements (see below)

## Installation Steps

### 1. Add Dependency

Add Flutter MCP to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mcp: ^1.0.4
```

Or install using command line:

```bash
flutter pub add flutter_mcp
```

### 2. Platform-Specific Setup

#### Android

Add required permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

#### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access for MCP communication</string>
```

#### macOS

Add to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

#### Windows

No additional configuration required.

#### Linux

Install system dependencies:

```bash
sudo apt-get install libsecret-1-0 libsecret-1-dev
```

### 3. Configuration

Create `assets/mcp_config.json`:

```json
{
  "servers": [
    {
      "id": "main_server",
      "name": "Main MCP Server",
      "command": "node",
      "args": ["server.js"],
      "env": {
        "NODE_ENV": "production"
      }
    }
  ],
  "llms": [
    {
      "id": "openai",
      "provider": "openai",
      "model": "gpt-4",
      "apiKey": "YOUR_API_KEY"
    }
  ],
  "background": {
    "enable": true,
    "interval": 900000
  }
}
```

### 4. Initialize

```dart
import 'package:flutter_mcp/flutter_mcp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final mcp = FlutterMCP();
  await mcp.initialize();
  
  runApp(MyApp());
}
```

## Verification

To verify installation:

```dart
// Check plugin version
print(FlutterMCP.version);

// Check platform support
print(FlutterMCP.platformSupported);
```

## Troubleshooting

### Common Issues

1. **Build Errors**
   - Clear Flutter cache: `flutter clean`
   - Update dependencies: `flutter pub upgrade`

2. **Permission Issues**
   - Ensure all platform permissions are correctly configured
   - Request runtime permissions on Android/iOS

3. **Configuration Errors**
   - Validate JSON configuration syntax
   - Check file paths are correct

## Next Steps

- [Getting Started](getting-started.md) - Basic usage examples
- [Platform Guides](../platform/README.md) - Platform-specific details