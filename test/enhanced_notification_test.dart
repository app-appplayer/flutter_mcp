import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/notifications/enhanced_notification_manager.dart';
import 'package:flutter_mcp/src/platform/notification/notification_manager.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart'
    as platform;
import 'package:flutter_mcp/src/events/enhanced_typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

class MockNotificationManager implements NotificationManager {
  final List<Map<String, dynamic>> shownNotifications = [];
  final List<String> hiddenNotifications = [];
  bool initializeCalled = false;

  @override
  Future<void> initialize(config) async {
    initializeCalled = true;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
    Map<String, dynamic>? data,
    List<platform.NotificationAction>? actions,
    String? channelId,
    platform.NotificationPriority priority =
        platform.NotificationPriority.normal,
    bool showProgress = false,
    int? progress,
    int? maxProgress,
    String? group,
    String? image,
    bool ongoing = false,
  }) async {
    shownNotifications.add({
      'title': title,
      'body': body,
      'icon': icon,
      'id': id,
      'data': data,
      'priority': priority,
    });
  }

  @override
  Future<void> hideNotification(String id) async {
    hiddenNotifications.add(id);
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  @override
  Future<void> cancelNotification(String id) async {
    return hideNotification(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    shownNotifications.clear();
  }

  @override
  Future<void> updateNotification({
    required String id,
    String? title,
    String? body,
    int? progress,
    Map<String, dynamic>? data,
  }) async {
    // Mock implementation
  }

  @override
  List<platform.NotificationInfo> getActiveNotifications() {
    return [];
  }

  @override
  Future<void> dispose() async {
    shownNotifications.clear();
    hiddenNotifications.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Enhanced Notification Manager Tests', () {
    late EnhancedNotificationManager manager;
    late MockNotificationManager mockManager;

    setUp(() async {
      // Reset the singleton instance to ensure clean state
      EnhancedNotificationManager.resetInstance();
      manager = EnhancedNotificationManager.instance;
      mockManager = MockNotificationManager();
      await manager.initialize(baseManager: mockManager);
    });

    tearDown(() {
      EnhancedNotificationManager.resetInstance();
    });

    test('Should initialize with custom base manager', () async {
      expect(mockManager.initializeCalled, isTrue);
    });

    test('Should show basic notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'test_1',
        title: 'Test Title',
        body: 'Test Body',
        style: NotificationStyle.basic,
      );

      await manager.showNotification(config);

      expect(mockManager.shownNotifications.length, equals(1));
      expect(
          mockManager.shownNotifications.first['title'], equals('Test Title'));
      expect(mockManager.shownNotifications.first['body'], equals('Test Body'));
      expect(mockManager.shownNotifications.first['id'], equals('test_1'));
    });

    test('Should show big text notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'test_2',
        title: 'Big Text',
        body:
            'This is a very long text that should be expanded in the notification',
        style: NotificationStyle.bigText,
      );

      await manager.showNotification(config);

      expect(mockManager.shownNotifications.length, equals(1));
      expect(mockManager.shownNotifications.first['title'], equals('Big Text'));
    });

    test('Should show inbox style notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'test_3',
        title: 'Inbox Style',
        body: 'Multiple items',
        style: NotificationStyle.inbox,
        inboxLines: ['Item 1', 'Item 2', 'Item 3'],
      );

      await manager.showNotification(config);

      expect(mockManager.shownNotifications.length, equals(1));
      expect(mockManager.shownNotifications.first['body'], equals('3 items'));
    });

    test('Should show messaging style notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'test_4',
        title: 'Chat',
        body: 'Initial message',
        style: NotificationStyle.messaging,
        messages: [
          NotificationMessage(text: 'Hello!', sender: 'Alice'),
          NotificationMessage(text: 'How are you?', sender: 'Bob'),
        ],
      );

      await manager.showNotification(config);

      expect(mockManager.shownNotifications.length, equals(1));
      expect(
          mockManager.shownNotifications.first['body'], equals('How are you?'));
    });

    test('Should show progress notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'test_5',
        title: 'Download',
        body: 'Downloading file...',
        style: NotificationStyle.progress,
        progress: 50,
        maxProgress: 100,
        ongoing: true,
      );

      await manager.showNotification(config);

      expect(mockManager.shownNotifications.length, equals(1));
      expect(mockManager.shownNotifications.first['title'], equals('Download'));
    });

    test('Should handle notification groups', () async {
      final config1 = EnhancedNotificationConfig(
        id: 'group_1',
        title: 'Message 1',
        body: 'First message',
        groupKey: 'chat_group',
      );

      final config2 = EnhancedNotificationConfig(
        id: 'group_2',
        title: 'Message 2',
        body: 'Second message',
        groupKey: 'chat_group',
      );

      await manager.showNotification(config1);
      await manager.showNotification(config2);

      // Should show both individual notifications plus a group summary
      expect(mockManager.shownNotifications.length, equals(3));

      // Check that group summary exists
      final groupSummary = mockManager.shownNotifications
          .where((n) => n['id'] == 'chat_group_summary')
          .first;
      expect(groupSummary['title'], equals('chat_group (2 items)'));
    });

    test('Should update progress notification', () async {
      final config = EnhancedNotificationConfig(
        id: 'progress_test',
        title: 'Upload',
        body: 'Uploading...',
        style: NotificationStyle.progress,
        progress: 0,
        maxProgress: 100,
      );

      await manager.showNotification(config);
      expect(mockManager.shownNotifications.length, equals(1));

      // Update progress
      await manager.updateProgress(
        'progress_test',
        progress: 75,
        maxProgress: 100,
      );

      // Should have updated the notification
      expect(mockManager.shownNotifications.length, equals(2));
    });

    test('Should hide notifications', () async {
      final config = EnhancedNotificationConfig(
        id: 'hide_test',
        title: 'Test',
        body: 'Test',
      );

      await manager.showNotification(config);
      await manager.hideNotification('hide_test');

      expect(mockManager.hiddenNotifications.contains('hide_test'), isTrue);
    });

    test('Should clear all notifications', () async {
      final config1 = EnhancedNotificationConfig(
        id: 'clear_1',
        title: 'Test 1',
        body: 'Test 1',
      );

      final config2 = EnhancedNotificationConfig(
        id: 'clear_2',
        title: 'Test 2',
        body: 'Test 2',
      );

      await manager.showNotification(config1);
      await manager.showNotification(config2);
      await manager.clearAll();

      expect(mockManager.hiddenNotifications.contains('clear_1'), isTrue);
      expect(mockManager.hiddenNotifications.contains('clear_2'), isTrue);
    });

    test('Should register and handle action handlers', () async {
      var actionHandled = false;
      String? handledNotificationId;
      Map<String, dynamic>? handledData;

      manager.registerActionHandler('reply', (id, data) {
        actionHandled = true;
        handledNotificationId = id;
        handledData = data;
      });

      // Simulate notification click
      manager.simulateNotificationClick('test_notification', {
        'actionId': 'reply',
        'extra': 'data',
      });

      expect(actionHandled, isTrue);
      expect(handledNotificationId, equals('test_notification'));
      expect(handledData?['extra'], equals('data'));
    });

    test('Should register and handle reply handlers', () async {
      var replyHandled = false;
      String? handledNotificationId;
      String? handledReply;

      manager.registerReplyHandler('reply_notification', (id, reply) {
        replyHandled = true;
        handledNotificationId = id;
        handledReply = reply;
      });

      // Simulate notification reply
      manager.simulateNotificationClick('reply_notification', {
        'reply': 'Test reply',
      });

      expect(replyHandled, isTrue);
      expect(handledNotificationId, equals('reply_notification'));
      expect(handledReply, equals('Test reply'));
    });

    test('Should publish events for notification interactions', () async {
      final eventSystem = EnhancedTypedEventSystem.instance;
      BackgroundTaskEvent? publishedEvent;

      eventSystem.subscribe<BackgroundTaskEvent>((event) {
        if (event.taskType == 'notification_interaction') {
          publishedEvent = event;
        }
      });

      // Simulate notification click
      manager.simulateNotificationClick('event_test', {'action': 'click'});

      await Future.delayed(
          Duration(milliseconds: 10)); // Allow event to propagate

      expect(publishedEvent, isNotNull);
      expect(publishedEvent?.taskType, equals('notification_interaction'));
      expect(publishedEvent?.result?['notificationId'], equals('event_test'));

      // Clean up subscription
    });

    group('Notification Group Manager', () {
      late NotificationGroupManager groupManager;

      setUp(() {
        groupManager = NotificationGroupManager();
      });

      test('Should track group notifications', () {
        groupManager.addToGroup('group1', 'notification1');
        groupManager.addToGroup('group1', 'notification2');

        expect(groupManager.getGroupCount('group1'), equals(2));
        expect(groupManager.getGroupNotifications('group1'),
            containsAll(['notification1', 'notification2']));
      });

      test('Should determine when to show group summary', () {
        groupManager.addToGroup('group1', 'notification1');
        expect(groupManager.shouldShowGroupSummary('group1'), isFalse);

        groupManager.addToGroup('group1', 'notification2');
        expect(groupManager.shouldShowGroupSummary('group1'), isTrue);
      });

      test('Should remove notifications from groups', () {
        groupManager.addToGroup('group1', 'notification1');
        groupManager.addToGroup('group1', 'notification2');

        groupManager.removeFromGroup('group1', 'notification1');

        expect(groupManager.getGroupCount('group1'), equals(1));
        expect(groupManager.getGroupNotifications('group1'),
            equals(['notification2']));
      });

      test('Should clear groups when count reaches zero', () {
        groupManager.addToGroup('group1', 'notification1');
        groupManager.removeFromGroup('group1', 'notification1');

        expect(groupManager.getGroupCount('group1'), equals(0));
        expect(groupManager.getGroupNotifications('group1'), isEmpty);
      });
    });

    group('Enhanced Notification Config', () {
      test('Should create basic config', () {
        final config = EnhancedNotificationConfig(
          id: 'test',
          title: 'Test Title',
          body: 'Test Body',
        );

        expect(config.id, equals('test'));
        expect(config.title, equals('Test Title'));
        expect(config.body, equals('Test Body'));
        expect(config.style, equals(NotificationStyle.basic));
      });

      test('Should serialize to map', () {
        final config = EnhancedNotificationConfig(
          id: 'test',
          title: 'Test Title',
          body: 'Test Body',
          style: NotificationStyle.bigText,
          actions: [
            NotificationAction(id: 'reply', title: 'Reply'),
          ],
          enableReply: true,
          replyLabel: 'Type a reply...',
        );

        final map = config.toMap();

        expect(map['id'], equals('test'));
        expect(map['title'], equals('Test Title'));
        expect(map['style'], equals('bigText'));
        expect(map['enableReply'], isTrue);
        expect(map['replyLabel'], equals('Type a reply...'));
        expect(map['actions'], isNotNull);
      });
    });
  });
}
