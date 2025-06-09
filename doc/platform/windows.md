# Windows Platform Guide

This guide covers Windows-specific implementation details and best practices for Flutter MCP.

## Requirements

- Windows 10 version 1903 or higher
- Visual Studio 2019 or 2022
- Windows SDK 10.0.18362 or higher
- .NET Framework 4.7.2 or higher

## Setup

### 1. CMakeLists.txt Configuration

Add to `windows/CMakeLists.txt`:

```cmake
# Enable console for debugging (remove for release)
set_target_properties(${BINARY_NAME} PROPERTIES
  WIN32_EXECUTABLE TRUE
)

# Link required libraries
target_link_libraries(${BINARY_NAME} PRIVATE
  winmm
  imm32
  user32
  kernel32
  advapi32
  shell32
  ole32
  oleaut32
  uuid
)
```

### 2. App Manifest

Create `windows/runner/app.manifest`:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

### 3. Resource File

Configure `windows/runner/Runner.rc`:

```rc
IDI_APP_ICON ICON "app_icon.ico"

VS_VERSION_INFO VERSIONINFO
 FILEVERSION 1,0,0,0
 PRODUCTVERSION 1,0,0,0
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904e4"
        BEGIN
            VALUE "CompanyName", "Your Company"
            VALUE "FileDescription", "MCP Application"
            VALUE "FileVersion", "1.0.0.0"
            VALUE "ProductName", "MCP"
            VALUE "ProductVersion", "1.0.0.0"
        END
    END
END
```

## Features

### System Tray

Windows supports comprehensive system tray integration:

```dart
await mcp.trayManager.initialize(
  icon: 'assets/tray_icon.ico',
  tooltip: 'MCP Application',
);

// Create context menu
await mcp.trayManager.setContextMenu([
  TrayMenuItem(
    label: 'Show',
    onClick: () => mcp.showMainWindow(),
  ),
  TrayMenuItem.separator(),
  TrayMenuItem(
    label: 'Status',
    submenu: [
      TrayMenuItem(
        label: 'Connected',
        checked: isConnected,
      ),
    ],
  ),
  TrayMenuItem.separator(),
  TrayMenuItem(
    label: 'Exit',
    onClick: () => mcp.quit(),
  ),
]);

// Handle tray events
mcp.trayManager.onTrayIconClick(() {
  mcp.toggleWindow();
});

mcp.trayManager.onTrayIconRightClick(() {
  mcp.trayManager.popUpContextMenu();
});
```

### Window Management

```dart
// Configure window
await mcp.windowManager.setAsFrameless();
await mcp.windowManager.setBackgroundColor(Colors.transparent);
await mcp.windowManager.setSize(Size(800, 600));
await mcp.windowManager.center();

// Window controls
await mcp.windowManager.show();
await mcp.windowManager.hide();
await mcp.windowManager.minimize();
await mcp.windowManager.maximize();
await mcp.windowManager.unmaximize();

// Custom title bar
await mcp.windowManager.setTitleBarStyle(TitleBarStyle.hidden);

// Window events
mcp.windowManager.addListener(WindowListener(
  onWindowFocus: () => print('Window focused'),
  onWindowBlur: () => print('Window blurred'),
  onWindowMinimize: () => print('Window minimized'),
  onWindowMaximize: () => print('Window maximized'),
  onWindowResize: () => print('Window resized'),
));
```

### Notifications

```dart
// Windows 10+ notifications
await mcp.notificationManager.show(
  id: 1,
  title: 'MCP Update',
  body: 'New message received',
  actions: [
    NotificationAction(
      id: 'reply',
      label: 'Reply',
      inputs: [
        NotificationInput(
          id: 'text',
          placeholder: 'Type your reply...',
        ),
      ],
    ),
    NotificationAction(
      id: 'dismiss',
      label: 'Dismiss',
    ),
  ],
);

// Toast notifications
await mcp.toastManager.show(
  title: 'MCP',
  message: 'Background sync completed',
  duration: Duration(seconds: 3),
);
```

### Registry Access

```dart
// Read from registry
final value = await mcp.platform.readRegistry(
  hive: RegistryHive.currentUser,
  key: r'Software\MCP',
  value: 'LastSync',
);

// Write to registry
await mcp.platform.writeRegistry(
  hive: RegistryHive.currentUser,
  key: r'Software\MCP',
  value: 'LastSync',
  data: DateTime.now().toIso8601String(),
  type: RegistryValueType.string,
);

// Create registry key
await mcp.platform.createRegistryKey(
  hive: RegistryHive.currentUser,
  key: r'Software\MCP\Settings',
);
```

### Process Management

```dart
// Start process
final process = await Process.start(
  'C:\\Program Files\\nodejs\\node.exe',
  ['server.js'],
  workingDirectory: 'C:\\mcp',
  runInShell: true,
);

// Create Windows service
await mcp.platform.createWindowsService(
  name: 'MCPService',
  displayName: 'MCP Background Service',
  description: 'MCP background processing service',
  executable: 'C:\\Program Files\\MCP\\service.exe',
  startType: ServiceStartType.automatic,
);

// Control service
await mcp.platform.startService('MCPService');
await mcp.platform.stopService('MCPService');
```

### COM Integration

```dart
// Initialize COM
await mcp.platform.initializeCOM();

// Use Windows Shell
final shell = WindowsShell();
await shell.showItemInFolder('C:\\mcp\\config.json');

// Task Scheduler
await mcp.platform.createScheduledTask(
  name: 'MCP Daily Sync',
  executable: 'C:\\Program Files\\MCP\\mcp.exe',
  arguments: ['--sync'],
  trigger: DailyTrigger(hour: 2, minute: 0),
);
```

## Background Execution

### Windows Service

```dart
// Register as Windows service
class MCPWindowsService extends WindowsService {
  @override
  void onStart(List<String> args) {
    // Initialize MCP
    mcp.initialize();
    mcp.backgroundService.start();
  }
  
  @override
  void onStop() {
    // Cleanup
    mcp.backgroundService.stop();
    mcp.dispose();
  }
}

// Install service
await WindowsService.install(
  serviceName: 'MCPService',
  displayName: 'MCP Service',
  serviceClass: MCPWindowsService,
);
```

### Task Scheduler

```dart
// Create scheduled task
await mcp.platform.createScheduledTask(
  name: 'MCP Background',
  description: 'MCP background processing',
  executable: Platform.resolvedExecutable,
  arguments: ['--background'],
  trigger: IntervalTrigger(interval: Duration(minutes: 30)),
  conditions: TaskConditions(
    runOnlyIfNetworkAvailable: true,
    stopIfGoingOnBatteries: false,
  ),
);
```

## File System

```dart
// File associations
await mcp.platform.registerFileAssociation(
  extension: '.mcp',
  description: 'MCP Configuration File',
  iconPath: 'C:\\Program Files\\MCP\\file_icon.ico',
  openCommand: '"${Platform.resolvedExecutable}" "%1"',
);

// Shell integration
await mcp.platform.addContextMenuItem(
  title: 'Open with MCP',
  command: '"${Platform.resolvedExecutable}" "%1"',
  fileExtensions: ['.json', '.mcp'],
);

// Monitor file changes
final watcher = DirectoryWatcher('C:\\mcp\\config');
watcher.events.listen((event) {
  if (event.type == ChangeType.modify) {
    mcp.reloadConfiguration();
  }
});
```

## Security

### Windows Credentials

```dart
// Store credentials securely
await mcp.platform.storeWindowsCredential(
  target: 'MCP_API_KEY',
  username: 'api',
  password: 'secret_key',
);

// Retrieve credentials
final credential = await mcp.platform.getWindowsCredential('MCP_API_KEY');
print('Username: ${credential.username}');
print('Password: ${credential.password}');

// Delete credentials
await mcp.platform.deleteWindowsCredential('MCP_API_KEY');
```

### UAC Elevation

```dart
// Check if running as admin
final isAdmin = await mcp.platform.isRunningAsAdmin();

// Request elevation
if (!isAdmin) {
  await mcp.platform.requestElevation(
    reason: 'Admin rights required for service installation',
  );
}

// Run elevated process
await mcp.platform.runElevated(
  executable: 'installer.exe',
  arguments: ['/silent'],
);
```

## Deployment

### MSIX Package

```yaml
# pubspec.yaml
msix_config:
  display_name: MCP Application
  publisher_display_name: Your Company
  identity_name: com.yourcompany.mcp
  publisher: CN=YourCompany
  logo_path: assets/logo.png
  capabilities: 'internetClient,privateNetworkClientServer'
  languages: 'en-us'
```

### Installer Creation

```dart
// Inno Setup script generation
await mcp.deployment.generateInnoScript(
  appName: 'MCP',
  appVersion: '1.0.0',
  appPublisher: 'Your Company',
  outputDir: 'build/windows/installer',
  files: [
    'build/windows/runner/Release/*.exe',
    'build/windows/runner/Release/*.dll',
  ],
);

// WiX installer
await mcp.deployment.generateWixInstaller(
  productName: 'MCP',
  manufacturer: 'Your Company',
  version: '1.0.0',
  upgradeCode: 'YOUR-GUID-HERE',
);
```

### Code Signing

```dart
// Sign executable
await mcp.deployment.signExecutable(
  file: 'mcp.exe',
  certificate: 'certificate.pfx',
  password: 'cert_password',
  timestampServer: 'http://timestamp.digicert.com',
);

// Verify signature
final isValid = await mcp.deployment.verifySignature('mcp.exe');
```

## Troubleshooting

### Common Issues

1. **DLL Dependencies**
   - Use Dependency Walker to check missing DLLs
   - Include Visual C++ Redistributables
   - Bundle required libraries

2. **Permission Issues**
   - Check UAC settings
   - Verify file/registry permissions
   - Run as administrator if needed

3. **Antivirus False Positives**
   - Sign your executables
   - Submit to antivirus vendors
   - Use well-known libraries

### Debugging

```dart
// Windows-specific debugging
if (Platform.isWindows) {
  // Enable console output
  mcp.platform.allocateConsole();
  
  // Windows event log
  await mcp.platform.writeEventLog(
    source: 'MCP',
    message: 'Application started',
    type: EventLogType.information,
  );
  
  // Debug output
  mcp.platform.outputDebugString('Debug message');
}
```

### Performance Monitoring

```dart
// Windows Performance Counters
final counter = await mcp.platform.createPerformanceCounter(
  category: 'MCP',
  counter: 'Requests per second',
);

// Update counter
await counter.increment();

// Windows ETW (Event Tracing)
final provider = await mcp.platform.createETWProvider(
  providerGuid: 'YOUR-GUID',
  providerName: 'MCP-ETW',
);

await provider.writeEvent(
  level: ETWLevel.information,
  keyword: 0x1,
  message: 'Request processed',
);
```

## Platform-Specific APIs

```dart
// Access Windows-specific features
if (Platform.isWindows) {
  // Get Windows version
  final version = await mcp.platform.getWindowsVersion();
  print('Windows ${version.major}.${version.minor} Build ${version.build}');
  
  // Use Windows-specific APIs
  if (version.major >= 10) {
    // Windows 10+ features
    await mcp.platform.setWindowsTheme(WindowsTheme.dark);
  }
}
```

## Next Steps

- [Linux Platform Guide](linux.md) - Linux-specific details
- [Deployment Guide](../guides/deployment.md) - Windows deployment strategies
- [Performance Guide](../advanced/performance.md) - Windows optimization techniques