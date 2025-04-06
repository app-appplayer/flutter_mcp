/// MCP Job schedule class
class MCPJob {
  /// Job ID
  final String? id;

  /// Job execution interval
  final Duration interval;

  /// Task function to execute
  final Function() task;

  /// Whether it's a one-time job
  final bool runOnce;

  /// Last execution time
  final DateTime? lastRun;

  /// Whether the job is paused
  final bool paused;

  /// Job display name (optional)
  final String? name;

  /// Job description (optional)
  final String? description;

  MCPJob({
    this.id,
    required this.interval,
    required this.task,
    this.runOnce = false,
    this.lastRun,
    this.paused = false,
    this.name,
    this.description,
  });

  /// Create a copy with updated properties
  MCPJob copyWith({
    String? id,
    Duration? interval,
    Function()? task,
    bool? runOnce,
    DateTime? lastRun,
    bool? paused,
    String? name,
    String? description,
  }) {
    return MCPJob(
      id: id ?? this.id,
      interval: interval ?? this.interval,
      task: task ?? this.task,
      runOnce: runOnce ?? this.runOnce,
      lastRun: lastRun ?? this.lastRun,
      paused: paused ?? this.paused,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }

  /// Create a periodic job
  factory MCPJob.every(Duration interval, {
    required Function() task,
    String? name,
    String? description,
  }) {
    return MCPJob(
      interval: interval,
      task: task,
      name: name,
      description: description,
    );
  }

  /// Create a one-time job
  factory MCPJob.once(Duration delay, {
    required Function() task,
    String? name,
    String? description,
  }) {
    return MCPJob(
      interval: delay,
      task: task,
      runOnce: true,
      name: name,
      description: description,
    );
  }

  /// Create a delayed job with callback
  factory MCPJob.delayed(Duration delay, {
    required Function() task,
    Function()? onComplete,
    String? name,
    String? description,
  }) {
    return MCPJob(
      interval: delay,
      task: () {
        task();
        onComplete?.call();
      },
      runOnce: true,
      name: name,
      description: description,
    );
  }

  /// Create a job with conditional execution
  factory MCPJob.conditional(
      Duration interval, {
        required Function() task,
        required bool Function() condition,
        String? name,
        String? description,
      }) {
    return MCPJob(
      interval: interval,
      task: () {
        if (condition()) {
          task();
        }
      },
      name: name,
      description: description,
    );
  }

  /// Convert to map for storage or display
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'interval_ms': interval.inMilliseconds,
      'run_once': runOnce,
      'last_run': lastRun?.toIso8601String(),
      'paused': paused,
      'name': name,
      'description': description,
    };
  }
}