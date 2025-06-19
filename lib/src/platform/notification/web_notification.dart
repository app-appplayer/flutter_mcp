import 'dart:async';
import 'package:universal_html/html.dart';
import 'package:universal_html/js_util.dart';

import '../../config/notification_config.dart' hide NotificationPriority;
import '../../utils/logger.dart';
import 'notification_manager.dart';
import 'notification_models.dart';
import '../../utils/exceptions.dart';

/// Web notification manager implementation using modern Web APIs
class WebNotificationManager implements NotificationManager {
  final Logger _logger = Logger('flutter_mcp.web_notification');
  bool _permissionGranted = false;

  /// Map of active notifications
  final Map<String, Notification> _activeNotifications = {};

  /// Notification click handlers
  final Map<String, Function(String id, Map<String, dynamic>? data)>
      _clickHandlers = {};

  /// Default notification icon
  String? _defaultIcon;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.fine('Initializing web notification manager');

    // Check if browser supports notifications
    if (!_isSupported()) {
      _logger.warning('Web notifications are not supported in this browser');
      return;
    }

    // Set default icon if provided
    if (config != null && config.icon != null) {
      _defaultIcon = config.icon;
    }

    // Check permission status
    final permission = Notification.permission;

    if (permission == 'granted') {
      _permissionGranted = true;
      _logger.fine('Notification permission already granted');
    } else if (permission == 'denied') {
      _permissionGranted = false;
      _logger.warning('Notification permission denied');
    } else {
      // Will need to request permission when showing notification
      _logger.fine('Notification permission not determined yet');
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
    Map<String, dynamic>? data,
    List<NotificationAction>? actions,
    String? channelId,
    NotificationPriority priority = NotificationPriority.normal,
    bool showProgress = false,
    int? progress,
    int? maxProgress,
    String? group,
    String? image,
    bool ongoing = false,
  }) async {
    _logger.fine('Showing web notification: $title');

    if (!_isSupported()) {
      _logger.warning('Web notifications are not supported');
      throw MCPPlatformNotSupportedException('Web Notifications');
    }

    // Request permission if not granted yet
    if (!_permissionGranted) {
      _logger.fine('Requesting notification permission');

      final permission = await Notification.requestPermission();
      _permissionGranted = permission == 'granted';

      if (!_permissionGranted) {
        _logger.warning('Notification permission not granted');
        throw MCPException('Notification permission denied by user');
      }
    }

    // Close existing notification with same ID
    await hideNotification(id);

    // Create notification options
    final options = <String, dynamic>{
      'body': body,
      'tag': id,
      'requireInteraction': true,
    };

    // Set icon (use default if not provided)
    if (icon != null) {
      options['icon'] = icon;
    } else if (_defaultIcon != null) {
      options['icon'] = _defaultIcon!;
    }

    try {
      // Create and display the notification
      final notification = Notification(
        title,
        body: options['body'] as String?,
        tag: options['tag'] as String?,
        icon: options['icon'] as String?,
      );
      _activeNotifications[id] = notification;

      // Set up click handler
      notification.onClick.listen((_) {
        _logger.fine('Notification clicked: $id');
        _handleNotificationTap(id);
      });

      // Return immediately as the notification has been displayed
      return;
    } catch (e, stackTrace) {
      _logger.severe('Failed to show web notification', e, stackTrace);
      throw MCPException(
          'Failed to show web notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.fine('Hiding web notification: $id');

    if (_activeNotifications.containsKey(id)) {
      try {
        _activeNotifications[id]!.close();
        _activeNotifications.remove(id);
      } catch (e, stackTrace) {
        _logger.severe('Failed to hide web notification', e, stackTrace);
        throw MCPException(
            'Failed to hide web notification: ${e.toString()}', e, stackTrace);
      }
    }
  }

  /// Register a notification click handler
  void registerClickHandler(
      String id, Function(String id, Map<String, dynamic>? data) handler) {
    _clickHandlers[id] = handler;
  }

  /// Unregister a notification click handler
  void unregisterClickHandler(String id) {
    _clickHandlers.remove(id);
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    _logger.fine('Clearing all web notifications');

    for (final id in _activeNotifications.keys.toList()) {
      await hideNotification(id);
    }
  }

  /// Request notification permission explicitly
  @override
  Future<bool> requestPermission() async {
    if (!_isSupported()) {
      return false;
    }

    _logger.fine('Explicitly requesting notification permission');
    final permission = await Notification.requestPermission();
    _permissionGranted = permission == 'granted';

    return _permissionGranted;
  }

  /// Check if notifications are supported
  bool _isSupported() {
    try {
      return hasProperty(window, 'Notification');
    } catch (e) {
      return false;
    }
  }

  /// Handle notification click
  void _handleNotificationTap(String id) {
    // Get the stored data for this notification
    final data = _activeNotifications[id];

    // Try focusing the window when notification is clicked
    try {
      callMethod(window, 'focus', []);
    } catch (e) {
      _logger.warning('Window focus failed: $e');
    }

    // Find specific handler for this ID
    if (_clickHandlers.containsKey(id)) {
      _clickHandlers[id]!(id, _convertNotificationToMap(data));
      return;
    }

    // Find default handler
    if (_clickHandlers.containsKey('default')) {
      _clickHandlers['default']!(id, _convertNotificationToMap(data));
    }
  }

  /// Convert Notification to a map for easier data handling
  Map<String, dynamic>? _convertNotificationToMap(Notification? notification) {
    if (notification == null) return null;

    return {
      'title': notification.title,
      'body': notification.body,
      'tag': notification.tag,
    };
  }

  /// Check if notification permission is granted
  bool get isPermissionGranted => _permissionGranted;

  @override
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  }) async {
    // Web notifications don't support updates, so we'll recreate
    if (_activeNotifications.containsKey(id)) {
      final oldNotification = _activeNotifications[id]!;
      await hideNotification(id);
      await showNotification(
        id: id,
        title: title ?? oldNotification.title ?? '',
        body: body ?? oldNotification.body ?? '',
        icon: oldNotification.icon,
        data: data,
        progress: progress,
      );
    }
  }

  @override
  Future<void> cancelNotification(String id) async {
    return hideNotification(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    return clearAll();
  }

  @override
  List<NotificationInfo> getActiveNotifications() {
    return _activeNotifications.entries.map((entry) {
      final notification = entry.value;
      return NotificationInfo(
        id: entry.key,
        title: notification.title ?? '',
        body: notification.body ?? '',
        shownAt: DateTime.now(), // Web API doesn't provide creation time
        data: _convertNotificationToMap(notification) ?? {},
      );
    }).toList();
  }

  @override
  Future<void> dispose() async {
    await clearAll();
    _clickHandlers.clear();
  }
}
