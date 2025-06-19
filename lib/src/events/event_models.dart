import 'event_system.dart';

/// Base class for all MCP events
abstract class McpEvent extends Event {
  /// Type identifier for the event
  String get eventType;

  /// Constructor
  McpEvent({super.timestamp, super.metadata});

  /// Convert event to Map for backward compatibility
  Map<String, dynamic> toMap();
}

/// Memory-related events
class MemoryEvent extends McpEvent {
  @override
  String get eventType => 'memory.high';

  final int currentMB;
  final int thresholdMB;
  final int peakMB;

  MemoryEvent({
    required this.currentMB,
    required this.thresholdMB,
    required this.peakMB,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'currentMB': currentMB,
        'thresholdMB': thresholdMB,
        'peakMB': peakMB,
        'timestamp': timestamp.toIso8601String(),
      };

  factory MemoryEvent.fromMap(Map<String, dynamic> map) {
    return MemoryEvent(
      currentMB: map['currentMB'] as int,
      thresholdMB: map['thresholdMB'] as int,
      peakMB: map['peakMB'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Server status events
class ServerEvent extends McpEvent {
  @override
  String get eventType => 'server.status';

  final String serverId;
  final ServerStatus status;
  final String? message;

  ServerEvent({
    required this.serverId,
    required this.status,
    this.message,
    Map<String, dynamic>? metadata,
    super.timestamp,
  }) : super(metadata: metadata ?? {});

  @override
  Map<String, dynamic> toMap() => {
        'serverId': serverId,
        'status': status.name,
        'message': message,
        'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ServerEvent.fromMap(Map<String, dynamic> map) {
    return ServerEvent(
      serverId: map['serverId'] as String,
      status: ServerStatus.values.byName(map['status'] as String),
      message: map['message'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum ServerStatus { starting, running, stopping, stopped, error }

/// Client status events
class ClientEvent extends McpEvent {
  @override
  String get eventType => 'client.status';

  final String clientId;
  final ClientStatus status;
  final String? message;
  final String? serverUrl;

  ClientEvent({
    required this.clientId,
    required this.status,
    this.message,
    this.serverUrl,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'status': status.name,
        'message': message,
        'serverUrl': serverUrl,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ClientEvent.fromMap(Map<String, dynamic> map) {
    return ClientEvent(
      clientId: map['clientId'] as String,
      status: ClientStatus.values.byName(map['status'] as String),
      message: map['message'] as String?,
      serverUrl: map['serverUrl'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum ClientStatus { connecting, connected, disconnecting, disconnected, error }

/// Performance-related events
class PerformanceEvent extends McpEvent {
  @override
  String get eventType => 'performance.metric';

  final String metricName;
  final double value;
  final double? capacity;
  final MetricType type;
  final String? unit;

  PerformanceEvent({
    required this.metricName,
    required this.value,
    this.capacity,
    required this.type,
    this.unit,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'metricName': metricName,
        'value': value,
        'capacity': capacity,
        'type': type.name,
        'unit': unit,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PerformanceEvent.fromMap(Map<String, dynamic> map) {
    return PerformanceEvent(
      metricName: map['metricName'] as String,
      value: (map['value'] as num).toDouble(),
      capacity: (map['capacity'] as num?)?.toDouble(),
      type: MetricType.values.byName(map['type'] as String),
      unit: map['unit'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum MetricType { counter, gauge, histogram, timer }

/// Error/exception events
class ErrorEvent extends McpEvent {
  @override
  String get eventType => 'error.occurred';

  final String errorCode;
  final String message;
  final String? component;
  final ErrorSeverity severity;
  final String? stackTrace;
  final Map<String, dynamic>? context;

  ErrorEvent({
    required this.errorCode,
    required this.message,
    this.component,
    required this.severity,
    this.stackTrace,
    this.context,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'errorCode': errorCode,
        'message': message,
        'component': component,
        'severity': severity.name,
        'stackTrace': stackTrace,
        'context': context,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ErrorEvent.fromMap(Map<String, dynamic> map) {
    return ErrorEvent(
      errorCode: map['errorCode'] as String,
      message: map['message'] as String,
      component: map['component'] as String?,
      severity: ErrorSeverity.values.byName(map['severity'] as String),
      stackTrace: map['stackTrace'] as String?,
      context: map['context'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum ErrorSeverity { low, medium, high, critical }

/// Alert severity levels
enum AlertSeverity { info, low, medium, high, critical }

/// Security events
class SecurityEvent extends McpEvent {
  @override
  String get eventType => 'security.event';

  final String eventType_;
  final AlertSeverity severity;
  final String message;
  final String? userId;
  final Map<String, dynamic> details;

  SecurityEvent({
    required this.eventType_,
    required this.severity,
    required this.message,
    this.userId,
    Map<String, dynamic>? details,
    super.timestamp,
  }) : details = details ?? {};

  @override
  Map<String, dynamic> toMap() => {
        'eventType': eventType_,
        'severity': severity.name,
        'message': message,
        'userId': userId,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SecurityEvent.fromMap(Map<String, dynamic> map) {
    return SecurityEvent(
      eventType_: map['eventType'] as String,
      severity: AlertSeverity.values.byName(map['severity'] as String),
      message: map['message'] as String,
      userId: map['userId'] as String?,
      details: Map<String, dynamic>.from(map['details'] ?? {}),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Security alert events
class SecurityAlert extends McpEvent {
  @override
  String get eventType => 'security.alert';

  final AlertSeverity severity;
  final String title;
  final String message;
  final Map<String, dynamic> details;

  SecurityAlert({
    required this.severity,
    required this.title,
    required this.message,
    Map<String, dynamic>? details,
    super.timestamp,
  }) : details = details ?? {};

  @override
  Map<String, dynamic> toMap() => {
        'severity': severity.name,
        'title': title,
        'message': message,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SecurityAlert.fromMap(Map<String, dynamic> map) {
    return SecurityAlert(
      severity: AlertSeverity.values.byName(map['severity'] as String),
      title: map['title'] as String,
      message: map['message'] as String,
      details: Map<String, dynamic>.from(map['details'] ?? {}),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Plugin lifecycle events
class PluginEvent extends McpEvent {
  @override
  String get eventType => 'plugin.lifecycle';

  final String pluginId;
  final String? version;
  final PluginLifecycleState state;
  final String? message;
  final Map<String, dynamic>? pluginMetadata;

  PluginEvent({
    required this.pluginId,
    this.version,
    required this.state,
    this.message,
    this.pluginMetadata,
    super.timestamp,
    super.metadata,
  });

  @override
  Map<String, dynamic> toMap() => {
        'pluginId': pluginId,
        'version': version,
        'state': state.name,
        'message': message,
        'pluginMetadata': pluginMetadata,
        'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PluginEvent.fromMap(Map<String, dynamic> map) {
    return PluginEvent(
      pluginId: map['pluginId'] as String,
      version: map['version'] as String?,
      state: PluginLifecycleState.values.byName(map['state'] as String),
      message: map['message'] as String?,
      pluginMetadata: map['pluginMetadata'] as Map<String, dynamic>?,
      metadata: map['metadata'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum PluginLifecycleState {
  loading,
  loaded,
  initializing,
  initialized,
  running,
  stopping,
  stopped,
  error
}

/// Background task events
class BackgroundTaskEvent extends McpEvent {
  @override
  String get eventType => 'background.task';

  final String taskId;
  final String taskType;
  final TaskStatus status;
  final String? message;
  final Duration? duration;
  final Map<String, dynamic>? result;

  BackgroundTaskEvent({
    required this.taskId,
    required this.taskType,
    required this.status,
    this.message,
    this.duration,
    this.result,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'taskType': taskType,
        'status': status.name,
        'message': message,
        'durationMs': duration?.inMilliseconds,
        'result': result,
        'timestamp': timestamp.toIso8601String(),
      };

  factory BackgroundTaskEvent.fromMap(Map<String, dynamic> map) {
    return BackgroundTaskEvent(
      taskId: map['taskId'] as String,
      taskType: map['taskType'] as String,
      status: TaskStatus.values.byName(map['status'] as String),
      message: map['message'] as String?,
      duration: map['durationMs'] != null
          ? Duration(milliseconds: map['durationMs'] as int)
          : null,
      result: map['result'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum TaskStatus { queued, running, completed, failed, cancelled }

/// Authentication/authorization events
class AuthEvent extends McpEvent {
  @override
  String get eventType => 'auth.event';

  final String userId;
  final AuthAction action;
  final bool success;
  final String? reason;
  final String? ipAddress;
  final String? userAgent;

  AuthEvent({
    required this.userId,
    required this.action,
    required this.success,
    this.reason,
    this.ipAddress,
    this.userAgent,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'action': action.name,
        'success': success,
        'reason': reason,
        'ipAddress': ipAddress,
        'userAgent': userAgent,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AuthEvent.fromMap(Map<String, dynamic> map) {
    return AuthEvent(
      userId: map['userId'] as String,
      action: AuthAction.values.byName(map['action'] as String),
      success: map['success'] as bool,
      reason: map['reason'] as String?,
      ipAddress: map['ipAddress'] as String?,
      userAgent: map['userAgent'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum AuthAction { login, logout, refresh, revoke, validate }
