import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

class AndroidBackgroundService implements BackgroundService {
  bool _isRunning = false;
  final MCPLogger _logger = MCPLogger('mcp.android_background');
  late BackgroundConfig _config;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('Android background service initializing');
    _config = config ?? BackgroundConfig.defaultConfig();
    await _initializeForegroundTask();
  }

  Future<void> _initializeForegroundTask() async {
    final androidOptions = AndroidNotificationOptions(
      channelId: _config.notificationChannelId ?? 'flutter_mcp_channel',
      channelName: _config.notificationChannelName ?? 'MCP Service',
      channelDescription: _config.notificationDescription ?? 'MCP Background Service',
    );

    final iosOptions = IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    );

    final taskOptions = ForegroundTaskOptions(
      autoRunOnBoot: _config.autoStartOnBoot,
      allowWifiLock: true,
      allowWakeLock: true,
      eventAction: ForegroundTaskEventAction.repeat(_config.intervalMs),
    );

    FlutterForegroundTask.init(
      androidNotificationOptions: androidOptions,
      iosNotificationOptions: iosOptions,
      foregroundTaskOptions: taskOptions,
    );

    FlutterForegroundTask.setTaskHandler(MCPTaskHandler());
  }

  @override
  Future<bool> start() async {
    _logger.debug('Android background service starting');

    if (await FlutterForegroundTask.isRunningService) {
      _logger.debug('Service is already running');
      _isRunning = true;
      return true;
    }

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: _config.notificationChannelName ?? 'MCP Service',
        notificationText: 'Running in background',
        callback: _startCallback,
      );

      _isRunning = result == ServiceRequestSuccess();
      _logger.debug('Service started: $_isRunning');
      return _isRunning;
    } catch (e, stackTrace) {
      _logger.error('Failed to start service', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _logger.debug('Android background service stopping');

    if (!await FlutterForegroundTask.isRunningService) {
      _logger.debug('Service is not running');
      _isRunning = false;
      return true;
    }

    try {
      final result = await FlutterForegroundTask.stopService();
      final success = result == ServiceRequestSuccess();
      _isRunning = false;
      _logger.debug('Service stopped successfully: $success');
      return success;
    } catch (e, stackTrace) {
      _logger.error('Failed to stop service', e, stackTrace);
      return false;
    }
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(MCPTaskHandler());
}

class MCPTaskHandler extends TaskHandler {
  final MCPLogger _logger = MCPLogger('mcp.android_task_handler');

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _logger.debug('Background task started at $timestamp');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _logger.debug('Background task executing at $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _logger.debug('Background task stopping at $timestamp');
  }
  // Called when data is sent using `FlutterForegroundTask.sendDataToTask`.
  @override
  void onReceiveData(Object data) {
    _logger.debug('onReceiveData: $data');
  }

  // Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    _logger.debug('onNotificationButtonPressed: $id');
  }

  // Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    _logger.debug('onNotificationPressed');
  }

  // Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    _logger.debug('onNotificationDismissed');
  }
}
