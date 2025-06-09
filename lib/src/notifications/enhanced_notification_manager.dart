import 'dart:async';
import 'dart:typed_data';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../platform/notification/notification_manager.dart';
import '../platform/notification/android_notification.dart';
import '../platform/notification/ios_notification.dart';
import '../platform/notification/desktop_notification.dart';
import '../platform/platform_factory.dart';
import '../events/enhanced_typed_event_system.dart';
import '../events/event_models.dart';

/// Rich notification style types
enum NotificationStyle {
  basic,
  bigText,
  bigPicture,
  inbox,
  messaging,
  media,
  progress,
}

/// Notification action button
class NotificationAction {
  final String id;
  final String title;
  final String? icon;
  final bool showInForeground;
  final bool requiresUnlock;
  final bool isDestructive;
  
  NotificationAction({
    required this.id,
    required this.title,
    this.icon,
    this.showInForeground = true,
    this.requiresUnlock = false,
    this.isDestructive = false,
  });
  
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'icon': icon,
    'showInForeground': showInForeground,
    'requiresUnlock': requiresUnlock,
    'isDestructive': isDestructive,
  };
}

/// Message for messaging style notifications
class NotificationMessage {
  final String text;
  final DateTime timestamp;
  final String? sender;
  final String? senderAvatar;
  
  NotificationMessage({
    required this.text,
    DateTime? timestamp,
    this.sender,
    this.senderAvatar,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toMap() => {
    'text': text,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'sender': sender,
    'senderAvatar': senderAvatar,
  };
}

/// Media control for media style notifications
class MediaControl {
  final String action;
  final String icon;
  final String? label;
  
  MediaControl({
    required this.action,
    required this.icon,
    this.label,
  });
  
  Map<String, dynamic> toMap() => {
    'action': action,
    'icon': icon,
    'label': label,
  };
}

/// Enhanced notification configuration
class EnhancedNotificationConfig {
  final String id;
  final String title;
  final String body;
  final NotificationStyle style;
  
  // Grouping
  final String? groupKey;
  final bool isGroupSummary;
  final int? groupAlertBehavior;
  
  // Rich content
  final String? largeIcon;
  final String? bigPicture;
  final List<String>? inboxLines;
  final List<NotificationMessage>? messages;
  final List<NotificationAction>? actions;
  final Uint8List? imageData;
  
  // Progress
  final int? progress;
  final int? maxProgress;
  final bool? indeterminate;
  
  // Media controls
  final List<MediaControl>? mediaControls;
  final String? mediaSession;
  
  // Styling
  final int? color;
  final String? category;
  final bool showTimestamp;
  final bool autoCancel;
  final bool ongoing;
  final int? visibility;
  final String? sound;
  final List<int>? vibrationPattern;
  final int? ledColor;
  final Duration? timeout;
  
  // Reply
  final bool enableReply;
  final String? replyLabel;
  final String? replyPlaceholder;
  
  // Additional data
  final Map<String, dynamic>? data;
  
  EnhancedNotificationConfig({
    required this.id,
    required this.title,
    required this.body,
    this.style = NotificationStyle.basic,
    this.groupKey,
    this.isGroupSummary = false,
    this.groupAlertBehavior,
    this.largeIcon,
    this.bigPicture,
    this.inboxLines,
    this.messages,
    this.actions,
    this.imageData,
    this.progress,
    this.maxProgress,
    this.indeterminate,
    this.mediaControls,
    this.mediaSession,
    this.color,
    this.category,
    this.showTimestamp = true,
    this.autoCancel = true,
    this.ongoing = false,
    this.visibility,
    this.sound,
    this.vibrationPattern,
    this.ledColor,
    this.timeout,
    this.enableReply = false,
    this.replyLabel,
    this.replyPlaceholder,
    this.data,
  });
  
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'style': style.name,
      'showTimestamp': showTimestamp,
      'autoCancel': autoCancel,
      'ongoing': ongoing,
      'enableReply': enableReply,
    };
    
    // Add optional fields
    if (groupKey != null) map['groupKey'] = groupKey;
    if (isGroupSummary) map['isGroupSummary'] = isGroupSummary;
    if (groupAlertBehavior != null) map['groupAlertBehavior'] = groupAlertBehavior;
    if (largeIcon != null) map['largeIcon'] = largeIcon;
    if (bigPicture != null) map['bigPicture'] = bigPicture;
    if (inboxLines != null) map['inboxLines'] = inboxLines;
    if (messages != null) map['messages'] = messages!.map((m) => m.toMap()).toList();
    if (actions != null) map['actions'] = actions!.map((a) => a.toMap()).toList();
    if (imageData != null) map['imageData'] = imageData;
    if (progress != null) map['progress'] = progress;
    if (maxProgress != null) map['maxProgress'] = maxProgress;
    if (indeterminate != null) map['indeterminate'] = indeterminate;
    if (mediaControls != null) map['mediaControls'] = mediaControls!.map((c) => c.toMap()).toList();
    if (mediaSession != null) map['mediaSession'] = mediaSession;
    if (color != null) map['color'] = color;
    if (category != null) map['category'] = category;
    if (visibility != null) map['visibility'] = visibility;
    if (sound != null) map['sound'] = sound;
    if (vibrationPattern != null) map['vibrationPattern'] = vibrationPattern;
    if (ledColor != null) map['ledColor'] = ledColor;
    if (timeout != null) map['timeout'] = timeout!.inMilliseconds;
    if (replyLabel != null) map['replyLabel'] = replyLabel;
    if (replyPlaceholder != null) map['replyPlaceholder'] = replyPlaceholder;
    if (data != null) map['data'] = data;
    
    return map;
  }
}

/// Notification group manager
class NotificationGroupManager {
  final Map<String, List<String>> _groups = {};
  final Map<String, int> _groupCounts = {};
  
  void addToGroup(String groupKey, String notificationId) {
    _groups.putIfAbsent(groupKey, () => []).add(notificationId);
    _groupCounts[groupKey] = (_groupCounts[groupKey] ?? 0) + 1;
  }
  
  void removeFromGroup(String groupKey, String notificationId) {
    _groups[groupKey]?.remove(notificationId);
    if (_groupCounts.containsKey(groupKey)) {
      _groupCounts[groupKey] = _groupCounts[groupKey]! - 1;
      if (_groupCounts[groupKey]! <= 0) {
        _groupCounts.remove(groupKey);
        _groups.remove(groupKey);
      }
    }
  }
  
  List<String> getGroupNotifications(String groupKey) {
    return List.unmodifiable(_groups[groupKey] ?? []);
  }
  
  int getGroupCount(String groupKey) {
    return _groupCounts[groupKey] ?? 0;
  }
  
  bool shouldShowGroupSummary(String groupKey) {
    return getGroupCount(groupKey) > 1;
  }
  
  void clearGroup(String groupKey) {
    _groups.remove(groupKey);
    _groupCounts.remove(groupKey);
  }
  
  void clear() {
    _groups.clear();
    _groupCounts.clear();
  }
}

/// Enhanced notification manager with rich notifications and grouping
class EnhancedNotificationManager {
  final Logger _logger = Logger('flutter_mcp.enhanced_notification_manager');
  late final NotificationManager _baseManager;
  final EnhancedTypedEventSystem _eventSystem = EnhancedTypedEventSystem.instance;
  final NotificationGroupManager _groupManager = NotificationGroupManager();
  
  // Action handlers
  final Map<String, void Function(String notificationId, Map<String, dynamic>? data)> _actionHandlers = {};
  
  // Reply handlers
  final Map<String, void Function(String notificationId, String reply)> _replyHandlers = {};
  
  // Active notifications tracking
  final Map<String, EnhancedNotificationConfig> _activeNotifications = {};
  
  // Singleton
  static EnhancedNotificationManager? _instance;
  
  static EnhancedNotificationManager get instance {
    _instance ??= EnhancedNotificationManager._internal();
    return _instance!;
  }
  
  EnhancedNotificationManager._internal();
  
  /// Initialize enhanced notification manager with platform-specific manager
  Future<void> initialize({NotificationManager? baseManager}) async {
    // Get platform-specific notification manager
    final factory = PlatformFactory();
    _baseManager = baseManager ?? factory.createNotificationManager();
    
    await _baseManager.initialize(null);
    
    // Set up base notification handlers if supported
    if (_baseManager is AndroidNotificationManager) {
      (_baseManager as AndroidNotificationManager).registerClickHandler('default', _handleNotificationClick);
    } else if (_baseManager is IOSNotificationManager) {
      (_baseManager as IOSNotificationManager).registerClickHandler('default', _handleNotificationClick);
    } else if (_baseManager is DesktopNotificationManager) {
      (_baseManager as DesktopNotificationManager).registerClickHandler('default', _handleNotificationClick);
    }
    
    _logger.info('Enhanced notification manager initialized');
  }
  
  /// Show an enhanced notification
  Future<void> showNotification(EnhancedNotificationConfig config) async {
    try {
      // Store notification config
      _activeNotifications[config.id] = config;
      
      // Handle grouping
      if (config.groupKey != null) {
        _groupManager.addToGroup(config.groupKey!, config.id);
        
        // Show group summary if needed
        if (_groupManager.shouldShowGroupSummary(config.groupKey!) && !config.isGroupSummary) {
          await _showGroupSummary(config.groupKey!);
        }
      }
      
      // Convert to platform notification based on style
      switch (config.style) {
        case NotificationStyle.basic:
          await _showBasicNotification(config);
          break;
          
        case NotificationStyle.bigText:
          await _showBigTextNotification(config);
          break;
          
        case NotificationStyle.bigPicture:
          await _showBigPictureNotification(config);
          break;
          
        case NotificationStyle.inbox:
          await _showInboxNotification(config);
          break;
          
        case NotificationStyle.messaging:
          await _showMessagingNotification(config);
          break;
          
        case NotificationStyle.media:
          await _showMediaNotification(config);
          break;
          
        case NotificationStyle.progress:
          await _showProgressNotification(config);
          break;
      }
      
      // Publish notification event
      _eventSystem.publish(BackgroundTaskEvent(
        taskId: 'notification_${config.id}',
        taskType: 'notification',
        status: TaskStatus.completed,
        message: 'Notification shown: ${config.title}',
      ));
      
    } catch (e, stackTrace) {
      _logger.severe('Failed to show notification', e, stackTrace);
      throw MCPException('Failed to show notification: $e');
    }
  }
  
  /// Hide a notification
  Future<void> hideNotification(String id) async {
    final config = _activeNotifications.remove(id);
    
    if (config?.groupKey != null) {
      _groupManager.removeFromGroup(config!.groupKey!, id);
      
      // Update or remove group summary
      if (!_groupManager.shouldShowGroupSummary(config.groupKey!)) {
        await _baseManager.hideNotification('${config.groupKey}_summary');
      } else {
        await _showGroupSummary(config.groupKey!);
      }
    }
    
    await _baseManager.hideNotification(id);
  }
  
  /// Hide all notifications in a group
  Future<void> hideNotificationGroup(String groupKey) async {
    final notifications = _groupManager.getGroupNotifications(groupKey);
    
    for (final id in notifications) {
      _activeNotifications.remove(id);
      await _baseManager.hideNotification(id);
    }
    
    // Hide group summary
    await _baseManager.hideNotification('${groupKey}_summary');
    
    _groupManager.clearGroup(groupKey);
  }
  
  /// Update notification progress
  Future<void> updateProgress(
    String id, {
    required int progress,
    required int maxProgress,
    bool indeterminate = false,
  }) async {
    final config = _activeNotifications[id];
    if (config == null || config.style != NotificationStyle.progress) {
      _logger.warning('Cannot update progress for non-progress notification: $id');
      return;
    }
    
    // Create updated config
    final updatedConfig = EnhancedNotificationConfig(
      id: config.id,
      title: config.title,
      body: config.body,
      style: config.style,
      progress: progress,
      maxProgress: maxProgress,
      indeterminate: indeterminate,
      ongoing: config.ongoing,
      autoCancel: config.autoCancel,
      data: config.data,
    );
    
    await showNotification(updatedConfig);
  }
  
  /// Register action handler
  void registerActionHandler(
    String actionId,
    void Function(String notificationId, Map<String, dynamic>? data) handler,
  ) {
    _actionHandlers[actionId] = handler;
    _logger.fine('Registered action handler for: $actionId');
  }
  
  /// Register reply handler
  void registerReplyHandler(
    String notificationId,
    void Function(String notificationId, String reply) handler,
  ) {
    _replyHandlers[notificationId] = handler;
    _logger.fine('Registered reply handler for notification: $notificationId');
  }
  
  /// Simulate notification click (for testing)
  void simulateNotificationClick(String id, Map<String, dynamic>? data) {
    _handleNotificationClick(id, data);
  }
  
  /// Reset singleton instance (for testing)
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
  
  /// Show basic notification
  Future<void> _showBasicNotification(EnhancedNotificationConfig config) async {
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
        additionalData: _buildNotificationData(config),
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show big text notification
  Future<void> _showBigTextNotification(EnhancedNotificationConfig config) async {
    // For platforms that support it, show expanded text
    // For others, fall back to basic notification
    final data = _buildNotificationData(config);
    data['style'] = 'bigText';
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show big picture notification
  Future<void> _showBigPictureNotification(EnhancedNotificationConfig config) async {
    final data = _buildNotificationData(config);
    data['style'] = 'bigPicture';
    if (config.bigPicture != null) data['bigPicture'] = config.bigPicture;
    if (config.imageData != null) data['imageData'] = config.imageData;
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show inbox style notification
  Future<void> _showInboxNotification(EnhancedNotificationConfig config) async {
    final data = _buildNotificationData(config);
    data['style'] = 'inbox';
    if (config.inboxLines != null) data['lines'] = config.inboxLines;
    
    // Build summary text
    final summary = config.inboxLines != null
        ? '${config.inboxLines!.length} items'
        : config.body;
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: summary,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: summary,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show messaging style notification
  Future<void> _showMessagingNotification(EnhancedNotificationConfig config) async {
    final data = _buildNotificationData(config);
    data['style'] = 'messaging';
    if (config.messages != null) {
      data['messages'] = config.messages!.map((m) => m.toMap()).toList();
    }
    
    // Use last message as body
    final lastMessage = config.messages?.isNotEmpty == true
        ? config.messages!.last.text
        : config.body;
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: lastMessage,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: lastMessage,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show media style notification
  Future<void> _showMediaNotification(EnhancedNotificationConfig config) async {
    final data = _buildNotificationData(config);
    data['style'] = 'media';
    data['ongoing'] = true; // Media notifications are typically ongoing
    if (config.mediaControls != null) {
      data['mediaControls'] = config.mediaControls!.map((c) => c.toMap()).toList();
    }
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show progress notification
  Future<void> _showProgressNotification(EnhancedNotificationConfig config) async {
    final data = _buildNotificationData(config);
    data['style'] = 'progress';
    data['ongoing'] = config.ongoing;
    if (config.progress != null) data['progress'] = config.progress;
    if (config.maxProgress != null) data['maxProgress'] = config.maxProgress;
    if (config.indeterminate != null) data['indeterminate'] = config.indeterminate;
    
    if (_baseManager is AndroidNotificationManager) {
      await (_baseManager as AndroidNotificationManager).showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
        additionalData: data,
      );
    } else {
      await _baseManager.showNotification(
        title: config.title,
        body: config.body,
        id: config.id,
        icon: config.largeIcon,
      );
    }
  }
  
  /// Show group summary notification
  Future<void> _showGroupSummary(String groupKey) async {
    final count = _groupManager.getGroupCount(groupKey);
    final notifications = _groupManager.getGroupNotifications(groupKey);
    
    // Build summary lines from active notifications
    final summaryLines = <String>[];
    for (final id in notifications.take(5)) { // Show up to 5 items
      final config = _activeNotifications[id];
      if (config != null) {
        summaryLines.add(config.title);
      }
    }
    
    final summaryConfig = EnhancedNotificationConfig(
      id: '${groupKey}_summary',
      title: '$groupKey ($count items)',
      body: summaryLines.join('\n'),
      style: NotificationStyle.inbox,
      groupKey: groupKey,
      isGroupSummary: true,
      inboxLines: summaryLines,
    );
    
    await showNotification(summaryConfig);
  }
  
  /// Build notification data
  Map<String, dynamic> _buildNotificationData(EnhancedNotificationConfig config) {
    final data = <String, dynamic>{};
    
    // Add base data
    if (config.data != null) data.addAll(config.data!);
    
    // Add enhanced fields
    if (config.groupKey != null) data['groupKey'] = config.groupKey;
    if (config.actions != null) {
      data['actions'] = config.actions!.map((a) => a.toMap()).toList();
    }
    if (config.color != null) data['color'] = config.color;
    if (config.category != null) data['category'] = config.category;
    if (config.enableReply) {
      data['enableReply'] = true;
      if (config.replyLabel != null) data['replyLabel'] = config.replyLabel;
      if (config.replyPlaceholder != null) data['replyPlaceholder'] = config.replyPlaceholder;
    }
    
    return data;
  }
  
  /// Handle notification click (exposed for testing)
  void _handleNotificationClick(String id, Map<String, dynamic>? data) {
    _logger.fine('Notification clicked: $id');
    
    // Check for action
    final actionId = data?['actionId'] as String?;
    if (actionId != null && _actionHandlers.containsKey(actionId)) {
      _actionHandlers[actionId]!(id, data);
    }
    
    // Check for reply
    final reply = data?['reply'] as String?;
    if (reply != null && _replyHandlers.containsKey(id)) {
      _replyHandlers[id]!(id, reply);
    }
    
    // Publish click event
    _eventSystem.publish(BackgroundTaskEvent(
      taskId: 'notification_click_$id',
      taskType: 'notification_interaction',
      status: TaskStatus.completed,
      result: {
        'notificationId': id,
        'action': actionId ?? 'click',
        'data': data,
      },
    ));
  }
  
  
  /// Clear all notifications
  Future<void> clearAll() async {
    for (final id in _activeNotifications.keys.toList()) {
      await hideNotification(id);
    }
    
    _activeNotifications.clear();
    _groupManager.clear();
  }
  
  /// Dispose
  void dispose() {
    _actionHandlers.clear();
    _replyHandlers.clear();
    _activeNotifications.clear();
    _groupManager.clear();
    // Platform specific managers may have their own cleanup
    if (_baseManager is AndroidNotificationManager) {
      (_baseManager as AndroidNotificationManager).dispose();
    }
  }
}