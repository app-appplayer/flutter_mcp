import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

/// Android background service implementation
class AndroidBackgroundService implements BackgroundService {
  bool _isRunning = false;
  final MCPLogger _logger = MCPLogger('mcp.android_background');

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('Android background service initialization');

    // Initialize the foreground task
    // Using the correct enum values for the latest flutter_foreground_task API
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: config?.notificationChannelId ?? 'flutter_mcp_channel',
        channelName: config?.notificationChannelName ?? 'MCP Service',
        channelDescription: config?.notificationDescription ?? 'MCP Background Service',
        channelImportance: NotificationChannelImportance.LOW,  // Using capital letters for enum
        priority: NotificationPriority.LOW,  // Using capital letters for enum
        icon: NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: config?.notificationIcon ?? 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: config?.autoStartOnBoot ?? false,
        allowWakeLock: true,
        allowWifiLock: true,
        eventAction: 'com.example.action.FOREGROUND_TASK',  // Added required parameter
      ),
    );
  }

  @override
  Future<bool> start() async {
    _logger.debug('Starting Android background service');

    bool result = await FlutterForegroundTask.startService(
      notificationTitle: 'MCP Service',
      notificationText: 'Running in background',
      callback: _startCallback,
    );

    _isRunning = result;
    return result;
  }

  @override
  Future<bool> stop() async {
    _logger.debug('Stopping Android background service');
    bool result = await FlutterForegroundTask.stopService();
    _isRunning = false;
    return result;
  }
}

// Background callback function that will be executed when the service starts
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(MCPTaskHandler());
}

/// MCP task handler for background processing
class MCPTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Initialize background task
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // Periodic event handling
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // Cleanup resources
  }

  @override
  void onButtonPressed(String id) {
    // Handle notification button press
  }
}