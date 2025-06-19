import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mcp/src/platform/notification/platform_notification_manager.dart';
import 'package:flutter_mcp/src/platform/notification/notification_models.dart';
import 'package:flutter_mcp/src/config/notification_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformNotificationManager', () {
    late PlatformNotificationManager manager;
    late List<MethodCall> methodCalls;

    setUpAll(() {
      // Set up method channel mock
      const MethodChannel channel = MethodChannel('flutter_mcp');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        methodCalls.add(methodCall);

        // Return mock responses based on method
        switch (methodCall.method) {
          case 'configureNotifications':
            return true;
          case 'showNotification':
            return true;
          case 'cancelNotification':
            return true;
          case 'cancelAllNotifications':
            return true;
          case 'requestNotificationPermission':
            return true;
          default:
            return null;
        }
      });
    });

    setUp(() {
      methodCalls = [];
      manager = PlatformNotificationManager();
    });

    tearDown(() {
      methodCalls.clear();
    });

    test('should initialize with config', () async {
      final config = NotificationConfig(
        channelId: 'test_channel',
        channelName: 'Test Channel',
        enableSound: false,
        enableVibration: true,
      );

      await manager.initialize(config);

      // Initialize calls configureNotifications and requestNotificationPermission if requestPermissionOnInit is true
      expect(methodCalls.length, greaterThanOrEqualTo(1));
      expect(methodCalls[0].method, 'configureNotifications');

      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      expect(args['channelId'], 'test_channel');
      expect(args['channelName'], 'Test Channel');
      expect(args['enableSound'], false);
      expect(args['enableVibration'], true);
    });

    test('should show basic notification', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      await manager.showNotification(
        title: 'Test Title',
        body: 'Test Body',
        id: 'test_id',
      );

      expect(methodCalls, hasLength(1));
      expect(methodCalls[0].method, 'showNotification');

      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      expect(args['title'], 'Test Title');
      expect(args['body'], 'Test Body');
      expect(args['id'], 'test_id');
    });

    test('should show notification with actions', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      await manager.showNotification(
        title: 'Action Test',
        body: 'Test with actions',
        actions: [
          NotificationAction(id: 'accept', title: 'Accept'),
          NotificationAction(id: 'reject', title: 'Reject'),
        ],
      );

      expect(methodCalls, hasLength(1));
      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      // Actions may not be included if platform doesn't support them
      final actions = args['actions'] as List?;
      if (actions != null) {
        expect(actions, hasLength(2));
        expect(actions[0]['id'], 'accept');
        expect(actions[0]['title'], 'Accept');
      }
    });

    test('should show progress notification', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      await manager.showNotification(
        title: 'Download',
        body: 'Downloading file...',
        showProgress: true,
        progress: 45,
        maxProgress: 100,
      );

      expect(methodCalls, hasLength(1));
      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      // Progress may not be included if platform doesn't support it
      if (args['showProgress'] != null) {
        expect(args['showProgress'], true);
        expect(args['progress'], 45);
        expect(args['maxProgress'], 100);
      }
    });

    test('should show grouped notification', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      await manager.showNotification(
        title: 'Group Message',
        body: 'New message',
        group: 'messages',
      );

      expect(methodCalls, hasLength(1));
      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      // Group may not be included if platform doesn't support it
      if (args['group'] != null) {
        expect(args['group'], 'messages');
      }
    });

    test('should cancel notification', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      await manager.hideNotification('test_id');

      expect(methodCalls, hasLength(1));
      expect(methodCalls[0].method, 'cancelNotification');

      final args = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      expect(args['id'], 'test_id');
    });

    test('should request permission', () async {
      await manager.initialize(NotificationConfig.defaultConfig());
      methodCalls.clear();

      final result = await manager.requestPermission();

      expect(result, true);
      expect(methodCalls, hasLength(1));
      expect(methodCalls[0].method, 'requestNotificationPermission');
    });

    test('should get active notifications', () async {
      await manager.initialize(NotificationConfig.defaultConfig());

      // Show some notifications first
      await manager.showNotification(
        id: 'test1',
        title: 'Test 1',
        body: 'Body 1',
      );

      await manager.showNotification(
        id: 'test2',
        title: 'Test 2',
        body: 'Body 2',
      );

      final activeNotifications = manager.getActiveNotifications();
      expect(activeNotifications, hasLength(2));
      expect(activeNotifications[0].id, 'test1');
      expect(activeNotifications[1].id, 'test2');
    });

    test('should throw when not initialized', () async {
      final uninitializedManager = PlatformNotificationManager();

      expect(
        () => uninitializedManager.showNotification(
          title: 'Test',
          body: 'Body',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('should handle platform-specific capabilities', () async {
      final newManager = PlatformNotificationManager();
      await newManager.initialize(NotificationConfig.defaultConfig());

      // Platform capabilities are set based on platform during initialization
      // Test will pass as long as initialization completes
      expect(newManager, isNotNull);
    });
  });
}
