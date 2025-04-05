import '../../config/notification_config.dart';

/// 알림 관리자 인터페이스
abstract class NotificationManager {
  /// 알림 관리자 초기화
  Future<void> initialize(NotificationConfig? config);

  /// 알림 표시
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  });

  /// 알림 숨김
  Future<void> hideNotification(String id);
}

/// 기능 없는 알림 관리자 (지원하지 않는 플랫폼용)
class NoOpNotificationManager implements NotificationManager {
  @override
  Future<void> initialize(NotificationConfig? config) async {}

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {}

  @override
  Future<void> hideNotification(String id) async {}
}