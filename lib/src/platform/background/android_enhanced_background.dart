import 'dart:async';
import 'package:flutter/services.dart';
import '../../config/background_config.dart';
import '../../config/enhanced_background_config.dart';
import '../../utils/exceptions.dart';
import '../../utils/enhanced_error_handler.dart';
import 'enhanced_background_service.dart';
import '../../utils/enhanced_resource_cleanup.dart';

/// Enhanced Android background service implementation
class AndroidEnhancedBackgroundService extends EnhancedBackgroundService {
  static const MethodChannel _channel = MethodChannel('flutter_mcp');
  static const EventChannel _eventChannel = EventChannel('flutter_mcp/background_events');
  
  StreamSubscription? _eventSubscription;
  final Map<String, Function()> _nativeTaskCallbacks = {};
  EnhancedBackgroundConfig? _currentConfig;
  
  AndroidEnhancedBackgroundService() : super('android');
  
  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    _currentConfig = config is EnhancedBackgroundConfig ? config : null;
    logger.fine('Initializing Android background service');
    
    // Set up event channel for native events
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleNativeEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (error) {
        logger.severe('Background event channel error', error);
      },
    );
    
    // Initialize native Android service
    await _channel.invokeMethod('initializeBackgroundService', {
      'enableForegroundService': config.enableForegroundService,
      'notificationTitle': config.notificationTitle,
      'notificationDescription': config.notificationDescription,
      'notificationIcon': config.notificationIcon,
      'notificationChannelId': config.notificationChannelId,
      'notificationChannelName': config.notificationChannelName,
      'notificationChannelDescription': config.notificationChannelDescription,
      'autoStartOnBoot': config.autoStartOnBoot,
      'keepAlive': config.keepAlive,
      'intervalMs': config.intervalMs,
      'wakeLock': config.wakeLock,
      'wifiLock': config.wifiLock,
    });
  }
  
  @override
  Future<bool> platformStart() async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        final result = await _channel.invokeMethod<bool>('startBackgroundService', {
          'isForeground': _currentConfig?.enableForegroundService ?? false,
        });
        
        if (result != true) {
          throw MCPException('Failed to start Android background service');
        }
        
        logger.info('Android background service started');
        return true;
      },
      context: 'android_background_start',
      component: 'background_service',
      fallbackValue: false,
    );
  }
  
  @override
  Future<bool> platformStop() async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        // Cancel event subscription
        await _eventSubscription?.cancel();
        _eventSubscription = null;
        
        // Stop native service
        final result = await _channel.invokeMethod<bool>('stopBackgroundService');
        
        logger.info('Android background service stopped');
        return result ?? true;
      },
      context: 'android_background_stop',
      component: 'background_service',
      fallbackValue: false,
    );
  }
  
  /// Handle events from native Android service
  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};
    
    logger.fine('Received native event: $type');
    
    switch (type) {
      case 'task_trigger':
        _handleTaskTrigger(data);
        break;
        
      case 'periodic_trigger':
        _handlePeriodicTrigger(data);
        break;
        
      case 'boot_completed':
        _handleBootCompleted(data);
        break;
        
      case 'connectivity_changed':
        _handleConnectivityChanged(data);
        break;
        
      case 'battery_changed':
        _handleBatteryChanged(data);
        break;
        
      case 'memory_warning':
        _handleMemoryWarning(data);
        break;
        
      default:
        logger.fine('Unknown native event type: $type');
    }
  }
  
  /// Handle task trigger from native
  void _handleTaskTrigger(Map<String, dynamic> data) {
    final taskId = data['taskId'] as String?;
    if (taskId == null) return;
    
    // Execute registered callback
    final callback = _nativeTaskCallbacks[taskId];
    if (callback != null) {
      registerTask(
        name: 'native_task_$taskId',
        execute: () async => callback(),
        priority: TaskPriority.high,
      );
    }
  }
  
  /// Handle periodic trigger
  void _handlePeriodicTrigger(Map<String, dynamic> data) {
    
    registerTask(
      name: 'periodic_task',
      execute: () async {
        logger.fine('Executing periodic background task');
        // Execute any registered periodic tasks
      },
      priority: TaskPriority.normal,
    );
  }
  
  /// Handle boot completed
  void _handleBootCompleted(Map<String, dynamic> data) {
    logger.info('Device boot completed, restarting background tasks');
    
    // Re-register scheduled tasks after boot
    if (_currentConfig?.schedule != null) {
      for (final job in _currentConfig!.schedule!) {
        if (job.enabled && job.runOnBoot) {
          registerTask(
            name: 'boot_job_${job.name}',
            execute: () async {
              logger.fine('Executing boot job: ${job.name}');
            },
            priority: TaskPriority.high,
          );
        }
      }
    }
  }
  
  /// Handle connectivity changes
  void _handleConnectivityChanged(Map<String, dynamic> data) {
    final isConnected = data['connected'] as bool? ?? false;
    final connectionType = data['type'] as String?;
    
    logger.fine('Connectivity changed: $connectionType (connected: $isConnected)');
    
    // Queue network-dependent tasks if connected
    if (isConnected) {
      registerTask(
        name: 'network_sync',
        execute: () async {
          logger.fine('Executing network sync tasks');
        },
        priority: TaskPriority.normal,
      );
    }
  }
  
  /// Handle battery changes
  void _handleBatteryChanged(Map<String, dynamic> data) {
    final level = data['level'] as int? ?? 100;
    final isCharging = data['charging'] as bool? ?? false;
    
    logger.fine('Battery changed: $level% (charging: $isCharging)');
    
    // Adjust task execution based on battery
    if (level < 20 && !isCharging) {
      logger.warning('Low battery detected, reducing background activity');
      // Could pause non-critical tasks
    }
  }
  
  /// Handle memory warnings
  void _handleMemoryWarning(Map<String, dynamic> data) {
    final level = data['level'] as String?;
    
    logger.warning('Memory warning received: $level');
    
    // Trigger cleanup
    registerTask(
      name: 'memory_cleanup',
      execute: () async {
        logger.fine('Performing memory cleanup');
        // Trigger resource cleanup
        EnhancedResourceCleanup.instance.checkForLeaks();
      },
      priority: TaskPriority.high,
    );
  }
  
  /// Schedule a native Android task
  Future<void> scheduleNativeTask({
    required String taskId,
    required Duration delay,
    required Function() callback,
    bool recurring = false,
    Map<String, dynamic>? constraints,
  }) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        // Register callback
        _nativeTaskCallbacks[taskId] = callback;
        
        // Schedule with native Android WorkManager
        await _channel.invokeMethod('scheduleBackgroundTask', {
          'taskId': taskId,
          'delayMillis': delay.inMilliseconds,
          'recurring': recurring,
          'constraints': constraints ?? {},
        });
        
        logger.fine('Scheduled native task: $taskId');
      },
      context: 'schedule_native_task',
      component: 'background_service',
      metadata: {'taskId': taskId},
    );
  }
  
  /// Cancel a native Android task
  Future<void> cancelNativeTask(String taskId) async {
    await EnhancedErrorHandler.instance.handleError(
      () async {
        _nativeTaskCallbacks.remove(taskId);
        
        await _channel.invokeMethod('cancelBackgroundTask', {
          'taskId': taskId,
        });
        
        logger.fine('Cancelled native task: $taskId');
      },
      context: 'cancel_native_task',
      component: 'background_service',
      metadata: {'taskId': taskId},
    );
  }
  
  /// Update foreground notification
  Future<void> updateNotification({
    String? title,
    String? description,
    Map<String, dynamic>? extras,
  }) async {
    if (!(_currentConfig?.enableForegroundService ?? false)) {
      logger.warning('Foreground service not enabled');
      return;
    }
    
    await EnhancedErrorHandler.instance.handleError(
      () async {
        await _channel.invokeMethod('updateNotification', {
          'title': title,
          'description': description,
          'extras': extras,
        });
      },
      context: 'update_notification',
      component: 'background_service',
    );
  }
  
  /// Request battery optimization exemption
  Future<bool> requestBatteryOptimizationExemption() async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        final result = await _channel.invokeMethod<bool>(
          'requestBatteryOptimizationExemption'
        );
        return result ?? false;
      },
      context: 'battery_optimization_exemption',
      component: 'background_service',
      fallbackValue: false,
    );
  }
  
  /// Check if battery optimization is disabled
  Future<bool> isBatteryOptimizationDisabled() async {
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        final result = await _channel.invokeMethod<bool>(
          'isBatteryOptimizationDisabled'
        );
        return result ?? true;
      },
      context: 'check_battery_optimization',
      component: 'background_service',
      fallbackValue: true,
    );
  }
  
  @override
  Map<String, dynamic> getStatistics() {
    final stats = super.getStatistics();
    stats['nativeTaskCallbacks'] = _nativeTaskCallbacks.length;
    stats['eventSubscription'] = _eventSubscription != null;
    return stats;
  }
}