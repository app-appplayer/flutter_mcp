import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import 'background_service.dart';

class AndroidBackgroundService implements BackgroundService {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');

  bool _isRunning = false;
  final Logger _logger = Logger('flutter_mcp.android_background');
  late BackgroundConfig _config;
  StreamSubscription? _eventSubscription;

  // Callback functions
  Function()? _onStart;
  Function(DateTime)? _onRepeat;
  Function()? _onDestroy;
  Function(Map<String, dynamic>)? _onEvent;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.fine('Android background service initializing');
    _config = config ?? BackgroundConfig.defaultConfig();

    // Initialize event listener
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        _logger.severe('Event channel error', error);
      },
    );

    // Initialize native service
    await _channel.invokeMethod('initialize', {
      'config': _config.toMap(),
    });
  }

  Future<void> configure({
    Function()? onStart,
    Function(DateTime)? onRepeat,
    Function()? onDestroy,
    Function(Map<String, dynamic>)? onEvent,
  }) async {
    _onStart = onStart;
    _onRepeat = onRepeat;
    _onDestroy = onDestroy;
    _onEvent = onEvent;

    await _channel.invokeMethod('configureBackgroundService', {
      'intervalMs': _config.intervalMs,
      'channelId': _config.notificationChannelId,
      'channelName': _config.notificationChannelName,
      'notificationDescription': _config.notificationDescription,
      'notificationIcon': _config.notificationIcon,
      'autoStartOnBoot': _config.autoStartOnBoot,
      'keepAlive': _config.keepAlive,
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};

    _logger.fine('Received event: $type');

    switch (type) {
      case 'backgroundEvent':
        final eventType = data['type'] as String?;
        if (eventType == 'start') {
          _onStart?.call();
        } else if (eventType == 'periodic') {
          final timestamp = data['timestamp'] as int?;
          if (timestamp != null) {
            _onRepeat
                ?.call(DateTime.fromMillisecondsSinceEpoch(timestamp ~/ 1000));
          }
        } else if (eventType == 'destroy') {
          _onDestroy?.call();
        }
        break;

      case 'backgroundTaskResult':
        _onEvent?.call(data);
        break;

      default:
        _logger.fine('Unknown event type: $type');
    }
  }

  @override
  Future<bool> start() async {
    _logger.fine('Android background service starting');

    try {
      final result =
          await _channel.invokeMethod<bool>('startBackgroundService');
      _isRunning = result ?? false;
      _logger.fine('Service started: $_isRunning');
      return _isRunning;
    } catch (e, stackTrace) {
      _logger.severe('Failed to start service', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _logger.fine('Android background service stopping');

    try {
      final result = await _channel.invokeMethod<bool>('stopBackgroundService');
      _isRunning = false;
      _logger.fine('Service stopped successfully');
      return result ?? true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to stop service', e, stackTrace);
      return false;
    }
  }

  Future<void> scheduleTask(
      String taskId, Duration delay, Function() task) async {
    try {
      await _channel.invokeMethod('scheduleBackgroundTask', {
        'taskId': taskId,
        'delayMillis': delay.inMilliseconds,
      });

      // Store task locally to execute when event is received
      _scheduledTasks[taskId] = task;
    } catch (e, stackTrace) {
      _logger.severe('Failed to schedule task', e, stackTrace);
    }
  }

  Future<void> cancelTask(String taskId) async {
    try {
      await _channel.invokeMethod('cancelBackgroundTask', {
        'taskId': taskId,
      });

      _scheduledTasks.remove(taskId);
    } catch (e, stackTrace) {
      _logger.severe('Failed to cancel task', e, stackTrace);
    }
  }

  final Map<String, Function()> _scheduledTasks = {};

  void dispose() {
    _eventSubscription?.cancel();
    _scheduledTasks.clear();
  }
}
