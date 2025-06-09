import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'src/config/mcp_config.dart';

abstract class FlutterMcpPlatform extends PlatformInterface {
  FlutterMcpPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMcpPlatform? _instance;

  static FlutterMcpPlatform get instance {
    if (_instance == null) {
      throw UnimplementedError(
        'FlutterMcpPlatform has not been initialized. Please register a platform implementation (e.g. FlutterMcpWeb.registerWith).',
      );
    }
    return _instance!;
  }

  static set instance(FlutterMcpPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns a [String] containing the version of the platform.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Initialize the platform implementation with config
  Future<void> initialize(MCPConfig config) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Start background service
  Future<bool> startBackgroundService() {
    throw UnimplementedError('startBackgroundService() has not been implemented.');
  }

  /// Stop background service
  Future<bool> stopBackgroundService() {
    throw UnimplementedError('stopBackgroundService() has not been implemented.');
  }

  /// Check if background service is running
  bool get isBackgroundServiceRunning {
    throw UnimplementedError('isBackgroundServiceRunning has not been implemented.');
  }

  /// Show notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) {
    throw UnimplementedError('showNotification() has not been implemented.');
  }

  /// Store a value securely
  Future<void> secureStore(String key, String value) {
    throw UnimplementedError('secureStore() has not been implemented.');
  }

  /// Read a value from secure storage
  Future<String?> secureRead(String key) {
    throw UnimplementedError('secureRead() has not been implemented.');
  }

  /// Shutdown all services
  Future<void> shutdown() {
    throw UnimplementedError('shutdown() has not been implemented.');
  }

  /// Check if a permission is granted
  Future<bool> checkPermission(String permission) {
    throw UnimplementedError('checkPermission() has not been implemented.');
  }

  /// Request a permission
  Future<bool> requestPermission(String permission) {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Request multiple permissions
  Future<Map<String, bool>> requestPermissions(List<String> permissions) {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() {
    throw UnimplementedError('cancelAllNotifications() has not been implemented.');
  }
}