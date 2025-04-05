import 'dart:io';

/// 플랫폼 유틸리티 클래스
class PlatformUtils {
  /// 모바일 플랫폼 여부
  static bool get isMobile =>
      Platform.isAndroid || Platform.isIOS;

  /// 데스크탑 플랫폼 여부
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 알림 지원 여부
  static bool get supportsNotifications =>
      Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux;

  /// 트레이 지원 여부
  static bool get supportsTray => isDesktop;

  /// 백그라운드 서비스 지원 여부
  static bool get supportsBackgroundService =>
      Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux;

  /// 안드로이드 버전 확인
  static Future<bool> isAndroidAtLeast(int sdkVersion) async {
    if (!Platform.isAndroid) return false;

    try {
      // 안드로이드 플랫폼 정보 확인 로직 구현
      return true; // 실제 구현에서는 플랫폼 정보 확인
    } catch (e) {
      return false;
    }
  }

  /// iOS 버전 확인
  static Future<bool> isIOSAtLeast(String version) async {
    if (!Platform.isIOS) return false;

    try {
      // iOS 플랫폼 정보 확인 로직 구현
      return true; // 실제 구현에서는 플랫폼 정보 확인
    } catch (e) {
      return false;
    }
  }
}
