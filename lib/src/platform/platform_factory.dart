import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/logger.dart';

// Platform-specific implementations
import 'background/background_service.dart';
import 'notification/notification_manager.dart';
import 'tray/tray_manager.dart';

// Native implementations
import 'background/android_enhanced_background.dart' as android_enhanced;
import 'background/ios_background.dart';
import 'background/desktop_background.dart';
import 'background/web_background.dart';
import 'notification/android_notification.dart';
import 'notification/ios_notification.dart';
import 'notification/web_notification.dart';
import 'notification/desktop_notification.dart';
import 'tray/macos_enhanced_tray.dart';
import 'tray/windows_tray.dart';
import 'tray/linux_tray.dart';
import 'storage/secure_storage.dart';
import 'storage/web_storage.dart';

/// Factory for creating platform-specific implementations
class PlatformFactory {
  final Logger _logger = Logger('flutter_mcp.platform_factory');

  /// Create appropriate background service for current platform
  BackgroundService createBackgroundService() {
    if (kIsWeb) {
      _logger.fine('Creating web background service');
      return WebBackgroundService();
    }

    try {
      if (io.Platform.isAndroid) {
        _logger.fine('Creating Android enhanced background service');
        return android_enhanced.AndroidEnhancedBackgroundService();
      } else if (io.Platform.isIOS) {
        _logger.fine('Creating iOS background service');
        return IOSBackgroundService();
      } else if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
        _logger.fine('Creating desktop background service');
        return DesktopBackgroundService();
      } else {
        _logger.warning('Unsupported platform for background service, using no-op implementation');
        return NoOpBackgroundService();
      }
    } catch (e) {
      _logger.warning('Error determining platform for background service: $e, using no-op implementation');
      return NoOpBackgroundService();
    }
  }

  /// Create appropriate notification manager for current platform
  NotificationManager createNotificationManager() {
    if (kIsWeb) {
      _logger.fine('Creating web notification manager');
      return WebNotificationManager();
    }

    try {
      if (io.Platform.isAndroid) {
        _logger.fine('Creating Android notification manager');
        return AndroidNotificationManager();
      } else if (io.Platform.isIOS) {
        _logger.fine('Creating iOS notification manager');
        return IOSNotificationManager();
      } else if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
        _logger.fine('Creating desktop notification manager');
        return DesktopNotificationManager();
      } else {
        _logger.warning('Unsupported platform for notification manager, using no-op implementation');
        return NoOpNotificationManager();
      }
    } catch (e) {
      _logger.warning('Error determining platform for notification manager: $e, using no-op implementation');
      return NoOpNotificationManager();
    }
  }

  /// Create appropriate tray manager for current platform
  TrayManager createTrayManager() {
    if (kIsWeb) {
      _logger.warning('Tray is not supported on web platform');
      return NoOpTrayManager();
    }

    try {
      if (io.Platform.isMacOS) {
        _logger.fine('Creating macOS enhanced tray manager');
        return MacOSEnhancedTrayManager();
      } else if (io.Platform.isWindows) {
        _logger.fine('Creating Windows tray manager');
        return WindowsTrayManager();
      } else if (io.Platform.isLinux) {
        _logger.fine('Creating Linux tray manager');
        return LinuxTrayManager();
      } else {
        _logger.warning('Unsupported platform for tray manager, using no-op implementation');
        return NoOpTrayManager();
      }
    } catch (e) {
      _logger.warning('Error determining platform for tray manager: $e, using no-op implementation');
      return NoOpTrayManager();
    }
  }

  /// Create appropriate storage manager for current platform
  SecureStorageManager createStorageManager() {
    if (kIsWeb) {
      _logger.fine('Creating web storage manager');
      return WebStorageManager(useLocalStorage: true);
    } else {
      _logger.fine('Creating secure storage manager');
      return SecureStorageManagerImpl();
    }
  }

  /// Check if the current platform supports a specific feature
  bool supportsFeature(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.background:
        if (kIsWeb) return true; // Limited web background support
        try {
          return io.Platform.isAndroid ||
              io.Platform.isIOS ||
              io.Platform.isMacOS ||
              io.Platform.isWindows ||
              io.Platform.isLinux;
        } catch (e) {
          return false;
        }

      case PlatformFeature.notification:
        if (kIsWeb) return true; // Web notifications API
        try {
          return io.Platform.isAndroid ||
              io.Platform.isIOS ||
              io.Platform.isMacOS ||
              io.Platform.isWindows ||
              io.Platform.isLinux;
        } catch (e) {
          return false;
        }

      case PlatformFeature.tray:
        if (kIsWeb) return false; // Web doesn't support system tray
        try {
          return io.Platform.isMacOS ||
              io.Platform.isWindows ||
              io.Platform.isLinux;
        } catch (e) {
          return false;
        }

      case PlatformFeature.secureStorage:
        return true; // All platforms have some form of storage
    }
  }

  /// Get current platform name
  String get platformName {
    if (kIsWeb) return 'Web';
    try {
      if (io.Platform.isAndroid) return 'Android';
      if (io.Platform.isIOS) return 'iOS';
      if (io.Platform.isWindows) return 'Windows';
      if (io.Platform.isMacOS) return 'macOS';
      if (io.Platform.isLinux) return 'Linux';
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }
}

/// Platform features enum
enum PlatformFeature {
  background,
  notification,
  tray,
  secureStorage,
}