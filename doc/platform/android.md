# Android Platform Guide

This guide covers Android-specific implementation details and best practices for Flutter MCP.

## Requirements

- Android 5.0 (API level 21) or higher
- Kotlin 1.5.0 or higher
- AndroidX support

## Setup

### 1. Permissions

Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### 2. Background Service

Configure the service in `AndroidManifest.xml`:

```xml
<service
    android:name="com.example.flutter_mcp.BackgroundService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="dataSync" />

<receiver
    android:name="com.example.flutter_mcp.BootReceiver"
    android:enabled="true"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
    </intent-filter>
</receiver>
```

### 3. ProGuard Rules

Add to `proguard-rules.pro`:

```
-keep class com.example.flutter_mcp.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
```

## Features

### Background Execution

Android supports long-running background tasks through:

1. **Foreground Service**
```dart
await mcp.backgroundService.startForeground(
  notification: NotificationConfig(
    title: 'MCP Service',
    body: 'Running in background',
    icon: 'notification_icon',
  ),
);
```

2. **WorkManager**
```dart
await mcp.backgroundService.scheduleWork(
  workerId: 'sync_work',
  interval: Duration(minutes: 15),
  constraints: WorkConstraints(
    requiresNetwork: true,
    requiresCharging: false,
  ),
);
```

### Notifications

1. **Notification Channels** (Android 8.0+)
```dart
await mcp.notificationManager.createChannel(
  channelId: 'mcp_notifications',
  channelName: 'MCP Notifications',
  importance: NotificationImportance.high,
);
```

2. **Rich Notifications**
```dart
await mcp.notificationManager.show(
  id: 1,
  title: 'MCP Update',
  body: 'New message received',
  payload: {'type': 'message', 'id': '123'},
  actions: [
    NotificationAction(
      id: 'reply',
      label: 'Reply',
      input: true,
    ),
    NotificationAction(
      id: 'dismiss',
      label: 'Dismiss',
    ),
  ],
);
```

### Storage

1. **Secure Storage**
```dart
// Uses Android Keystore
await mcp.secureStorage.write('api_key', 'secret_value');
final value = await mcp.secureStorage.read('api_key');
```

2. **App-Specific Storage**
```dart
final appDir = await getApplicationDocumentsDirectory();
final mcpDir = Directory('${appDir.path}/mcp');
await mcpDir.create(recursive: true);
```

### Process Management

```dart
// Start MCP server process
final process = await Process.start(
  'node',
  ['mcp_server.js'],
  workingDirectory: appDir.path,
  environment: {'NODE_ENV': 'production'},
);
```

## Optimization

### Battery Optimization

1. **Doze Mode Handling**
```dart
// Request exemption (requires user approval)
await mcp.platform.requestBatteryOptimizationExemption();

// Check if exempted
final isExempted = await mcp.platform.isBatteryOptimizationExempted();
```

2. **Adaptive Battery**
```dart
// Adjust behavior based on battery level
final batteryLevel = await mcp.platform.getBatteryLevel();
if (batteryLevel < 20) {
  // Reduce background activity
  await mcp.backgroundService.setInterval(Duration(hours: 1));
}
```

### Memory Management

```dart
// Monitor app memory
void onTrimMemory(int level) {
  switch (level) {
    case TRIM_MEMORY_RUNNING_LOW:
      // Reduce memory usage
      mcp.clearCaches();
      break;
    case TRIM_MEMORY_UI_HIDDEN:
      // App in background
      mcp.reduceMemoryFootprint();
      break;
  }
}
```

### Network Optimization

```dart
// Use connectivity awareness
final connectivity = await Connectivity().checkConnectivity();
if (connectivity == ConnectivityResult.mobile) {
  // Reduce data usage on mobile
  mcp.setDataSaverMode(true);
}

// Monitor network changes
Connectivity().onConnectivityChanged.listen((result) {
  mcp.handleNetworkChange(result);
});
```

## Best Practices

### 1. Handle System Restrictions

```dart
// Check and request permissions at runtime
Future<bool> checkPermissions() async {
  final notification = await Permission.notification.status;
  if (!notification.isGranted) {
    return await Permission.notification.request().isGranted;
  }
  return true;
}
```

### 2. Lifecycle Management

```dart
class MCPLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        mcp.onBackground();
        break;
      case AppLifecycleState.resumed:
        mcp.onForeground();
        break;
      case AppLifecycleState.detached:
        mcp.onTerminate();
        break;
    }
  }
}
```

### 3. Handle Deep Links

```dart
// Configure deep links in AndroidManifest.xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="mcp" android:host="action" />
</intent-filter>

// Handle in app
void handleDeepLink(Uri uri) {
  if (uri.scheme == 'mcp' && uri.host == 'action') {
    final action = uri.queryParameters['type'];
    mcp.handleAction(action);
  }
}
```

### 4. Multi-Window Support

```dart
// Handle multi-window mode
if (Platform.isAndroid) {
  final isInMultiWindow = await mcp.platform.isInMultiWindowMode();
  if (isInMultiWindow) {
    // Adjust UI for smaller window
  }
}
```

## Troubleshooting

### Common Issues

1. **Background Service Stops**
   - Check battery optimization settings
   - Implement proper foreground service
   - Handle system memory pressure

2. **Notification Not Showing**
   - Verify notification permissions
   - Check notification channel settings
   - Ensure proper icon resources

3. **Storage Access Issues**
   - Request storage permissions
   - Use scoped storage (Android 10+)
   - Handle permission denial gracefully

### Debugging

```dart
// Enable verbose logging
MCPLogger.instance.setLevel(LogLevel.verbose);

// Monitor system events
SystemChannels.lifecycle.setMessageHandler((message) {
  print('System event: $message');
  return null;
});
```

## Platform-Specific APIs

```dart
// Access Android-specific APIs
if (Platform.isAndroid) {
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  print('Android SDK: ${androidInfo.version.sdkInt}');
  
  // Use Android-specific features
  if (androidInfo.version.sdkInt >= 31) {
    // Android 12+ specific code
  }
}
```

## Next Steps

- [iOS Platform Guide](ios.md) - iOS-specific details
- [Background Execution](../advanced/background-execution.md) - Advanced background strategies
- [Performance Optimization](../advanced/performance.md) - Platform optimization techniques