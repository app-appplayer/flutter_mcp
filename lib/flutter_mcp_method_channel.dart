import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_mcp_platform_interface.dart';
import 'src/config/mcp_config.dart';
import 'src/config/background_config.dart';
import 'src/config/notification_config.dart';
import 'src/config/tray_config.dart';
import 'src/utils/exceptions.dart';
import 'src/utils/typed_platform_channel.dart';
import 'src/models/platform_messages.dart';

/// An implementation of [FlutterMcpPlatform] that uses method channels.
class MethodChannelFlutterMcp extends FlutterMcpPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_mcp');

  /// Type-safe platform channel
  final TypedPlatformChannel _typedChannel = FlutterMCPChannel.instance;

  /// The event channel for platform events
  @visibleForTesting
  final eventChannel = const EventChannel('flutter_mcp/events');

  /// Stream controller for platform events
  final _eventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Cached event stream
  Stream<Map<String, dynamic>>? _eventStream;

  /// Background service state
  bool _isBackgroundServiceRunning = false;

  /// Constructor
  MethodChannelFlutterMcp() {
    // Set up method call handler for native -> Flutter calls
    methodChannel.setMethodCallHandler(_handleMethodCall);

    // Set up event stream
    _eventStream = eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .handleError((error) {
      _eventStreamController.addError(error);
    });

    // Forward events to controller
    _eventStream!.listen(
      (event) => _eventStreamController.add(event),
      onError: (error) => _eventStreamController.addError(error),
    );
  }

  /// Handle method calls from native
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBackgroundServiceStateChanged':
        _isBackgroundServiceRunning = call.arguments['isRunning'] as bool;
        _eventStreamController.add({
          'type': 'backgroundServiceStateChanged',
          'data': {'isRunning': _isBackgroundServiceRunning},
        });
        break;
      case 'onBackgroundTaskResult':
        _eventStreamController.add({
          'type': 'backgroundTaskResult',
          'data': call.arguments,
        });
        break;
      case 'onNotificationReceived':
        _eventStreamController.add({
          'type': 'notificationReceived',
          'data': call.arguments,
        });
        break;
      case 'onTrayEvent':
        _eventStreamController.add({
          'type': 'trayEvent',
          'data': call.arguments,
        });
        break;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  /// Platform event stream
  Stream<Map<String, dynamic>> get eventStream => _eventStreamController.stream;

  @override
  Future<String?> getPlatformVersion() async {
    try {
      final version =
          await methodChannel.invokeMethod<String>('getPlatformVersion');
      return version;
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to get platform version', e.code, e.details);
    }
  }

  @override
  Future<void> initialize(MCPConfig config) async {
    try {
      await methodChannel.invokeMethod<void>('initialize', config.toJson());
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to initialize', e.code, e.details);
    }
  }

  // Background Service Methods
  @override
  Future<bool> startBackgroundService() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('startBackgroundService');
      _isBackgroundServiceRunning = result ?? false;
      return _isBackgroundServiceRunning;
    } on PlatformException catch (e) {
      throw MCPBackgroundExecutionException(
          'Failed to start background service: ${e.message}', e.details);
    }
  }

  @override
  Future<bool> stopBackgroundService() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('stopBackgroundService');
      _isBackgroundServiceRunning = !(result ?? true);
      return result ?? false;
    } on PlatformException catch (e) {
      throw MCPBackgroundExecutionException(
          'Failed to stop background service: ${e.message}', e.details);
    }
  }

  @override
  bool get isBackgroundServiceRunning => _isBackgroundServiceRunning;

  /// Configure background service
  Future<void> configureBackgroundService(BackgroundConfig config) async {
    try {
      await methodChannel.invokeMethod<void>(
          'configureBackgroundService', config.toJson());
    } on PlatformException catch (e) {
      throw MCPBackgroundExecutionException(
          'Failed to configure background service: ${e.message}', e.details);
    }
  }

  /// Schedule a background task
  Future<void> scheduleBackgroundTask({
    required String taskId,
    required Duration delay,
    Map<String, dynamic>? data,
  }) async {
    try {
      await methodChannel.invokeMethod<void>('scheduleBackgroundTask', {
        'taskId': taskId,
        'delayMillis': delay.inMilliseconds,
        'data': data,
      });
    } on PlatformException catch (e) {
      throw MCPBackgroundExecutionException(
          'Failed to schedule task: ${e.message}', e.details);
    }
  }

  /// Cancel a scheduled background task
  Future<void> cancelBackgroundTask(String taskId) async {
    try {
      await methodChannel
          .invokeMethod<void>('cancelBackgroundTask', {'taskId': taskId});
    } on PlatformException catch (e) {
      throw MCPBackgroundExecutionException(
          'Failed to cancel task: ${e.message}', e.details);
    }
  }

  // Notification Methods
  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String id = 'mcp_notification',
  }) async {
    try {
      await methodChannel.invokeMethod<void>('showNotification', {
        'title': title,
        'body': body,
        'icon': icon,
        'id': id,
      });
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to show notification', e.code, e.details);
    }
  }

  /// Request notification permission
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await methodChannel
          .invokeMethod<bool>('requestNotificationPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw MCPPermissionDeniedException('notification');
      }
      throw MCPPlatformException(
          'Failed to request notification permission', e.code, e.details);
    }
  }

  /// Configure notification settings
  Future<void> configureNotifications(NotificationConfig config) async {
    try {
      await methodChannel.invokeMethod<void>(
          'configureNotifications', config.toJson());
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to configure notifications', e.code, e.details);
    }
  }

  /// Cancel a notification
  Future<void> cancelNotification(String id) async {
    try {
      await methodChannel.invokeMethod<void>('cancelNotification', {'id': id});
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to cancel notification', e.code, e.details);
    }
  }

  // Secure Storage Methods
  @override
  Future<void> secureStore(String key, String value) async {
    try {
      await methodChannel.invokeMethod<void>('secureStore', {
        'key': key,
        'value': value,
      });
    } on PlatformException catch (e) {
      throw MCPSecureStorageException(
          'Failed to store secure value: ${e.message}', e.details);
    }
  }

  @override
  Future<String?> secureRead(String key) async {
    try {
      final value =
          await methodChannel.invokeMethod<String>('secureRead', {'key': key});
      return value;
    } on PlatformException catch (e) {
      if (e.code == 'KEY_NOT_FOUND') {
        return null;
      }
      throw MCPSecureStorageException(
          'Failed to read secure value: ${e.message}', e.details);
    }
  }

  /// Delete a secure storage entry
  Future<void> secureDelete(String key) async {
    try {
      await methodChannel.invokeMethod<void>('secureDelete', {'key': key});
    } on PlatformException catch (e) {
      throw MCPSecureStorageException(
          'Failed to delete secure value: ${e.message}', e.details);
    }
  }

  /// Check if key exists in secure storage
  Future<bool> secureContainsKey(String key) async {
    try {
      final result = await methodChannel
          .invokeMethod<bool>('secureContainsKey', {'key': key});
      return result ?? false;
    } on PlatformException catch (e) {
      throw MCPSecureStorageException(
          'Failed to check secure key: ${e.message}', e.details);
    }
  }

  /// Delete all secure storage entries
  Future<void> secureDeleteAll() async {
    try {
      await methodChannel.invokeMethod<void>('secureDeleteAll');
    } on PlatformException catch (e) {
      throw MCPSecureStorageException(
          'Failed to delete all secure values: ${e.message}', e.details);
    }
  }

  // System Tray Methods (Desktop only)
  /// Show system tray icon
  Future<void> showTrayIcon({
    String? iconPath,
    String? tooltip,
  }) async {
    try {
      await methodChannel.invokeMethod<void>('showTrayIcon', {
        'iconPath': iconPath,
        'tooltip': tooltip,
      });
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to show tray icon', e.code, e.details);
    }
  }

  /// Hide system tray icon
  Future<void> hideTrayIcon() async {
    try {
      await methodChannel.invokeMethod<void>('hideTrayIcon');
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to hide tray icon', e.code, e.details);
    }
  }

  /// Set tray menu items
  Future<void> setTrayMenu(List<Map<String, dynamic>> items) async {
    try {
      await methodChannel.invokeMethod<void>('setTrayMenu', {'items': items});
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to set tray menu', e.code, e.details);
    }
  }

  /// Update tray tooltip
  Future<void> updateTrayTooltip(String tooltip) async {
    try {
      await methodChannel
          .invokeMethod<void>('updateTrayTooltip', {'tooltip': tooltip});
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to update tray tooltip', e.code, e.details);
    }
  }

  /// Configure system tray
  Future<void> configureTray(TrayConfig config) async {
    try {
      await methodChannel.invokeMethod<void>('configureTray', config.toJson());
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to configure tray', e.code, e.details);
    }
  }

  // Lifecycle Methods
  @override
  Future<void> shutdown() async {
    try {
      // Stop all services
      if (_isBackgroundServiceRunning) {
        await stopBackgroundService();
      }

      // Cancel all notifications
      await cancelAllNotifications();

      // Hide tray icon if shown
      await hideTrayIcon();

      // Call native shutdown
      await methodChannel.invokeMethod<void>('shutdown');

      // Close event stream
      await _eventStreamController.close();
    } on PlatformException catch (e) {
      throw MCPPlatformException('Failed to shutdown', e.code, e.details);
    }
  }

  @override
  Future<bool> checkPermission(String permission) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'checkPermission',
        {'permission': permission},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to check permission', e.code, e.details);
    }
  }

  @override
  Future<bool> requestPermission(String permission) async {
    try {
      final result = await methodChannel.invokeMethod<bool>(
        'requestPermission',
        {'permission': permission},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw MCPPermissionDeniedException(permission);
      }
      throw MCPPlatformException(
          'Failed to request permission', e.code, e.details);
    }
  }

  @override
  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'requestPermissions',
        {'permissions': permissions},
      );

      if (result == null) return {};

      return result.map(
          (key, value) => MapEntry(key.toString(), value as bool? ?? false));
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to request permissions', e.code, e.details);
    }
  }

  @override
  Future<void> cancelAllNotifications() async {
    try {
      await methodChannel.invokeMethod<void>('cancelAllNotifications');
    } on PlatformException catch (e) {
      throw MCPPlatformException(
          'Failed to cancel all notifications', e.code, e.details);
    }
  }

  /// Type-safe version of showNotification
  Future<void> showNotificationTyped({
    required String id,
    required String title,
    required String body,
    NotificationConfig? config,
  }) async {
    final message = ShowNotificationMessage(
      id: id,
      title: title,
      body: body,
      config: config,
    );

    final response = await _typedChannel.sendMessage(message);
    if (response.isError) {
      throw MCPPlatformException(
        'Failed to show notification',
        'NOTIFICATION_ERROR',
        response,
      );
    }
  }

  /// Type-safe version of executeBackgroundTask
  Future<void> executeBackgroundTaskTyped({
    required String taskId,
    required Map<String, dynamic> data,
  }) async {
    final message = ExecuteBackgroundTaskMessage(
      taskId: taskId,
      data: data,
    );

    final response = await _typedChannel.sendMessage(message);
    if (response.isError) {
      throw MCPPlatformException(
        'Failed to execute background task',
        'BACKGROUND_TASK_ERROR',
        response,
      );
    }
  }

  /// Type-safe version of requesting permission
  Future<bool> requestPermissionTyped(String permission,
      {String? rationale}) async {
    final message = RequestPermissionMessage(
      permission: permission,
      rationale: rationale,
    );

    final response = await _typedChannel.sendMessage(message);
    if (response is PermissionResponse) {
      return response.granted;
    }

    throw MCPPlatformException(
      'Invalid response type for permission request',
      'INVALID_RESPONSE',
      response,
    );
  }

  /// Type-safe version of checking system info
  Future<SystemInfoResponse> getSystemInfoTyped() async {
    const message = GetSystemInfoMessage();

    final response = await _typedChannel.sendMessage(message);
    if (response is SystemInfoResponse) {
      return response;
    }

    throw MCPPlatformException(
      'Invalid response type for system info',
      'INVALID_RESPONSE',
      response,
    );
  }

  /// Dispose resources
  void dispose() {
    _eventStreamController.close();
  }
}

/// Platform exceptions
class MCPPlatformException extends MCPException {
  final String code;
  final dynamic details;

  MCPPlatformException(super.message, this.code, [this.details]);

  @override
  String toString() =>
      'MCPPlatformException($code): $message\nDetails: $details';
}

class MCPPermissionDeniedException extends MCPPlatformException {
  MCPPermissionDeniedException(String permission)
      : super(
            'Permission denied: $permission', 'PERMISSION_DENIED', permission);
}

class MCPBackgroundExecutionException extends MCPPlatformException {
  MCPBackgroundExecutionException(String message, [dynamic details])
      : super(message, 'BACKGROUND_EXECUTION_ERROR', details);
}

class MCPSecureStorageException extends MCPPlatformException {
  MCPSecureStorageException(String message, [dynamic details])
      : super(message, 'SECURE_STORAGE_ERROR', details);
}
