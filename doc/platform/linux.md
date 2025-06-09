# Linux Platform Guide

This guide covers Linux-specific implementation details and best practices for Flutter MCP.

## Requirements

- Ubuntu 18.04 LTS or higher (or equivalent distribution)
- GTK 3.0 or higher
- libsecret for secure storage
- D-Bus for system integration
- systemd (optional, for service management)

## Setup

### 1. System Dependencies

Install required packages:

```bash
sudo apt-get update
sudo apt-get install \
  libgtk-3-dev \
  libsecret-1-dev \
  libjsoncpp-dev \
  libappindicator3-dev \
  libnotify-dev \
  libgirepository1.0-dev
```

### 2. CMakeLists.txt Configuration

Add to `linux/CMakeLists.txt`:

```cmake
# Find required packages
pkg_check_modules(APPINDICATOR3 REQUIRED appindicator3-0.1)
pkg_check_modules(LIBSECRET REQUIRED libsecret-1)
pkg_check_modules(LIBNOTIFY REQUIRED libnotify)

# Include directories
target_include_directories(${BINARY_NAME} PRIVATE
  ${APPINDICATOR3_INCLUDE_DIRS}
  ${LIBSECRET_INCLUDE_DIRS}
  ${LIBNOTIFY_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(${BINARY_NAME} PRIVATE
  ${APPINDICATOR3_LIBRARIES}
  ${LIBSECRET_LIBRARIES}
  ${LIBNOTIFY_LIBRARIES}
)
```

### 3. Desktop Entry

Create `linux/mcp.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=MCP
Comment=Model Context Protocol Application
Icon=mcp
Exec=/usr/local/bin/mcp
Categories=Development;Utility;
StartupNotify=true
Terminal=false
```

## Features

### System Tray

Linux system tray using AppIndicator3:

```dart
await mcp.trayManager.initialize(
  icon: 'assets/tray_icon.png',
  label: 'MCP',
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
        label: isConnected ? '● Connected' : '○ Disconnected',
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

// Status icon variations
await mcp.trayManager.setIcon(
  isConnected ? 'assets/tray_connected.png' : 'assets/tray_disconnected.png'
);
```

### Notifications

Using libnotify for desktop notifications:

```dart
await mcp.notificationManager.show(
  id: 1,
  title: 'MCP Update',
  body: 'New message received',
  icon: 'assets/notification_icon.png',
  urgency: NotificationUrgency.normal,
  actions: [
    NotificationAction(
      id: 'open',
      label: 'Open',
    ),
    NotificationAction(
      id: 'dismiss',
      label: 'Dismiss',
    ),
  ],
);

// Check notification server capabilities
final capabilities = await mcp.notificationManager.getCapabilities();
if (capabilities.contains('actions')) {
  // Server supports actions
}
```

### D-Bus Integration

```dart
// Register D-Bus service
await mcp.platform.registerDBusService(
  name: 'com.example.MCP',
  path: '/com/example/MCP',
  interface: 'com.example.MCP.Interface',
);

// Export methods
await mcp.platform.exportDBusMethod(
  'SendMessage',
  (String message) async {
    await mcp.processMessage(message);
    return 'Message processed';
  },
);

// Emit signals
await mcp.platform.emitDBusSignal(
  'StatusChanged',
  {'status': 'connected'},
);
```

### Systemd Service

Create systemd service for background execution:

```ini
# /etc/systemd/user/mcp.service
[Unit]
Description=MCP Background Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mcp --background
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

Register and control:

```dart
// Install systemd service
await mcp.platform.installSystemdService(
  name: 'mcp',
  description: 'MCP Background Service',
  execStart: '/usr/local/bin/mcp --background',
  user: true, // User service
);

// Control service
await mcp.platform.startSystemdService('mcp');
await mcp.platform.stopSystemdService('mcp');
await mcp.platform.enableSystemdService('mcp'); // Auto-start

// Check status
final status = await mcp.platform.getSystemdServiceStatus('mcp');
```

### Window Management

```dart
// X11 window properties
await mcp.windowManager.setWindowType(WindowType.normal);
await mcp.windowManager.setSkipTaskbar(false);
await mcp.windowManager.setAlwaysOnTop(false);

// Wayland compatibility
if (await mcp.platform.isWayland()) {
  // Use Wayland-compatible features
  await mcp.windowManager.useWaylandProtocols();
}

// Desktop integration
await mcp.windowManager.setDesktopFileName('mcp.desktop');
```

### File System

```dart
// XDG directories
final configDir = await mcp.platform.getXDGConfigHome(); // ~/.config
final dataDir = await mcp.platform.getXDGDataHome();     // ~/.local/share
final cacheDir = await mcp.platform.getXDGCacheHome();   // ~/.cache

// Application directories
final appConfigDir = '$configDir/mcp';
final appDataDir = '$dataDir/mcp';
final appCacheDir = '$cacheDir/mcp';

// Create directories
await Directory(appConfigDir).create(recursive: true);
await Directory(appDataDir).create(recursive: true);
await Directory(appCacheDir).create(recursive: true);

// Monitor file changes with inotify
final watcher = DirectoryWatcher(appConfigDir);
watcher.events.listen((event) {
  if (event.path.endsWith('config.json')) {
    mcp.reloadConfiguration();
  }
});
```

### Secure Storage

Using libsecret for secure credential storage:

```dart
// Store credentials
await mcp.secureStorage.write(
  key: 'api_key',
  value: 'secret_value',
  attributes: {
    'application': 'mcp',
    'service': 'api',
  },
);

// Retrieve credentials
final apiKey = await mcp.secureStorage.read(
  key: 'api_key',
  attributes: {
    'application': 'mcp',
    'service': 'api',
  },
);

// Delete credentials
await mcp.secureStorage.delete(key: 'api_key');

// List all keys
final keys = await mcp.secureStorage.getAllKeys();
```

### Process Management

```dart
// Launch processes
final process = await Process.start(
  '/usr/bin/node',
  ['server.js'],
  workingDirectory: '/home/user/mcp',
  environment: {
    'NODE_ENV': 'production',
    'LD_LIBRARY_PATH': '/usr/local/lib',
  },
);

// Monitor process
process.stdout.transform(utf8.decoder).listen((data) {
  print('Output: $data');
});

// Check if process exists
final pid = await mcp.platform.findProcessByName('node');
if (pid != null) {
  // Process is running
  await mcp.platform.sendSignal(pid, ProcessSignal.sighup);
}
```

## Package Management

### Debian/Ubuntu Package

Create `debian/control`:

```
Package: mcp
Version: 1.0.0
Architecture: amd64
Maintainer: Your Name <email@example.com>
Depends: libgtk-3-0, libsecret-1-0, libnotify4
Description: Model Context Protocol Application
 MCP integration for Flutter applications
```

Build package:

```bash
# Create package structure
mkdir -p debian/usr/local/bin
cp build/linux/x64/release/bundle/mcp debian/usr/local/bin/

# Create .deb package
dpkg-deb --build debian mcp_1.0.0_amd64.deb
```

### AppImage

Create portable AppImage:

```bash
# Use linuxdeployqt
linuxdeployqt build/linux/x64/release/bundle/mcp \
  -appimage \
  -extra-plugins=iconengines,platformthemes
```

### Flatpak

Create `com.example.MCP.yaml`:

```yaml
app-id: com.example.MCP
runtime: org.freedesktop.Platform
runtime-version: '21.08'
sdk: org.freedesktop.Sdk
command: mcp

modules:
  - name: mcp
    buildsystem: simple
    build-commands:
      - install -D mcp /app/bin/mcp
    sources:
      - type: file
        path: build/linux/x64/release/bundle/mcp
```

### Snap

Create `snap/snapcraft.yaml`:

```yaml
name: mcp
version: '1.0.0'
summary: Model Context Protocol Application
description: |
  MCP integration for Flutter applications

confinement: strict
grade: stable

apps:
  mcp:
    command: mcp
    plugs:
      - network
      - network-bind
      - desktop
      - desktop-legacy
      - wayland
      - x11

parts:
  mcp:
    plugin: dump
    source: build/linux/x64/release/bundle/
```

## Distribution-Specific Support

### Ubuntu/Debian

```dart
// Check distribution
final distro = await mcp.platform.getLinuxDistribution();
if (distro.id == 'ubuntu' || distro.id == 'debian') {
  // Ubuntu/Debian specific code
  await mcp.platform.installAptPackage('nodejs');
}
```

### Fedora/RHEL

```dart
if (distro.id == 'fedora' || distro.id == 'rhel') {
  // Fedora/RHEL specific code
  await mcp.platform.installDnfPackage('nodejs');
}
```

### Arch Linux

```dart
if (distro.id == 'arch') {
  // Arch specific code
  await mcp.platform.installPacmanPackage('nodejs');
}
```

## Troubleshooting

### Common Issues

1. **Missing Dependencies**
   ```bash
   # Check missing libraries
   ldd build/linux/x64/release/bundle/mcp
   
   # Install missing packages
   sudo apt-get install libgtk-3-0
   ```

2. **Permission Issues**
   ```bash
   # Fix permissions
   chmod +x build/linux/x64/release/bundle/mcp
   
   # For system services
   sudo chown root:root /etc/systemd/system/mcp.service
   ```

3. **Display Issues**
   ```bash
   # Check display
   echo $DISPLAY
   
   # For headless systems
   export DISPLAY=:0
   ```

### Debugging

```dart
// Enable Linux-specific debugging
if (Platform.isLinux) {
  // GTK debugging
  Platform.environment['GTK_DEBUG'] = 'all';
  
  // GLib debugging
  Platform.environment['G_MESSAGES_DEBUG'] = 'all';
  
  // D-Bus debugging
  Platform.environment['DBUS_VERBOSE'] = '1';
}

// System logs
await mcp.platform.writeToJournal(
  message: 'MCP started',
  priority: JournalPriority.info,
  fields: {
    'MCP_VERSION': '1.0.0',
    'MCP_PID': pid.toString(),
  },
);
```

### Performance Monitoring

```dart
// Monitor system resources
final cpuInfo = await mcp.platform.getCPUInfo();
final memInfo = await mcp.platform.getMemoryInfo();
final diskInfo = await mcp.platform.getDiskInfo();

// Process statistics
final stats = await mcp.platform.getProcessStats(pid);
print('CPU usage: ${stats.cpuPercent}%');
print('Memory usage: ${stats.memoryMB}MB');

// System load
final loadAvg = await mcp.platform.getLoadAverage();
print('Load average: ${loadAvg.oneMinute}');
```

## Security

### SELinux

```bash
# Create SELinux policy
cat > mcp.te << EOF
policy_module(mcp, 1.0.0)

type mcp_t;
type mcp_exec_t;

# Define permissions
allow mcp_t self:tcp_socket create_stream_socket_perms;
allow mcp_t self:udp_socket create_socket_perms;
EOF

# Compile and install
checkmodule -M -m -o mcp.mod mcp.te
semodule_package -o mcp.pp -m mcp.mod
semodule -i mcp.pp
```

### AppArmor

```bash
# Create AppArmor profile
cat > /etc/apparmor.d/usr.local.bin.mcp << EOF
#include <tunables/global>

/usr/local/bin/mcp {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  /usr/local/bin/mcp mr,
  /home/*/.config/mcp/** rw,
  /home/*/.local/share/mcp/** rw,
  /home/*/.cache/mcp/** rw,
  
  network tcp,
  network udp,
}
EOF

# Load profile
apparmor_parser -r /etc/apparmor.d/usr.local.bin.mcp
```

## Platform-Specific APIs

```dart
// Access Linux-specific features
if (Platform.isLinux) {
  // Get kernel version
  final kernel = await mcp.platform.getKernelVersion();
  print('Kernel: $kernel');
  
  // Distribution info
  final distro = await mcp.platform.getLinuxDistribution();
  print('Distribution: ${distro.name} ${distro.version}');
  
  // Desktop environment
  final desktop = await mcp.platform.getDesktopEnvironment();
  print('Desktop: $desktop');
}
```

## Next Steps

- [Web Platform Guide](web.md) - Web-specific details
- [Deployment Guide](../guides/deployment.md) - Linux deployment strategies
- [Security Guide](../advanced/security.md) - Linux security best practices