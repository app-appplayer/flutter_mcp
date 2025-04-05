import 'dart:io';
import '../config/mcp_config.dart';
import '../config/background_config.dart';
import '../config/notification_config.dart';
import '../config/tray_config.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart';

import 'background/background_service.dart';
import 'background/android_background.dart';
import 'background/ios_background.dart';
import 'background/desktop_background.dart';
import 'notification/notification_manager.dart';
import 'notification/android_notification.dart';
import 'notification/ios_notification.dart';
import 'tray/tray_manager.dart';
import 'tray/macos_tray.dart';
import 'tray/windows_tray.dart';
import 'lifecycle_manager.dart';
import '../storage/secure_storage.dart';

/// MCP 플랫폼 서비스 통합 클래스
class PlatformServices {
  // 플랫폼 서비스
  BackgroundService? _backgroundService;
  NotificationManager? _notificationManager;
  TrayManager? _trayManager;
  SecureStorageManager? _secureStorage;
  LifecycleManager? _lifecycleManager;

  bool _initialized = false;

  /// 로거
  final MCPLogger _logger = MCPLogger('mcp.platform_services');

  /// 백그라운드 서비스 실행 중 여부
  bool get isBackgroundServiceRunning => _backgroundService?.isRunning ?? false;

  /// 플랫폼 서비스 초기화
  Future<void> initialize(MCPConfig config) async {
    if (_initialized) return;

    _logger.debug('플랫폼 서비스 초기화');

    // 보안 저장소 초기화 (항상 초기화)
    _secureStorage = createSecureStorage();
    await _secureStorage!.initialize();

    // 플랫폼별 서비스 초기화
    if (config.useBackgroundService && PlatformUtils.supportsBackgroundService) {
      _backgroundService = createBackgroundService();
      await _backgroundService!.initialize(config.background);
    }

    if (config.useNotification && PlatformUtils.supportsNotifications) {
      _notificationManager = createNotificationManager();
      await _notificationManager!.initialize(config.notification);
    }

    if (config.useTray && PlatformUtils.supportsTray) {
      _trayManager = createTrayManager();
      await _trayManager!.initialize(config.tray);
    }

    if (config.lifecycleManaged) {
      _lifecycleManager = LifecycleManager();
      _lifecycleManager!.initialize();
    }

    _initialized = true;
  }

  /// 백그라운드 서비스 시작
  Future<bool> startBackgroundService() async {
    if (_backgroundService == null) {
      _logger.warning('백그라운드 서비스가 초기화되지 않았습니다');
      return false;
    }

    _logger.debug('백그라운드 서비스 시작');
    return await _backgroundService!.start();
  }

  /// 알림 표시
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
  }) async {
    if (_notificationManager == null) {
      _logger.warning('알림 관리자가 초기화되지 않았습니다');
      return;
    }

    _logger.debug('알림 표시: $title');
    await _notificationManager!.showNotification(
      title: title,
      body: body,
      icon: icon,
    );
  }

  /// 보안 저장소에 저장
  Future<void> secureStore(String key, String value) async {
    if (_secureStorage == null) {
      throw Exception('보안 저장소가 초기화되지 않았습니다');
    }

    _logger.debug('보안 저장소에 저장: $key');
    await _secureStorage!.saveString(key, value);
  }

  /// 보안 저장소에서 읽기
  Future<String?> secureRead(String key) async {
    if (_secureStorage == null) {
      throw Exception('보안 저장소가 초기화되지 않았습니다');
    }

    _logger.debug('보안 저장소에서 읽기: $key');
    return await _secureStorage!.readString(key);
  }

  /// 모든 서비스 종료
  Future<void> shutdown() async {
    _logger.debug('플랫폼 서비스 종료');

    if (_backgroundService != null) {
      await _backgroundService!.stop();
    }

    if (_trayManager != null) {
      await _trayManager!.dispose();
    }

    if (_lifecycleManager != null) {
      _lifecycleManager!.dispose();
    }
  }

  /// 플랫폼에 맞는 백그라운드 서비스 생성
  BackgroundService createBackgroundService() {
    if (Platform.isAndroid) {
      return AndroidBackgroundService();
    } else if (Platform.isIOS) {
      return IOSBackgroundService();
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return DesktopBackgroundService();
    } else {
      return NoOpBackgroundService();
    }
  }

  /// 플랫폼에 맞는 알림 관리자 생성
  NotificationManager createNotificationManager() {
    if (Platform.isAndroid) {
      return AndroidNotificationManager();
    } else if (Platform.isIOS) {
      return IOSNotificationManager();
    } else {
      return NoOpNotificationManager();
    }
  }

  /// 플랫폼에 맞는 트레이 관리자 생성
  TrayManager createTrayManager() {
    if (Platform.isMacOS) {
      return MacOSTrayManager();
    } else if (Platform.isWindows) {
      return WindowsTrayManager();
    } else {
      return NoOpTrayManager();
    }
  }

  /// 보안 저장소 관리자 생성
  SecureStorageManager createSecureStorage() {
    return SecureStorageManagerImpl();
  }
}