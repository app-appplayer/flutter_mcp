/// Event builder utility for consistent event publishing patterns
library;

import '../events/event_models.dart';
import '../utils/event_system.dart';
import '../utils/logger.dart';

/// Builder for creating and publishing events consistently
class EventBuilder {
  static final Logger _logger = Logger('flutter_mcp.EventBuilder');
  
  /// Build and publish a client event
  static void publishClientEvent({
    required String clientId,
    required ClientStatus status,
    String? message,
    String? serverUrl,
  }) {
    final event = ClientEvent(
      clientId: clientId,
      status: status,
      message: message,
      serverUrl: serverUrl,
    );
    
    _logger.fine('Publishing client event: $clientId -> ${status.name}');
    EventSystem.instance.publishTyped<ClientEvent>(event);
  }
  
  /// Build and publish a server event
  static void publishServerEvent({
    required String serverId,
    required ServerStatus status,
    String? message,
    Map<String, dynamic>? metadata,
  }) {
    final event = ServerEvent(
      serverId: serverId,
      status: status,
      message: message,
      metadata: metadata,
    );
    
    _logger.fine('Publishing server event: $serverId -> ${status.name}');
    EventSystem.instance.publishTyped<ServerEvent>(event);
  }
  
  /// Build and publish a performance event
  static void publishPerformanceEvent({
    required String metricName,
    required double value,
    double? capacity,
    MetricType type = MetricType.gauge,
    String? unit,
  }) {
    final event = PerformanceEvent(
      metricName: metricName,
      value: value,
      capacity: capacity,
      type: type,
      unit: unit,
    );
    
    _logger.finest('Publishing performance event: $metricName = $value${unit ?? ''}');
    EventSystem.instance.publishTyped<PerformanceEvent>(event);
  }
  
  /// Build and publish a plugin event
  static void publishPluginEvent({
    required String pluginId,
    required PluginLifecycleState state,
    String? version,
    String? message,
    Map<String, dynamic>? metadata,
  }) {
    final event = PluginEvent(
      pluginId: pluginId,
      state: state,
      version: version,
      message: message,
      metadata: metadata,
    );
    
    _logger.fine('Publishing plugin event: $pluginId -> ${state.name}');
    EventSystem.instance.publishTyped<PluginEvent>(event);
  }
  
  /// Build and publish an error event
  static void publishErrorEvent({
    required String errorCode,
    required String message,
    String? component,
    ErrorSeverity severity = ErrorSeverity.medium,
    String? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final event = ErrorEvent(
      errorCode: errorCode,
      message: message,
      component: component,
      severity: severity,
      stackTrace: stackTrace,
      context: context,
    );
    
    final logLevel = _getLogLevelForSeverity(severity);
    _logger.log(logLevel, 'Publishing error event: $component - $message');
    EventSystem.instance.publishTyped<ErrorEvent>(event);
  }
  
  /// Build and publish a memory event
  static void publishMemoryEvent({
    required int currentMB,
    required int thresholdMB,
    required int peakMB,
  }) {
    final event = MemoryEvent(
      currentMB: currentMB,
      thresholdMB: thresholdMB,
      peakMB: peakMB,
    );
    
    _logger.fine('Publishing memory event: ${currentMB}MB / ${thresholdMB}MB (peak: ${peakMB}MB)');
    EventSystem.instance.publishTyped<MemoryEvent>(event);
  }
  
  /// Build and publish a background task event
  static void publishBackgroundTaskEvent({
    required String taskId,
    required String taskType,
    required TaskStatus status,
    String? message,
    Duration? duration,
    Map<String, dynamic>? result,
  }) {
    final event = BackgroundTaskEvent(
      taskId: taskId,
      taskType: taskType,
      status: status,
      message: message,
      duration: duration,
      result: result,
    );
    
    _logger.fine('Publishing background task event: $taskId ($taskType) -> ${status.name}');
    EventSystem.instance.publishTyped<BackgroundTaskEvent>(event);
  }
  
  /// Build and publish an auth event
  static void publishAuthEvent({
    required String userId,
    required AuthAction action,
    required bool success,
    String? reason,
    String? ipAddress,
    String? userAgent,
  }) {
    final event = AuthEvent(
      userId: userId,
      action: action,
      success: success,
      reason: reason,
      ipAddress: ipAddress,
      userAgent: userAgent,
    );
    
    _logger.fine('Publishing auth event: $userId -> ${action.name} (${success ? 'success' : 'failure'})');
    EventSystem.instance.publishTyped<AuthEvent>(event);
  }
  
  /// Get logger level for error severity
  static Level _getLogLevelForSeverity(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Level.INFO;
      case ErrorSeverity.medium:
        return Level.WARNING;
      case ErrorSeverity.high:
        return Level.SEVERE;
      case ErrorSeverity.critical:
        return Level.SHOUT;
    }
  }
  
  /// Publish multiple events as a batch
  static void publishBatch(List<McpEvent> events) {
    if (events.isEmpty) return;
    
    _logger.fine('Publishing batch of ${events.length} events');
    
    for (final event in events) {
      // Publish each event with its appropriate type
      if (event is ClientEvent) {
        EventSystem.instance.publishTyped<ClientEvent>(event);
      } else if (event is ServerEvent) {
        EventSystem.instance.publishTyped<ServerEvent>(event);
      } else if (event is PerformanceEvent) {
        EventSystem.instance.publishTyped<PerformanceEvent>(event);
      } else if (event is PluginEvent) {
        EventSystem.instance.publishTyped<PluginEvent>(event);
      } else if (event is ErrorEvent) {
        EventSystem.instance.publishTyped<ErrorEvent>(event);
      } else if (event is MemoryEvent) {
        EventSystem.instance.publishTyped<MemoryEvent>(event);
      } else if (event is BackgroundTaskEvent) {
        EventSystem.instance.publishTyped<BackgroundTaskEvent>(event);
      } else if (event is AuthEvent) {
        EventSystem.instance.publishTyped<AuthEvent>(event);
      } else {
        // Fallback for unknown event types
        EventSystem.instance.publish(event.eventType, event.toMap());
      }
    }
  }
}

/// Fluent event builder for more complex event construction
class FluentEventBuilder {
  final String _eventType;
  final Map<String, dynamic> _data = {};
  String? _errorMessage;
  DateTime? _timestamp;
  
  FluentEventBuilder._(this._eventType);
  
  /// Create a client event builder
  static FluentEventBuilder client(String clientId) {
    return FluentEventBuilder._('client')
      ..addData('clientId', clientId);
  }
  
  /// Create a server event builder
  static FluentEventBuilder server(String serverId) {
    return FluentEventBuilder._('server')
      ..addData('serverId', serverId);
  }
  
  /// Create a performance event builder
  static FluentEventBuilder performance(String metricName) {
    return FluentEventBuilder._('performance')
      ..addData('metricName', metricName);
  }
  
  /// Add data to the event
  FluentEventBuilder addData(String key, dynamic value) {
    _data[key] = value;
    return this;
  }
  
  /// Add multiple data entries
  FluentEventBuilder addAllData(Map<String, dynamic> data) {
    _data.addAll(data);
    return this;
  }
  
  /// Set error message
  FluentEventBuilder withError(String errorMessage) {
    _errorMessage = errorMessage;
    return this;
  }
  
  /// Set custom timestamp
  FluentEventBuilder withTimestamp(DateTime timestamp) {
    _timestamp = timestamp;
    return this;
  }
  
  /// Add metadata with automatic timestamp
  FluentEventBuilder withMetadata(Map<String, dynamic> metadata) {
    return addAllData({
      'metadata': {
        'timestamp': (_timestamp ?? DateTime.now()).toIso8601String(),
        ...metadata,
      }
    });
  }
  
  /// Build and publish the event
  void publish() {
    final eventData = Map<String, dynamic>.from(_data);
    
    if (_errorMessage != null) {
      eventData['errorMessage'] = _errorMessage;
    }
    
    if (_timestamp != null) {
      eventData['timestamp'] = _timestamp!.toIso8601String();
    } else if (!eventData.containsKey('timestamp')) {
      eventData['timestamp'] = DateTime.now().toIso8601String();
    }
    
    EventSystem.instance.publish(_eventType, eventData);
  }
  
  /// Build the event data without publishing
  Map<String, dynamic> build() {
    final eventData = Map<String, dynamic>.from(_data);
    
    if (_errorMessage != null) {
      eventData['errorMessage'] = _errorMessage;
    }
    
    if (_timestamp != null) {
      eventData['timestamp'] = _timestamp!.toIso8601String();
    } else if (!eventData.containsKey('timestamp')) {
      eventData['timestamp'] = DateTime.now().toIso8601String();
    }
    
    return eventData;
  }
}