/// 백그라운드 서비스 설정
class BackgroundConfig {
  /// 알림 채널 ID (Android)
  final String? notificationChannelId;

  /// 알림 채널 이름 (Android)
  final String? notificationChannelName;

  /// 알림 채널 설명 (Android)
  final String? notificationDescription;

  /// 알림 아이콘 (Android)
  final String? notificationIcon;

  /// 부팅 시 자동 시작 여부
  final bool autoStartOnBoot;

  /// 백그라운드 작업 간격 (밀리초)
  final int intervalMs;

  /// 연결 유지
  final bool keepAlive;

  BackgroundConfig({
    this.notificationChannelId,
    this.notificationChannelName,
    this.notificationDescription,
    this.notificationIcon,
    this.autoStartOnBoot = false,
    this.intervalMs = 5000,
    this.keepAlive = true,
  });

  /// 기본 설정 생성
  factory BackgroundConfig.defaultConfig() {
    return BackgroundConfig(
      notificationChannelId: 'flutter_mcp_channel',
      notificationChannelName: 'MCP Service',
      notificationDescription: 'MCP Background Service',
      autoStartOnBoot: false,
      intervalMs: 5000,
      keepAlive: true,
    );
  }
}