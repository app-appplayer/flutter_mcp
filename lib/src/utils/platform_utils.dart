import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform utility class
class PlatformUtils {
  /// Check if running on mobile platform
  static bool get isMobile {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid || io.Platform.isIOS;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on desktop platform
  static bool get isDesktop {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on macOS
  static bool get isMacOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isMacOS;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on Linux
  static bool get isLinux {
    if (kIsWeb) return false;
    try {
      return io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// Check if notifications are supported
  static bool get supportsNotifications {
    if (kIsWeb) return true; // Web supports notifications via Web API
    try {
      return io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// Check if tray is supported
  static bool get supportsTray {
    if (kIsWeb) return false; // Web doesn't support system tray
    try {
      return io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// Check if background service is supported
  static bool get supportsBackgroundService {
    if (kIsWeb) return true; // Web supports limited background functionality
    try {
      return io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on Android with minimum SDK version
  static Future<bool> isAndroidAtLeast(int sdkVersion) async {
    if (kIsWeb) return false;
    try {
      if (!io.Platform.isAndroid) return false;

      // Implementation would require platform channel to get Android SDK version
      // This is a placeholder implementation
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on iOS with minimum version
  static Future<bool> isIOSAtLeast(String version) async {
    if (kIsWeb) return false;
    try {
      if (!io.Platform.isIOS) return false;

      // Implementation would require platform channel to get iOS version
      // This is a placeholder implementation
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get platform name
  static String get platformName {
    if (kIsWeb) return 'Web';
    try {
      if (io.Platform.isAndroid) return 'Android';
      if (io.Platform.isIOS) return 'iOS';
      if (io.Platform.isWindows) return 'Windows';
      if (io.Platform.isMacOS) return 'macOS';
      if (io.Platform.isLinux) return 'Linux';
      if (io.Platform.isFuchsia) return 'Fuchsia';
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Check if secure storage is supported
  static bool get supportsSecureStorage {
    if (kIsWeb) return true; // Web supports secure storage via browser APIs
    try {
      return io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }
}