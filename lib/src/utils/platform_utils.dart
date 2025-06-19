import 'dart:io' as io;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'logger.dart';

/// Platform utility class with enhanced error handling and diagnostics
class PlatformUtils {
  static final Logger _logger = Logger('flutter_mcp.platform_utils');

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
      _logger.warning('Failed to determine platform name: $e');
      return 'Unknown';
    }
  }

  /// Check if running on mobile platform
  static bool get isMobile {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid || io.Platform.isIOS;
    } catch (e) {
      _logger.warning('Failed to check mobile platform: $e');
      return false;
    }
  }

  /// Check if running on desktop platform
  static bool get isDesktop {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows ||
          io.Platform.isMacOS ||
          io.Platform.isLinux;
    } catch (e) {
      _logger.warning('Failed to check desktop platform: $e');
      return false;
    }
  }

  /// Check if running on Windows
  static bool get isWindows {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows;
    } catch (e) {
      _logger.warning('Failed to check Windows platform: $e');
      return false;
    }
  }

  /// Check if running on macOS
  static bool get isMacOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isMacOS;
    } catch (e) {
      _logger.warning('Failed to check macOS platform: $e');
      return false;
    }
  }

  /// Check if running on Linux
  static bool get isLinux {
    if (kIsWeb) return false;
    try {
      return io.Platform.isLinux;
    } catch (e) {
      _logger.warning('Failed to check Linux platform: $e');
      return false;
    }
  }

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// Check if running on native platform (not web)
  static bool get isNative => !kIsWeb;

  /// Check if running on Android
  static bool get isAndroid {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid;
    } catch (e) {
      _logger.warning('Failed to check Android platform: $e');
      return false;
    }
  }

  /// Check if running on iOS
  static bool get isIOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isIOS;
    } catch (e) {
      _logger.warning('Failed to check iOS platform: $e');
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
        _logger
            .warning('Notifications not supported on platform: $platformName');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check notification support: $e');
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
      final supported =
          io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;

      if (!supported) {
        _logger.warning('System tray not supported on platform: $platformName');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check tray support: $e');
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
        _logger.warning(
            'Background service not supported on platform: $platformName');
      }
      return supported;
    } catch (e) {
      _logger.warning('Failed to check background service support: $e');
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

      // Get Android SDK version from platform channel
      final currentSdkVersion = await _getAndroidSdkVersion();
      if (currentSdkVersion == null) {
        // If we can't get the version, assume it's supported for backward compatibility
        return true;
      }

      return currentSdkVersion >= sdkVersion;
    } catch (e) {
      // If platform channel fails, fall back to operating system version parsing
      return _parseAndroidVersionFromOS(sdkVersion);
    }
  }

  /// Check if running on iOS with minimum version
  static Future<bool> isIOSAtLeast(String version) async {
    if (kIsWeb) return false;
    try {
      if (!io.Platform.isIOS) return false;

      // Get iOS version from platform channel
      final currentVersion = await _getIOSVersion();
      if (currentVersion == null) {
        // If we can't get the version, assume it's supported for backward compatibility
        return true;
      }

      return _compareVersions(currentVersion, version) >= 0;
    } catch (e) {
      // If platform channel fails, fall back to operating system version parsing
      return _parseIOSVersionFromOS(version);
    }
  }

  /// Get Android SDK version through platform channel
  static Future<int?> _getAndroidSdkVersion() async {
    try {
      if (!kIsWeb && io.Platform.isAndroid) {
        // Try to get from system properties first
        final androidInfo = await _getSystemProperty('ro.build.version.sdk');
        if (androidInfo != null) {
          return int.tryParse(androidInfo);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get iOS version through platform channel
  static Future<String?> _getIOSVersion() async {
    try {
      if (!kIsWeb && io.Platform.isIOS) {
        // Try to get from system version
        final versionString = io.Platform.operatingSystemVersion;
        final versionMatch =
            RegExp(r'Version (\d+\.\d+(?:\.\d+)?)').firstMatch(versionString);
        if (versionMatch != null) {
          return versionMatch.group(1);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get system property (Android)
  static Future<String?> _getSystemProperty(String property) async {
    try {
      if (!kIsWeb && io.Platform.isAndroid) {
        // Use Process to get system property
        final result = await io.Process.run('getprop', [property]);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse Android version from OS string (fallback)
  static bool _parseAndroidVersionFromOS(int targetSdkVersion) {
    try {
      final osVersion = io.Platform.operatingSystemVersion;
      // Try to extract version number from OS version string
      final versionMatch = RegExp(r'(\d+)').firstMatch(osVersion);
      if (versionMatch != null) {
        final majorVersion = int.tryParse(versionMatch.group(1) ?? '');
        if (majorVersion != null) {
          // Convert Android version to approximate SDK level
          // This is a rough mapping for fallback purposes
          final sdkLevel = _androidVersionToSdkLevel(majorVersion);
          return sdkLevel >= targetSdkVersion;
        }
      }
      // If we can't parse, assume supported
      return true;
    } catch (e) {
      return true;
    }
  }

  /// Parse iOS version from OS string (fallback)
  static bool _parseIOSVersionFromOS(String targetVersion) {
    try {
      final osVersion = io.Platform.operatingSystemVersion;
      // Try to extract version from OS version string
      final versionMatch =
          RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(osVersion);
      if (versionMatch != null) {
        final currentVersion = versionMatch.group(1) ?? '';
        return _compareVersions(currentVersion, targetVersion) >= 0;
      }
      // If we can't parse, assume supported
      return true;
    } catch (e) {
      return true;
    }
  }

  /// Convert Android version number to SDK level (rough mapping)
  static int _androidVersionToSdkLevel(int androidVersion) {
    // Rough mapping of Android versions to SDK levels
    switch (androidVersion) {
      case 4:
        return 14; // Android 4.0
      case 5:
        return 21; // Android 5.0
      case 6:
        return 23; // Android 6.0
      case 7:
        return 24; // Android 7.0
      case 8:
        return 26; // Android 8.0
      case 9:
        return 28; // Android 9.0
      case 10:
        return 29; // Android 10
      case 11:
        return 30; // Android 11
      case 12:
        return 31; // Android 12
      case 13:
        return 33; // Android 13
      case 14:
        return 34; // Android 14
      default:
        // For unknown versions, assume latest known + offset
        return androidVersion > 14 ? 34 + (androidVersion - 14) : 14;
    }
  }

  /// Compare version strings (e.g., "14.5" vs "15.0")
  static int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map(int.tryParse).toList();
    final v2Parts = version2.split('.').map(int.tryParse).toList();

    // Normalize lengths
    final maxLength = math.max(v1Parts.length, v2Parts.length);

    for (int i = 0; i < maxLength; i++) {
      final v1Part = i < v1Parts.length ? (v1Parts[i] ?? 0) : 0;
      final v2Part = i < v2Parts.length ? (v2Parts[i] ?? 0) : 0;

      if (v1Part > v2Part) return 1;
      if (v1Part < v2Part) return -1;
    }

    return 0; // Equal
  }

  /// Get detailed platform version information
  static Future<Map<String, dynamic>> getPlatformVersionInfo() async {
    final info = <String, dynamic>{
      'platform': platformName,
      'isWeb': kIsWeb,
    };

    if (!kIsWeb) {
      info['operatingSystemVersion'] = io.Platform.operatingSystemVersion;

      if (io.Platform.isAndroid) {
        info['androidSdkVersion'] = await _getAndroidSdkVersion();
        info['androidVersion'] =
            await _getSystemProperty('ro.build.version.release');
      } else if (io.Platform.isIOS) {
        info['iosVersion'] = await _getIOSVersion();
      }
    }

    return info;
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
