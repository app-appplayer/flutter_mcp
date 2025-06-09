# macOS Platform Guide

This guide covers macOS-specific implementation details and best practices for Flutter MCP.

## Requirements

- macOS 10.15 (Catalina) or higher
- Xcode 13.0 or higher
- Swift 5.0 or higher

## Setup

### 1. Entitlements

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.process</key>
<true/>
```

### 2. Info.plist Configuration

```xml
<key>LSApplicationCategoryType</key>
<string>public.app-category.developer-tools</string>
<key>NSUserNotificationAlertStyle</key>
<string>alert</string>
```

### 3. App Sandbox (if enabled)

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.downloads.read-write</key>
<true/>
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/usr/local/bin/</string>
</array>
```

## Features

### System Tray

macOS supports comprehensive system tray (menu bar) integration:

```dart
await mcp.trayManager.initialize(
  icon: 'assets/tray_icon.png',
  tooltip: 'MCP Application',
);

// Create menu
await mcp.trayManager.setMenu([
  TrayMenuItem(
    label: 'Show Window',
    onClick: () => mcp.showMainWindow(),
  ),
  TrayMenuItem.separator(),
  TrayMenuItem(
    label: 'Status',
    submenu: [
      TrayMenuItem(
        label: 'Connected',
        checked: isConnected,
        enabled: false,
      ),
    ],
  ),
  TrayMenuItem.separator(),
  TrayMenuItem(
    label: 'Quit',
    onClick: () => mcp.quit(),
  ),
]);
```

### Window Management

```dart
// Configure main window
await mcp.windowManager.configure(
  title: 'MCP Application',
  minimumSize: Size(400, 300),
  maximumSize: Size(1200, 800),
  center: true,
  backgroundColor: Colors.transparent,
  titleBarStyle: TitleBarStyle.hidden,
);

// Window controls
await mcp.windowManager.minimize();
await mcp.windowManager.maximize();
await mcp.windowManager.restore();
await mcp.windowManager.close();

// Window events
mcp.windowManager.onEvent.listen((event) {
  switch (event) {
    case WindowEvent.focus:
      // Window gained focus
      break;
    case WindowEvent.blur:
      // Window lost focus
      break;
    case WindowEvent.resize:
      // Window resized
      break;
  }
});
```

### Native Menus

```dart
// Create application menu
final menu = Menu(
  items: [
    Submenu(
      label: 'File',
      items: [
        MenuItem(
          label: 'New',
          shortcut: Shortcut(key: 'n', cmd: true),
          onPressed: () => createNew(),
        ),
        MenuItem.separator(),
        MenuItem(
          label: 'Quit',
          shortcut: Shortcut(key: 'q', cmd: true),
          onPressed: () => quit(),
        ),
      ],
    ),
    Submenu(
      label: 'Edit',
      items: [
        MenuItem.standard(StandardMenuItem.copy),
        MenuItem.standard(StandardMenuItem.paste),
      ],
    ),
  ],
);

await mcp.menuManager.setApplicationMenu(menu);
```

### Dock Integration

```dart
// Set dock badge
await mcp.dockManager.setBadge('3');

// Set dock icon
await mcp.dockManager.setIcon('assets/dock_icon.png');

// Dock menu
await mcp.dockManager.setMenu([
  MenuItem(label: 'New Window', onPressed: () => openNewWindow()),
]);

// Bounce dock icon
await mcp.dockManager.bounce(type: BounceType.critical);
```

### Touch Bar Support

```dart
// Configure Touch Bar
await mcp.touchBarManager.setItems([
  TouchBarButton(
    label: 'Send',
    backgroundColor: Colors.blue,
    onClick: () => sendMessage(),
  ),
  TouchBarSpacer.flexible(),
  TouchBarSegmentedControl(
    segments: ['Chat', 'Settings'],
    selectedIndex: 0,
    onChange: (index) => switchTab(index),
  ),
]);
```

### Background Service

macOS allows unrestricted background execution:

```dart
// No special configuration needed
await mcp.backgroundService.start();

// Use launchd for auto-start
await mcp.platform.installLaunchAgent(
  identifier: 'com.example.mcp',
  programPath: '/Applications/MCP.app/Contents/MacOS/MCP',
  runAtLoad: true,
);
```

### File System Access

```dart
// Open file dialog
final result = await mcp.platform.showOpenPanel(
  allowsMultipleSelection: false,
  canChooseDirectories: false,
  allowedFileTypes: ['json', 'txt'],
);

if (result != null) {
  final file = File(result.first);
  // Process file
}

// Save file dialog
final savePath = await mcp.platform.showSavePanel(
  defaultName: 'config.json',
  allowedFileTypes: ['json'],
);
```

### Process Management

```dart
// Launch external processes
final process = await Process.start(
  '/usr/local/bin/node',
  ['server.js'],
  workingDirectory: '/Users/user/mcp',
  environment: {'NODE_ENV': 'production'},
);

// Monitor process
process.stdout.listen((data) {
  print('Output: ${utf8.decode(data)}');
});

// Check if process is running
final isRunning = await mcp.platform.isProcessRunning('node');
```

## Optimization

### Memory Management

```dart
// Monitor memory usage
final memoryInfo = await mcp.platform.getMemoryInfo();
print('Memory used: ${memoryInfo.resident}');
print('Virtual memory: ${memoryInfo.virtual}');

// Set memory pressure handler
mcp.platform.onMemoryPressure((level) {
  if (level == MemoryPressureLevel.critical) {
    mcp.performEmergencyCleanup();
  }
});
```

### Power Management

```dart
// Prevent system sleep
final assertion = await mcp.platform.preventSystemSleep(
  reason: 'MCP background processing',
);

// Release when done
await assertion.release();

// Monitor power events
mcp.platform.powerEvents.listen((event) {
  switch (event) {
    case PowerEvent.sleep:
      mcp.prepareForSleep();
      break;
    case PowerEvent.wake:
      mcp.resumeFromSleep();
      break;
  }
});
```

### App Nap Prevention

```dart
// Disable App Nap for continuous operation
await mcp.platform.disableAppNap();

// Monitor activity
final activity = await mcp.platform.beginActivity(
  reason: 'Background processing',
  options: ActivityOptions.userInitiated,
);

// End activity when done
await activity.end();
```

## Best Practices

### 1. Universal Binary Support

```yaml
# In pubspec.yaml
flutter:
  assets:
    - assets/icons/
  
  # Platform-specific assets
  macos:
    binary_arch:
      - x86_64
      - arm64
```

### 2. Code Signing

```bash
# Sign the app
codesign --force --deep --sign "Developer ID Application: Your Name" MCP.app

# Verify signature
codesign --verify --verbose MCP.app

# Notarize for distribution
xcrun altool --notarize-app --file MCP.zip --primary-bundle-id com.example.mcp
```

### 3. Hardened Runtime

```xml
<!-- Enable hardened runtime -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
<key>com.apple.security.cs.allow-jit</key>
<true/>
```

### 4. Sparkle Updates

```dart
// Integrate Sparkle for auto-updates
await mcp.updateManager.configure(
  feedURL: 'https://example.com/mcp/appcast.xml',
  automaticChecks: true,
  interval: Duration(hours: 24),
);

// Check for updates manually
await mcp.updateManager.checkForUpdates();
```

## Distribution

### Mac App Store

1. **Sandboxing Requirements**
   - Enable App Sandbox
   - Declare all entitlements
   - Remove prohibited APIs

2. **Review Guidelines**
   - Provide clear app description
   - Include proper screenshots
   - Handle trial/purchase flow

### Direct Distribution

1. **Developer ID Signing**
   ```bash
   productbuild --component MCP.app /Applications --sign "Developer ID Installer: Your Name" MCP.pkg
   ```

2. **DMG Creation**
   ```bash
   hdiutil create -volname MCP -srcfolder MCP.app -ov -format UDZO MCP.dmg
   codesign --sign "Developer ID Application: Your Name" MCP.dmg
   ```

## Troubleshooting

### Common Issues

1. **Sandbox Violations**
   - Check Console.app for violations
   - Add necessary entitlements
   - Use temporary exceptions sparingly

2. **Code Signing Issues**
   - Verify developer certificates
   - Check provisioning profiles
   - Clear derived data

3. **Notarization Failures**
   - Check for unsigned binaries
   - Verify entitlements
   - Review notarization log

### Debugging

```dart
// Enable macOS-specific debugging
if (Platform.isMacOS) {
  // Use native logging
  mcp.platform.log('Debug message', level: 'debug');
  
  // Monitor system events
  mcp.platform.systemEvents.listen((event) {
    print('System event: $event');
  });
}
```

## Platform-Specific APIs

```dart
// Access macOS-specific features
if (Platform.isMacOS) {
  // Get system information
  final info = await mcp.platform.getSystemInfo();
  print('macOS ${info.version} (${info.build})');
  
  // Use macOS-specific APIs
  final workspace = await mcp.platform.getWorkspace();
  await workspace.openURL('https://example.com');
}
```

## Next Steps

- [Windows Platform Guide](windows.md) - Windows-specific details
- [Distribution Guide](../guides/distribution.md) - App distribution strategies
- [Security Guide](../advanced/security.md) - macOS security best practices