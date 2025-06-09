import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// Android notification manager implementation
class AndroidNotificationManager implements NotificationManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');
  
  final Logger _logger = Logger('flutter_mcp.android_notification');
  StreamSubscription? _eventSubscription;

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

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.fine('Android notification manager initializing');

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
        'channelId': _channelId,
        'channelName': _channelName,
        'channelDescription': _channelDescription,
        'enableSound': _soundEnabled,
        'enableVibration': _vibrationEnabled,
        'priority': _defaultPriority.index,
        'icon': _defaultIcon,
      });

      // Request notification permission
      final hasPermission = await _channel.invokeMethod<bool>('requestNotificationPermission');
      if (hasPermission != true) {
        _logger.warning('Notification permission not granted');
      }

      _logger.fine('Android notification manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize Android notification manager', e, stackTrace);
      throw MCPException('Failed to initialize Android notification manager: ${e.toString()}', e, stackTrace);
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
    _logger.fine('Showing Android notification: $title, ID: $id');

    try {
      // Store additional data for later retrieval
      final notificationData = additionalData ?? {};
      notificationData['title'] = title;
      notificationData['body'] = body;
      _notificationData[id] = notificationData;

      // Show notification using native implementation
      await _channel.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'icon': icon ?? _defaultIcon,
        'priority': _defaultPriority.index,
        'enableSound': _soundEnabled,
        'enableVibration': _vibrationEnabled,
        'channelId': _channelId,
        'additionalData': additionalData,
      });

      // Add to active notifications
      _activeNotifications.add(id);

      _logger.fine('Android notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to show Android notification', e, stackTrace);
      throw MCPException('Failed to show Android notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.fine('Hiding Android notification: $id');

    try {
      // Cancel the notification using native implementation
      await _channel.invokeMethod('cancelNotification', {
        'id': id,
      });

      // Remove from active notifications and data store
      _activeNotifications.remove(id);
      _notificationData.remove(id);

      _logger.fine('Android notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to hide Android notification', e, stackTrace);
      throw MCPException('Failed to hide Android notification: ${e.toString()}', e, stackTrace);
    }
  }

  /// Clear all active notifications
  Future<void> clearAllNotifications() async {
    _logger.fine('Clearing all Android notifications');

    try {
      await _channel.invokeMethod('cancelAllNotifications');
      _activeNotifications.clear();
      _notificationData.clear();

      _logger.fine('All Android notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear all Android notifications', e, stackTrace);
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