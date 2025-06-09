import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import '../../utils/performance_monitor.dart';
import '../../utils/event_system.dart';
import 'background_service.dart';

/// iOS background service implementation
/// Uses limited iOS background modes (fetch, processing, location)
class IOSBackgroundService implements BackgroundService {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');
  
  bool _isRunning = false;
  final Logger _logger = Logger('flutter_mcp.ios_background');
  late BackgroundConfig _config;
  StreamSubscription? _eventSubscription;
  
  // iOS-specific background task tracking
  Timer? _backgroundTimer;
  int _taskExecutionCount = 0;
  static const Duration _iosBackgroundTimeLimit = Duration(seconds: 30);
  
  // Callback functions
  Function()? _onStart;
  Function(DateTime)? _onRepeat;
  Function()? _onDestroy;
  Function(Map<String, dynamic>)? _onEvent;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.fine('iOS background service initializing');
    _config = config ?? BackgroundConfig.defaultConfig();
    
    // iOS has strict background execution limits
    if (_config.intervalMs < 900000) { // Less than 15 minutes
      _logger.warning('iOS background fetch minimum interval is 15 minutes');
    }
    
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
    
    // Ensure iOS minimum interval
    final adjustedInterval = _config.intervalMs < 900000 ? 900000 : _config.intervalMs;
    
    await _channel.invokeMethod('configureBackgroundService', {
      'intervalMs': adjustedInterval,
      'keepAlive': _config.keepAlive,
      'taskIdentifier': 'com.flutter.mcp.background.refresh',
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
          _taskExecutionCount = 0;
          _onStart?.call();
          
          // Start performance monitoring
          PerformanceMonitor.instance.startTimer('ios.background.session');
        } else if (eventType == 'periodic') {
          final timestamp = data['timestamp'] as int?;
          if (timestamp != null) {
            _taskExecutionCount++;
            final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp ~/ 1000);
            
            // Create a timer to ensure we complete within iOS time limits
            _backgroundTimer = Timer(_iosBackgroundTimeLimit, () {
              _logger.warning('iOS background task approaching time limit');
            });
            
            _onRepeat?.call(dateTime);
            
            // Cancel the warning timer
            _backgroundTimer?.cancel();
            
            // Publish task completion
            EventSystem.instance.publish('ios.background.task.completed', {
              'executionCount': _taskExecutionCount,
              'timestamp': dateTime.toIso8601String(),
            });
          }
        } else if (eventType == 'destroy') {
          _onDestroy?.call();
          
          // Stop performance monitoring
          PerformanceMonitor.instance.stopTimer('ios.background.session');
          
          // Publish session summary
          EventSystem.instance.publish('ios.background.session.ended', {
            'totalExecutions': _taskExecutionCount,
          });
        }
        break;
      
      case 'backgroundTaskResult':
        final taskId = data['taskId'] as String?;
        if (taskId != null && _scheduledTasks.containsKey(taskId)) {
          _scheduledTasks[taskId]?.call();
          _scheduledTasks.remove(taskId);
        }
        _onEvent?.call(data);
        break;
      
      default:
        _logger.fine('Unknown event type: $type');
    }
  }

  @override
  Future<bool> start() async {
    _logger.fine('iOS background service starting');

    try {
      final result = await _channel.invokeMethod<bool>('startBackgroundService', {
        'taskType': 'refresh',
      });
      _isRunning = result ?? false;
      
      if (_isRunning) {
        // Publish iOS-specific start event
        EventSystem.instance.publish('background.started', {
          'platform': 'ios',
          'restrictions': {
            'minInterval': '15 minutes',
            'maxExecutionTime': '30 seconds',
            'backgroundModes': ['fetch', 'processing'],
          },
        });
      }
      
      _logger.fine('Service started: $_isRunning');
      return _isRunning;
    } catch (e, stackTrace) {
      _logger.severe('Failed to start service', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    _logger.fine('iOS background service stopping');

    try {
      final result = await _channel.invokeMethod<bool>('stopBackgroundService');
      _isRunning = false;
      
      // Publish stop event with iOS-specific stats
      EventSystem.instance.publish('background.stopped', {
        'platform': 'ios',
        'taskExecutionCount': _taskExecutionCount,
      });
      
      _logger.fine('Service stopped successfully');
      return result ?? true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to stop service', e, stackTrace);
      return false;
    }
  }

  Future<void> scheduleTask(String taskId, Duration delay, Function() task) async {
    try {
      // iOS has minimum delay of 15 minutes for background fetch
      final adjustedDelay = delay.inMilliseconds < 900000 
          ? Duration(minutes: 15) 
          : delay;
          
      await _channel.invokeMethod('scheduleBackgroundTask', {
        'taskId': taskId,
        'delayMillis': adjustedDelay.inMilliseconds,
      });
      
      // Store task locally to execute when event is received
      _scheduledTasks[taskId] = task;
      
      _logger.info('Scheduled task $taskId with delay ${adjustedDelay.inMinutes} minutes');
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
    _backgroundTimer?.cancel();
  }
}