import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/logger.dart';
import '../storage/secure_storage.dart';

// Platform-specific implementations
import 'background/background_service.dart';
import 'notification/notification_manager.dart';
import 'tray/tray_manager.dart';

// Native implementations
import 'background/android_background.dart';
import 'background/ios_background.dart';
import 'background/desktop_background.dart';
import 'notification/android_notification.dart';
import 'notification/ios_notification.dart';
import 'notification/desktop_notification.dart';
import 'tray/macos_tray.dart';
import 'tray/windows_tray.dart';
import 'tray/linux_tray.dart';

// Web implementations
import 'web/web_background.dart';
import 'web/web_notification.dart';
import 'web/web_storage.dart';

/// Factory for creating platform-specific implementations
class PlatformFactory {
  final MCPLogger _logger = MCPLogger('mcp.platform_factory');

  /// Create appropriate background service for current platform
  BackgroundService createBackgroundService() {
    if (kIsWeb) {
      _logger.debug('Creating web background service');
      return WebBackgroundService();
    }

    if (io.Platform.isAndroid) {
      _logger.debug('Creating Android background service');
      return AndroidBackgroundService();
    } else if (io.Platform.isIOS) {
      _logger.debug('Creating iOS background service');
      return IOSBackgroundService();
    } else if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
      _logger.debug('Creating desktop background service');
      return DesktopBackgroundService();
    } else {
      _logger.warning('No background service implementation for current platform');
      return NoOpBackgroundService();
    }
  }

  /// Create appropriate notification manager for current platform
  NotificationManager createNotificationManager() {
    if (kIsWeb) {
      _logger.debug('Creating web notification manager');
      return WebNotificationManager();
    }

    if (io.Platform.isAndroid) {
      _logger.debug('Creating Android notification manager');
      return AndroidNotificationManager();
    } else if (io.Platform.isIOS) {
      _logger.debug('Creating iOS notification manager');
      return IOSNotificationManager();
    } else if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
      _logger.debug('Creating desktop notification manager');
      return DesktopNotificationManager();
    } else {
      _logger.warning('No notification manager implementation for current platform');
      return NoOpNotificationManager();
    }
  }

  /// Create appropriate tray manager for current platform
  TrayManager createTrayManager() {
    if (kIsWeb) {
      _logger.warning('Tray is not supported on web platform');
      return NoOpTrayManager();
    }

    if (io.Platform.isMacOS) {
      _logger.debug('Creating macOS tray manager');
      return MacOSTrayManager();
    } else if (io.Platform.isWindows) {
      _logger.debug('Creating Windows tray manager');
      return WindowsTrayManager();
    } else if (io.Platform.isLinux) {
      _logger.debug('Creating Linux tray manager');
      return LinuxTrayManager();
    } else {
      _logger.warning('No tray manager implementation for current platform');
      return NoOpTrayManager();
    }
  }

  /// Create appropriate storage manager for current platform
  SecureStorageManager createStorageManager() {
    if (kIsWeb) {
      _logger.debug('Creating web storage manager');
      // Ensure WebStorageManager implements SecureStorageManager
      return WebStorageManager();
    } else {
      _logger.debug('Creating secure storage manager');
      // Use SecureStorageManagerImpl from secure_storage.dart
      return SecureStorageManagerImpl();
    }
  }

  /// Check if the current platform supports a specific feature
  bool supportsFeature(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.background:
        return kIsWeb || io.Platform.isAndroid || io.Platform.isIOS ||
            io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;

      case PlatformFeature.notification:
        return kIsWeb || io.Platform.isAndroid || io.Platform.isIOS ||
            io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux;

      case PlatformFeature.tray:
        return !kIsWeb && (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux);

      case PlatformFeature.secureStorage:
        return true; // All platforms have some form of storage
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