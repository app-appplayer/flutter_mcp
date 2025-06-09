# Background Jobs Example

This example demonstrates how to schedule and manage background tasks using Flutter MCP.

## Overview

This example shows how to:
- Schedule periodic background jobs
- Handle platform-specific background implementations
- Manage job lifecycle
- Persist job state across app restarts

## Code Example

### Configuration

```dart
// lib/config/job_config.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class JobConfig {
  static List<JobDefinition> get jobs => [
    JobDefinition(
      id: 'sync-data',
      name: 'Data Synchronization',
      description: 'Sync local data with server',
      interval: Duration(minutes: 15),
      callback: _syncData,
      constraints: JobConstraints(
        requiresNetwork: true,
        requiresCharging: false,
        requiresIdle: false,
      ),
    ),
    JobDefinition(
      id: 'cleanup-cache',
      name: 'Cache Cleanup',
      description: 'Clean old cache files',
      interval: Duration(hours: 24),
      callback: _cleanupCache,
      constraints: JobConstraints(
        requiresNetwork: false,
        requiresCharging: true,
        requiresIdle: true,
      ),
    ),
    JobDefinition(
      id: 'fetch-notifications',
      name: 'Fetch Notifications',
      description: 'Check for new notifications',
      interval: Duration(minutes: 30),
      callback: _fetchNotifications,
      constraints: JobConstraints(
        requiresNetwork: true,
        requiresCharging: false,
        requiresIdle: false,
      ),
    ),
  ];
  
  static Future<JobResult> _syncData() async {
    try {
      final server = await FlutterMCP.connect('primary-server');
      final localData = await LocalStorage.getUnsyncedData();
      
      if (localData.isEmpty) {
        return JobResult.success('No data to sync');
      }
      
      final result = await server.execute('syncData', {
        'data': localData,
        'lastSync': await LocalStorage.getLastSyncTime(),
      });
      
      await LocalStorage.markDataAsSynced(localData);
      await LocalStorage.setLastSyncTime(DateTime.now());
      
      return JobResult.success('Synced ${localData.length} items');
    } catch (e) {
      return JobResult.failure('Sync failed: $e');
    }
  }
  
  static Future<JobResult> _cleanupCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();
      int deletedCount = 0;
      
      for (final file in files) {
        if (file is File) {
          final age = DateTime.now().difference(file.lastModifiedSync());
          if (age > Duration(days: 7)) {
            file.deleteSync();
            deletedCount++;
          }
        }
      }
      
      return JobResult.success('Deleted $deletedCount cache files');
    } catch (e) {
      return JobResult.failure('Cleanup failed: $e');
    }
  }
  
  static Future<JobResult> _fetchNotifications() async {
    try {
      final server = await FlutterMCP.connect('notification-server');
      final result = await server.execute('getNotifications', {
        'since': await LocalStorage.getLastNotificationCheck(),
      });
      
      final notifications = result['notifications'] as List;
      
      if (notifications.isNotEmpty) {
        for (final notification in notifications) {
          await NotificationService.show(
            title: notification['title'],
            body: notification['body'],
            payload: notification['payload'],
          );
        }
      }
      
      await LocalStorage.setLastNotificationCheck(DateTime.now());
      
      return JobResult.success('Fetched ${notifications.length} notifications');
    } catch (e) {
      return JobResult.failure('Notification fetch failed: $e');
    }
  }
}
```

### Background Service Implementation

```dart
// lib/services/background_service.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:isolate';

class BackgroundServiceImpl {
  static const String _channelName = 'mcp_background_jobs';
  
  static Future<void> initialize() async {
    // Platform-specific initialization
    if (Platform.isAndroid) {
      await _initializeAndroid();
    } else if (Platform.isIOS) {
      await _initializeIOS();
    } else {
      await _initializeDesktop();
    }
  }
  
  static Future<void> _initializeAndroid() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }
  
  static Future<void> _initializeIOS() async {
    // Use BGTaskScheduler for iOS 13+
    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 15,
        forceAlarmManager: false,
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: true,
      ),
      _backgroundFetchHeadlessTask,
    );
  }
  
  static Future<void> _initializeDesktop() async {
    // Desktop platforms use isolates
    await _setupDesktopIsolate();
  }
  
  static Future<void> scheduleJob(JobDefinition job) async {
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        job.id,
        job.name,
        frequency: job.interval,
        constraints: Constraints(
          networkType: job.constraints.requiresNetwork
              ? NetworkType.connected
              : NetworkType.not_required,
          requiresBatteryNotLow: !job.constraints.requiresCharging,
          requiresCharging: job.constraints.requiresCharging,
          requiresDeviceIdle: job.constraints.requiresIdle,
        ),
        inputData: {
          'jobId': job.id,
        },
      );
    } else if (Platform.isIOS) {
      await BGTaskScheduler.shared.register(
        job.id,
        job.interval.inMinutes,
      );
    } else {
      await _scheduleDesktopJob(job);
    }
  }
  
  static Future<void> cancelJob(String jobId) async {
    if (Platform.isAndroid) {
      await Workmanager().cancelByUniqueName(jobId);
    } else if (Platform.isIOS) {
      await BGTaskScheduler.shared.cancel(jobId);
    } else {
      await _cancelDesktopJob(jobId);
    }
  }
  
  static Future<void> _scheduleDesktopJob(JobDefinition job) async {
    // Desktop implementation using Timer
    Timer.periodic(job.interval, (timer) async {
      await _executeJob(job);
    });
  }
  
  static Future<void> _executeJob(JobDefinition job) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Execute in isolate to avoid blocking UI
      final result = await Isolate.run(() => job.callback());
      
      stopwatch.stop();
      
      // Log execution
      await _logJobExecution(
        jobId: job.id,
        result: result,
        duration: stopwatch.elapsed,
      );
      
      // Notify listeners
      JobEventBus.emit(JobExecutedEvent(
        jobId: job.id,
        result: result,
        duration: stopwatch.elapsed,
      ));
    } catch (e, stack) {
      stopwatch.stop();
      
      final result = JobResult.failure(e.toString());
      
      await _logJobExecution(
        jobId: job.id,
        result: result,
        duration: stopwatch.elapsed,
        error: e,
        stackTrace: stack,
      );
      
      JobEventBus.emit(JobFailedEvent(
        jobId: job.id,
        error: e,
        stackTrace: stack,
      ));
    }
  }
}

// Android callback dispatcher
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await FlutterMCP.initialize();
      
      final jobId = inputData!['jobId'] as String;
      final job = JobConfig.jobs.firstWhere((j) => j.id == jobId);
      
      final result = await job.callback();
      
      return result.success;
    } catch (e) {
      return false;
    }
  });
}

// iOS background fetch handler  
void _backgroundFetchHeadlessTask(HeadlessTask task) async {
  if (task.timeout) {
    BackgroundFetch.finish(task.taskId);
    return;
  }
  
  try {
    await FlutterMCP.initialize();
    
    // Execute all due jobs
    for (final job in JobConfig.jobs) {
      if (_shouldExecuteJob(job)) {
        await job.callback();
      }
    }
    
    BackgroundFetch.finish(task.taskId);
  } catch (e) {
    BackgroundFetch.finish(task.taskId);
  }
}
```

### Job Management UI

```dart
// lib/screens/job_management_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/job_provider.dart';

class JobManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Background Jobs'),
      ),
      body: Consumer<JobProvider>(
        builder: (context, provider, child) {
          return ListView.builder(
            itemCount: provider.jobs.length,
            itemBuilder: (context, index) {
              final job = provider.jobs[index];
              final status = provider.getJobStatus(job.id);
              final lastRun = provider.getLastRun(job.id);
              
              return Card(
                margin: EdgeInsets.all(8),
                child: ExpansionTile(
                  title: Text(job.name),
                  subtitle: Text(job.description),
                  leading: _buildStatusIcon(status),
                  trailing: Switch(
                    value: status.isEnabled,
                    onChanged: (enabled) {
                      if (enabled) {
                        provider.enableJob(job.id);
                      } else {
                        provider.disableJob(job.id);
                      }
                    },
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Interval', job.interval.toString()),
                          _buildInfoRow('Last Run', lastRun?.toString() ?? 'Never'),
                          _buildInfoRow('Status', status.toString()),
                          if (status.lastError != null)
                            _buildInfoRow('Last Error', status.lastError!),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                icon: Icon(Icons.play_arrow),
                                label: Text('Run Now'),
                                onPressed: status.isRunning
                                    ? null
                                    : () => provider.runJobNow(job.id),
                              ),
                              OutlinedButton.icon(
                                icon: Icon(Icons.history),
                                label: Text('View History'),
                                onPressed: () => _showJobHistory(context, job.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
  
  Widget _buildStatusIcon(JobStatus status) {
    if (status.isRunning) {
      return CircularProgressIndicator(strokeWidth: 2);
    }
    
    IconData icon;
    Color color;
    
    if (!status.isEnabled) {
      icon = Icons.pause_circle;
      color = Colors.grey;
    } else if (status.lastError != null) {
      icon = Icons.error;
      color = Colors.red;
    } else {
      icon = Icons.check_circle;
      color = Colors.green;
    }
    
    return Icon(icon, color: color);
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
  
  void _showJobHistory(BuildContext context, String jobId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JobHistoryScreen(jobId: jobId),
      ),
    );
  }
}
```

### Job Provider

```dart
// lib/providers/job_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class JobProvider extends ChangeNotifier {
  final BackgroundService _backgroundService;
  final Map<String, JobStatus> _jobStatuses = {};
  final Map<String, DateTime> _lastRuns = {};
  final Map<String, List<JobExecution>> _jobHistory = {};
  
  List<JobDefinition> get jobs => JobConfig.jobs;
  
  JobProvider(this._backgroundService) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Load job statuses from storage
    final savedStatuses = await LocalStorage.getJobStatuses();
    _jobStatuses.addAll(savedStatuses);
    
    // Load job history
    final savedHistory = await LocalStorage.getJobHistory();
    _jobHistory.addAll(savedHistory);
    
    // Subscribe to job events
    JobEventBus.on<JobExecutedEvent>().listen((event) {
      _handleJobExecuted(event);
    });
    
    JobEventBus.on<JobFailedEvent>().listen((event) {
      _handleJobFailed(event);
    });
    
    notifyListeners();
  }
  
  JobStatus getJobStatus(String jobId) {
    return _jobStatuses[jobId] ?? JobStatus.disabled();
  }
  
  DateTime? getLastRun(String jobId) {
    return _lastRuns[jobId];
  }
  
  List<JobExecution> getJobHistory(String jobId) {
    return _jobHistory[jobId] ?? [];
  }
  
  Future<void> enableJob(String jobId) async {
    final job = jobs.firstWhere((j) => j.id == jobId);
    
    await _backgroundService.scheduleJob(job);
    
    _jobStatuses[jobId] = JobStatus.enabled();
    await LocalStorage.saveJobStatus(jobId, _jobStatuses[jobId]!);
    
    notifyListeners();
  }
  
  Future<void> disableJob(String jobId) async {
    await _backgroundService.cancelJob(jobId);
    
    _jobStatuses[jobId] = JobStatus.disabled();
    await LocalStorage.saveJobStatus(jobId, _jobStatuses[jobId]!);
    
    notifyListeners();
  }
  
  Future<void> runJobNow(String jobId) async {
    final job = jobs.firstWhere((j) => j.id == jobId);
    
    _jobStatuses[jobId] = JobStatus.running();
    notifyListeners();
    
    try {
      final result = await job.callback();
      _handleJobExecuted(JobExecutedEvent(
        jobId: jobId,
        result: result,
        duration: Duration.zero,
      ));
    } catch (e, stack) {
      _handleJobFailed(JobFailedEvent(
        jobId: jobId,
        error: e,
        stackTrace: stack,
      ));
    }
  }
  
  void _handleJobExecuted(JobExecutedEvent event) {
    _jobStatuses[event.jobId] = JobStatus.enabled();
    _lastRuns[event.jobId] = DateTime.now();
    
    final execution = JobExecution(
      jobId: event.jobId,
      timestamp: DateTime.now(),
      result: event.result,
      duration: event.duration,
    );
    
    _jobHistory.putIfAbsent(event.jobId, () => []).add(execution);
    
    LocalStorage.saveJobExecution(event.jobId, execution);
    
    notifyListeners();
  }
  
  void _handleJobFailed(JobFailedEvent event) {
    _jobStatuses[event.jobId] = JobStatus.error(event.error.toString());
    
    final execution = JobExecution(
      jobId: event.jobId,
      timestamp: DateTime.now(),
      result: JobResult.failure(event.error.toString()),
      duration: Duration.zero,
      error: event.error,
      stackTrace: event.stackTrace,
    );
    
    _jobHistory.putIfAbsent(event.jobId, () => []).add(execution);
    
    LocalStorage.saveJobExecution(event.jobId, execution);
    
    notifyListeners();
  }
}

class JobStatus {
  final bool isEnabled;
  final bool isRunning;
  final String? lastError;
  
  JobStatus({
    required this.isEnabled,
    required this.isRunning,
    this.lastError,
  });
  
  factory JobStatus.enabled() => JobStatus(
    isEnabled: true,
    isRunning: false,
  );
  
  factory JobStatus.disabled() => JobStatus(
    isEnabled: false,
    isRunning: false,
  );
  
  factory JobStatus.running() => JobStatus(
    isEnabled: true,
    isRunning: true,
  );
  
  factory JobStatus.error(String error) => JobStatus(
    isEnabled: true,
    isRunning: false,
    lastError: error,
  );
}
```

### Platform-Specific Implementations

#### Android Implementation

```kotlin
// android/app/src/main/kotlin/com/example/app/BackgroundService.kt
class BackgroundService : HeadlessJsTaskService() {
    override fun getTaskConfig(intent: Intent): HeadlessJsTaskConfig? {
        return intent.extras?.let {
            HeadlessJsTaskConfig(
                "BackgroundTask",
                Arguments.fromBundle(it),
                5000, // timeout
                true // allowedInForeground
            )
        }
    }
}
```

#### iOS Implementation

```swift
// ios/Runner/BackgroundTasks.swift
import BackgroundTasks

@available(iOS 13.0, *)
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.example.app.refresh",
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Execute Flutter background task
        FlutterBackgroundService.shared.executeTask { success in
            task.setTaskCompleted(success: success)
        }
        
        // Schedule next refresh
        scheduleAppRefresh()
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.example.app.refresh"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
}
```

## Testing

```dart
// test/background_job_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp_test/flutter_mcp_test.dart';

void main() {
  group('Background Jobs', () {
    test('executes sync job successfully', () async {
      // Mock server response
      MCPTestEnvironment.mockServer('primary-server', {
        'syncData': (params) => {
          'synced': params['data'].length,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });
      
      // Mock local storage
      MockLocalStorage.setUnsyncedData([
        {'id': 1, 'data': 'test1'},
        {'id': 2, 'data': 'test2'},
      ]);
      
      // Execute job
      final result = await JobConfig.jobs
          .firstWhere((j) => j.id == 'sync-data')
          .callback();
      
      expect(result.success, isTrue);
      expect(result.message, contains('Synced 2 items'));
    });
    
    test('handles job failure gracefully', () async {
      // Mock server error
      MCPTestEnvironment.mockServerError(
        'primary-server',
        'syncData',
        MCPException('Server unavailable'),
      );
      
      // Execute job
      final result = await JobConfig.jobs
          .firstWhere((j) => j.id == 'sync-data')
          .callback();
      
      expect(result.success, isFalse);
      expect(result.message, contains('Sync failed'));
    });
    
    test('respects job constraints', () async {
      final job = JobDefinition(
        id: 'test-job',
        name: 'Test Job',
        description: 'Test',
        interval: Duration(minutes: 1),
        callback: () async => JobResult.success('Done'),
        constraints: JobConstraints(
          requiresNetwork: true,
          requiresCharging: true,
          requiresIdle: true,
        ),
      );
      
      // Simulate constraints not met
      MockDeviceStatus.setNetworkAvailable(false);
      
      final shouldRun = await BackgroundService.shouldExecuteJob(job);
      expect(shouldRun, isFalse);
    });
  });
}
```

## Key Concepts

### Job Constraints

Jobs can specify execution constraints:

```dart
JobConstraints(
  requiresNetwork: true,    // Only run with network
  requiresCharging: true,   // Only run when charging
  requiresIdle: true,       // Only run when device idle
  requiredNetworkType: NetworkType.unmetered, // WiFi only
)
```

### Job Lifecycle

1. **Scheduled**: Job is registered with the system
2. **Pending**: Waiting for constraints to be met
3. **Running**: Job is currently executing
4. **Completed**: Job finished successfully
5. **Failed**: Job encountered an error

### Error Recovery

Jobs should handle errors gracefully:

```dart
try {
  // Perform work
  return JobResult.success('Completed');
} catch (e) {
  // Log error
  logger.error('Job failed', error: e);
  
  // Retry logic
  if (shouldRetry(e)) {
    return JobResult.retry('Will retry');
  }
  
  return JobResult.failure('Failed: $e');
}
```

## Best Practices

1. **Keep Jobs Short**: Background jobs have limited execution time
2. **Handle Interruptions**: Jobs may be killed by the system
3. **Persist State**: Save progress to resume if interrupted
4. **Battery Efficient**: Minimize battery usage
5. **Test Thoroughly**: Test on all target platforms

## Next Steps

- Explore [Plugin Development](./plugin-development.md)
- Learn about [State Management](./state-management.md)
- Try [Real-time Updates](./realtime-updates.md)