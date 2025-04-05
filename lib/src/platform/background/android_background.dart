import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

/// 안드로이드 백그라운드 서비스 구현
class AndroidBackgroundService implements BackgroundService {
  bool _isRunning = false;
  late FlutterForegroundTask _foregroundTask;
  final MCPLogger _logger = MCPLogger('mcp.android_background');

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.debug('안드로이드 백그라운드 서비스 초기화');
    _foregroundTask = FlutterForegroundTask();

    await _foregroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: config?.notificationChannelId ?? 'flutter_mcp_channel',
        channelName: config?.notificationChannelName ?? 'MCP Service',
        channelDescription: config?.notificationDescription ?? 'MCP Background Service',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: config?.notificationIcon,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: 5000,
        autoRunOnBoot: config?.autoStartOnBoot ?? false,
        allowWifiLock: true,
      ),
      printDevLog: false,
    );
  }

  @override
  Future<bool> start() async {
    _logger.debug('안드로이드 백그라운드 서비스 시작');
    bool result = await _foregroundTask.startService(
      notificationTitle: 'MCP Service',
      notificationText: 'Running in background',
      callback: _startCallback,
    );

    _isRunning = result;
    return result;
  }

  @override
  Future<bool> stop() async {
    _logger.debug('안드로이드 백그라운드 서비스 중지');
    bool result = await _foregroundTask.stopService();
    _isRunning = false;
    return result;
  }
}

// 백그라운드에서 실행될 콜백
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(MCPTaskHandler());
}

/// MCP 태스크 핸들러
class MCPTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // 백그라운드 작업 시작
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // 주기적으로 실행되는 이벤트
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // 작업 정리
  }

  @override
  void onButtonPressed(String id) {
    // 알림 버튼 클릭 처리
  }
}