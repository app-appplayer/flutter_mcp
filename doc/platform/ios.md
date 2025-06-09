# iOS Platform Guide

This guide covers iOS-specific implementation details and best practices for Flutter MCP.

## Requirements

- iOS 12.0 or higher
- Xcode 13.0 or higher
- Swift 5.0 or higher

## Setup

### 1. Info.plist Configuration

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
    <string>audio</string>
</array>

<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access for MCP communication</string>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.example.mcp.refresh</string>
    <string>com.example.mcp.processing</string>
</array>
```

### 2. Capabilities

Enable in Xcode project settings:
- Background Modes
  - Background fetch
  - Background processing
  - Audio (if needed)
- Push Notifications (if using remote notifications)

### 3. App Groups (for data sharing)

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.example.mcp</string>
</array>
```

## Features

### Background Execution

iOS has strict background execution limits:

1. **Background Fetch** (15 minute intervals)
```dart
await mcp.backgroundService.registerFetchTask(
  taskId: 'mcp_fetch',
  minimumInterval: Duration(minutes: 15),
  handler: () async {
    // Perform quick updates (30 seconds max)
    await quickSync();
  },
);
```

2. **Background Processing** (longer tasks)
```dart
await mcp.backgroundService.registerProcessingTask(
  taskId: 'mcp_processing',
  requiresExternalPower: false,
  requiresNetworkConnectivity: true,
  handler: () async {
    // Longer running tasks (several minutes)
    await deepSync();
  },
);
```

3. **Background URL Session**
```dart
// For downloads/uploads that continue in background
final session = await mcp.createBackgroundURLSession(
  identifier: 'mcp_background_session',
  configuration: URLSessionConfiguration(
    allowsCellularAccess: true,
    timeoutIntervalForRequest: 60,
  ),
);
```

### Notifications

1. **Request Permission**
```dart
final settings = await mcp.notificationManager.requestPermission(
  alert: true,
  badge: true,
  sound: true,
  criticalAlert: false,
);
```

2. **Rich Notifications**
```dart
await mcp.notificationManager.show(
  id: 1,
  title: 'MCP Update',
  body: 'New message received',
  sound: 'notification.caf',
  badge: 1,
  attachments: [
    NotificationAttachment(
      identifier: 'image',
      url: 'assets/notification_image.png',
    ),
  ],
);
```

3. **Notification Service Extension**
```swift
// NotificationServiceExtension.swift
class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, 
                           withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // Modify notification content
        let modifiedContent = request.content.mutableCopy() as! UNMutableNotificationContent
        modifiedContent.title = "MCP: \(modifiedContent.title)"
        contentHandler(modifiedContent)
    }
}
```

### Storage

1. **Keychain Access**
```dart
// Secure storage using iOS Keychain
await mcp.secureStorage.write(
  'api_key', 
  'secret_value',
  accessibility: KeychainAccessibility.whenUnlockedThisDeviceOnly,
);
```

2. **App Groups (sharing data)**
```dart
// Share data between app and extensions
final sharedContainer = await getSharedContainerPath('group.com.example.mcp');
final sharedFile = File('$sharedContainer/shared_data.json');
```

### System Integration

1. **Siri Shortcuts**
```dart
await mcp.platform.donateShortcut(
  shortcut: SiriShortcut(
    identifier: 'send_mcp_message',
    title: 'Send MCP Message',
    suggestedInvocationPhrase: 'Send message with MCP',
  ),
);
```

2. **Handoff**
```dart
await mcp.platform.startActivity(
  activityType: 'com.example.mcp.chat',
  userInfo: {'conversationId': '123'},
  webpageURL: 'https://example.com/chat/123',
);
```

## Optimization

### Battery and Performance

1. **Low Power Mode Detection**
```dart
final isLowPowerMode = await mcp.platform.isLowPowerModeEnabled();
if (isLowPowerMode) {
  // Reduce background activity
  await mcp.backgroundService.pause();
}
```

2. **Thermal State Monitoring**
```dart
mcp.platform.thermalStateStream.listen((state) {
  switch (state) {
    case ThermalState.nominal:
      // Normal operation
      break;
    case ThermalState.serious:
      // Reduce activity
      mcp.reduceProcessing();
      break;
    case ThermalState.critical:
      // Minimal activity only
      mcp.suspendNonCritical();
      break;
  }
});
```

### Memory Management

```dart
// Respond to memory warnings
void didReceiveMemoryWarning() {
  mcp.clearCaches();
  mcp.releaseNonCriticalResources();
}

// Monitor memory pressure
mcp.platform.memoryPressureStream.listen((pressure) {
  if (pressure == MemoryPressure.critical) {
    mcp.emergencyCleanup();
  }
});
```

### Network Optimization

```dart
// Use iOS network path monitoring
final monitor = NetworkPathMonitor();
monitor.pathUpdateHandler = (path) {
  if (path.isExpensive) {
    // Cellular or metered connection
    mcp.enableDataSaver();
  }
  if (!path.isSatisfied) {
    // No network
    mcp.enterOfflineMode();
  }
};
```

## Best Practices

### 1. Handle App Transport Security

```xml
<!-- Only if absolutely necessary -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

### 2. Background Task Completion

```dart
// Always call completion handler
Future<void> handleBackgroundFetch(String taskId) async {
  try {
    await performFetch();
    mcp.backgroundService.completeTask(taskId, success: true);
  } catch (e) {
    mcp.backgroundService.completeTask(taskId, success: false);
  }
}
```

### 3. State Restoration

```dart
// Save state for app restoration
await mcp.platform.saveState({
  'currentView': 'chat',
  'conversationId': '123',
});

// Restore state
final state = await mcp.platform.restoreState();
if (state != null) {
  navigateToView(state['currentView']);
}
```

### 4. Handle Silent Push

```swift
// AppDelegate.swift
func application(_ application: UIApplication, 
                didReceiveRemoteNotification userInfo: [AnyHashable : Any], 
                fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Handle silent push
    FlutterMCPPlugin.handleBackgroundNotification(userInfo) { result in
        completionHandler(result)
    }
}
```

## Troubleshooting

### Common Issues

1. **Background Tasks Not Running**
   - Check Background Modes capability
   - Verify task identifiers in Info.plist
   - Monitor task scheduling with Console.app

2. **Keychain Access Issues**
   - Check entitlements
   - Verify keychain access groups
   - Handle first launch after restore

3. **Network Issues**
   - Check local network permission
   - Handle App Transport Security
   - Test with different network conditions

### Debugging

```dart
// Enable iOS-specific debugging
if (Platform.isIOS) {
  MCPLogger.instance.enableIOSConsoleLogging();
  
  // Monitor iOS system logs
  mcp.platform.systemLogStream.listen((log) {
    print('System: $log');
  });
}
```

### Testing Background Modes

```bash
# Simulate background fetch
xcrun simctl background_fetch booted com.example.app

# Simulate background processing
xcrun simctl background_processing booted com.example.app
```

## Platform-Specific APIs

```dart
// Access iOS-specific APIs
if (Platform.isIOS) {
  final iosInfo = await DeviceInfoPlugin().iosInfo;
  print('iOS Version: ${iosInfo.systemVersion}');
  
  // Use iOS-specific features
  if (double.parse(iosInfo.systemVersion) >= 15.0) {
    // iOS 15+ specific code
    await mcp.platform.configureFocusModes();
  }
}
```

## App Store Guidelines

1. **Background Execution**
   - Must provide user value
   - Cannot drain battery excessively
   - Must handle task completion properly

2. **Privacy**
   - Declare all data usage in App Store Connect
   - Request permissions appropriately
   - Handle permission denial gracefully

3. **Network Usage**
   - Respect cellular data settings
   - Handle offline scenarios
   - Implement proper retry logic

## Next Steps

- [macOS Platform Guide](macos.md) - macOS-specific details
- [Background Execution](../advanced/background-execution.md) - iOS background strategies
- [App Store Submission](../guides/app-store.md) - Submission guidelines