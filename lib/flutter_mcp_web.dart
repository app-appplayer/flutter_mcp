import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_mcp_platform_interface.dart';
import 'src/config/mcp_config.dart';
import 'src/platform/background/web_background.dart';
import 'src/platform/notification/web_notification.dart';
import 'src/platform/storage/web_storage.dart';
import 'src/utils/logger.dart';
import 'src/utils/exceptions.dart';

/// A web implementation of the FlutterMcpPlatform of the FlutterMcp plugin.
class FlutterMcpWeb extends FlutterMcpPlatform {
  // Logger
  final MCPLogger _logger = MCPLogger('flutter_mcp_web');

  // Web-specific services
  WebBackgroundService? _backgroundService;
  WebNotificationManager? _notificationManager;
  WebStorageManager? _storageManager;

  // Plugin state
  bool _initialized = false;
  //MCPConfig? _config;

  /// Constructs a FlutterMcpWeb
  FlutterMcpWeb();

  static void registerWith(Registrar registrar) {
    FlutterMcpPlatform.instance = FlutterMcpWeb();
  }

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
    try {
      final version = web.window.navigator.userAgent;
      return version;
    } catch (e, stackTrace) {
      _logger.error('Failed to get platform version', e, stackTrace);
      return 'Unknown';
    }
  }

  /// Initialize the plugin on web platform
  @override
  Future<void> initialize(MCPConfig config) async {
    if (_initialized) {
      _logger.warning('Web platform is already initialized');
      return;
    }

    //_config = config;
    _logger.debug('Initializing FlutterMCP for web platform');

    try {
      // Initialize platform services
      if (config.useBackgroundService) {
        _logger.debug('Initializing web background service');
        _backgroundService = WebBackgroundService();
        await _backgroundService!.initialize(config.background);
      }

      if (config.useNotification) {
        _logger.debug('Initializing web notification manager');
        _notificationManager = WebNotificationManager();
        await _notificationManager!.initialize(config.notification);
      }

      if (config.secure) {
        _logger.debug('Initializing web storage manager');
        _storageManager = WebStorageManager(useLocalStorage: true);
        await _storageManager!.initialize();
      }

      _initialized = true;
      _logger.info('Web platform initialization completed');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize web platform', e, stackTrace);
      throw MCPInitializationException('Failed to initialize web platform', e, stackTrace);
    }
  }

  /// Start background service
  @override
  Future<bool> startBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Web platform is not initialized');
    }

    if (_backgroundService == null) {
      _logger.warning('Background service is not available');
      return false;
    }

    return await _backgroundService!.start();
  }

  /// Stop background service
  @override
  Future<bool> stopBackgroundService() async {
    if (!_initialized) {
      throw MCPException('Web platform is not initialized');
    }

    if (_backgroundService == null) {
      _logger.warning('Background service is not available');
      return false;
    }

    return await _backgroundService!.stop();
  }

  /// Show notification
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    if (!_initialized) {
      throw MCPException('Web platform is not initialized');
    }

    if (_notificationManager == null) {
      _logger.warning('Notification manager is not available');
      return;
    }

    await _notificationManager!.showNotification(
      title: title,
      body: body,
      icon: icon,
      id: id,
    );
  }

  /// Store a value securely
  @override
  Future<void> secureStore(String key, String value) async {
    if (!_initialized) {
      throw MCPException('Web platform is not initialized');
    }

    if (_storageManager == null) {
      _logger.warning('Storage manager is not available');
      return;
    }

    await _storageManager!.saveString(key, value);
  }

  /// Read a value from secure storage
  @override
  Future<String?> secureRead(String key) async {
    if (!_initialized) {
      throw MCPException('Web platform is not initialized');
    }

    if (_storageManager == null) {
      _logger.warning('Storage manager is not available');
      return null;
    }

    return await _storageManager!.readString(key);
  }

  /// Check if background service is running
  @override
  bool get isBackgroundServiceRunning {
    return _backgroundService?.isRunning ?? false;
  }

  /// Shutdown all services
  @override
  Future<void> shutdown() async {
    if (!_initialized) return;

    _logger.debug('Shutting down web platform');

    if (_backgroundService != null) {
      await _backgroundService!.stop();
    }

    _initialized = false;
  }
}