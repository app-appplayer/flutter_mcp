import 'dart:async';
import 'dart:collection';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// iOS notification manager implementation
class IOSNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.ios_notification');

  // Store notification data for later retrieval
  final Map<String, Map<String, dynamic>> _notificationData = {};

  // Notification click handlers
  final Map<String, Function(String, Map<String, dynamic>?)> _clickHandlers = {
  };

  // Active notifications queue (since iOS doesn't have a notification center API)
  final Queue<String> _activeNotifications = Queue<String>();

  // Maximum concurrent notifications (iOS has a limit)
  final int _maxConcurrentNotifications = 64;

  // Configuration
  bool _soundEnabled = true;
  final bool _badgesEnabled = true;
  NotificationPriority _defaultPriority = NotificationPriority.high;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('iOS notification manager initializing');

    // Apply configuration if provided
    if (config != null) {
      _soundEnabled = config.enableSound;
      _defaultPriority = config.priority;
    }

    // iOS notification settings
    final DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: _soundEnabled,
      requestBadgePermission: _badgesEnabled,
      requestAlertPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: _soundEnabled,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );

    try {
      final bool? initialized = await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      if (initialized == true) {
        _logger.debug('iOS notification manager initialized successfully');
      } else {
        _logger.warning(
            'iOS notification manager initialization returned: $initialized');
      }

      // Request permissions
      await _requestPermissions();
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to initialize iOS notification manager', e, stackTrace);
      throw MCPException(
          'Failed to initialize iOS notification manager: ${e.toString()}', e,
          stackTrace);
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
    _logger.debug('Showing iOS notification: $title, ID: $id');

    try {
      // Store additional data for later retrieval
      final notificationData = additionalData ?? {};
      _notificationData[id] = notificationData;

      // Configure iOS-specific details
      final DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: _badgesEnabled,
        presentSound: _soundEnabled,
        sound: _soundEnabled ? 'default' : null,
        badgeNumber: _getNextBadgeNumber(),
        threadIdentifier: id,
        // Group notifications with the same ID
        categoryIdentifier: 'mcp_category',
        subtitle: notificationData['subtitle'] as String?,
        interruptionLevel: _getInterruptionLevel(_defaultPriority),
      );

      // Platform-specific details
      final NotificationDetails platformDetails = NotificationDetails(
        iOS: iOSDetails,
      );

      // Generate unique ID by hashing the ID string
      final int notificationId = id.hashCode;

      // Check if we need to manage the queue
      _manageConcurrentNotifications(id);

      // Show the notification
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        platformDetails,
        payload: id,
      );

      // Add to active notifications
      _activeNotifications.add(id);

      _logger.debug('iOS notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to show iOS notification', e, stackTrace);
      throw MCPException(
          'Failed to show iOS notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding iOS notification: $id');

    try {
      // Cancel the notification by its ID hash
      await _notificationsPlugin.cancel(id.hashCode);

      // Remove from active notifications and data store
      _activeNotifications.remove(id);
      _notificationData.remove(id);

      _logger.debug('iOS notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to hide iOS notification', e, stackTrace);
      throw MCPException(
          'Failed to hide iOS notification: ${e.toString()}', e, stackTrace);
    }
  }

  /// Clear all active notifications
  Future<void> clearAllNotifications() async {
    _logger.debug('Clearing all iOS notifications');

    try {
      await _notificationsPlugin.cancelAll();
      _activeNotifications.clear();
      _notificationData.clear();

      // Reset badge count
      await _resetBadgeCount();

      _logger.debug('All iOS notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to clear all iOS notifications', e, stackTrace);
      throw MCPException(
          'Failed to clear all iOS notifications: ${e.toString()}', e,
          stackTrace);
    }
  }

  /// Register a notification click handler
  void registerClickHandler(String id,
      Function(String, Map<String, dynamic>?) handler) {
    _clickHandlers[id] = handler;
  }

  /// Unregister a notification click handler
  void unregisterClickHandler(String id) {
    _clickHandlers.remove(id);
  }

  /// Request notification permissions from the user
  Future<bool> _requestPermissions() async {
    _logger.debug('Requesting iOS notification permissions');

    try {
      final IOSFlutterLocalNotificationsPlugin? iOSPlugin =
      _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin != null) {
        final bool? result = await iOSPlugin.requestPermissions(
          alert: true,
          badge: _badgesEnabled,
          sound: _soundEnabled,
          critical: _defaultPriority == NotificationPriority.high ||
              _defaultPriority == NotificationPriority.max,
        );

        return result ?? false;
      }

      return false;
    } catch (e) {
      _logger.error('Failed to request iOS notification permissions', e);
      return false;
    }
  }

  /// Reset badge count
  Future<void> _resetBadgeCount() async {
    try {
      final IOSFlutterLocalNotificationsPlugin? iOSPlugin =
      _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin != null) {
        await iOSPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      _logger.error('Failed to reset badge count', e);
    }
  }

  /// Get next badge number (incrementing for each notification)
  int _getNextBadgeNumber() {
    return _activeNotifications.length + 1;
  }

  /// Manage concurrent notifications (iOS has a limit)
  void _manageConcurrentNotifications(String newId) {
    // If we're at the limit, remove the oldest notification
    if (_activeNotifications.length >= _maxConcurrentNotifications) {
      final oldestId = _activeNotifications.removeFirst();
      _notificationsPlugin.cancel(oldestId.hashCode);
      _notificationData.remove(oldestId);

      _logger.debug(
          'Removed oldest notification to stay within limit: $oldestId');
    }
  }

  /// Convert priority to iOS interruption level
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

  /// Legacy iOS notification callback (for iOS <10)
  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    _logger.debug('iOS notification tapped: $payload');

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