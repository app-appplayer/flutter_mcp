/// 알림 설정
class NotificationConfig {
  /// 알림 채널 ID (Android)
  final String? channelId;

  /// 알림 채널 이름 (Android)
  final String? channelName;

  /// 알림 채널 설명 (Android)
  final String? channelDescription;

  /// 알림 아이콘
  final String? icon;

  /// 알림음 사용 여부
  final bool enableSound;

  /// 알림 진동 사용 여부
  final bool enableVibration;

  /// 알림 중요도
  final NotificationPriority priority;

  NotificationConfig({
    this.channelId,
    this.channelName,
    this.channelDescription,
    this.icon,
    this.enableSound = true,
    this.enableVibration = true,
    this.priority = NotificationPriority.normal,
  });
}

/// 알림 중요도
enum NotificationPriority {
  min,
  low,
  normal,
  high,
  max,
}