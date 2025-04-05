import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// Desktop notification manager implementation for macOS, Windows, and Linux
class DesktopNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.desktop_notification');

  final String _platformName;

  DesktopNotificationManager() : _platformName = Platform.isMacOS
      ? 'macOS'
      : Platform.isWindows
      ? 'Windows'
      : 'Linux';

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('$_platformName notification manager initializing');

    try {
      // Set up platform-specific settings
      final InitializationSettings initSettings = InitializationSettings(
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: config?.enableSound ?? true,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open',
          defaultIcon: config?.icon != null
              ? AssetsLinuxIcon(config!.icon!)
              : null,
        ),
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      _logger.debug('$_platformName notification manager initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize $_platformName notification manager',
          e, stackTrace);
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('Showing $_platformName notification: $title');

    try {
      // Platform specific details
      final NotificationDetails details = NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: 'MCP Notification',
        ),
        linux: LinuxNotificationDetails(
          icon: icon != null ? AssetsLinuxIcon(icon) : null,
          actions: [
            LinuxNotificationAction(
              key: 'open',
              label: 'Open',
            ),
          ],
        ),
      );

      await _notificationsPlugin.show(
        id.hashCode, // Use hash code for ID
        title,
        body,
        details,
        payload: id,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to show $_platformName notification', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding $_platformName notification: $id');

    try {
      await _notificationsPlugin.cancel(id.hashCode);
    } catch (e, stackTrace) {
      _logger.error('Failed to hide $_platformName notification', e, stackTrace);
    }
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('Notification tapped: ${response.payload}');

    // Handle notification tap event
    // This could be expanded to include a callback system
  }
}