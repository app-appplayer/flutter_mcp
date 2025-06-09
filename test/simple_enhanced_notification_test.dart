import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/notifications/enhanced_notification_manager.dart';
import 'package:flutter_mcp/src/platform/notification/notification_manager.dart';

class MockNotificationManager implements NotificationManager {
  final List<Map<String, dynamic>> shownNotifications = [];
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
  }) async {
    shownNotifications.add({
      'title': title,
      'body': body,
      'icon': icon,
      'id': id,
    });
  }

  @override
  Future<void> hideNotification(String id) async {
    // Mock implementation
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Enhanced Notification Manager Basic Tests', () {
    test('Should create notification config', () {
      final config = EnhancedNotificationConfig(
        id: 'test',
        title: 'Test Title',
        body: 'Test Body',
        style: NotificationStyle.basic,
      );

      expect(config.id, equals('test'));
      expect(config.title, equals('Test Title'));
      expect(config.body, equals('Test Body'));
      expect(config.style, equals(NotificationStyle.basic));
    });

    test('Should serialize notification config to map', () {
      final config = EnhancedNotificationConfig(
        id: 'test',
        title: 'Test Title',
        body: 'Test Body',
        style: NotificationStyle.bigText,
        enableReply: true,
        replyLabel: 'Reply here...',
      );

      final map = config.toMap();

      expect(map['id'], equals('test'));
      expect(map['title'], equals('Test Title'));
      expect(map['body'], equals('Test Body'));
      expect(map['style'], equals('bigText'));
      expect(map['enableReply'], isTrue);
      expect(map['replyLabel'], equals('Reply here...'));
    });

    test('Should create notification actions', () {
      final action = NotificationAction(
        id: 'reply',
        title: 'Reply',
        icon: 'reply_icon',
        requiresUnlock: true,
      );

      expect(action.id, equals('reply'));
      expect(action.title, equals('Reply'));
      expect(action.icon, equals('reply_icon'));
      expect(action.requiresUnlock, isTrue);

      final map = action.toMap();
      expect(map['id'], equals('reply'));
      expect(map['title'], equals('Reply'));
      expect(map['requiresUnlock'], isTrue);
    });

    test('Should create notification messages', () {
      final message = NotificationMessage(
        text: 'Hello!',
        sender: 'Alice',
        senderAvatar: 'avatar.png',
      );

      expect(message.text, equals('Hello!'));
      expect(message.sender, equals('Alice'));
      expect(message.senderAvatar, equals('avatar.png'));
      expect(message.timestamp, isNotNull);

      final map = message.toMap();
      expect(map['text'], equals('Hello!'));
      expect(map['sender'], equals('Alice'));
    });

    test('Should create media controls', () {
      final control = MediaControl(
        action: 'play',
        icon: 'play_icon',
        label: 'Play',
      );

      expect(control.action, equals('play'));
      expect(control.icon, equals('play_icon'));
      expect(control.label, equals('Play'));

      final map = control.toMap();
      expect(map['action'], equals('play'));
      expect(map['icon'], equals('play_icon'));
      expect(map['label'], equals('Play'));
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

    test('Should handle notification styles enum', () {
      expect(NotificationStyle.basic.name, equals('basic'));
      expect(NotificationStyle.bigText.name, equals('bigText'));
      expect(NotificationStyle.bigPicture.name, equals('bigPicture'));
      expect(NotificationStyle.inbox.name, equals('inbox'));
      expect(NotificationStyle.messaging.name, equals('messaging'));
      expect(NotificationStyle.media.name, equals('media'));
      expect(NotificationStyle.progress.name, equals('progress'));
    });
  });
}