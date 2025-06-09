# Flutter MCP Example App

A comprehensive example application demonstrating the capabilities of the Flutter MCP framework v1.0.0 with native platform integrations.

## Features

- MCP server and client creation and management
- OpenAI/Claude LLM integration
- Real-time chat interface
- **Native platform features** (no external packages):
  - Background service with platform-specific implementations
  - Native notifications with proper permission handling
  - Secure storage using platform-specific encryption
  - System tray integration (desktop platforms)
- Performance monitoring and metrics
- Memory management with automatic cleanup
- Cross-platform support (Android, iOS, macOS, Windows, Linux, Web)

## Getting Started

### Prerequisites

- Flutter SDK 3.0.0 or higher
- Dart SDK 2.17.0 or higher
- OpenAI or Claude API key

### Installation

1. Clone the repository:
```bash
git clone https://github.com/app-appplayer/flutter_mcp.git
cd flutter_mcp/example
```

2. Install dependencies:
```bash
flutter pub get
```

3. Configure platform-specific settings (optional):
   - **Android**: Foreground service types in `pubspec.yaml`
   - **iOS**: Add necessary permissions to `Info.plist`
   - **Desktop**: Ensure system tray icon is in `assets/icons/`

4. Run the app:
```bash
# For mobile/desktop
flutter run

# For specific platform
flutter run -d android
flutter run -d ios
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

### Usage

1. **Configure API Keys**
   - Enter your OpenAI or Claude API key
   - Click "Save API Keys" to store them securely

2. **Start MCP Services**
   - Click the "Start" button to initialize MCP services
   - The status will change to "Running" when services are active

3. **Start Chatting**
   - Type your message in the input field
   - Press Enter or click the send button
   - The LLM response will appear in the chat window

4. **Check Status**
   - Click the info icon in the top right to view system status
   - Monitor memory usage, active components, and performance metrics

## Structure

```
example/
├── lib/
│   ├── main.dart               # Main application with all features
│   ├── v1_features_demo.dart   # v1.0.0 specific features demo
│   └── native_features_demo.dart # Native platform features demo
├── assets/
│   └── icons/
│       └── tray_icon.png      # System tray icon
├── pubspec.yaml               # Dependencies and configuration
├── mcp_config.json           # MCP configuration example
├── mcp_config.yaml           # Alternative YAML configuration
├── README.md                 # Main documentation
├── README_NATIVE_FEATURES.md # Native features guide
└── README_ko.md             # Korean documentation
```

## Key Components

### MCPConfig
Manages the MCP system initialization configuration:
- App name and version
- Background service settings
- Notification configuration
- System tray setup
- Performance monitoring options
- Logging configuration (uses standard Dart logging package)

### Service Lifecycle
Demonstrates proper service management:
- Service initialization
- Server and client creation
- LLM integration
- Graceful shutdown

### Error Handling
Comprehensive error handling throughout:
- API key validation
- Service initialization errors
- Network errors
- Memory issues

## Platform-Specific Features

- **Windows/macOS/Linux**: 
  - System tray with menu
  - Full background service
  - Desktop notifications
  
- **Android/iOS**: 
  - Push notifications
  - Limited background service
  - Secure storage for API keys
  
- **Web**: 
  - Local storage
  - Limited background functionality
  - Browser notifications

## Troubleshooting

### API Key Errors
- Verify your API key is correct
- Check your network connection
- Ensure the API service is not rate-limited

### Service Start Failure
- Check if services are already running
- View logs for detailed error information
- Ensure MCP is properly initialized

### Memory Issues
- Monitor memory usage in status dialog
- Adjust memory threshold in configuration
- Enable performance monitoring

### Chat Not Working
- Ensure services are running
- Verify LLM is properly configured
- Check API key validity

## Best Practices

1. **API Key Security**: Always store API keys securely using SharedPreferences
2. **Resource Management**: Properly disconnect and clean up resources when stopping services
3. **Error Handling**: Provide user-friendly error messages with recovery options
4. **State Management**: Track service states accurately to prevent race conditions
5. **Memory Management**: Monitor and manage memory usage, especially for long-running sessions

## Advanced Features

### v1.0.0 Features (🧪 icon in app)
- **Performance Monitoring**: Real-time metrics and resource tracking
- **Memory Management**: Automatic cleanup with configurable thresholds
- **Health Monitoring**: System health checks with streaming updates
- **Batch Processing**: Efficient parallel LLM request handling
- **Circuit Breaker**: Automatic error recovery and failure protection
- **Enhanced Logging**: Configurable logging with Dart standard logging package

### Native Platform Features (📱 icon in app)
- **Background Service**: Platform-specific implementations
  - Android: Foreground service with notification
  - iOS: Background fetch and tasks
  - Desktop: Full background service support
- **Notifications**: Native notification APIs without external packages
  - Android: NotificationManager with channels
  - iOS: UserNotifications framework
  - Desktop: Platform-specific notification systems
- **Secure Storage**: Platform encryption for sensitive data
  - Android: EncryptedSharedPreferences
  - iOS: Keychain Services
  - Desktop: OS credential stores
- **System Tray** (Desktop only): Native tray icon management
  - Windows: Win32 API integration
  - macOS: NSStatusItem
  - Linux: AppIndicator/SystemTray

### Configuration Features
- **YAML/JSON Configuration**: Load settings from external files
- **Task Scheduling**: Define scheduled tasks in configuration
- **Custom Foreground Service Types** (Android): Configure in pubspec.yaml
- **Permission Management**: Automatic permission requests

See [README_NATIVE_FEATURES.md](README_NATIVE_FEATURES.md) for detailed native features documentation.

## Code Examples

### Logging Configuration
```dart
// Configure logging at app startup
FlutterMcpLogging.configure(
  level: Level.FINE,
  enableDebugLogging: true,
);

// Create a logger for your component
final logger = Logger('flutter_mcp.demo_app');

// Use the logger
logger.info('Starting services...');
logger.warning('Low memory detected');
logger.error('Failed to connect: $error');
```

### Loading Configuration from File
```dart
// Load from JSON file
final config = await ConfigLoader.loadFromJsonFile('assets/mcp_config.json');

// Load from YAML file
final config = await ConfigLoader.loadFromYamlFile('assets/mcp_config.yaml');

// Initialize with loaded config
await FlutterMCP.instance.init(config);
```

### Native Feature Usage
```dart
// Start background service
await FlutterMCP.instance.platformServices.startBackgroundService();

// Show notification
await FlutterMCP.instance.platformServices.showNotification(
  title: 'MCP Demo',
  body: 'Background task completed',
  id: 'task_complete',
);

// Secure storage
await FlutterMCP.instance.platformServices.secureStore('api_key', 'secret_value');
final apiKey = await FlutterMCP.instance.platformServices.secureRead('api_key');
```

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License - see the LICENSE file for details.