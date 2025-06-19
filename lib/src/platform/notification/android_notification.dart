import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart' hide NotificationPriority;
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import 'notification_manager.dart';
import 'notification_models.dart';

/// Android notification manager implementation
class AndroidNotificationManager implements NotificationManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');

  final Logger _logger = Logger('flutter_mcp.android_notification');
  StreamSubscription? _eventSubscription;

  // Store notification data for later retrieval
  final Map<String, Map<String, dynamic>> _notificationData = {};

  // Notification click handlers
  final Map<String, Function(String, Map<String, dynamic>?)> _clickHandlers =
      {};

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
      // Convert from config NotificationPriority to models NotificationPriority
      _defaultPriority = NotificationPriority.values[config.priority.index];
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
      final hasPermission =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      if (hasPermission != true) {
        _logger.warning('Notification permission not granted');
      }

      _logger.fine('Android notification manager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to initialize Android notification manager', e, stackTrace);
      throw MCPException(
          'Failed to initialize Android notification manager: ${e.toString()}',
          e,
          stackTrace);
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
    _logger.fine('Showing Android notification: $title, ID: $id');

    try {
      // Store additional data for later retrieval
      final notificationData = data ?? {};
      notificationData['title'] = title;
      notificationData['body'] = body;
      _notificationData[id] = notificationData;

      // Show notification using native implementation
      await _channel.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'icon': icon ?? _defaultIcon,
        'priority': priority.index,
        'enableSound': _soundEnabled,
        'enableVibration': _vibrationEnabled,
        'channelId': channelId ?? _channelId,
        'data': data,
        'actions': actions?.map((a) => a.toMap()).toList(),
        'showProgress': showProgress,
        'progress': progress,
        'maxProgress': maxProgress,
        'group': group,
        'image': image,
        'ongoing': ongoing,
      });

      // Add to active notifications
      _activeNotifications.add(id);

      _logger.fine('Android notification shown successfully: $id');
    } catch (e, stackTrace) {
      _logger.severe('Failed to show Android notification', e, stackTrace);
      throw MCPException('Failed to show Android notification: ${e.toString()}',
          e, stackTrace);
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
      throw MCPException('Failed to hide Android notification: ${e.toString()}',
          e, stackTrace);
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
      _logger.severe(
          'Failed to clear all Android notifications', e, stackTrace);
      throw MCPException(
          'Failed to clear all Android notifications: ${e.toString()}',
          e,
          stackTrace);
    }
  }

  /// Register a notification click handler
  void registerClickHandler(
      String id, Function(String, Map<String, dynamic>?) handler) {
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

  @override
  Future<void> dispose() async {
    _eventSubscription?.cancel();
    _clickHandlers.clear();
    _notificationData.clear();
    _activeNotifications.clear();
  }

  @override
  Future<bool> requestPermission() async {
    // Android doesn't need explicit permission for notifications
    // (unless targeting Android 13+)
    if (Platform.isAndroid) {
      final sdkInt = await _channel.invokeMethod<int>('getAndroidSdkVersion');
      if (sdkInt != null && sdkInt >= 33) {
        // Android 13+ requires permission
        final granted =
            await _channel.invokeMethod<bool>('requestNotificationPermission');
        return granted ?? false;
      }
    }
    return true;
  }

  @override
  Future<void> cancelNotification(String id) async {
    await hideNotification(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _channel.invokeMethod('cancelAllNotifications');
      _activeNotifications.clear();
      _notificationData.clear();
    } catch (e) {
      _logger.severe('Failed to cancel all notifications', e);
    }
  }

  @override
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  }) async {
    if (!_activeNotifications.contains(id)) {
      return;
    }

    try {
      await _channel.invokeMethod('updateNotification', {
        'id': id,
        'title': title,
        'body': body,
        'progress': progress,
        'data': data,
      });
    } catch (e) {
      _logger.severe('Failed to update notification', e);
    }
  }

  @override
  List<NotificationInfo> getActiveNotifications() {
    return _activeNotifications.map((id) {
      final data = _notificationData[id] ?? {};
      return NotificationInfo(
        id: id,
        title: data['title'] ?? '',
        body: data['body'] ?? '',
        shownAt: DateTime.now(), // We should track this properly
        data: data,
      );
    }).toList();
  }
}
