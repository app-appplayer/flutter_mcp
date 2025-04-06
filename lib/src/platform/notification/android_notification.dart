import 'dart:async';
import 'dart:collection';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// Android notification manager implementation
class AndroidNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.android_notification');

  // Store notification data for later retrieval
  final Map<String, Map<String, dynamic>> _notificationData = {};

  // Notification click handlers
  final Map<String, Function(String, Map<String, dynamic>?)> _clickHandlers = {};

  // Active notification IDs
  final Set<String> _activeNotifications = <String>{};

  // Channel configuration
  String _channelId = 'flutter_mcp_channel';
  String _channelName = 'MCP Notifications';
  String _channelDescription = 'Notifications from MCP';

  // Configuration
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  NotificationPriority _defaultPriority = NotificationPriority.high;
  String? _defaultIcon;

  // Last notification ID (for group summaries)
  int _lastNotificationId = 0;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('Android notification manager initializing');

    // Apply configuration if provided
    if (config != null) {
      _channelId = config.channelId ?? _channelId;
      _channelName = config.channelName ?? _channelName;
      _channelDescription = config.channelDescription ?? _channelDescription;
      _soundEnabled = config.enableSound;
      _vibrationEnabled = config.enableVibration;
      _defaultPriority = config.priority;
      _defaultIcon = config.icon;
    }

    // Android notification settings
    final AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings(_defaultIcon ?? 'app_icon');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    try {
      // Initialize the notifications plugin
      final bool? initialized = await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
      );

      if (initialized == true) {
        _logger.debug('Android notification manager initialized successfully');
      } else {
        _logger.warning('Android notification manager initialization returned: $initialized');
      }

      // Create notification channel
      await _createNotificationChannel();
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize Android notification manager', e, stackTrace);
      throw MCPException('Failed to initialize Android notification manager: ${e.toString()}', e, stackTrace);
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
    _logger.debug('Showing Android notification: $title, ID: $id');

    try {
      // Store additional data for later retrieval
      final notificationData = additionalData ?? {};
      _notificationData[id] = notificationData;

      // Configure Android-specific details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: _getImportance(_defaultPriority),
        priority: _getPriority(_defaultPriority),
        icon: icon ?? _defaultIcon,
        enableVibration: _vibrationEnabled,
        enableLights: true,
        playSound: _soundEnabled,
        groupKey: 'mcp_notifications',
        setAsGroupSummary: false,
        channelShowBadge: true,
        autoCancel: false,
      );

      // Platform-specific details
      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      // Generate unique ID by hashing the ID string
      final int notificationId = id.hashCode;

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

      // Update group summary if we have multiple notifications
      if (_activeNotifications.length > 1) {
        await _updateGroupSummary();
      }

      _logger.debug('Android notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to show Android notification', e, stackTrace);
      throw MCPException('Failed to show Android notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding Android notification: $id');

    try {
      // Cancel the notification by its ID hash
      await _notificationsPlugin.cancel(id.hashCode);

      // Remove from active notifications and data store
      _activeNotifications.remove(id);
      _notificationData.remove(id);

      // Update group summary if we still have notifications
      if (_activeNotifications.length > 1) {
        await _updateGroupSummary();
      } else if (_activeNotifications.isEmpty) {
        // Cancel the summary if no more notifications
        await _notificationsPlugin.cancel(0);
      }

      _logger.debug('Android notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to hide Android notification', e, stackTrace);
      throw MCPException('Failed to hide Android notification: ${e.toString()}', e, stackTrace);
    }
  }

  /// Clear all active notifications
  Future<void> clearAllNotifications() async {
    _logger.debug('Clearing all Android notifications');

    try {
      await _notificationsPlugin.cancelAll();
      _activeNotifications.clear();
      _notificationData.clear();

      _logger.debug('All Android notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to clear all Android notifications', e, stackTrace);
      throw MCPException('Failed to clear all Android notifications: ${e.toString()}', e, stackTrace);
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

  /// Create notification channel for Android 8.0+
  Future<void> _createNotificationChannel() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Create high importance channel for normal notifications
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          enableVibration: _vibrationEnabled,
          enableLights: true,
          playSound: _soundEnabled,
        ),
      );

      // Create a low importance channel for summary notifications
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          '${_channelId}_summary',
          '${_channelName} Summary',
          description: 'Summary notifications',
          importance: Importance.low,
        ),
      );
    }
  }

  /// Update the group summary notification
  Future<void> _updateGroupSummary() async {
    if (_activeNotifications.isEmpty) return;

    try {
      // Create summary details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        '${_channelId}_summary',
        '${_channelName} Summary',
        channelDescription: 'Summary notifications',
        importance: Importance.low,
        priority: Priority.low,
        groupKey: 'mcp_notifications',
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          _activeNotifications.map((id) =>
          _notificationData[id]?['title'] as String? ?? 'Notification').toList(),
          contentTitle: '${_activeNotifications.length} notifications',
          summaryText: '${_activeNotifications.length} new messages',
        ),
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      // Show summary notification
      await _notificationsPlugin.show(
        0, // Use ID 0 for summary
        '${_activeNotifications.length} notifications',
        'You have ${_activeNotifications.length} active notifications',
        platformDetails,
      );
    } catch (e) {
      _logger.error('Failed to update notification group summary', e);
    }
  }

  /// Convert priority to Android importance
  Importance _getImportance(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.max:
        return Importance.max;
      case NotificationPriority.high:
        return Importance.high;
      case NotificationPriority.normal:
        return Importance.defaultImportance;
      case NotificationPriority.low:
        return Importance.low;
      case NotificationPriority.min:
        return Importance.min;
      default:
        return Importance.defaultImportance;
    }
  }

  /// Convert priority to Android priority
  Priority _getPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.max:
        return Priority.max;
      case NotificationPriority.high:
        return Priority.high;
      case NotificationPriority.normal:
        return Priority.defaultPriority;
      case NotificationPriority.low:
        return Priority.low;
      case NotificationPriority.min:
        return Priority.min;
      default:
        return Priority.defaultPriority;
    }
  }

  /// Notification response callback
  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    _logger.debug('Android notification tapped: $payload');

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

/// Background notification handler
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  // Background processing can be added here if needed
  // This function needs to be a top-level function
}