import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart' hide NotificationPriority;
import '../../utils/logger.dart';
import '../../events/event_system.dart';
import 'notification_manager.dart';
import 'notification_models.dart';

/// Platform-specific notification manager implementation
class PlatformNotificationManager implements NotificationManager {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');

  final Logger _logger = Logger('flutter_mcp.platform_notification');
  NotificationConfig? _config;
  bool _initialized = false;

  // Track shown notifications
  final Map<String, NotificationInfo> _activeNotifications = {};

  // Platform capabilities
  bool _supportsActions = false;
  bool _supportsImages = false;
  bool _supportsProgress = false;
  bool _supportsGrouping = false;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    if (_initialized) {
      _logger.fine('Notification manager already initialized');
      return;
    }

    _logger.fine('Initializing platform notification manager');
    _config = config ?? NotificationConfig.defaultConfig();

    try {
      // Configure native notification system
      await _channel.invokeMethod(
        'configureNotifications',
        _config!.toMap(),
      );

      // Check platform capabilities
      await _checkCapabilities();

      // Set up event listener for notification interactions
      _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            _handleNotificationEvent(Map<String, dynamic>.from(event));
          }
        },
        onError: (error) {
          _logger.severe('Notification event channel error', error);
        },
      );

      // Request permission if needed
      if (_config!.requestPermissionOnInit) {
        await requestPermission();
      }

      _initialized = true;
      _logger.info('Platform notification manager initialized');

      // Publish initialization event
      EventSystem.instance.publishTopic('notification.initialized', {
        'platform': _getPlatformName(),
        'capabilities': {
          'actions': _supportsActions,
          'images': _supportsImages,
          'progress': _supportsProgress,
          'grouping': _supportsGrouping,
        },
      });
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to initialize notification manager', e, stackTrace);
      throw Exception('Failed to initialize notifications: $e');
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
    if (!_initialized) {
      throw StateError('Notification manager not initialized');
    }

    _logger.fine('Showing notification: $id');

    try {
      // Prepare notification data
      final notificationData = {
        'id': id,
        'title': title,
        'body': body,
        'icon': icon ?? _config?.defaultIcon,
        'channelId': channelId ?? _config?.channelId ?? 'default',
        'priority': priority.index,
        'data': data ?? {},
        'ongoing': ongoing,
      };

      // Add optional features based on platform capabilities
      if (_supportsActions && actions != null && actions.isNotEmpty) {
        notificationData['actions'] = actions.map((a) => a.toMap()).toList();
      }

      if (_supportsImages && image != null) {
        notificationData['image'] = image;
      }

      if (_supportsProgress && showProgress) {
        notificationData['showProgress'] = true;
        if (progress != null) notificationData['progress'] = progress;
        if (maxProgress != null) notificationData['maxProgress'] = maxProgress;
      }

      if (_supportsGrouping && group != null) {
        notificationData['group'] = group;
      }

      // Show notification via platform channel
      await _channel.invokeMethod('showNotification', notificationData);

      // Track active notification
      _activeNotifications[id] = NotificationInfo(
        id: id,
        title: title,
        body: body,
        shownAt: DateTime.now(),
        data: data ?? {},
      );

      // Publish notification shown event
      EventSystem.instance.publishTopic('notification.shown', {
        'id': id,
        'title': title,
        'body': body,
        'platform': _getPlatformName(),
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to show notification', e, stackTrace);
      throw Exception('Failed to show notification: $e');
    }
  }

  @override
  Future<void> hideNotification(String id) async {
    if (!_initialized) {
      throw StateError('Notification manager not initialized');
    }

    _logger.fine('Hiding notification: $id');

    try {
      await _channel.invokeMethod('cancelNotification', {
        'id': id,
      });

      // Remove from active notifications
      _activeNotifications.remove(id);

      // Publish notification hidden event
      EventSystem.instance.publishTopic('notification.hidden', {
        'id': id,
        'platform': _getPlatformName(),
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to hide notification', e, stackTrace);
      throw Exception('Failed to hide notification: $e');
    }
  }

  /// Request notification permission
  @override
  Future<bool> requestPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      final granted = result ?? false;

      _logger.info('Notification permission ${granted ? "granted" : "denied"}');

      // Publish permission event
      EventSystem.instance.publishTopic('notification.permission', {
        'granted': granted,
        'platform': _getPlatformName(),
      });

      return granted;
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to request notification permission', e, stackTrace);
      return false;
    }
  }

  /// Update notification (for progress notifications)
  @override
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  }) async {
    if (!_initialized) {
      throw StateError('Notification manager not initialized');
    }

    if (!_supportsProgress) {
      _logger.warning('Platform does not support progress notifications');
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
    } catch (e, stackTrace) {
      _logger.severe('Failed to update notification', e, stackTrace);
    }
  }

  /// Cancel all notifications
  @override
  Future<void> cancelAllNotifications() async {
    if (!_initialized) {
      throw StateError('Notification manager not initialized');
    }

    try {
      await _channel.invokeMethod('cancelAllNotifications');
      _activeNotifications.clear();

      EventSystem.instance.publishTopic('notification.all_cancelled', {
        'platform': _getPlatformName(),
      });
    } catch (e, stackTrace) {
      _logger.severe('Failed to cancel all notifications', e, stackTrace);
    }
  }

  /// Get active notifications
  @override
  List<NotificationInfo> getActiveNotifications() {
    return _activeNotifications.values.toList();
  }

  /// Handle notification events from platform
  void _handleNotificationEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};

    _logger.fine('Received notification event: $type');

    switch (type) {
      case 'notificationTapped':
        final id = data['id'] as String?;
        final notificationData = data['data'] as Map<String, dynamic>?;

        EventSystem.instance.publishTopic('notification.tapped', {
          'id': id,
          'data': notificationData,
          'platform': _getPlatformName(),
        });
        break;

      case 'notificationActionTapped':
        final id = data['id'] as String?;
        final actionId = data['actionId'] as String?;
        final notificationData = data['data'] as Map<String, dynamic>?;

        EventSystem.instance.publishTopic('notification.action', {
          'id': id,
          'actionId': actionId,
          'data': notificationData,
          'platform': _getPlatformName(),
        });
        break;

      case 'notificationDismissed':
        final id = data['id'] as String?;
        _activeNotifications.remove(id);

        EventSystem.instance.publishTopic('notification.dismissed', {
          'id': id,
          'platform': _getPlatformName(),
        });
        break;
    }
  }

  /// Check platform notification capabilities
  Future<void> _checkCapabilities() async {
    try {
      // Android doesn't have a checkNotificationCapabilities method
      // Set default capabilities based on platform
      if (Platform.isAndroid) {
        _supportsActions = true;
        _supportsImages = true;
        _supportsProgress = true;
        _supportsGrouping = true;
      } else if (Platform.isIOS) {
        _supportsActions = true;
        _supportsImages = true;
        _supportsProgress = false;
        _supportsGrouping = true;
      } else {
        // Default for other platforms
        _supportsActions = false;
        _supportsImages = false;
        _supportsProgress = false;
        _supportsGrouping = false;
      }

      _logger.fine('Platform notification capabilities: '
          'actions=$_supportsActions, images=$_supportsImages, '
          'progress=$_supportsProgress, grouping=$_supportsGrouping');
    } catch (e) {
      _logger.warning('Failed to check notification capabilities', e);
    }
  }

  /// Get platform name
  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Cancel a specific notification
  @override
  Future<void> cancelNotification(String id) async {
    return hideNotification(id);
  }

  /// Dispose resources
  @override
  Future<void> dispose() async {
    _activeNotifications.clear();
    _initialized = false;
  }
}
