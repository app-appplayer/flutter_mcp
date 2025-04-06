import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// Desktop notification manager implementation for macOS, Windows, and Linux
class DesktopNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.desktop_notification');

  final String _platformName;

  // Notification data storage
  final Map<String, Map<String, dynamic>> _notificationData = {};

  // Notification click handlers
  final Map<String, Function(String, Map<String, dynamic>?)> _clickHandlers = {};

  // Configuration
  NotificationPriority _defaultPriority = NotificationPriority.normal;
  String? _defaultIcon;
  bool _soundEnabled = true;

  DesktopNotificationManager() : _platformName = Platform.isMacOS
      ? 'macOS'
      : Platform.isWindows
      ? 'Windows'
      : 'Linux';

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('$_platformName notification manager initializing');

    // Apply configuration if provided
    if (config != null) {
      _soundEnabled = config.enableSound;
      _defaultPriority = config.priority;
      _defaultIcon = config.icon;
    }

    try {
      // Set up platform-specific settings
      final InitializationSettings initSettings = InitializationSettings(
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: _soundEnabled,
          defaultPresentAlert: true,
          defaultPresentBadge: true,
          defaultPresentSound: _soundEnabled,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open',
          defaultIcon: _defaultIcon != null
              ? AssetsLinuxIcon(_defaultIcon!)
              : null,
        ),
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      _logger.debug('$_platformName notification manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize $_platformName notification manager',
          e, stackTrace);
      throw MCPException('Failed to initialize $_platformName notification manager: ${e.toString()}',
          e, stackTrace);
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
    Map<String, dynamic>? additionalData,
  }) async {
    _logger.debug('Showing $_platformName notification: $title');

    try {
      // Store notification data
      final notificationData = additionalData ?? {};
      _notificationData[id] = notificationData;

      // Platform specific details
      final NotificationDetails details = _createPlatformSpecificDetails(
        title: title,
        body: body,
        icon: icon,
        id: id,
      );

      // Generate unique ID by hashing the ID string
      final int notificationId = id.hashCode;

      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: id,
      );

      _logger.debug('$_platformName notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to show $_platformName notification', e, stackTrace);
      throw MCPException('Failed to show $_platformName notification: ${e.toString()}',
          e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding $_platformName notification: $id');

    try {
      await _notificationsPlugin.cancel(id.hashCode);
      _notificationData.remove(id);

      _logger.debug('$_platformName notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to hide $_platformName notification', e, stackTrace);
      throw MCPException('Failed to hide $_platformName notification: ${e.toString()}',
          e, stackTrace);
    }
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    _logger.debug('Clearing all $_platformName notifications');

    try {
      await _notificationsPlugin.cancelAll();
      _notificationData.clear();

      _logger.debug('All $_platformName notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to clear all $_platformName notifications', e, stackTrace);
      throw MCPException('Failed to clear all $_platformName notifications: ${e.toString()}',
          e, stackTrace);
    }
  }

  /// Register a notification click handler
  void registerClickHandler(String id, Function(String, Map<String, dynamic>?) handler) {
    _clickHandlers[id] = handler;
  }

  /// Unregister a notification click handler
  void unregisterClickHandler(String id) {
    _clickHandlers.remove(id);
  }

  /// Create platform-specific notification details
  NotificationDetails _createPlatformSpecificDetails({
    required String title,
    required String body,
    String? icon,
    required String id,
  }) {
    if (Platform.isMacOS) {
      return NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: _soundEnabled,
          sound: _soundEnabled ? 'default' : null,
          subtitle: _notificationData[id]?['subtitle'] as String?,
          interruptionLevel: _getInterruptionLevel(_defaultPriority),
          threadIdentifier: id,
        ),
      );
    } else if (Platform.isLinux) {
      return NotificationDetails(
        linux: LinuxNotificationDetails(
          icon: icon != null
              ? AssetsLinuxIcon(icon)
              : _defaultIcon != null
              ? AssetsLinuxIcon(_defaultIcon!)
              : null,
          actions: [
            LinuxNotificationAction(
              key: 'open',
              label: 'Open',
            ),
          ],
          urgency: _getLinuxUrgency(_defaultPriority),
        ),
      );
    } else {
      // Windows - currently flutter_local_notifications doesn't have specific Windows settings
      // Using generic notification details
      return const NotificationDetails();
    }
  }

  /// Convert priority to macOS interruption level
  InterruptionLevel _getInterruptionLevel(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.max:
        return InterruptionLevel.timeSensitive;
      case NotificationPriority.high:
        return InterruptionLevel.timeSensitive;
      case NotificationPriority.normal:
        return InterruptionLevel.active;
      case NotificationPriority.low:
        return InterruptionLevel.passive;
      case NotificationPriority.min:
        return InterruptionLevel.passive;

    }
  }

  /// Convert priority to Linux urgency
  LinuxNotificationUrgency _getLinuxUrgency(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.max:
      case NotificationPriority.high:
        return LinuxNotificationUrgency.critical;
      case NotificationPriority.normal:
        return LinuxNotificationUrgency.normal;
      case NotificationPriority.low:
      case NotificationPriority.min:
        return LinuxNotificationUrgency.low;
    }
  }


  /// Notification response callback
  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    _logger.debug('$_platformName notification tapped: $payload');

    if (payload != null) {
      _handleNotificationTap(payload);
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(String id) {
    // Get the stored data for this notification
    final data = _notificationData[id];

    // Find specific handler for this ID
    if (_clickHandlers.containsKey(id)) {
      _clickHandlers[id]!(id, data);
      return;
    }

    // Find default handler
    if (_clickHandlers.containsKey('default')) {
      _clickHandlers['default']!(id, data);
    }
  }
}