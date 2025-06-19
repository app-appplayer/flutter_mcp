import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../config/notification_config.dart' hide NotificationPriority;
import '../../utils/logger.dart';
import '../../events/event_system.dart';
import 'notification_manager.dart';
import 'notification_models.dart';

/// Enhanced notification manager with scheduling and advanced features
class EnhancedNotificationManager implements NotificationManager {
  static const MethodChannel _channel =
      MethodChannel('flutter_mcp/notification');
  static const EventChannel _eventChannel =
      EventChannel('flutter_mcp/notification_events');

  final Logger _logger = Logger('flutter_mcp.enhanced_notification');
  final EventSystem _eventSystem = EventSystem.instance;

  NotificationConfig? _config;
  bool _initialized = false;
  StreamSubscription? _eventSubscription;

  // Track active and scheduled notifications
  final Map<String, NotificationInfo> _activeNotifications = {};
  final Map<String, Timer> _scheduledTimers = {};
  final Map<String, ScheduledNotificationInfo> _scheduledNotifications = {};

  // Platform capabilities
  bool _supportsActions = false;
  bool _supportsImages = false;
  bool _supportsProgress = false;
  bool _supportsGrouping = false;
  bool _supportsScheduling = false;

  @override
  Future<void> initialize(NotificationConfig? config) async {
    if (_initialized) {
      _logger.fine('Enhanced notification manager already initialized');
      return;
    }

    _config = config ?? NotificationConfig();

    try {
      // Check platform capabilities
      await _checkCapabilities();

      // Set up event listener for notification interactions
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map<String, dynamic>) {
            _handleNotificationEvent(event);
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
      _logger.info('Enhanced notification manager initialized');

      // Publish initialization event
      await _eventSystem.publish(NotificationInitializedEvent(
        platform: _getPlatformName(),
        capabilities: NotificationCapabilities(
          actions: _supportsActions,
          images: _supportsImages,
          progress: _supportsProgress,
          grouping: _supportsGrouping,
          scheduling: _supportsScheduling,
        ),
      ));
    } catch (e, stackTrace) {
      _logger.severe(
          'Failed to initialize enhanced notification manager', e, stackTrace);
      throw Exception('Failed to initialize notifications: $e');
    }
  }

  /// Schedule a notification to be shown at a specific time
  Future<String> scheduleNotification({
    required String title,
    required DateTime scheduledTime,
    String? body,
    String? icon,
    NotificationPriority priority = NotificationPriority.normal,
    List<NotificationAction>? actions,
    String? imageUrl,
    int? progress,
    String? groupKey,
    Map<String, dynamic>? data,
    Duration? repeatInterval,
  }) async {
    if (!_initialized) {
      throw StateError('Notification manager not initialized');
    }

    final id = 'scheduled_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    if (scheduledTime.isBefore(now)) {
      _logger.warning('Scheduled time is in the past, showing immediately');
      await showNotification(
        title: title,
        body: body ?? '',
        id: id,
        icon: icon,
        data: data,
        actions: actions,
        priority: priority,
        image: imageUrl,
        showProgress: progress != null,
        progress: progress,
        group: groupKey,
      );
      return id;
    }

    final delay = scheduledTime.difference(now);

    final scheduledInfo = ScheduledNotificationInfo(
      id: id,
      title: title,
      body: body ?? '',
      icon: icon,
      priority: priority,
      actions: actions ?? [],
      imageUrl: imageUrl,
      progress: progress,
      groupKey: groupKey,
      data: data ?? {},
      scheduledTime: scheduledTime,
      repeatInterval: repeatInterval,
      createdAt: now,
    );

    _scheduledNotifications[id] = scheduledInfo;

    void showScheduledNotification() {
      if (_scheduledNotifications.containsKey(id)) {
        final info = _scheduledNotifications[id]!;

        showNotification(
          title: info.title,
          body: info.body,
          id: id,
          icon: info.icon,
          data: info.data,
          actions: info.actions,
          priority: info.priority,
          image: info.imageUrl,
          showProgress: info.progress != null,
          progress: info.progress,
          group: info.groupKey,
        );

        _scheduledNotifications.remove(id);
        _scheduledTimers.remove(id);

        // Publish scheduled notification shown event
        _eventSystem.publish(ScheduledNotificationShownEvent(
          id: id,
          scheduledTime: info.scheduledTime,
          actualTime: DateTime.now(),
        ));

        // Schedule repeat if specified
        if (info.repeatInterval != null) {
          scheduleNotification(
            title: info.title,
            scheduledTime: DateTime.now().add(info.repeatInterval!),
            body: info.body,
            icon: info.icon,
            priority: info.priority,
            actions: info.actions,
            imageUrl: info.imageUrl,
            progress: info.progress,
            groupKey: info.groupKey,
            data: info.data,
            repeatInterval: info.repeatInterval,
          );
        }
      }
    }

    final timer = Timer(delay, showScheduledNotification);
    _scheduledTimers[id] = timer;

    _logger.info(
        'Notification scheduled for ${scheduledTime.toIso8601String()}: $title');

    // Publish scheduling event
    await _eventSystem.publish(NotificationScheduledEvent(
      id: id,
      title: title,
      scheduledTime: scheduledTime,
      repeatInterval: repeatInterval,
    ));

    return id;
  }

  /// Cancel a scheduled notification
  Future<bool> cancelScheduledNotification(String id) async {
    final timer = _scheduledTimers[id];
    if (timer != null) {
      timer.cancel();
      _scheduledTimers.remove(id);
      final info = _scheduledNotifications.remove(id);

      _logger.info('Cancelled scheduled notification: $id');

      // Publish cancellation event
      if (info != null) {
        await _eventSystem.publish(NotificationCancelledEvent(
          id: id,
          title: info.title,
          wasScheduled: true,
        ));
      }

      return true;
    }
    return false;
  }

  /// Get all scheduled notifications
  List<ScheduledNotificationInfo> getScheduledNotifications() {
    return _scheduledNotifications.values.toList();
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllScheduledNotifications() async {
    final count = _scheduledTimers.length;

    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    _scheduledNotifications.clear();

    _logger.info('Cancelled $count scheduled notifications');

    // Publish bulk cancellation event
    await _eventSystem.publish(AllNotificationsCancelledEvent(
      count: count,
      includesScheduled: true,
    ));
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
      await _eventSystem.publish(NotificationShownEvent(
        id: id,
        title: title,
        body: body,
        priority: priority,
      ));
    } catch (e, stackTrace) {
      _logger.severe('Failed to show notification', e, stackTrace);

      // Publish error event
      await _eventSystem.publish(NotificationErrorEvent(
        id: id,
        title: title,
        error: e.toString(),
      ));

      throw Exception('Failed to show notification: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final bool granted = await _channel.invokeMethod('requestPermission');

      // Publish permission event
      await _eventSystem.publish(NotificationPermissionEvent(
        granted: granted,
        platform: _getPlatformName(),
      ));

      _logger.info('Notification permission: $granted');
      return granted;
    } catch (e) {
      _logger.severe('Failed to request notification permission', e);
      return false;
    }
  }

  @override
  Future<void> cancelNotification(String id) async {
    try {
      await _channel.invokeMethod('cancelNotification', {'id': id});

      final info = _activeNotifications.remove(id);

      // Also cancel if it's a scheduled notification
      await cancelScheduledNotification(id);

      // Publish cancellation event
      if (info != null) {
        await _eventSystem.publish(NotificationCancelledEvent(
          id: id,
          title: info.title,
          wasScheduled: false,
        ));
      }

      _logger.fine('Cancelled notification: $id');
    } catch (e) {
      _logger.severe('Failed to cancel notification', e);
    }
  }

  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _channel.invokeMethod('cancelAllNotifications');

      final activeCount = _activeNotifications.length;
      _activeNotifications.clear();

      // Also cancel all scheduled notifications
      await cancelAllScheduledNotifications();

      // Publish bulk cancellation event
      await _eventSystem.publish(AllNotificationsCancelledEvent(
        count: activeCount,
        includesScheduled: true,
      ));

      _logger.info('Cancelled all notifications');
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
    try {
      final updateData = {
        'id': id,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        if (progress != null) 'progress': progress,
        if (data != null) 'data': data,
      };

      await _channel.invokeMethod('updateNotification', updateData);

      // Update local tracking
      final info = _activeNotifications[id];
      if (info != null) {
        _activeNotifications[id] = NotificationInfo(
          id: id,
          title: title ?? info.title,
          body: body ?? info.body,
          shownAt: info.shownAt,
          data: {...info.data, ...?data},
        );
      }

      // Publish update event
      await _eventSystem.publish(NotificationUpdatedEvent(
        id: id,
        title: title,
        body: body,
        progress: progress,
      ));

      _logger.fine('Updated notification: $id');
    } catch (e) {
      _logger.severe('Failed to update notification', e);
    }
  }

  @override
  List<NotificationInfo> getActiveNotifications() {
    return _activeNotifications.values.toList();
  }

  @override
  Future<void> dispose() async {
    // Cancel all timers
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    _scheduledNotifications.clear();

    await _eventSubscription?.cancel();
    _activeNotifications.clear();
    _initialized = false;

    _logger.info('Enhanced notification manager disposed');
  }

  // Private methods
  Future<void> _checkCapabilities() async {
    try {
      final capabilities = await _channel.invokeMethod('getCapabilities');
      if (capabilities is Map) {
        _supportsActions = capabilities['actions'] ?? false;
        _supportsImages = capabilities['images'] ?? false;
        _supportsProgress = capabilities['progress'] ?? false;
        _supportsGrouping = capabilities['grouping'] ?? false;
        _supportsScheduling =
            capabilities['scheduling'] ?? true; // Software scheduling
      }
    } catch (e) {
      _logger.warning('Failed to check capabilities, using defaults', e);
      _supportsScheduling = true; // Always support software scheduling
    }
  }

  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  void _handleNotificationEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final id = event['id'] as String?;

    if (type == null || id == null) return;

    switch (type) {
      case 'clicked':
        _eventSystem.publish(NotificationClickedEvent(
          id: id,
          actionId: event['actionId'] as String?,
          data: Map<String, dynamic>.from(event['data'] ?? {}),
        ));
        break;
      case 'dismissed':
        _activeNotifications.remove(id);
        _eventSystem.publish(NotificationDismissedEvent(id: id));
        break;
      case 'action':
        _eventSystem.publish(NotificationActionEvent(
          id: id,
          actionId: event['actionId'] as String,
          data: Map<String, dynamic>.from(event['data'] ?? {}),
        ));
        break;
    }
  }

  @override
  Future<void> hideNotification(String id) => cancelNotification(id);
}

/// Extended notification info for scheduled notifications
class ScheduledNotificationInfo extends NotificationInfo {
  final DateTime scheduledTime;
  final Duration? repeatInterval;
  final String? icon;
  final NotificationPriority priority;
  final List<NotificationAction> actions;
  final String? imageUrl;
  final int? progress;
  final String? groupKey;
  final DateTime createdAt;

  ScheduledNotificationInfo({
    required super.id,
    required super.title,
    super.body = '',
    required this.scheduledTime,
    this.repeatInterval,
    DateTime? shownAt,
    super.data,
    this.icon,
    this.priority = NotificationPriority.normal,
    this.actions = const [],
    this.imageUrl,
    this.progress,
    this.groupKey,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        super(shownAt: shownAt ?? DateTime.now());
}

/// Notification capabilities
class NotificationCapabilities {
  final bool actions;
  final bool images;
  final bool progress;
  final bool grouping;
  final bool scheduling;

  const NotificationCapabilities({
    required this.actions,
    required this.images,
    required this.progress,
    required this.grouping,
    required this.scheduling,
  });
}

// Event classes for the event system
class NotificationInitializedEvent extends Event {
  final String platform;
  final NotificationCapabilities capabilities;

  NotificationInitializedEvent({
    required this.platform,
    required this.capabilities,
  });
}

class NotificationScheduledEvent extends Event {
  final String id;
  final String title;
  final DateTime scheduledTime;
  final Duration? repeatInterval;

  NotificationScheduledEvent({
    required this.id,
    required this.title,
    required this.scheduledTime,
    this.repeatInterval,
  });
}

class ScheduledNotificationShownEvent extends Event {
  final String id;
  final DateTime scheduledTime;
  final DateTime actualTime;

  ScheduledNotificationShownEvent({
    required this.id,
    required this.scheduledTime,
    required this.actualTime,
  });
}

class NotificationShownEvent extends Event {
  final String id;
  final String title;
  final String body;
  final NotificationPriority priority;

  NotificationShownEvent({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
  });
}

class NotificationClickedEvent extends Event {
  final String id;
  final String? actionId;
  final Map<String, dynamic> data;

  NotificationClickedEvent({
    required this.id,
    this.actionId,
    required this.data,
  });
}

class NotificationDismissedEvent extends Event {
  final String id;

  NotificationDismissedEvent({required this.id});
}

class NotificationActionEvent extends Event {
  final String id;
  final String actionId;
  final Map<String, dynamic> data;

  NotificationActionEvent({
    required this.id,
    required this.actionId,
    required this.data,
  });
}

class NotificationCancelledEvent extends Event {
  final String id;
  final String title;
  final bool wasScheduled;

  NotificationCancelledEvent({
    required this.id,
    required this.title,
    required this.wasScheduled,
  });
}

class AllNotificationsCancelledEvent extends Event {
  final int count;
  final bool includesScheduled;

  AllNotificationsCancelledEvent({
    required this.count,
    required this.includesScheduled,
  });
}

class NotificationUpdatedEvent extends Event {
  final String id;
  final String? title;
  final String? body;
  final int? progress;

  NotificationUpdatedEvent({
    required this.id,
    this.title,
    this.body,
    this.progress,
  });
}

class NotificationPermissionEvent extends Event {
  final bool granted;
  final String platform;

  NotificationPermissionEvent({
    required this.granted,
    required this.platform,
  });
}

class NotificationErrorEvent extends Event {
  final String id;
  final String title;
  final String error;

  NotificationErrorEvent({
    required this.id,
    required this.title,
    required this.error,
  });
}
