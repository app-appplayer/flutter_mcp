import '../../events/event_system.dart';

/// Notification priority levels
enum NotificationPriority { low, normal, high, critical }

/// Notification action
class NotificationAction {
  final String id;
  final String title;
  final String? icon;
  final bool requiresInput;
  final String? inputPlaceholder;

  const NotificationAction({
    required this.id,
    required this.title,
    this.icon,
    this.requiresInput = false,
    this.inputPlaceholder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
      'requiresInput': requiresInput,
      'inputPlaceholder': inputPlaceholder,
    };
  }

  factory NotificationAction.fromMap(Map<String, dynamic> map) {
    return NotificationAction(
      id: map['id'] as String,
      title: map['title'] as String,
      icon: map['icon'] as String?,
      requiresInput: map['requiresInput'] as bool? ?? false,
      inputPlaceholder: map['inputPlaceholder'] as String?,
    );
  }
}

/// Notification information
class NotificationInfo {
  final String id;
  final String title;
  final String body;
  final DateTime shownAt;
  final Map<String, dynamic> data;

  const NotificationInfo({
    required this.id,
    required this.title,
    required this.body,
    required this.shownAt,
    this.data = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'shownAt': shownAt.toIso8601String(),
      'data': data,
    };
  }

  factory NotificationInfo.fromMap(Map<String, dynamic> map) {
    return NotificationInfo(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      shownAt: DateTime.parse(map['shownAt'] as String),
      data: Map<String, dynamic>.from(map['data'] ?? {}),
    );
  }
}

/// Extended notification info for scheduled notifications
class ScheduledNotificationInfo {
  final String id;
  final String title;
  final String? body;
  final String? icon;
  final NotificationPriority priority;
  final List<NotificationAction> actions;
  final String? imageUrl;
  final int? progress;
  final String? groupKey;
  final Map<String, dynamic> data;
  final DateTime scheduledTime;
  final Duration? repeatInterval;
  final DateTime createdAt;

  const ScheduledNotificationInfo({
    required this.id,
    required this.title,
    this.body,
    this.icon,
    this.priority = NotificationPriority.normal,
    this.actions = const [],
    this.imageUrl,
    this.progress,
    this.groupKey,
    this.data = const {},
    required this.scheduledTime,
    this.repeatInterval,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'icon': icon,
      'priority': priority.index,
      'actions': actions.map((a) => a.toMap()).toList(),
      'imageUrl': imageUrl,
      'progress': progress,
      'groupKey': groupKey,
      'data': data,
      'scheduledTime': scheduledTime.toIso8601String(),
      'repeatInterval': repeatInterval?.inMilliseconds,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ScheduledNotificationInfo.fromMap(Map<String, dynamic> map) {
    return ScheduledNotificationInfo(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      icon: map['icon'] as String?,
      priority: NotificationPriority.values[map['priority'] as int? ?? 1],
      actions: (map['actions'] as List<dynamic>?)
              ?.map(
                  (a) => NotificationAction.fromMap(a as Map<String, dynamic>))
              .toList() ??
          [],
      imageUrl: map['imageUrl'] as String?,
      progress: map['progress'] as int?,
      groupKey: map['groupKey'] as String?,
      data: Map<String, dynamic>.from(map['data'] ?? {}),
      scheduledTime: DateTime.parse(map['scheduledTime'] as String),
      repeatInterval: map['repeatInterval'] != null
          ? Duration(milliseconds: map['repeatInterval'] as int)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
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

  Map<String, dynamic> toMap() {
    return {
      'actions': actions,
      'images': images,
      'progress': progress,
      'grouping': grouping,
      'scheduling': scheduling,
    };
  }

  factory NotificationCapabilities.fromMap(Map<String, dynamic> map) {
    return NotificationCapabilities(
      actions: map['actions'] as bool? ?? false,
      images: map['images'] as bool? ?? false,
      progress: map['progress'] as bool? ?? false,
      grouping: map['grouping'] as bool? ?? false,
      scheduling: map['scheduling'] as bool? ?? false,
    );
  }
}

// Event classes for the notification system
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
