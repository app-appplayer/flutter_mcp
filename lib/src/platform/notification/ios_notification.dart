import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// iOS notification manager implementation
class IOSNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.ios_notification');

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('iOS notification manager initialization');

    // iOS notification settings
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request iOS permissions
    await _requestPermissions();
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('Showing iOS notification: $title');

    // iOS notification settings
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    NotificationDetails platformChannelSpecifics =
    const NotificationDetails(iOS: iOSPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
      payload: id,
    );
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding iOS notification: $id');

    await _notificationsPlugin.cancel(0);
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    _logger.debug('Requesting iOS notification permissions');

    final iOS = _notificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

    if (iOS != null) {
      await iOS.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Notification tap handler
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('Notification tapped: ${response.payload}');

    // Handle notification tap event
  }
}