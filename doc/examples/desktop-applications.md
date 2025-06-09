# Desktop Applications Example

This example demonstrates building desktop applications with Flutter MCP, including system tray integration, native menus, and file system access.

## Overview

This example shows how to:
- Integrate with system tray
- Create native menus
- Handle file system operations
- Implement desktop-specific features

## System Tray Integration

### Basic Tray Setup

```dart
// lib/services/tray_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener, WindowListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();
  
  bool _initialized = false;
  Function()? onShowWindow;
  Function()? onQuitApp;
  
  Future<void> initialize() async {
    if (_initialized) return;
    
    await trayManager.setIcon(
      Platform.isWindows
          ? 'assets/icons/tray_icon.ico'
          : 'assets/icons/tray_icon.png',
    );
    
    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Show Window',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'check_updates',
          label: 'Check for Updates',
        ),
        MenuItem(
          key: 'preferences',
          label: 'Preferences',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    );
    
    await trayManager.setContextMenu(menu);
    await trayManager.setToolTip('Flutter MCP Desktop');
    
    trayManager.addListener(this);
    windowManager.addListener(this);
    
    _initialized = true;
  }
  
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }
  
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        onShowWindow?.call();
        break;
      case 'check_updates':
        _checkForUpdates();
        break;
      case 'preferences':
        _showPreferences();
        break;
      case 'quit':
        onQuitApp?.call();
        break;
    }
  }
  
  @override
  void onWindowClose() {
    windowManager.hide();
  }
  
  Future<void> showNotification(String title, String message) async {
    // Platform-specific notification
    if (Platform.isMacOS) {
      await Process.run('osascript', [
        '-e',
        'display notification "$message" with title "$title"',
      ]);
    } else if (Platform.isWindows) {
      // Use Windows notification API
      await trayManager.setIcon(
        'assets/icons/tray_icon_notification.ico',
      );
      
      Timer(Duration(seconds: 3), () {
        trayManager.setIcon(
          'assets/icons/tray_icon.ico',
        );
      });
    } else if (Platform.isLinux) {
      await Process.run('notify-send', [title, message]);
    }
  }
  
  void _checkForUpdates() {
    // Implement update check logic
    showNotification(
      'Update Check',
      'You are running the latest version',
    );
  }
  
  void _showPreferences() {
    // Show preferences window
    windowManager.show();
    // Navigate to preferences screen
  }
  
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
```

### Advanced Tray Features

```dart
// lib/services/advanced_tray_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class AdvancedTrayService extends TrayService {
  final _serverStatuses = <String, ServerStatus>{};
  Timer? _statusUpdateTimer;
  
  @override
  Future<void> initialize() async {
    await super.initialize();
    
    // Start monitoring server statuses
    _startStatusMonitoring();
    
    // Update tray menu dynamically
    _updateTrayMenu();
  }
  
  void _startStatusMonitoring() {
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _updateServerStatuses();
    });
  }
  
  Future<void> _updateServerStatuses() async {
    final servers = FlutterMCP.serverManager.getServers();
    
    for (final server in servers) {
      final isConnected = await server.isConnected;
      _serverStatuses[server.name] = isConnected
          ? ServerStatus.connected
          : ServerStatus.disconnected;
    }
    
    _updateTrayMenu();
    _updateTrayIcon();
  }
  
  void _updateTrayMenu() {
    final serverMenuItems = _serverStatuses.entries.map((entry) {
      final serverName = entry.key;
      final status = entry.value;
      
      return MenuItem(
        key: 'server_$serverName',
        label: '$serverName: ${status.name}',
        enabled: status == ServerStatus.disconnected,
      );
    }).toList();
    
    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Show Window',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'servers',
          label: 'Servers',
          submenu: Menu(
            items: serverMenuItems,
          ),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    );
    
    trayManager.setContextMenu(menu);
  }
  
  void _updateTrayIcon() {
    final hasDisconnectedServers = _serverStatuses.values
        .any((status) => status == ServerStatus.disconnected);
    
    final iconPath = hasDisconnectedServers
        ? 'assets/icons/tray_icon_warning.png'
        : 'assets/icons/tray_icon_connected.png';
    
    trayManager.setIcon(iconPath);
  }
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key?.startsWith('server_') ?? false) {
      final serverName = menuItem.key!.substring(7);
      _reconnectServer(serverName);
    } else {
      super.onTrayMenuItemClick(menuItem);
    }
  }
  
  Future<void> _reconnectServer(String serverName) async {
    try {
      await FlutterMCP.connect(serverName);
      showNotification(
        'Server Connected',
        '$serverName connected successfully',
      );
    } catch (e) {
      showNotification(
        'Connection Failed',
        'Failed to connect to $serverName',
      );
    }
  }
  
  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    super.dispose();
  }
}

enum ServerStatus {
  connected,
  disconnected,
  error,
}
```

## Native Menu Integration

### Application Menu

```dart
// lib/services/menu_service.dart
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class MenuService {
  static const _channel = MethodChannel('flutter_mcp/menu');
  
  static Future<void> setupApplicationMenu() async {
    if (Platform.isMacOS) {
      await _setupMacOSMenu();
    } else if (Platform.isWindows || Platform.isLinux) {
      await _setupWindowsLinuxMenu();
    }
  }
  
  static Future<void> _setupMacOSMenu() async {
    final menu = PlatformMenu(
      menus: [
        PlatformMenu(
          label: 'Flutter MCP',
          menus: [
            PlatformMenuItem(
              label: 'About Flutter MCP',
              onSelected: () => _showAbout(),
            ),
            const PlatformMenuDivider(),
            PlatformMenuItem(
              label: 'Preferences',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: () => _showPreferences(),
            ),
            const PlatformMenuDivider(),
            PlatformMenuItem(
              label: 'Quit',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyQ,
                meta: true,
              ),
              onSelected: () => _quitApp(),
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Connection',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: () => _newConnection(),
            ),
            PlatformMenuItem(
              label: 'Open Configuration',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: () => _openConfiguration(),
            ),
            const PlatformMenuDivider(),
            PlatformMenuItem(
              label: 'Export Logs',
              onSelected: () => _exportLogs(),
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Toggle Full Screen',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                control: true,
              ),
              onSelected: () => _toggleFullScreen(),
            ),
            const PlatformMenuDivider(),
            PlatformMenuItem(
              label: 'Show Server List',
              onSelected: () => _showServerList(),
            ),
            PlatformMenuItem(
              label: 'Show Activity Monitor',
              onSelected: () => _showActivityMonitor(),
            ),
          ],
        ),
      ],
    );
    
    await _channel.invokeMethod('setApplicationMenu', menu.toJson());
  }
  
  static Future<void> _setupWindowsLinuxMenu() async {
    // Windows/Linux menu setup
    // These platforms typically use in-window menus
  }
  
  static void _showAbout() {
    // Show about dialog
  }
  
  static void _showPreferences() {
    // Navigate to preferences
  }
  
  static void _quitApp() {
    // Quit application
  }
  
  static void _newConnection() {
    // Show new connection dialog
  }
  
  static void _openConfiguration() {
    // Open configuration file
  }
  
  static void _exportLogs() {
    // Export logs to file
  }
  
  static void _toggleFullScreen() {
    windowManager.setFullScreen(
      !windowManager.isFullScreen,
    );
  }
  
  static void _showServerList() {
    // Navigate to server list
  }
  
  static void _showActivityMonitor() {
    // Show activity monitor window
  }
}
```

### Context Menus

```dart
// lib/widgets/context_menu_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContextMenuWidget extends StatelessWidget {
  final Widget child;
  final List<PlatformMenuItem> menuItems;
  
  const ContextMenuWidget({
    Key? key,
    required this.child,
    required this.menuItems,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [],
      child: GestureDetector(
        onSecondaryTapDown: (details) => _showContextMenu(
          context,
          details.globalPosition,
        ),
        child: child,
      ),
    );
  }
  
  void _showContextMenu(BuildContext context, Offset position) {
    final menu = PlatformMenu(
      label: '',
      menus: menuItems,
    );
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: menuItems.map((item) {
        if (item is PlatformMenuDivider) {
          return const PopupMenuDivider();
        }
        
        return PopupMenuItem(
          child: Row(
            children: [
              Expanded(
                child: Text(item.label),
              ),
              if (item.shortcut != null)
                Text(
                  _formatShortcut(item.shortcut!),
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          onTap: item.onSelected,
        );
      }).toList(),
    );
  }
  
  String _formatShortcut(SingleActivator shortcut) {
    final parts = <String>[];
    
    if (shortcut.meta) parts.add('⌘');
    if (shortcut.control) parts.add('⌃');
    if (shortcut.alt) parts.add('⌥');
    if (shortcut.shift) parts.add('⇧');
    
    parts.add(shortcut.trigger.keyLabel);
    
    return parts.join('');
  }
}
```

## File System Operations

### File Manager Integration

```dart
// lib/services/file_service.dart
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FileService {
  static Future<String?> pickFile({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    
    return result?.files.single.path;
  }
  
  static Future<List<String>?> pickMultipleFiles({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: true,
      allowedExtensions: allowedExtensions,
    );
    
    return result?.paths.whereType<String>().toList();
  }
  
  static Future<String?> pickDirectory() async {
    return await FilePicker.platform.getDirectoryPath();
  }
  
  static Future<String?> saveFile({
    String? fileName,
    List<String>? allowedExtensions,
  }) async {
    return await FilePicker.platform.saveFile(
      fileName: fileName,
      allowedExtensions: allowedExtensions,
    );
  }
  
  static Future<Directory> getApplicationDirectory() async {
    if (Platform.isMacOS) {
      return await getApplicationSupportDirectory();
    } else if (Platform.isWindows || Platform.isLinux) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE']!;
      return Directory('$home/.flutter_mcp');
    }
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<void> openInExplorer(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  }
  
  static Future<void> watchDirectory(
    String path,
    void Function(FileSystemEvent) onEvent,
  ) async {
    final directory = Directory(path);
    
    if (!await directory.exists()) {
      throw FileSystemException('Directory does not exist', path);
    }
    
    directory.watch(recursive: true).listen(onEvent);
  }
  
  static Future<Map<String, dynamic>> getFileInfo(String path) async {
    final file = File(path);
    final stat = await file.stat();
    
    return {
      'path': path,
      'name': path.split(Platform.pathSeparator).last,
      'size': stat.size,
      'modified': stat.modified.toIso8601String(),
      'created': stat.accessed.toIso8601String(),
      'type': stat.type.toString(),
    };
  }
}
```

### File Drop Support

```dart
// lib/widgets/file_drop_zone.dart
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

class FileDropZone extends StatefulWidget {
  final Widget child;
  final Function(List<String>) onFilesDropped;
  final List<String>? allowedExtensions;
  
  const FileDropZone({
    Key? key,
    required this.child,
    required this.onFilesDropped,
    this.allowedExtensions,
  }) : super(key: key);
  
  @override
  _FileDropZoneState createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;
  
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() => _isDragging = true);
      },
      onDragExited: (details) {
        setState(() => _isDragging = false);
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        
        final files = details.files
            .map((file) => file.path)
            .where((path) => _isAllowedFile(path))
            .toList();
        
        if (files.isNotEmpty) {
          widget.onFilesDropped(files);
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isDragging
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: _isDragging
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            widget.child,
            if (_isDragging)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download,
                          size: 48,
                          color: Theme.of(context).primaryColor,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Drop files here',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.allowedExtensions != null)
                          Text(
                            'Allowed: ${widget.allowedExtensions!.join(", ")}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  bool _isAllowedFile(String path) {
    if (widget.allowedExtensions == null) return true;
    
    final extension = path.split('.').last.toLowerCase();
    return widget.allowedExtensions!.contains(extension);
  }
}
```

## Desktop UI Components

### Window Management

```dart
// lib/services/window_service.dart
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';

class WindowService {
  static Future<void> initialize() async {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.default,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  static Future<void> setTitle(String title) async {
    await windowManager.setTitle(title);
  }
  
  static Future<void> setSize(Size size) async {
    await windowManager.setSize(size);
  }
  
  static Future<void> center() async {
    await windowManager.center();
  }
  
  static Future<void> toggleFullScreen() async {
    final isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
  }
  
  static Future<void> minimize() async {
    await windowManager.minimize();
  }
  
  static Future<void> maximize() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
  
  static Future<void> close() async {
    await windowManager.close();
  }
  
  static Future<void> setAlwaysOnTop(bool alwaysOnTop) async {
    await windowManager.setAlwaysOnTop(alwaysOnTop);
  }
  
  static Future<void> setOpacity(double opacity) async {
    await windowManager.setOpacity(opacity);
  }
}
```

### Custom Title Bar

```dart
// lib/widgets/custom_title_bar.dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  
  const CustomTitleBar({
    Key? key,
    required this.title,
    this.actions,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: Theme.of(context).primaryColor,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (actions != null) ...actions!,
          WindowButtons(),
        ],
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WindowButton(
          icon: Icons.minimize,
          onPressed: () => windowManager.minimize(),
        ),
        WindowButton(
          icon: Icons.crop_square,
          onPressed: () async {
            final isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
        ),
        WindowButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          isClose: true,
        ),
      ],
    );
  }
}

class WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  
  const WindowButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 46,
        height: 32,
        child: Icon(
          icon,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}
```

## Desktop Features Implementation

### Auto-Start Configuration

```dart
// lib/services/autostart_service.dart
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoStartService {
  static Future<void> initialize() async {
    final packageInfo = await PackageInfo.fromPlatform();
    
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
  }
  
  static Future<bool> isEnabled() async {
    return await launchAtStartup.isEnabled();
  }
  
  static Future<void> enable() async {
    await launchAtStartup.enable();
  }
  
  static Future<void> disable() async {
    await launchAtStartup.disable();
  }
  
  static Future<void> toggle() async {
    final enabled = await isEnabled();
    if (enabled) {
      await disable();
    } else {
      await enable();
    }
  }
}
```

### Keyboard Shortcuts

```dart
// lib/services/shortcut_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class ShortcutService {
  static final Map<String, HotKey> _hotkeys = {};
  
  static Future<void> initialize() async {
    await hotKeyManager.unregisterAll();
  }
  
  static Future<void> registerShortcut({
    required String id,
    required KeyCombination combination,
    required VoidCallback onPressed,
  }) async {
    final hotkey = HotKey(
      key: combination.key,
      modifiers: combination.modifiers,
      scope: HotKeyScope.system,
    );
    
    await hotKeyManager.register(
      hotkey,
      keyDownHandler: (_) => onPressed(),
    );
    
    _hotkeys[id] = hotkey;
  }
  
  static Future<void> unregisterShortcut(String id) async {
    final hotkey = _hotkeys[id];
    if (hotkey != null) {
      await hotKeyManager.unregister(hotkey);
      _hotkeys.remove(id);
    }
  }
  
  static Future<void> registerDefaultShortcuts() async {
    // New window
    await registerShortcut(
      id: 'new_window',
      combination: KeyCombination(
        key: LogicalKeyboardKey.keyN,
        modifiers: [ModifierKey.meta],
      ),
      onPressed: () => _createNewWindow(),
    );
    
    // Toggle full screen
    await registerShortcut(
      id: 'toggle_fullscreen',
      combination: KeyCombination(
        key: LogicalKeyboardKey.keyF,
        modifiers: [ModifierKey.meta, ModifierKey.control],
      ),
      onPressed: () => WindowService.toggleFullScreen(),
    );
    
    // Show preferences
    await registerShortcut(
      id: 'show_preferences',
      combination: KeyCombination(
        key: LogicalKeyboardKey.comma,
        modifiers: [ModifierKey.meta],
      ),
      onPressed: () => _showPreferences(),
    );
  }
  
  static void _createNewWindow() {
    // Create new window logic
  }
  
  static void _showPreferences() {
    // Show preferences logic
  }
}

class KeyCombination {
  final LogicalKeyboardKey key;
  final List<ModifierKey> modifiers;
  
  KeyCombination({
    required this.key,
    this.modifiers = const [],
  });
}
```

## Desktop Application Example

### Main Application

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'services/window_service.dart';
import 'services/tray_service.dart';
import 'services/menu_service.dart';
import 'services/shortcut_service.dart';
import 'services/autostart_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize desktop services
  await WindowService.initialize();
  await TrayService().initialize();
  await MenuService.setupApplicationMenu();
  await ShortcutService.initialize();
  await AutoStartService.initialize();
  
  // Initialize MCP
  await FlutterMCP.initialize(MCPConfig(
    servers: {
      'main-server': ServerConfig(
        uri: 'ws://localhost:3000',
      ),
    },
  ));
  
  runApp(DesktopApp());
}

class DesktopApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP Desktop',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.standard,
      ),
      home: DesktopHomeScreen(),
    );
  }
}
```

### Desktop Home Screen

```dart
// lib/screens/desktop_home_screen.dart
import 'package:flutter/material.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/file_drop_zone.dart';

class DesktopHomeScreen extends StatefulWidget {
  @override
  _DesktopHomeScreenState createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 0;
  
  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: Icons.dashboard,
      label: 'Dashboard',
      page: DashboardPage(),
    ),
    NavigationItem(
      icon: Icons.cloud,
      label: 'Servers',
      page: ServersPage(),
    ),
    NavigationItem(
      icon: Icons.folder,
      label: 'Files',
      page: FilesPage(),
    ),
    NavigationItem(
      icon: Icons.settings,
      label: 'Settings',
      page: SettingsPage(),
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          CustomTitleBar(
            title: 'Flutter MCP Desktop',
            actions: [
              IconButton(
                icon: Icon(Icons.search, color: Colors.white),
                onPressed: () => _showSearch(),
              ),
            ],
          ),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  extended: true,
                  destinations: _navigationItems
                      .map((item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            label: Text(item.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: FileDropZone(
                    onFilesDropped: _handleFilesDropped,
                    child: _navigationItems[_selectedIndex].page,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _showSearch() {
    showDialog(
      context: context,
      builder: (context) => SearchDialog(),
    );
  }
  
  void _handleFilesDropped(List<String> files) {
    // Handle dropped files
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dropped ${files.length} files'),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final Widget page;
  
  NavigationItem({
    required this.icon,
    required this.label,
    required this.page,
  });
}
```

## Testing Desktop Features

```dart
// test/desktop_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('Desktop Services', () {
    test('tray service initializes', () async {
      final trayService = MockTrayService();
      
      await trayService.initialize();
      
      verify(trayService.initialize()).called(1);
    });
    
    test('window service handles sizing', () async {
      final windowService = MockWindowService();
      
      await windowService.setSize(Size(1200, 800));
      await windowService.center();
      
      verify(windowService.setSize(any)).called(1);
      verify(windowService.center()).called(1);
    });
    
    test('file service picks files', () async {
      final fileService = MockFileService();
      
      when(fileService.pickFile())
          .thenAnswer((_) async => '/path/to/file.txt');
      
      final file = await fileService.pickFile();
      
      expect(file, equals('/path/to/file.txt'));
    });
  });
}
```

## Best Practices

### Platform-Specific Code

```dart
// Use platform checks appropriately
if (Platform.isMacOS) {
  // macOS specific code
} else if (Platform.isWindows) {
  // Windows specific code
} else if (Platform.isLinux) {
  // Linux specific code
}
```

### Resource Management

```dart
// Properly dispose of desktop resources
@override
void dispose() {
  TrayService().dispose();
  WindowService.dispose();
  ShortcutService.dispose();
  super.dispose();
}
```

### Performance Considerations

```dart
// Use appropriate window update strategies
windowManager.setIgnoreMouseEvents(true); // For overlay windows
windowManager.setSkipTaskbar(true); // For background windows
```

## Next Steps

- Explore [Web Applications](./web-applications.md)
- Learn about [Android Integration](./android-integration.md)
- Try [iOS Integration](./ios-integration.md)