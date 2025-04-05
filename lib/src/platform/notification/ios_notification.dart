import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// iOS 알림 관리자 구현
class IOSNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.ios_notification');

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('iOS 알림 관리자 초기화');

    // iOS 알림 설정
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // iOS 권한 요청
    await _requestPermissions();
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('iOS 알림 표시: $title');

    // iOS 알림 설정
    DarwinNotificationDetails iOSPlatformChannelSpecifics =
    const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    NotificationDetails platformChannelSpecifics =
    NotificationDetails(iOS: iOSPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
      payload: id,
    );
  }

  @override
  Future<void> hideNotification(String id) async {
    _logger.debug('iOS 알림 숨김: $id');

    await _notificationsPlugin.cancel(0);
  }

  /// 알림 권한 요청
  Future<void> _requestPermissions() async {
    _logger.debug('iOS 알림 권한 요청');

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation
    IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// 알림 탭 핸들러
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('알림 탭됨: ${response.payload}');

    // 알림 탭 이벤트 처리
  }
}