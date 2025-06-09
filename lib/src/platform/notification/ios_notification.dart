import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// iOS notification manager implementation
class IOSNotificationManager implements NotificationManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');
  
  final Logger _logger = Logger('flutter_mcp.ios_notification');
  StreamSubscription? _eventSubscription;

  // Store notification data for later retrieval
  final Map<String, Map<String, dynamic>> _notificationData = {};

  // Notification click handlers
  final Map<String, Function(String, Map<String, dynamic>?)> _clickHandlers = {};

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
    _logger.fine('iOS notification manager initializing');

    // Apply configuration if provided
    if (config != null) {
      _soundEnabled = config.enableSound;
      _defaultPriority = config.priority;
    }

    // Initialize event listener for notification responses
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        _logger.severe('Event channel error', error);
      },
    );

    try {
      // Initialize native notification system
      await _channel.invokeMethod('configureNotifications', {
        'enableSound': _soundEnabled,
        'enableBadges': _badgesEnabled,
        'priority': _defaultPriority.index,
      });

      // Request notification permission
      final hasPermission = await _channel.invokeMethod<bool>('requestNotificationPermission');
      if (hasPermission != true) {
        _logger.warning('Notification permission not granted');
      } else {
        _logger.fine('iOS notification permissions granted');
      }

      _logger.fine('iOS notification manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize iOS notification manager', e, stackTrace);
      throw MCPException('Failed to initialize iOS notification manager: ${e.toString()}', e, stackTrace);
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};
    
    _logger.fine('Received notification event: $type');
    
    if (type == 'notificationEvent') {
      final action = data['action'] as String?;
      final notificationId = data['notificationId'] as String?;
      
      if (action == 'click' && notificationId != null) {
        _handleNotificationTap(notificationId);
      } else if (action == 'dismiss' && notificationId != null) {
        _activeNotifications.remove(notificationId);
        _notificationData.remove(notificationId);
      }
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
    _logger.fine('Showing iOS notification: $title, ID: $id');

    try {
      // Store additional data for later retrieval
      final notificationData = additionalData ?? {};
      notificationData['title'] = title;
      notificationData['body'] = body;
      _notificationData[id] = notificationData;

      // Check if we need to manage the queue
      _manageConcurrentNotifications(id);

      // Show notification using native implementation
      await _channel.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'subtitle': notificationData['subtitle'] as String?,
        'priority': _defaultPriority.index,
        'enableSound': _soundEnabled,
        'enableBadges': _badgesEnabled,
        'badgeNumber': _getNextBadgeNumber(),
        'threadIdentifier': id,
        'categoryIdentifier': 'mcp_category',
        'additionalData': additionalData,
      });

      // Add to active notifications
      _activeNotifications.add(id);

      _logger.fine('iOS notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to show iOS notification', e, stackTrace);
      throw MCPException('Failed to show iOS notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.fine('Hiding iOS notification: $id');

    try {
      // Cancel the notification using native implementation
      await _channel.invokeMethod('cancelNotification', {
        'id': id,
      });

      // Remove from active notifications and data store
      _activeNotifications.remove(id);
      _notificationData.remove(id);

      _logger.fine('iOS notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to hide iOS notification', e, stackTrace);
      throw MCPException('Failed to hide iOS notification: ${e.toString()}', e, stackTrace);
    }
  }

  /// Clear all active notifications
  Future<void> clearAllNotifications() async {
    _logger.fine('Clearing all iOS notifications');

    try {
      await _channel.invokeMethod('cancelAllNotifications');
      _activeNotifications.clear();
      _notificationData.clear();

      // Reset badge count
      await _resetBadgeCount();

      _logger.fine('All iOS notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear all iOS notifications', e, stackTrace);
      throw MCPException('Failed to clear all iOS notifications: ${e.toString()}', e, stackTrace);
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

  /// Reset badge count
  Future<void> _resetBadgeCount() async {
    try {
      // Badge count is automatically reset when all notifications are cleared
      _logger.fine('Badge count reset');
    } catch (e) {
      _logger.severe('Failed to reset badge count', e);
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
      
      // Cancel the oldest notification
      _channel.invokeMethod('cancelNotification', {
        'id': oldestId,
      });
      
      _notificationData.remove(oldestId);

      _logger.fine('Removed oldest notification to stay within limit: $oldestId');
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

  /// Get active notification count
  int get activeNotificationCount => _activeNotifications.length;

  /// Check if a notification is active
  bool isNotificationActive(String id) => _activeNotifications.contains(id);

  void dispose() {
    _eventSubscription?.cancel();
    _clickHandlers.clear();
    _notificationData.clear();
    _activeNotifications.clear();
  }
}