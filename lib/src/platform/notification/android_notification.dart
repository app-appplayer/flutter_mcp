import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../config/notification_config.dart';
import '../../utils/logger.dart';
import 'notification_manager.dart';

/// 안드로이드 알림 관리자 구현
class AndroidNotificationManager implements NotificationManager {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final MCPLogger _logger = MCPLogger('mcp.android_notification');

  String _channelId = 'flutter_mcp_channel';
  String _channelName = 'MCP Notifications';
  String _channelDescription = 'Notifications from MCP';

  @override
  Future<void> initialize(NotificationConfig? config) async {
    _logger.debug('안드로이드 알림 관리자 초기화');

    if (config != null) {
      _channelId = config.channelId ?? _channelId;
      _channelName = config.channelName ?? _channelName;
      _channelDescription = config.channelDescription ?? _channelDescription;
    }

    // 안드로이드 알림 설정
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('app_icon');

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    _logger.debug('안드로이드 알림 표시: $title');

    // 안드로이드 알림 채널 설정
    AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

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
    _logger.debug('안드로이드 알림 숨김: $id');

    await _notificationsPlugin.cancel(0); // ID에 따라 여러 알림 관리 가능
  }

  /// 알림 탭 핸들러
  void _onNotificationTap(NotificationResponse response) {
    _logger.debug('알림 탭됨: ${response.payload}');

    // 알림 탭 이벤트 처리
    // 예: 앱을 포그라운드로 가져오기, 특정 화면으로 이동 등
  }
}