import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';

/// Desktop notification manager implementation for macOS, Windows, and Linux
class DesktopNotificationManager implements NotificationManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');
  
  final Logger _logger = Logger('flutter_mcp.desktop_notification');
  StreamSubscription? _eventSubscription;

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
    _logger.fine('$_platformName notification manager initializing');

    // Apply configuration if provided
    if (config != null) {
      _soundEnabled = config.enableSound;
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
        'enableSound': _soundEnabled,
        'priority': _defaultPriority.index,
        'icon': _defaultIcon,
      });

      _logger.fine('$_platformName notification manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize $_platformName notification manager', e, stackTrace);
      throw MCPException('Failed to initialize $_platformName notification manager: ${e.toString()}', e, stackTrace);
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
    _logger.fine('Showing $_platformName notification: $title');

    try {
      // Store notification data
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
        'subtitle': notificationData['subtitle'] as String?,
        'additionalData': additionalData,
      });

      _logger.fine('$_platformName notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to show $_platformName notification', e, stackTrace);
      throw MCPException('Failed to show $_platformName notification: ${e.toString()}', e, stackTrace);
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.fine('Hiding $_platformName notification: $id');

    try {
      await _channel.invokeMethod('cancelNotification', {
        'id': id,
      });
      _notificationData.remove(id);

      _logger.fine('$_platformName notification hidden successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to hide $_platformName notification', e, stackTrace);
      throw MCPException('Failed to hide $_platformName notification: ${e.toString()}', e, stackTrace);
    }
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    _logger.fine('Clearing all $_platformName notifications');

    try {
      await _channel.invokeMethod('cancelAllNotifications');
      _notificationData.clear();

      _logger.fine('All $_platformName notifications cleared successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear all $_platformName notifications', e, stackTrace);
      throw MCPException('Failed to clear all $_platformName notifications: ${e.toString()}', e, stackTrace);
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
  int get activeNotificationCount => _notificationData.length;

  /// Check if a notification is active
  bool isNotificationActive(String id) => _notificationData.containsKey(id);

  void dispose() {
    _eventSubscription?.cancel();
    _clickHandlers.clear();
    _notificationData.clear();
  }
}