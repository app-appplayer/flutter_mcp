import 'dart:async';

import '../config/mcp_config.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart' show PlatformUtils;
import '../utils/error_recovery.dart';
import '../utils/exceptions.dart';

import 'background/background_service.dart';
import 'notification/notification_manager.dart';
import 'tray/tray_manager.dart';
import 'lifecycle_manager.dart';
import 'storage/secure_storage.dart';
import 'platform_factory.dart';

/// MCP platform services integration class
class PlatformServices {
  // Platform services
  BackgroundService? _backgroundService;
  NotificationManager? _notificationManager;
  TrayManager? _trayManager;
  SecureStorageManager? _secureStorage;
  LifecycleManager? _lifecycleManager;

  bool _initialized = false;
  //MCPConfig? _config;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.platform_services');

  /// Platform factory
  final PlatformFactory _factory = PlatformFactory();

  /// Resource cleanup callbacks
  final List<Future<void> Function()> _cleanupCallbacks = [];

  /// Background service running status
  bool get isBackgroundServiceRunning => _backgroundService?.isRunning ?? false;

  /// Initialize platform services
  Future<void> initialize(MCPConfig config) async {
    if (_initialized) {
      _logger.warning('Platform services already initialized');
      return;
    }

    _logger.debug('Initializing platform services');
    //_config = config;

    try {
      // Initialize secure storage
      if(config.secure) {
        await _initializeSecureStorage(config);
      }

      // Initialize platform-specific services with improved error handling
      if (config.useBackgroundService) {
        if (PlatformUtils.supportsBackgroundService) {
          await _initializeBackgroundService(config);
        } else {
          _logger.warning('Background service requested but not supported on this platform: ${PlatformUtils.platformName}');
          throw MCPPlatformNotSupportedException(
            'background',
            errorCode: 'BACKGROUND_SERVICE_UNSUPPORTED',
            context: {'platform': PlatformUtils.platformName},
            resolution: 'Disable background service in config for this platform or use a supported platform'
          );
        }
      }

      if (config.useNotification) {
        if (PlatformUtils.supportsNotifications) {
          await _initializeNotificationManager(config);
        } else {
          _logger.warning('Notifications requested but not supported on this platform: ${PlatformUtils.platformName}');
          throw MCPPlatformNotSupportedException(
            'notifications',
            errorCode: 'NOTIFICATIONS_UNSUPPORTED',
            context: {'platform': PlatformUtils.platformName},
            resolution: 'Disable notifications in config for this platform or use a supported platform'
          );
        }
      }

      if (config.useTray) {
        if (PlatformUtils.supportsTray) {
          await _initializeTrayManager(config);
        } else {
          _logger.warning('System tray requested but not supported on this platform: ${PlatformUtils.platformName}');
          throw MCPPlatformNotSupportedException(
            'tray',
            errorCode: 'TRAY_UNSUPPORTED',
            context: {'platform': PlatformUtils.platformName},
            resolution: 'Disable system tray in config for this platform or use a supported platform'
          );
        }
      }

      if (config.lifecycleManaged) {
        _initializeLifecycleManager();
      }

      _initialized = true;
      _logger.info('Platform services initialization completed');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize platform services', e, stackTrace);
      await _cleanupOnError();
      throw MCPInitializationException('Failed to initialize platform services', e, stackTrace);
    }
  }

  /// Initialize secure storage
  Future<void> _initializeSecureStorage(MCPConfig config) async {
    _logger.debug('Initializing secure storage');

    try {
      _secureStorage = _factory.createStorageManager();
      await _secureStorage!.initialize();

      // Add cleanup callback
      _cleanupCallbacks.add(() async {
        _logger.debug('Cleaning up secure storage');
        // No specific cleanup needed for storage
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize secure storage', e, stackTrace);
      throw MCPInitializationException('Failed to initialize secure storage', e, stackTrace);
    }
  }

  /// Initialize background service
  Future<void> _initializeBackgroundService(MCPConfig config) async {
    _logger.debug('Initializing background service');

    try {
      _backgroundService = _factory.createBackgroundService();
      await ErrorRecovery.tryWithRetry(
            () => _backgroundService!.initialize(config.background),
        operationName: 'initialize background service',
        maxRetries: 2,
      );

      // Add cleanup callback
      _cleanupCallbacks.add(() async {
        _logger.debug('Stopping background service');
        if (_backgroundService != null && _backgroundService!.isRunning) {
          await _backgroundService!.stop();
        }
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize background service', e, stackTrace);
      throw MCPInitializationException('Failed to initialize background service', e, stackTrace);
    }
  }

  /// Initialize notification manager
  Future<void> _initializeNotificationManager(MCPConfig config) async {
    _logger.debug('Initializing notification manager');

    try {
      _notificationManager = _factory.createNotificationManager();
      await ErrorRecovery.tryWithRetry(
            () => _notificationManager!.initialize(config.notification),
        operationName: 'initialize notification manager',
        maxRetries: 2,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize notification manager', e, stackTrace);
      throw MCPInitializationException('Failed to initialize notification manager', e, stackTrace);
    }
  }

  /// Initialize tray manager
  Future<void> _initializeTrayManager(MCPConfig config) async {
    _logger.debug('Initializing tray manager');

    try {
      _trayManager = _factory.createTrayManager();
      await ErrorRecovery.tryWithRetry(
            () => _trayManager!.initialize(config.tray),
        operationName: 'initialize tray manager',
        maxRetries: 2,
      );

      // Add cleanup callback
      _cleanupCallbacks.add(() async {
        _logger.debug('Disposing tray manager');
        if (_trayManager != null) {
          await _trayManager!.dispose();
        }
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize tray manager', e, stackTrace);
      throw MCPInitializationException('Failed to initialize tray manager', e, stackTrace);
    }
  }

  /// Initialize lifecycle manager
  void _initializeLifecycleManager() {
    _logger.debug('Initializing lifecycle manager');

    try {
      _lifecycleManager = LifecycleManager();
      _lifecycleManager!.initialize();

      // Add cleanup callback
      _cleanupCallbacks.add(() async {
        _logger.debug('Disposing lifecycle manager');
        if (_lifecycleManager != null) {
          _lifecycleManager!.dispose();
        }
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize lifecycle manager', e, stackTrace);
      throw MCPInitializationException('Failed to initialize lifecycle manager', e, stackTrace);
    }
  }

  /// Start background service
  Future<bool> startBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_backgroundService == null) {
      _logger.warning('Background service not initialized');
      return false;
    }

    _logger.debug('Starting background service');
    return await ErrorRecovery.tryWithRetry(
          () => _backgroundService!.start(),
      operationName: 'start background service',
      maxRetries: 2,
    );
  }

  /// Stop background service
  Future<bool> stopBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_backgroundService == null) {
      _logger.warning('Background service not initialized');
      return false;
    }

    _logger.debug('Stopping background service');
    return await ErrorRecovery.tryWithRetry(
          () => _backgroundService!.stop(),
      operationName: 'stop background service',
      maxRetries: 2,
    );
  }

  /// Show notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_notificationManager == null) {
      _logger.warning('Notification manager not initialized');
      return;
    }

    _logger.debug('Showing notification: $title');
    await ErrorRecovery.tryWithRetry(
          () => _notificationManager!.showNotification(
        title: title,
        body: body,
        icon: icon,
        id: id,
      ),
      operationName: 'show notification',
      maxRetries: 2,
    );
  }

  /// Hide notification
  Future<void> hideNotification(String id) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_notificationManager == null) {
      _logger.warning('Notification manager not initialized');
      return;
    }

    _logger.debug('Hiding notification: $id');
    await ErrorRecovery.tryWithRetry(
          () => _notificationManager!.hideNotification(id),
      operationName: 'hide notification',
      maxRetries: 2,
    );
  }

  /// Store value securely
  Future<void> secureStore(String key, String value) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_secureStorage == null) {
      throw MCPException('Secure storage not initialized');
    }

    _logger.debug('Storing secure value: $key');
    await ErrorRecovery.tryWithRetry(
          () => _secureStorage!.saveString(key, value),
      operationName: 'store secure value',
      maxRetries: 2,
    );
  }

  /// Read value from secure storage
  Future<String?> secureRead(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_secureStorage == null) {
      throw MCPException('Secure storage not initialized');
    }

    _logger.debug('Reading secure value: $key');
    return await ErrorRecovery.tryWithRetry(
          () => _secureStorage!.readString(key),
      operationName: 'read secure value',
      maxRetries: 2,
    );
  }

  /// Delete from secure storage
  Future<bool> secureDelete(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_secureStorage == null) {
      throw MCPException('Secure storage not initialized');
    }

    _logger.debug('Deleting secure value: $key');
    return await ErrorRecovery.tryWithRetry(
          () => _secureStorage!.delete(key),
      operationName: 'delete secure value',
      maxRetries: 2,
    );
  }

  /// Check if secure storage contains key
  Future<bool> secureContains(String key) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_secureStorage == null) {
      throw MCPException('Secure storage not initialized');
    }

    return await ErrorRecovery.tryWithRetry(
          () => _secureStorage!.containsKey(key),
      operationName: 'check secure key',
      maxRetries: 2,
    );
  }

  /// Set tray menu items
  Future<void> setTrayMenu(List<TrayMenuItem> items) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_trayManager == null) {
      _logger.warning('Tray manager not initialized');
      return;
    }

    _logger.debug('Setting tray menu items');
    await ErrorRecovery.tryWithRetry(
          () => _trayManager!.setContextMenu(items),
      operationName: 'set tray menu',
      maxRetries: 2,
    );
  }

  /// Set tray icon
  Future<void> setTrayIcon(String path) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_trayManager == null) {
      _logger.warning('Tray manager not initialized');
      return;
    }

    _logger.debug('Setting tray icon: $path');
    await ErrorRecovery.tryWithRetry(
          () => _trayManager!.setIcon(path),
      operationName: 'set tray icon',
      maxRetries: 2,
    );
  }

  /// Set tray tooltip
  Future<void> setTrayTooltip(String tooltip) async {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_trayManager == null) {
      _logger.warning('Tray manager not initialized');
      return;
    }

    _logger.debug('Setting tray tooltip: $tooltip');
    await ErrorRecovery.tryWithRetry(
          () => _trayManager!.setTooltip(tooltip),
      operationName: 'set tray tooltip',
      maxRetries: 2,
    );
  }

  /// Set lifecycle change listener
  void setLifecycleChangeListener(Function(dynamic) listener) {
    if (!_initialized) {
      throw MCPException('Platform services not initialized');
    }

    if (_lifecycleManager == null) {
      _logger.warning('Lifecycle manager not initialized');
      return;
    }

    _logger.debug('Setting lifecycle change listener');
    _lifecycleManager!.setLifecycleChangeListener(listener);
  }

  /// Shut down all services
  Future<void> shutdown() async {
    _logger.debug('Shutting down platform services');

    // Execute all cleanup callbacks in reverse order
    for (final callback in _cleanupCallbacks.reversed) {
      try {
        await callback();
      } catch (e, stackTrace) {
        _logger.error('Error during cleanup', e, stackTrace);
      }
    }

    _cleanupCallbacks.clear();
    _initialized = false;
    _logger.info('Platform services shutdown completed');
  }

  /// Clean up resources on initialization error
  Future<void> _cleanupOnError() async {
    _logger.debug('Cleaning up after initialization error');

    // Execute all cleanup callbacks added so far
    for (final callback in _cleanupCallbacks.reversed) {
      try {
        await callback();
      } catch (e) {
        _logger.error('Error during error cleanup', e);
      }
    }

    _cleanupCallbacks.clear();
  }

  /// Get current platform name
  String get platformName => PlatformUtils.platformName;
}