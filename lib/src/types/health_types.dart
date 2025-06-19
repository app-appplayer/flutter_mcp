/// Health status enumeration
enum MCPHealthStatus { healthy, degraded, unhealthy }

/// Health check result
class MCPHealthCheckResult {
  final MCPHealthStatus status;
  final String? message;
  final Map<String, dynamic>? details;
  final DateTime timestamp;

  MCPHealthCheckResult({
    required this.status,
    this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'message': message,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };

  factory MCPHealthCheckResult.fromJson(Map<String, dynamic> json) {
    return MCPHealthCheckResult(
      status: MCPHealthStatus.values.byName(json['status'] as String),
      message: json['message'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
