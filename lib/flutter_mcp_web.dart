import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:universal_html/html.dart' as web;

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
  
  /// Returns status of web platform capabilities
  Map<String, dynamic> getWebCapabilities() {
    return {
      'supportsBackgroundService': _supportsBackgroundService(),
      'supportsNotifications': _supportsNotifications(),
      'supportsLocalStorage': _supportsLocalStorage(),
      'supportsMCP': false, // Web platform has limited MCP capabilities
    };
  }
  
  /// Check if background service is supported
  bool _supportsBackgroundService() {
    try {
      return web.window.navigator.serviceWorker != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Check if notifications are supported
  bool _supportsNotifications() {
    try {
      return web.Notification.permission != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Check if local storage is supported
  bool _supportsLocalStorage() {
    try {
      // Just try to access localStorage property to see if it's available
      web.window.localStorage;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Initialize the plugin on web platform
  @override
  Future<void> initialize(MCPConfig config) async {
    if (_initialized) {
      _logger.info('Web platform is already initialized');
      return;
    }

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
      _logger.debug('Background service is not available');
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
      _logger.debug('Background service is not available');
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
      _logger.debug('Notification manager is not available');
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
      _logger.debug('Storage manager is not available');
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
      _logger.debug('Storage manager is not available');
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

    try {
      // Stop background service if running
      if (_backgroundService != null) {
        await _backgroundService!.stop();
        _backgroundService = null;
      }
      
      // Clean up notification handlers if any
      if (_notificationManager != null) {
        _notificationManager = null;
      }
      
      _initialized = false;
      _logger.info('Web platform shutdown complete');
    } catch (e, stackTrace) {
      _logger.error('Error during web platform shutdown', e, stackTrace);
      // Still mark as not initialized
      _initialized = false;
    }
  }
  
  /// [UNSUPPORTED ON WEB] Create an MCP server
  Future<String> createServer({
    required String name,
    required String version,
    dynamic capabilities,
    Map<String, dynamic>? options,
  }) async {
    _logger.debug('Server creation not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'MCP Server creation is not supported on web platform',
      errorCode: 'WEB_SERVER_NOT_SUPPORTED',
    );
  }
  
  /// [UNSUPPORTED ON WEB] Create an MCP client
  Future<String> createClient({
    required String name,
    required String version,
    dynamic capabilities,
    String? transportCommand,
    List<String>? transportArgs,
    Map<String, dynamic>? options,
  }) async {
    _logger.debug('Client creation not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'MCP Client creation is not supported on web platform',
      errorCode: 'WEB_CLIENT_NOT_SUPPORTED',
    );
  }
  
  /// [UNSUPPORTED ON WEB] Connect an MCP server
  Future<bool> connectServer(String serverId) async {
    _logger.debug('Server connection not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'MCP Server connection is not supported on web platform',
      errorCode: 'WEB_SERVER_NOT_SUPPORTED',
    );
  }
  
  /// [UNSUPPORTED ON WEB] Connect an MCP client
  Future<bool> connectClient(String clientId) async {
    _logger.debug('Client connection not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'MCP Client connection is not supported on web platform',
      errorCode: 'WEB_CLIENT_NOT_SUPPORTED',
    );
  }
  
  /// [UNSUPPORTED ON WEB] Create and configure an LLM
  Future<String> createLlm({
    required String providerName,
    required dynamic config,
    Map<String, dynamic>? options,
  }) async {
    _logger.debug('LLM creation not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'LLM creation is not supported on web platform',
      errorCode: 'WEB_LLM_NOT_SUPPORTED',
    );
  }
  
  /// [UNSUPPORTED ON WEB] Send a chat message to LLM
  Future<dynamic> chat(
    String llmId,
    String userInput, {
    Map<String, dynamic>? options,
  }) async {
    _logger.debug('LLM chat not supported on web platform');
    throw MCPPlatformNotSupportedException(
      'LLM chat is not supported on web platform',
      errorCode: 'WEB_LLM_NOT_SUPPORTED',
    );
  }
  
  /// Get web platform status information
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _initialized,
      'platform': 'web',
      'backgroundServiceRunning': _backgroundService?.isRunning ?? false,
      'notificationsSupported': _supportsNotifications(),
      'storageSupported': _supportsLocalStorage(),
      'backgroundServiceSupported': _supportsBackgroundService(),
      'limitations': [
        'MCP server and client support is limited on web',
        'LLM integration is limited on web',
        'Background processing is limited to browser restrictions',
      ]
    };
  }
}