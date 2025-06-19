/// Background job configuration
class Job {
  /// Job name
  final String name;

  /// Cron expression for scheduling
  final String cronExpression;

  /// Whether the job is enabled
  final bool enabled;

  /// Job priority (high, normal, low)
  final String? priority;

  /// Whether to run on boot
  final bool runOnBoot;

  /// Maximum execution time
  final Duration? maxExecutionTime;

  /// Retry on failure
  final bool retryOnFailure;

  /// Maximum retry attempts
  final int maxRetries;

  /// Job metadata
  final Map<String, dynamic>? metadata;

  Job({
    required this.name,
    required this.cronExpression,
    this.enabled = true,
    this.priority,
    this.runOnBoot = false,
    this.maxExecutionTime,
    this.retryOnFailure = true,
    this.maxRetries = 3,
    this.metadata,
  });

  /// Create from JSON
  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      name: json['name'] as String,
      cronExpression: json['cronExpression'] as String,
      enabled: json['enabled'] as bool? ?? true,
      priority: json['priority'] as String?,
      runOnBoot: json['runOnBoot'] as bool? ?? false,
      maxExecutionTime: json['maxExecutionTimeMs'] != null
          ? Duration(milliseconds: json['maxExecutionTimeMs'] as int)
          : null,
      retryOnFailure: json['retryOnFailure'] as bool? ?? true,
      maxRetries: json['maxRetries'] as int? ?? 3,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'cronExpression': cronExpression,
      'enabled': enabled,
      'priority': priority,
      'runOnBoot': runOnBoot,
      'maxExecutionTimeMs': maxExecutionTime?.inMilliseconds,
      'retryOnFailure': retryOnFailure,
      'maxRetries': maxRetries,
      'metadata': metadata,
    };
  }

  /// Validate the job configuration
  bool validate() {
    if (name.isEmpty) return false;
    if (cronExpression.isEmpty) return false;
    if (maxRetries < 0) return false;
    return true;
  }
}
