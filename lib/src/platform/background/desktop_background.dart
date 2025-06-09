import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/background_config.dart';
import '../../utils/logger.dart';
import '../../utils/performance_monitor.dart';
import '../../utils/event_system.dart';
import 'background_service.dart';

/// Desktop (macOS, Windows, Linux) background service implementation
class DesktopBackgroundService implements BackgroundService {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/events');
  
  bool _isRunning = false;
  Timer? _backgroundTimer;
  BackgroundConfig? _config;
  final Logger _logger = Logger('flutter_mcp.desktop_background');
  StreamSubscription? _eventSubscription;
  
  // Task management
  Future<void> Function()? _taskHandler;
  int _taskExecutionCount = 0;
  int _errorCount = 0;
  final int _maxConsecutiveErrors = 5;
  DateTime? _lastTaskExecution;
  
  // Performance monitoring
  String? _currentTimerId;
  
  // Callback functions
  Function()? _onStart;
  Function(DateTime)? _onRepeat;
  Function()? _onDestroy;
  Function(Map<String, dynamic>)? _onEvent;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize(BackgroundConfig? config) async {
    _logger.fine('Desktop background service initializing');
    _config = config ?? BackgroundConfig.defaultConfig();
    _errorCount = 0;
    _taskExecutionCount = 0;
    
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
      'config': _config!.toMap(),
    });
    
    // Publish initialization event
    EventSystem.instance.publish('background.initialized', {
      'platform': 'desktop',
      'config': config?.toJson(),
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
      'intervalMs': _config?.intervalMs ?? 60000,
      'keepAlive': _config?.keepAlive ?? true,
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
          PerformanceMonitor.instance.startTimer('desktop.background.session');
        } else if (eventType == 'periodic') {
          final timestamp = data['timestamp'] as int?;
          if (timestamp != null) {
            _taskExecutionCount++;
            _lastTaskExecution = DateTime.fromMillisecondsSinceEpoch(timestamp ~/ 1000);
            _onRepeat?.call(_lastTaskExecution!);
            
            // For desktop, also execute any registered task handler
            if (_taskHandler != null) {
              _performBackgroundTask();
            }
          }
        } else if (eventType == 'destroy') {
          _onDestroy?.call();
          PerformanceMonitor.instance.stopTimer('desktop.background.session');
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
      
      case 'trayEvent':
        _onEvent?.call(data);
        break;
      
      default:
        _logger.fine('Unknown event type: $type');
    }
  }

  @override
  Future<bool> start() async {
    if (_isRunning) {
      _logger.warning('Background service already running');
      return false;
    }
    
    _logger.fine('Desktop background service starting');

    try {
      final result = await _channel.invokeMethod<bool>('startBackgroundService');
      _isRunning = result ?? false;
      
      if (_isRunning) {
        // Use configured interval or default
        final intervalMs = _config?.intervalMs ?? 60000; // Default 1 minute
        final interval = Duration(milliseconds: intervalMs);
        
        // Set up timer for periodic tasks (as backup to native implementation)
        _backgroundTimer = Timer.periodic(interval, (timer) {
          if (_onRepeat != null || _taskHandler != null) {
            _performBackgroundTask();
          }
        });
        
        // Publish start event
        EventSystem.instance.publish('background.started', {
          'platform': 'desktop',
          'intervalMs': intervalMs,
          'features': {
            'systemTray': true,
            'notifications': true,
            'unlimitedExecution': true,
          },
        });
      }
      
      _logger.info('Desktop background service started: $_isRunning');
      return _isRunning;
    } catch (e, stackTrace) {
      _logger.severe('Failed to start service', e, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    if (!_isRunning) {
      _logger.warning('Background service not running');
      return false;
    }
    
    _logger.fine('Desktop background service stopping');

    try {
      final result = await _channel.invokeMethod<bool>('stopBackgroundService');
      
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _isRunning = false;
      
      // Publish stop event
      EventSystem.instance.publish('background.stopped', {
        'platform': 'desktop',
        'taskExecutionCount': _taskExecutionCount,
        'errorCount': _errorCount,
      });
      
      _logger.info('Desktop background service stopped after $_taskExecutionCount executions');
      return result ?? true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to stop service', e, stackTrace);
      return false;
    }
  }

  /// Register a custom task handler
  void registerTaskHandler(Future<void> Function() handler) {
    _taskHandler = handler;
    _logger.fine('Custom task handler registered');
  }

  /// Perform background task
  Future<void> _performBackgroundTask() async {
    _logger.fine('Performing desktop background task');
    
    // Start performance monitoring
    _currentTimerId = PerformanceMonitor.instance.startTimer('desktop.background.task');
    
    try {
      _lastTaskExecution = DateTime.now();
      
      // Execute registered task handler if available
      if (_taskHandler != null) {
        await _taskHandler!();
      } else {
        // Default background tasks
        await _performDefaultTasks();
      }
      
      _taskExecutionCount++;
      _errorCount = 0; // Reset error count on success
      
      // Record successful execution
      PerformanceMonitor.instance.stopTimer(_currentTimerId!, success: true);
      PerformanceMonitor.instance.incrementCounter('desktop.background.success');
      
      // Publish task completion event
      EventSystem.instance.publish('background.task.completed', {
        'platform': 'desktop',
        'executionCount': _taskExecutionCount,
        'duration': DateTime.now().difference(_lastTaskExecution!).inMilliseconds,
      });
      
    } catch (e, stackTrace) {
      _errorCount++;
      _logger.severe('Background task error ($_errorCount/$_maxConsecutiveErrors)', e, stackTrace);
      
      // Record failed execution
      PerformanceMonitor.instance.stopTimer(_currentTimerId!, success: false);
      PerformanceMonitor.instance.incrementCounter('desktop.background.errors');
      
      // Publish error event
      EventSystem.instance.publish('background.task.error', {
        'platform': 'desktop',
        'error': e.toString(),
        'errorCount': _errorCount,
      });
      
      // Stop service if too many consecutive errors
      if (_errorCount >= _maxConsecutiveErrors) {
        _logger.severe('Too many consecutive errors, stopping background service');
        await stop();
      }
    }
  }
  
  /// Perform default background tasks
  Future<void> _performDefaultTasks() async {
    // Memory monitoring
    if (_config?.keepAlive ?? true) {
      EventSystem.instance.publish('background.heartbeat', {
        'platform': 'desktop',
        'timestamp': DateTime.now().toIso8601String(),
        'uptime': DateTime.now().difference(_lastTaskExecution ?? DateTime.now()).inSeconds,
      });
    }
    
    // Additional default tasks can be added here
    // - System resource monitoring
    // - Cache cleanup
    // - Log rotation
    // - Health checks
  }

  Future<void> scheduleTask(String taskId, Duration delay, Function() task) async {
    try {
      await _channel.invokeMethod('scheduleBackgroundTask', {
        'taskId': taskId,
        'delayMillis': delay.inMilliseconds,
      });
      
      // Store task locally to execute when event is received
      _scheduledTasks[taskId] = task;
      
      // For desktop, we can also use a Dart timer
      Timer(delay, () {
        if (_scheduledTasks.containsKey(taskId)) {
          _scheduledTasks[taskId]?.call();
          _scheduledTasks.remove(taskId);
        }
      });
      
      _logger.info('Scheduled task $taskId with delay ${delay.inSeconds} seconds');
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
  
  /// Update configuration dynamically
  Future<void> updateConfig(BackgroundConfig config) async {
    _config = config;
    
    // If interval changed and service is running, restart with new config
    if (_isRunning && config.intervalMs != _config?.intervalMs) {
      _logger.info('Restarting background service with new interval: ${config.intervalMs}ms');
      await stop();
      await start();
    }
  }
  
  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'platform': 'desktop',
      'isRunning': _isRunning,
      'taskExecutionCount': _taskExecutionCount,
      'errorCount': _errorCount,
      'lastTaskExecution': _lastTaskExecution?.toIso8601String(),
      'config': _config?.toJson(),
    };
  }

  void dispose() {
    _eventSubscription?.cancel();
    _scheduledTasks.clear();
    _backgroundTimer?.cancel();
  }
}