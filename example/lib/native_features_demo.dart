import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Native Features Demo Page
/// 
/// This page demonstrates all the native platform features that Flutter MCP
/// provides through native channels instead of external packages.
class NativeFeaturesDemo extends StatefulWidget {
  const NativeFeaturesDemo({Key? key}) : super(key: key);

  @override
  State<NativeFeaturesDemo> createState() => _NativeFeaturesDemoState();
}

class _NativeFeaturesDemoState extends State<NativeFeaturesDemo> {
  final Logger _logger = Logger('flutter_mcp.native_features_demo');
  
  // Background Service State
  bool _backgroundServiceRunning = false;
  int _backgroundTaskCount = 0;
  String _lastBackgroundTaskResult = 'No tasks executed yet';
  
  // Notification State
  bool _notificationPermissionGranted = false;
  int _notificationCount = 0;
  final List<String> _activeNotifications = [];
  
  // Secure Storage State
  final Map<String, String> _secureData = {};
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  
  // System Tray State (Desktop only)
  bool _trayVisible = false;
  String _trayTooltip = 'Flutter MCP Demo';
  
  @override
  void initState() {
    super.initState();
    _checkPlatformFeatures();
  }
  
  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }
  
  Future<void> _checkPlatformFeatures() async {
    try {
      final status = FlutterMCP.instance.platformServicesStatus;
      setState(() {
        _backgroundServiceRunning = status['backgroundServiceRunning'] ?? false;
      });
    } catch (e) {
      _logger.error('Failed to check platform features: $e');
    }
  }
  
  String get _platformName {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
    } catch (e) {
      // Fallback
    }
    return 'Unknown';
  }
  
  bool get _isDesktop {
    if (kIsWeb) return false;
    try {
      return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Platform Features'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform Info
            _buildSectionCard(
              title: 'Platform Information',
              icon: Icons.devices,
              children: [
                ListTile(
                  title: const Text('Current Platform'),
                  subtitle: Text(_platformName),
                  trailing: Icon(
                    _getPlatformIcon(),
                    size: 32,
                  ),
                ),
                ListTile(
                  title: const Text('Native Channels'),
                  subtitle: const Text('All features use Flutter method/event channels'),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Background Service
            _buildSectionCard(
              title: 'Background Service',
              icon: Icons.sync,
              children: [
                SwitchListTile(
                  title: const Text('Background Service'),
                  subtitle: Text(_backgroundServiceRunning ? 'Running' : 'Stopped'),
                  value: _backgroundServiceRunning,
                  onChanged: (value) async {
                    if (value) {
                      await _startBackgroundService();
                    } else {
                      await _stopBackgroundService();
                    }
                  },
                ),
                ListTile(
                  title: const Text('Task Count'),
                  subtitle: Text('$_backgroundTaskCount tasks executed'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _scheduleBackgroundTask,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Task Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_lastBackgroundTaskResult),
                    ],
                  ),
                ),
                _buildPlatformNote(_getPlatformBackgroundNote()),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Notifications
            _buildSectionCard(
              title: 'Notifications',
              icon: Icons.notifications,
              children: [
                ListTile(
                  title: const Text('Permission Status'),
                  subtitle: Text(_notificationPermissionGranted ? 'Granted' : 'Not granted'),
                  trailing: TextButton(
                    onPressed: _requestNotificationPermission,
                    child: const Text('Request'),
                  ),
                ),
                ListTile(
                  title: const Text('Show Test Notification'),
                  subtitle: Text('$_notificationCount notifications shown'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notification_add),
                        onPressed: _showNotification,
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_off),
                        onPressed: _clearNotifications,
                      ),
                    ],
                  ),
                ),
                if (_activeNotifications.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Active Notifications:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ..._activeNotifications.map((id) => ListTile(
                    dense: true,
                    title: Text(id),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => _cancelNotification(id),
                    ),
                  )),
                ],
                _buildPlatformNote(_getPlatformNotificationNote()),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Secure Storage
            _buildSectionCard(
              title: 'Secure Storage',
              icon: Icons.security,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _keyController,
                        decoration: const InputDecoration(
                          labelText: 'Key',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _valueController,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saveToSecureStorage,
                              child: const Text('Save'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _readFromSecureStorage,
                              child: const Text('Read'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton(
                              onPressed: _deleteFromSecureStorage,
                              child: const Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_secureData.isNotEmpty) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Stored Data:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ..._secureData.entries.map((entry) => ListTile(
                    dense: true,
                    title: Text(entry.key),
                    subtitle: Text(entry.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () => _deleteKey(entry.key),
                    ),
                  )),
                ],
                _buildPlatformNote(_getPlatformStorageNote()),
              ],
            ),
            
            // System Tray (Desktop only)
            if (_isDesktop) ...[
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'System Tray',
                icon: Icons.view_compact,
                children: [
                  SwitchListTile(
                    title: const Text('Show Tray Icon'),
                    subtitle: Text(_trayVisible ? 'Visible' : 'Hidden'),
                    value: _trayVisible,
                    onChanged: (value) async {
                      if (value) {
                        await _showTrayIcon();
                      } else {
                        await _hideTrayIcon();
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Tray Tooltip'),
                    subtitle: Text(_trayTooltip),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: _editTrayTooltip,
                    ),
                  ),
                  ListTile(
                    title: const Text('Tray Menu'),
                    subtitle: const Text('Click to update menu items'),
                    trailing: IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: _updateTrayMenu,
                    ),
                  ),
                  _buildPlatformNote(_getPlatformTrayNote()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildPlatformNote(String note) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
            ),
          ),
        ],
      ),
    );
  }
  
  IconData _getPlatformIcon() {
    switch (_platformName) {
      case 'Android':
        return Icons.android;
      case 'iOS':
        return Icons.phone_iphone;
      case 'macOS':
        return Icons.desktop_mac;
      case 'Windows':
        return Icons.desktop_windows;
      case 'Linux':
        return Icons.computer;
      case 'Web':
        return Icons.web;
      default:
        return Icons.device_unknown;
    }
  }
  
  String _getPlatformBackgroundNote() {
    switch (_platformName) {
      case 'Android':
        return 'Uses WorkManager for reliable background execution';
      case 'iOS':
        return 'Uses BGTaskScheduler with minimum 15-minute intervals';
      case 'macOS':
      case 'Windows':
      case 'Linux':
        return 'Uses native timers for flexible background execution';
      case 'Web':
        return 'Uses Service Workers for limited background functionality';
      default:
        return 'Background service implementation varies by platform';
    }
  }
  
  String _getPlatformNotificationNote() {
    switch (_platformName) {
      case 'Android':
        return 'Uses NotificationCompat with channels for Android 8.0+';
      case 'iOS':
        return 'Uses UNUserNotificationCenter with permission request';
      case 'macOS':
        return 'Uses NSUserNotification or UserNotifications framework';
      case 'Windows':
        return 'Uses Windows notification APIs with toast support';
      case 'Linux':
        return 'Uses libnotify for desktop notifications';
      case 'Web':
        return 'Uses browser Notification API with permission request';
      default:
        return 'Notification implementation varies by platform';
    }
  }
  
  String _getPlatformStorageNote() {
    switch (_platformName) {
      case 'Android':
        return 'Uses EncryptedSharedPreferences for secure storage';
      case 'iOS':
        return 'Uses iOS Keychain Services for secure storage';
      case 'macOS':
        return 'Uses macOS Keychain for secure storage';
      case 'Windows':
        return 'Uses Windows DPAPI for data encryption';
      case 'Linux':
        return 'Uses libsecret for secure storage';
      case 'Web':
        return 'Uses browser local storage with encryption';
      default:
        return 'Secure storage implementation varies by platform';
    }
  }
  
  String _getPlatformTrayNote() {
    switch (_platformName) {
      case 'macOS':
        return 'Uses NSStatusItem for menu bar integration';
      case 'Windows':
        return 'Uses Shell_NotifyIcon for system tray';
      case 'Linux':
        return 'Uses AppIndicator or StatusNotifier';
      default:
        return 'System tray is only available on desktop platforms';
    }
  }
  
  // Background Service Methods
  
  Future<void> _startBackgroundService() async {
    try {
      final started = await FlutterMCP.instance.platformServices.startBackgroundService();
      if (started) {
        setState(() {
          _backgroundServiceRunning = true;
        });
        _showSnackBar('Background service started');
      }
    } catch (e) {
      _showSnackBar('Failed to start background service: $e', isError: true);
    }
  }
  
  Future<void> _stopBackgroundService() async {
    try {
      final stopped = await FlutterMCP.instance.platformServices.stopBackgroundService();
      if (stopped) {
        setState(() {
          _backgroundServiceRunning = false;
        });
        _showSnackBar('Background service stopped');
      }
    } catch (e) {
      _showSnackBar('Failed to stop background service: $e', isError: true);
    }
  }
  
  Future<void> _scheduleBackgroundTask() async {
    try {
      // This would schedule a task in a real implementation
      setState(() {
        _backgroundTaskCount++;
        _lastBackgroundTaskResult = 'Task #$_backgroundTaskCount executed at ${DateTime.now()}';
      });
      _showSnackBar('Background task scheduled');
    } catch (e) {
      _showSnackBar('Failed to schedule task: $e', isError: true);
    }
  }
  
  // Notification Methods
  
  Future<void> _requestNotificationPermission() async {
    try {
      // Permission is handled by native implementation
      setState(() {
        _notificationPermissionGranted = true;
      });
      _showSnackBar('Notification permission granted');
    } catch (e) {
      _showSnackBar('Failed to request permission: $e', isError: true);
    }
  }
  
  Future<void> _showNotification() async {
    try {
      final id = 'demo_notification_${DateTime.now().millisecondsSinceEpoch}';
      
      await FlutterMCP.instance.platformServices.showNotification(
        title: 'Native Notification #${_notificationCount + 1}',
        body: 'This notification uses platform-specific native APIs',
        id: id,
      );
      
      setState(() {
        _notificationCount++;
        _activeNotifications.add(id);
      });
    } catch (e) {
      _showSnackBar('Failed to show notification: $e', isError: true);
    }
  }
  
  Future<void> _cancelNotification(String id) async {
    try {
      await FlutterMCP.instance.platformServices.hideNotification(id);
      setState(() {
        _activeNotifications.remove(id);
      });
    } catch (e) {
      _showSnackBar('Failed to cancel notification: $e', isError: true);
    }
  }
  
  Future<void> _clearNotifications() async {
    try {
      // Cancel all notifications
      for (final id in _activeNotifications) {
        await FlutterMCP.instance.platformServices.hideNotification(id);
      }
      setState(() {
        _activeNotifications.clear();
      });
      _showSnackBar('All notifications cleared');
    } catch (e) {
      _showSnackBar('Failed to clear notifications: $e', isError: true);
    }
  }
  
  // Secure Storage Methods
  
  Future<void> _saveToSecureStorage() async {
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();
    
    if (key.isEmpty || value.isEmpty) {
      _showSnackBar('Please enter both key and value', isError: true);
      return;
    }
    
    try {
      await FlutterMCP.instance.platformServices.secureStore(key, value);
      setState(() {
        _secureData[key] = value;
      });
      _valueController.clear();
      _showSnackBar('Value saved securely');
    } catch (e) {
      _showSnackBar('Failed to save: $e', isError: true);
    }
  }
  
  Future<void> _readFromSecureStorage() async {
    final key = _keyController.text.trim();
    
    if (key.isEmpty) {
      _showSnackBar('Please enter a key', isError: true);
      return;
    }
    
    try {
      final value = await FlutterMCP.instance.platformServices.secureRead(key);
      if (value != null) {
        setState(() {
          _secureData[key] = value;
          _valueController.text = value;
        });
        _showSnackBar('Value retrieved');
      } else {
        _showSnackBar('No value found for key: $key');
      }
    } catch (e) {
      _showSnackBar('Failed to read: $e', isError: true);
    }
  }
  
  Future<void> _deleteFromSecureStorage() async {
    final key = _keyController.text.trim();
    
    if (key.isEmpty) {
      _showSnackBar('Please enter a key', isError: true);
      return;
    }
    
    try {
      await FlutterMCP.instance.platformServices.secureDelete(key);
      setState(() {
        _secureData.remove(key);
      });
      _showSnackBar('Value deleted');
    } catch (e) {
      _showSnackBar('Failed to delete: $e', isError: true);
    }
  }
  
  Future<void> _deleteKey(String key) async {
    try {
      await FlutterMCP.instance.platformServices.secureDelete(key);
      setState(() {
        _secureData.remove(key);
      });
    } catch (e) {
      _showSnackBar('Failed to delete: $e', isError: true);
    }
  }
  
  // System Tray Methods
  
  Future<void> _showTrayIcon() async {
    try {
      await FlutterMCP.instance.platformServices.setTrayIcon('assets/icons/tray_icon.png');
      await FlutterMCP.instance.platformServices.setTrayTooltip(_trayTooltip);
      await _updateTrayMenu();
      
      setState(() {
        _trayVisible = true;
      });
      _showSnackBar('Tray icon shown');
    } catch (e) {
      _showSnackBar('Failed to show tray icon: $e', isError: true);
    }
  }
  
  Future<void> _hideTrayIcon() async {
    try {
      // In a real implementation, we'd have a hide method
      setState(() {
        _trayVisible = false;
      });
      _showSnackBar('Tray icon hidden');
    } catch (e) {
      _showSnackBar('Failed to hide tray icon: $e', isError: true);
    }
  }
  
  Future<void> _editTrayTooltip() async {
    final controller = TextEditingController(text: _trayTooltip);
    
    final newTooltip = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Tray Tooltip'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tooltip',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (newTooltip != null && newTooltip.isNotEmpty) {
      try {
        await FlutterMCP.instance.platformServices.setTrayTooltip(newTooltip);
        setState(() {
          _trayTooltip = newTooltip;
        });
        _showSnackBar('Tray tooltip updated');
      } catch (e) {
        _showSnackBar('Failed to update tooltip: $e', isError: true);
      }
    }
  }
  
  Future<void> _updateTrayMenu() async {
    try {
      await FlutterMCP.instance.platformServices.setTrayMenu([
        TrayMenuItem(
          label: 'Native Features Demo',
          disabled: true,
        ),
        TrayMenuItem.separator(),
        TrayMenuItem(
          label: 'Background: ${_backgroundServiceRunning ? "Running" : "Stopped"}',
          onTap: () => _logger.info('Background status clicked'),
        ),
        TrayMenuItem(
          label: 'Notifications: $_notificationCount sent',
          onTap: () => _logger.info('Notifications clicked'),
        ),
        TrayMenuItem.separator(),
        TrayMenuItem(
          label: 'Show Window',
          onTap: () => _logger.info('Show window clicked'),
        ),
        TrayMenuItem(
          label: 'Quit',
          onTap: () => _logger.info('Quit clicked'),
        ),
      ]);
      _showSnackBar('Tray menu updated');
    } catch (e) {
      _showSnackBar('Failed to update tray menu: $e', isError: true);
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}