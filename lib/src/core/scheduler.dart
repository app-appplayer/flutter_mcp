import 'dart:async';
import '../config/job.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// MCP Job scheduler
class MCPScheduler {
  /// Registered jobs
  final Map<String, MCPJob> _jobs = {};

  /// Timer for job checking
  Timer? _timer;

  /// Running status
  bool _isRunning = false;

  /// Logger
  final MCPLogger _logger = MCPLogger('mcp.scheduler');

  /// Jobs in execution
  final Set<String> _runningJobs = {};

  /// Job execution history (last 100 executions)
  final List<_JobExecution> _executionHistory = [];

  /// Maximum history size
  final int _maxHistorySize = 100;

  /// Running status
  bool get isRunning => _isRunning;

  /// Number of registered jobs
  int get jobCount => _jobs.length;

  /// Initialize the scheduler
  void initialize() {
    _logger.debug('Scheduler initialization');
  }

  /// Add a job
  String addJob(MCPJob job) {
    final jobId = job.id ?? 'job_${DateTime.now().millisecondsSinceEpoch}_${_jobs.length}';
    _jobs[jobId] = job.copyWith(id: jobId);
    _logger.debug('Job added: $jobId, interval: ${job.interval}');
    return jobId;
  }

  /// Remove a job
  void removeJob(String jobId) {
    _logger.debug('Removing job: $jobId');
    _jobs.remove(jobId);
  }

  /// Start the scheduler
  void start() {
    if (_isRunning) {
      _logger.warning('Scheduler is already running');
      return;
    }

    _logger.debug('Starting scheduler');

    // Cancel any existing timer to avoid duplicates
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), _checkJobs);
    _isRunning = true;
  }

  /// Stop the scheduler
  void stop() {
    _logger.debug('Stopping scheduler');

    // Cancel the timer if it exists
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }

    _isRunning = false;
  }

  /// Check jobs for execution
  void _checkJobs(Timer timer) {
    final now = DateTime.now();

    for (final entry in _jobs.entries.toList()) {
      final jobId = entry.key;
      final job = entry.value;

      // Skip if job is already running (avoid concurrent execution)
      if (_runningJobs.contains(jobId)) {
        continue;
      }

      if (job.lastRun == null ||
          now.difference(job.lastRun!) >= job.interval) {
        // Execute job
        _executeJob(jobId, job, now);
      }
    }
  }

  /// Execute a job
  void _executeJob(String jobId, MCPJob job, DateTime now) {
    _logger.debug('Executing job: $jobId');

    // Mark job as running
    _runningJobs.add(jobId);

    // Record execution start
    final execution = _JobExecution(
        jobId: jobId,
        startTime: now,
        status: _JobExecutionStatus.running
    );
    _addToHistory(execution);

    try {
      // Execute job task
      job.task();

      // Update execution record
      execution.complete();

      // Update last run time
      _jobs[jobId] = job.copyWith(lastRun: now);

      // Remove one-time job if needed
      if (job.runOnce) {
        _logger.debug('Removing one-time job: $jobId');
        _jobs.remove(jobId);
      }
    } catch (e, stackTrace) {
      _logger.error('Error executing job: $jobId', e, stackTrace);

      // Update execution record with error
      execution.fail(e.toString());
    } finally {
      // Mark job as not running anymore
      _runningJobs.remove(jobId);
    }
  }

  /// Get job information
  MCPJob? getJob(String jobId) {
    return _jobs[jobId];
  }

  /// Get all job IDs
  List<String> getAllJobIds() {
    return _jobs.keys.toList();
  }

  /// Get list of jobs
  List<MCPJob> getAllJobs() {
    return _jobs.values.toList();
  }

  /// Check if a job exists
  bool hasJob(String jobId) {
    return _jobs.containsKey(jobId);
  }

  /// Get job execution history
  List<Map<String, dynamic>> getExecutionHistory() {
    return _executionHistory.map((e) => e.toJson()).toList();
  }

  /// Pause a job
  void pauseJob(String jobId) {
    final job = _jobs[jobId];
    if (job != null) {
      _jobs[jobId] = job.copyWith(paused: true);
      _logger.debug('Job paused: $jobId');
    }
  }

  /// Resume a job
  void resumeJob(String jobId) {
    final job = _jobs[jobId];
    if (job != null) {
      _jobs[jobId] = job.copyWith(paused: false);
      _logger.debug('Job resumed: $jobId');
    }
  }

  /// Get job status
  Map<String, dynamic> getJobStatus(String jobId) {
    final job = _jobs[jobId];
    if (job == null) {
      throw MCPResourceNotFoundException(jobId, 'Job not found');
    }

    return {
      'id': jobId,
      'running': _runningJobs.contains(jobId),
      'paused': job.paused,
      'last_run': job.lastRun?.toIso8601String(),
      'interval': job.interval.inMilliseconds,
      'one_time': job.runOnce,
    };
  }

  /// Add execution to history
  void _addToHistory(_JobExecution execution) {
    _executionHistory.add(execution);

    // Trim history if needed
    while (_executionHistory.length > _maxHistorySize) {
      _executionHistory.removeAt(0);
    }
  }

  /// Clean up resources
  void dispose() {
    stop();
    _jobs.clear();
    _runningJobs.clear();
    _executionHistory.clear();
    _logger.debug('Scheduler disposed');
  }
}

/// Job execution record
class _JobExecution {
  final String jobId;
  final DateTime startTime;
  DateTime? endTime;
  _JobExecutionStatus status;
  String? errorMessage;

  _JobExecution({
    required this.jobId,
    required this.startTime,
    required this.status,
  });

  /// Mark as completed
  void complete() {
    endTime = DateTime.now();
    status = _JobExecutionStatus.completed;
  }

  /// Mark as failed
  void fail(String message) {
    endTime = DateTime.now();
    status = _JobExecutionStatus.failed;
    errorMessage = message;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'job_id': jobId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'status': status.toString().split('.').last,
      'duration': endTime?.difference(startTime).inMilliseconds,
      'error': errorMessage,
    };
  }
}

/// Job execution status
enum _JobExecutionStatus {
  running,
  completed,
  failed,
}