import 'dart:async';
import 'dart:html' as html;
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../notification/notification_manager.dart';

/// Web notification manager implementation
class WebNotificationManager implements NotificationManager {
  final MCPLogger _logger = MCPLogger('mcp.web_notification');
  bool _permissionGranted = false;

  /// Map of active notifications
  final Map<String, html.Notification> _activeNotifications = {};

  /// Notification click handler
  Function(String id)? _onNotificationClick;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('Initializing web notification manager');

    // Check if browser supports notifications
    if (!_isSupported()) {
      _logger.warning('Web notifications are not supported in this browser');
      return;
    }

    // Check permission status
    final permission = html.Notification.permission;

    if (permission == 'granted') {
      _permissionGranted = true;
      _logger.debug('Notification permission already granted');
    } else if (permission == 'denied') {
      _permissionGranted = false;
      _logger.warning('Notification permission denied');
    } else {
      // Will need to request permission when showing notification
      _logger.debug('Notification permission not determined yet');
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('Showing web notification: $title');

    if (!_isSupported()) {
      _logger.warning('Web notifications are not supported');
      return;
    }

    // Request permission if not granted yet
    if (!_permissionGranted) {
      _logger.debug('Requesting notification permission');

      final permission = await html.Notification.requestPermission();
      _permissionGranted = permission == 'granted';

      if (!_permissionGranted) {
        _logger.warning('Notification permission not granted');
        return;
      }
    }

    // Close existing notification with same ID
    await hideNotification(id);

    // Create notification options
    final Map<String, dynamic> options = {
      'body': body,
      'tag': id,
    };

    if (icon != null) {
      options['icon'] = icon;
    }

    // Create and display the notification
    try {
      // Use the correct constructor based on the updated API
      final notification = html.Notification(
          title,
          body: options['body'],
          tag: options['tag'],
          icon: options['icon']
      );
      _activeNotifications[id] = notification;

      // Set up click handler
      notification.onClick.listen((_) {
        _logger.debug('Notification clicked: $id');
        if (_onNotificationClick != null) {
          _onNotificationClick!(id);
        }
      });

      // Auto-close after 5 seconds (browsers may handle this differently)
      Timer(const Duration(seconds: 5), () {
        hideNotification(id);
      });
    } catch (e) {
      _logger.error('Failed to show web notification', e);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('Hiding web notification: $id');

    if (_activeNotifications.containsKey(id)) {
      try {
        _activeNotifications[id]!.close();
        _activeNotifications.remove(id);
      } catch (e) {
        _logger.error('Failed to hide web notification', e);
      }
    }
  }

  /// Set notification click handler
  void setClickHandler(Function(String id) handler) {
    _onNotificationClick = handler;
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    _logger.debug('Clearing all web notifications');

    for (final id in _activeNotifications.keys.toList()) {
      await hideNotification(id);
    }
  }

  /// Request notification permission explicitly
  Future<bool> requestPermission() async {
    if (!_isSupported()) {
      return false;
    }

    _logger.debug('Explicitly requesting notification permission');
    final permission = await html.Notification.requestPermission();
    _permissionGranted = permission == 'granted';

    return _permissionGranted;
  }

  /// Check if notifications are supported
  bool _isSupported() {
    return html.Notification.supported;
  }

  /// Check if notification permission is granted
  bool get isPermissionGranted => _permissionGranted;
}