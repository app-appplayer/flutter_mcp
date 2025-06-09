import 'dart:async';
import 'dart:collection';
import 'package:meta/meta.dart';
import '../../config/background_config.dart';
import '../../config/enhanced_background_config.dart';
import '../../config/background_job.dart';
import '../../utils/logger.dart';
import '../../utils/exceptions.dart';
import '../../utils/enhanced_error_handler.dart';
import '../../monitoring/health_monitor.dart';
import '../../utils/enhanced_resource_cleanup.dart';
import '../../utils/event_system.dart';
import '../../../flutter_mcp.dart' show MCPHealthStatus, MCPHealthCheckResult;
import 'background_service.dart';

/// Task priority levels
enum TaskPriority {
  high,
  normal,
  low
}

/// Background task status
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled
}

/// Enhanced background task with metadata
class BackgroundTask {
  final String id;
  final String name;
  final TaskPriority priority;
  final Future<void> Function() execute;
  final Duration? timeout;
  final bool allowConcurrent;
  final List<String> dependencies;
  final Map<String, dynamic> metadata;
  
  TaskStatus status;
  DateTime? startTime;
  DateTime? endTime;
  String? errorMessage;
  int retryCount;
  
  BackgroundTask({
    required this.id,
    required this.name,
    required this.execute,
    this.priority = TaskPriority.normal,
    this.timeout,
    this.allowConcurrent = false,
    this.dependencies = const [],
    this.metadata = const {},
    this.status = TaskStatus.pending,
    this.retryCount = 0,
  });
  
  Duration? get executionTime {
    if (startTime == null) return null;
    return (endTime ?? DateTime.now()).difference(startTime!);
  }
  
  bool get canRun {
    return status == TaskStatus.pending && 
           (allowConcurrent || status != TaskStatus.running);
  }
}

/// Enhanced background service base class
abstract class EnhancedBackgroundService implements BackgroundService, HealthCheckProvider {
  final Logger logger;
  final EventSystem _eventSystem = EventSystem.instance;
  
  // Task management
  final Map<String, BackgroundTask> _tasks = {};
  final Queue<String> _taskQueue = Queue<String>();
  final Set<String> _runningTasks = {};
  final Map<String, Timer> _scheduledTasks = {};
  
  // Service state
  bool _isRunning = false;
  bool _isInitialized = false;
  EnhancedBackgroundConfig? _config;
  Timer? _taskProcessor;
  
  // Statistics
  int _totalTasksExecuted = 0;
  int _totalTasksFailed = 0;
  final Map<String, int> _taskExecutionCounts = {};
  
  EnhancedBackgroundService(String platformName) 
    : logger = Logger('flutter_mcp.enhanced_background.$platformName');
  
  @override
  bool get isRunning => _isRunning;
  
  bool get isInitialized => _isInitialized;
  
  @override
  String get componentId => 'background_service';
  
  @override
  Future<void> initialize(BackgroundConfig? config) async {
    if (_isInitialized) {
      logger.warning('Background service already initialized');
      return;
    }
    
    await EnhancedErrorHandler.instance.handleError(
      () async {
        _config = config is EnhancedBackgroundConfig 
            ? config 
            : EnhancedBackgroundConfig.fromBase(config ?? BackgroundConfig.defaultConfig());
        
        // Platform-specific initialization
        await platformInitialize(_config!);
        
        _isInitialized = true;
        logger.info('Background service initialized');
        
        // Health monitor will be set up separately
        
        // Register for resource cleanup
        EnhancedResourceCleanup.instance.registerResource(
          key: 'background_service',
          resource: this,
          disposeFunction: (_) async => await stop(),
          type: 'BackgroundService',
          description: 'Platform background service',
          priority: 300,
        );
      },
      context: 'background_service_init',
      component: 'background_service',
    );
  }
  
  @override
  Future<bool> start() async {
    if (!_isInitialized) {
      throw MCPException('Background service not initialized');
    }
    
    if (_isRunning) {
      logger.warning('Background service already running');
      return true;
    }
    
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        // Platform-specific start
        final started = await platformStart();
        if (!started) {
          throw MCPException('Failed to start platform background service');
        }
        
        _isRunning = true;
        
        // Start task processor
        _startTaskProcessor();
        
        // Process scheduled jobs from config
        if (_config?.schedule != null) {
          _scheduleConfigJobs(_config!.schedule!);
        }
        
        logger.info('Background service started');
        _publishServiceEvent('started');
        
        return true;
      },
      context: 'background_service_start',
      component: 'background_service',
      fallbackValue: false,
    );
  }
  
  @override
  Future<bool> stop() async {
    if (!_isRunning) {
      logger.warning('Background service not running');
      return true;
    }
    
    return await EnhancedErrorHandler.instance.handleError(
      () async {
        // Cancel all scheduled tasks
        _cancelAllScheduledTasks();
        
        // Stop task processor
        _taskProcessor?.cancel();
        _taskProcessor = null;
        
        // Wait for running tasks to complete
        await _waitForRunningTasks();
        
        // Platform-specific stop
        final stopped = await platformStop();
        
        _isRunning = false;
        logger.info('Background service stopped');
        _publishServiceEvent('stopped');
        
        return stopped;
      },
      context: 'background_service_stop',
      component: 'background_service',
      fallbackValue: false,
    );
  }
  
  /// Register a background task
  String registerTask({
    required String name,
    required Future<void> Function() execute,
    TaskPriority priority = TaskPriority.normal,
    Duration? timeout,
    bool allowConcurrent = false,
    List<String>? dependencies,
    Map<String, dynamic>? metadata,
  }) {
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}';
    
    final task = BackgroundTask(
      id: taskId,
      name: name,
      execute: execute,
      priority: priority,
      timeout: timeout,
      allowConcurrent: allowConcurrent,
      dependencies: dependencies ?? [],
      metadata: metadata ?? {},
    );
    
    _tasks[taskId] = task;
    _enqueueTask(taskId);
    
    logger.fine('Registered task: $name (id: $taskId)');
    return taskId;
  }
  
  /// Schedule a task to run after a delay
  void scheduleTask({
    required String name,
    required Duration delay,
    required Future<void> Function() execute,
    bool recurring = false,
    TaskPriority priority = TaskPriority.normal,
  }) {
    final scheduleId = 'schedule_${DateTime.now().millisecondsSinceEpoch}';
    
    void runTask() {
      registerTask(
        name: name,
        execute: execute,
        priority: priority,
      );
    }
    
    if (recurring) {
      _scheduledTasks[scheduleId] = Timer.periodic(delay, (_) => runTask());
    } else {
      _scheduledTasks[scheduleId] = Timer(delay, runTask);
    }
    
    logger.fine('Scheduled task: $name (recurring: $recurring)');
  }
  
  /// Cancel a scheduled task
  void cancelScheduledTask(String scheduleId) {
    _scheduledTasks[scheduleId]?.cancel();
    _scheduledTasks.remove(scheduleId);
  }
  
  /// Cancel a pending task
  bool cancelTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return false;
    
    if (task.status == TaskStatus.pending) {
      task.status = TaskStatus.cancelled;
      _taskQueue.remove(taskId);
      logger.fine('Cancelled task: ${task.name}');
      return true;
    }
    
    return false;
  }
  
  /// Get task status
  TaskStatus? getTaskStatus(String taskId) {
    return _tasks[taskId]?.status;
  }
  
  /// Get all tasks
  List<BackgroundTask> getAllTasks() {
    return _tasks.values.toList();
  }
  
  /// Get running tasks
  List<BackgroundTask> getRunningTasks() {
    return _tasks.values
        .where((task) => task.status == TaskStatus.running)
        .toList();
  }
  
  /// Platform-specific initialization
  @protected
  Future<void> platformInitialize(BackgroundConfig config);
  
  /// Platform-specific start
  @protected
  Future<bool> platformStart();
  
  /// Platform-specific stop
  @protected
  Future<bool> platformStop();
  
  /// Start task processor
  void _startTaskProcessor() {
    _taskProcessor?.cancel();
    _taskProcessor = Timer.periodic(Duration(seconds: 1), (_) {
      _processNextTask();
    });
  }
  
  /// Process next task in queue
  void _processNextTask() {
    if (_taskQueue.isEmpty) return;
    
    // Find next runnable task
    String? taskId;
    for (final id in _taskQueue) {
      final task = _tasks[id];
      if (task != null && task.canRun && _canRunTask(task)) {
        taskId = id;
        break;
      }
    }
    
    if (taskId != null) {
      _taskQueue.remove(taskId);
      _executeTask(taskId);
    }
  }
  
  /// Check if task can run based on dependencies
  bool _canRunTask(BackgroundTask task) {
    // Check dependencies
    for (final depId in task.dependencies) {
      final dep = _tasks[depId];
      if (dep == null) continue;
      
      if (dep.status != TaskStatus.completed) {
        return false;
      }
    }
    
    // Check concurrent execution
    if (!task.allowConcurrent && _runningTasks.contains(task.id)) {
      return false;
    }
    
    return true;
  }
  
  /// Execute a task
  void _executeTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return;
    
    task.status = TaskStatus.running;
    task.startTime = DateTime.now();
    _runningTasks.add(taskId);
    
    logger.fine('Executing task: ${task.name}');
    _publishTaskEvent('started', task);
    
    // Execute with timeout and error handling
    Future<void> executeWithTimeout() {
      if (task.timeout != null) {
        return task.execute().timeout(task.timeout!);
      }
      return task.execute();
    }
    
    EnhancedErrorHandler.instance.handleError(
      executeWithTimeout,
      context: 'background_task_execution',
      component: 'background_service',
      metadata: {
        'taskId': taskId,
        'taskName': task.name,
        'priority': task.priority.name,
      },
      recoveryStrategy: 'retry',
    ).then((_) {
      // Task completed successfully
      task.status = TaskStatus.completed;
      task.endTime = DateTime.now();
      _runningTasks.remove(taskId);
      _totalTasksExecuted++;
      _taskExecutionCounts[task.name] = 
          (_taskExecutionCounts[task.name] ?? 0) + 1;
      
      logger.fine('Task completed: ${task.name} (${task.executionTime?.inMilliseconds}ms)');
      _publishTaskEvent('completed', task);
      
    }).catchError((error, stackTrace) {
      // Task failed
      task.status = TaskStatus.failed;
      task.endTime = DateTime.now();
      task.errorMessage = error.toString();
      _runningTasks.remove(taskId);
      _totalTasksFailed++;
      
      logger.severe('Task failed: ${task.name}', error, stackTrace);
      _publishTaskEvent('failed', task);
      
      // Retry if configured
      if (task.retryCount < (_config?.maxRetries ?? 0)) {
        task.retryCount++;
        task.status = TaskStatus.pending;
        _enqueueTask(taskId);
        logger.fine('Retrying task: ${task.name} (attempt ${task.retryCount})');
      }
    });
  }
  
  /// Enqueue task based on priority
  void _enqueueTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return;
    
    // Priority queue implementation
    final queueList = _taskQueue.toList();
    int insertIndex = queueList.length;
    
    for (int i = 0; i < queueList.length; i++) {
      final otherTask = _tasks[queueList[i]];
      if (otherTask != null && task.priority.index > otherTask.priority.index) {
        insertIndex = i;
        break;
      }
    }
    
    queueList.insert(insertIndex, taskId);
    _taskQueue.clear();
    _taskQueue.addAll(queueList);
  }
  
  /// Schedule jobs from configuration
  void _scheduleConfigJobs(List<Job> jobs) {
    for (final job in jobs) {
      if (!job.enabled) continue;
      
      scheduleTask(
        name: job.name,
        delay: _parseCronExpression(job.cronExpression),
        execute: () async {
          logger.fine('Executing scheduled job: ${job.name}');
          _publishJobEvent('executed', job);
        },
        recurring: true,
        priority: _parsePriority(job.priority),
      );
    }
  }
  
  /// Parse cron expression to duration (simplified)
  Duration _parseCronExpression(String cron) {
    // Simplified parsing - in real implementation, use a cron parser
    if (cron.contains('* * * * *')) {
      return Duration(minutes: 1);
    } else if (cron.contains('0 * * * *')) {
      return Duration(hours: 1);
    } else if (cron.contains('0 0 * * *')) {
      return Duration(days: 1);
    }
    return Duration(hours: 1); // Default
  }
  
  /// Parse priority string
  TaskPriority _parsePriority(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return TaskPriority.high;
      case 'low':
        return TaskPriority.low;
      default:
        return TaskPriority.normal;
    }
  }
  
  /// Cancel all scheduled tasks
  void _cancelAllScheduledTasks() {
    for (final timer in _scheduledTasks.values) {
      timer.cancel();
    }
    _scheduledTasks.clear();
  }
  
  /// Wait for running tasks to complete
  Future<void> _waitForRunningTasks() async {
    if (_runningTasks.isEmpty) return;
    
    logger.fine('Waiting for ${_runningTasks.length} running tasks to complete');
    
    final timeout = Duration(seconds: 30);
    final startTime = DateTime.now();
    
    while (_runningTasks.isNotEmpty) {
      if (DateTime.now().difference(startTime) > timeout) {
        logger.warning('Timeout waiting for tasks to complete');
        break;
      }
      
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
  
  @override
  Future<MCPHealthCheckResult> performHealthCheck() async {
    final pendingCount = _taskQueue.length;
    final failureRate = _totalTasksExecuted > 0 
        ? _totalTasksFailed / _totalTasksExecuted 
        : 0.0;
    
    MCPHealthStatus status;
    String message;
    
    if (!_isRunning) {
      status = MCPHealthStatus.unhealthy;
      message = 'Background service not running';
    } else if (failureRate > 0.5) {
      status = MCPHealthStatus.unhealthy;
      message = 'High task failure rate: ${(failureRate * 100).toStringAsFixed(1)}%';
    } else if (pendingCount > 100) {
      status = MCPHealthStatus.degraded;
      message = 'Large task backlog: $pendingCount pending tasks';
    } else if (failureRate > 0.2) {
      status = MCPHealthStatus.degraded;
      message = 'Elevated task failure rate: ${(failureRate * 100).toStringAsFixed(1)}%';
    } else {
      status = MCPHealthStatus.healthy;
      message = 'Background service operational';
    }
    
    return MCPHealthCheckResult(
      status: status,
      message: message,
      details: getStatistics(),
    );
  }
  
  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isRunning': _isRunning,
      'totalTasksExecuted': _totalTasksExecuted,
      'totalTasksFailed': _totalTasksFailed,
      'runningTasks': _runningTasks.length,
      'pendingTasks': _taskQueue.length,
      'scheduledTasks': _scheduledTasks.length,
      'taskExecutionCounts': _taskExecutionCounts,
      'tasks': _tasks.values.map((task) => {
        'id': task.id,
        'name': task.name,
        'status': task.status.name,
        'priority': task.priority.name,
        'executionTime': task.executionTime?.inMilliseconds,
        'retryCount': task.retryCount,
      }).toList(),
    };
  }
  
  /// Publish service event
  void _publishServiceEvent(String action) {
    _eventSystem.publish('background_service.$action', {
      'timestamp': DateTime.now().toIso8601String(),
      'statistics': getStatistics(),
    });
  }
  
  /// Publish task event
  void _publishTaskEvent(String action, BackgroundTask task) {
    _eventSystem.publish('background_task.$action', {
      'taskId': task.id,
      'taskName': task.name,
      'status': task.status.name,
      'priority': task.priority.name,
      'executionTime': task.executionTime?.inMilliseconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Publish job event
  void _publishJobEvent(String action, Job job) {
    _eventSystem.publish('background_job.$action', {
      'jobName': job.name,
      'cronExpression': job.cronExpression,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// Background service factory
class BackgroundServiceFactory {
  static BackgroundService create(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return AndroidEnhancedBackgroundService();
      case 'ios':
        return IOSEnhancedBackgroundService();
      case 'windows':
      case 'linux':
      case 'macos':
        return DesktopEnhancedBackgroundService();
      case 'web':
        return WebEnhancedBackgroundService();
      default:
        return NoOpBackgroundService();
    }
  }
}

// Placeholder implementations - these would be in separate files
class AndroidEnhancedBackgroundService extends EnhancedBackgroundService {
  AndroidEnhancedBackgroundService() : super('android');
  
  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    // Android-specific initialization
  }
  
  @override
  Future<bool> platformStart() async {
    // Android-specific start
    return true;
  }
  
  @override
  Future<bool> platformStop() async {
    // Android-specific stop
    return true;
  }
}

class IOSEnhancedBackgroundService extends EnhancedBackgroundService {
  IOSEnhancedBackgroundService() : super('ios');
  
  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    // iOS-specific initialization
  }
  
  @override
  Future<bool> platformStart() async {
    // iOS-specific start
    return true;
  }
  
  @override
  Future<bool> platformStop() async {
    // iOS-specific stop
    return true;
  }
}

class DesktopEnhancedBackgroundService extends EnhancedBackgroundService {
  DesktopEnhancedBackgroundService() : super('desktop');
  
  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    // Desktop-specific initialization
  }
  
  @override
  Future<bool> platformStart() async {
    // Desktop-specific start
    return true;
  }
  
  @override
  Future<bool> platformStop() async {
    // Desktop-specific stop
    return true;
  }
}

class WebEnhancedBackgroundService extends EnhancedBackgroundService {
  WebEnhancedBackgroundService() : super('web');
  
  @override
  Future<void> platformInitialize(BackgroundConfig config) async {
    // Web-specific initialization using Service Workers
  }
  
  @override
  Future<bool> platformStart() async {
    // Web-specific start
    return true;
  }
  
  @override
  Future<bool> platformStop() async {
    // Web-specific stop
    return true;
  }
}