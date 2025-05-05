import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'logger.dart';

/// Platform utility class with enhanced error handling and diagnostics
class PlatformUtils {
  static final MCPLogger _logger = MCPLogger('mcp.platform_utils');
  
  /// Current platform name for diagnostic purposes
  static String get platformName {
    if (kIsWeb) return 'Web';
    try {
      if (io.Platform.isAndroid) return 'Android';
      if (io.Platform.isIOS) return 'iOS';
      if (io.Platform.isMacOS) return 'macOS';
      if (io.Platform.isWindows) return 'Windows';
      if (io.Platform.isLinux) return 'Linux';
      if (io.Platform.isFuchsia) return 'Fuchsia';
      return 'Unknown';
    } catch (e) {
      _logger.warning('Failed to determine platform name', e);
      return 'Unknown';
    }
  }
  
  /// Check if running on mobile platform
  static bool get isMobile {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid || io.Platform.isIOS;
    } catch (e) {
      _logger.warning('Failed to check mobile platform', e);
      return false;
    }
  }

  /// Check if running on desktop platform
  static bool get isDesktop {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux;
    } catch (e) {
      _logger.warning('Failed to check desktop platform', e);
      return false;
    }
  }

  /// Check if running on Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows;
    } catch (e) {
      _logger.warning('Failed to check Windows platform', e);
      return false;
    }
  }

  /// Check if running on macOS
  static bool get isMacOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isMacOS;
    } catch (e) {
      _logger.warning('Failed to check macOS platform', e);
      return false;
    }
  }

  /// Check if running on Linux
  static bool get isLinux {
    if (kIsWeb) return false;
    try {
      return io.Platform.isLinux;
    } catch (e) {
      _logger.warning('Failed to check Linux platform', e);
      return false;
    }
  }

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;
  
  /// Check if running on Android
  static bool get isAndroid {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid;
    } catch (e) {
      _logger.warning('Failed to check Android platform', e);
      return false;
    }
  }
  
  /// Check if running on iOS
  static bool get isIOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isIOS;
    } catch (e) {
      _logger.warning('Failed to check iOS platform', e);
      return false;
    }
  }

  /// Check if notifications are supported
  static bool get supportsNotifications {
    if (kIsWeb) return true; // Web supports notifications via Web API
    try {
      final supported = io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
      
      if (!supported) {
        _logger.warning('Notifications not supported on platform: ${platformName}');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check notification support', e);
      return false;
    }
  }

  /// Check if tray is supported
  static bool get supportsTray {
    if (kIsWeb) {
      _logger.info('System tray not supported on Web');
      return false;
    }
    
    try {
      final supported = io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;
      
      if (!supported) {
        _logger.warning('System tray not supported on platform: ${platformName}');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check tray support', e);
      return false;
    }
  }

  /// Check if background service is supported
  static bool get supportsBackgroundService {
    if (kIsWeb) {
      _logger.info('Web supports limited background functionality');
      return true;
    }
    
    try {
      final supported = io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux;
          
      if (!supported) {
        _logger.warning('Background service not supported on platform: ${platformName}');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check background service support', e);
      return false;
    }
  }
  
  /// Checks if a feature is supported on the current platform
  static bool isFeatureSupported(String feature) {
    switch (feature.toLowerCase()) {
      case 'notifications':
        return supportsNotifications;
      case 'tray':
        return supportsTray;
      case 'background':
        return supportsBackgroundService;
      case 'secure_storage':
        return !kIsWeb; // All non-web platforms support secure storage
      default:
        _logger.warning('Unknown feature to check: $feature');
        return false;
    }
  }
  
  /// Get a map of platform features and their support status
  static Map<String, bool> getFeatureSupport() {
    return {
      'notifications': supportsNotifications,
      'tray': supportsTray,
      'background': supportsBackgroundService,
      'secure_storage': !kIsWeb,
      'web': isWeb,
      'mobile': isMobile,
      'desktop': isDesktop,
    };
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

  // Platform name is already defined at the top of this class

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