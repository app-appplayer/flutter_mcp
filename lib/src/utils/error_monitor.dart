import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'error_handler.dart';
import 'exceptions.dart';
import 'logger.dart';
import '../events/event_system.dart';
import '../config/app_config.dart';

/// Real-time error monitoring and alerting system
class ErrorMonitor {
  static final Logger _logger = Logger('flutter_mcp.error_monitor');
  static ErrorMonitor? _instance;

  final Queue<ErrorMetric> _metrics = Queue();
  final Map<String, ErrorPattern> _patterns = {};
  final List<ErrorAlert> _activeAlerts = [];

  Timer? _monitoringTimer;
  StreamController<ErrorAlert>? _alertController;
  StreamController<ErrorDashboard>? _dashboardController;

  bool _isMonitoring = false;
  Duration _monitoringInterval = Duration(minutes: 1);
  int _maxMetricsHistory = 1440; // 24 hours at 1-minute intervals

  /// Get singleton instance
  static ErrorMonitor get instance {
    _instance ??= ErrorMonitor._internal();
    return _instance!;
  }

  ErrorMonitor._internal() {
    _initializeConfiguration();
    _setupErrorHandlerIntegration();
  }

  /// Initialize configuration
  void _initializeConfiguration() {
    try {
      final config = AppConfig.instance.scoped('errorMonitoring');
      _monitoringInterval =
          config.getDuration('interval', defaultValue: Duration(minutes: 1));
      _maxMetricsHistory = config.get<int>('maxHistory', defaultValue: 1440);
    } catch (e) {
      _logger.fine('Using default error monitoring configuration');
    }
  }

  /// Set up integration with error handler
  void _setupErrorHandlerIntegration() {
    MCPErrorHandler.instance.addErrorCallback(_onError);
  }

  /// Handle new error from error handler
  void _onError(ErrorReport report) {
    _updateErrorPatterns(report);
    _checkForAlerts(report);
  }

  /// Start error monitoring
  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _alertController = StreamController<ErrorAlert>.broadcast();
    _dashboardController = StreamController<ErrorDashboard>.broadcast();

    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectMetrics();
      _updateDashboard();
    });

    _logger.info(
        'Started error monitoring with interval: ${_monitoringInterval.inMinutes} minutes');
  }

  /// Stop error monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;

    _alertController?.close();
    _dashboardController?.close();
    _alertController = null;
    _dashboardController = null;

    _logger.info('Stopped error monitoring');
  }

  /// Collect current error metrics
  void _collectMetrics() {
    final now = DateTime.now();
    final recentErrors =
        MCPErrorHandler.instance.getRecentErrors(within: _monitoringInterval);

    final metric = ErrorMetric(
      timestamp: now,
      totalErrors: recentErrors.length,
      errorsByType: _groupErrorsByType(recentErrors),
      errorsBySeverity: _groupErrorsBySeverity(recentErrors),
      recoveredErrors: recentErrors.where((e) => e.error.recoverable).length,
      averageResolutionTime: _calculateAverageResolutionTime(recentErrors),
    );

    _metrics.add(metric);

    // Keep history size under limit
    while (_metrics.length > _maxMetricsHistory) {
      _metrics.removeFirst();
    }
  }

  /// Group errors by type
  Map<String, int> _groupErrorsByType(List<ErrorReport> errors) {
    final groups = <String, int>{};
    for (final error in errors) {
      final type = error.error.runtimeType.toString();
      groups[type] = (groups[type] ?? 0) + 1;
    }
    return groups;
  }

  /// Group errors by severity
  Map<String, int> _groupErrorsBySeverity(List<ErrorReport> errors) {
    final groups = <String, int>{};
    for (final error in errors) {
      final severity = _getErrorSeverity(error.error);
      groups[severity.name] = (groups[severity.name] ?? 0) + 1;
    }
    return groups;
  }

  /// Get error severity (simplified version)
  ErrorSeverity _getErrorSeverity(dynamic error) {
    if (error.toString().contains('Security') ||
        error.toString().contains('Initialization')) {
      return ErrorSeverity.critical;
    }
    if (error.toString().contains('Platform') ||
        error.toString().contains('Network')) {
      return ErrorSeverity.high;
    }
    if (error.toString().contains('Validation') ||
        error.toString().contains('Timeout')) {
      return ErrorSeverity.medium;
    }
    return ErrorSeverity.low;
  }

  /// Calculate average resolution time for errors
  Duration? _calculateAverageResolutionTime(List<ErrorReport> errors) {
    if (errors.isEmpty) return null;

    // For now, simulate resolution time based on error type
    var totalMs = 0;
    var count = 0;

    for (final error in errors) {
      if (error.error.recoverable) {
        // Simulate different resolution times based on error type
        if (error.error is MCPNetworkException) {
          totalMs += 5000; // 5 seconds
        } else if (error.error is MCPTimeoutException) {
          totalMs += 10000; // 10 seconds
        } else {
          totalMs += 2000; // 2 seconds
        }
        count++;
      }
    }

    return count > 0 ? Duration(milliseconds: totalMs ~/ count) : null;
  }

  /// Update error patterns
  void _updateErrorPatterns(ErrorReport report) {
    final errorKey = '${report.error.runtimeType}_${report.error.errorCode}';

    if (!_patterns.containsKey(errorKey)) {
      _patterns[errorKey] = ErrorPattern(
        errorType: report.error.runtimeType.toString(),
        errorCode: report.error.errorCode,
        firstOccurrence: report.timestamp,
        occurrences: [],
      );
    }

    final pattern = _patterns[errorKey]!;
    pattern.occurrences.add(report.timestamp);
    pattern.lastOccurrence = report.timestamp;

    // Keep only recent occurrences (last 24 hours)
    final cutoff = DateTime.now().subtract(Duration(hours: 24));
    pattern.occurrences.removeWhere((time) => time.isBefore(cutoff));

    // Check for concerning patterns
    _analyzePattern(pattern);
  }

  /// Analyze error pattern for concerning trends
  void _analyzePattern(ErrorPattern pattern) {
    final now = DateTime.now();

    // Check for error spikes (more than 5 errors in 5 minutes)
    final recentOccurrences = pattern.occurrences
        .where((time) => now.difference(time).inMinutes <= 5)
        .length;

    if (recentOccurrences > 5) {
      _createAlert(
        AlertType.errorSpike,
        'Error spike detected: ${pattern.errorType}',
        'Detected $recentOccurrences occurrences of ${pattern.errorType} in the last 5 minutes',
        AlertSeverity.high,
        {'pattern': pattern.errorType, 'occurrences': recentOccurrences},
      );
    }

    // Check for recurring errors (more than 20 in last hour)
    final hourlyOccurrences = pattern.occurrences
        .where((time) => now.difference(time).inHours <= 1)
        .length;

    if (hourlyOccurrences > 20) {
      _createAlert(
        AlertType.recurringError,
        'Recurring error detected: ${pattern.errorType}',
        'Detected $hourlyOccurrences occurrences of ${pattern.errorType} in the last hour',
        AlertSeverity.medium,
        {'pattern': pattern.errorType, 'occurrences': hourlyOccurrences},
      );
    }
  }

  /// Check for alerts based on new error
  void _checkForAlerts(ErrorReport report) {
    // Critical error alert
    if (_getErrorSeverity(report.error) == ErrorSeverity.critical) {
      _createAlert(
        AlertType.criticalError,
        'Critical error occurred',
        'A critical error was encountered: ${report.error.message}',
        AlertSeverity.critical,
        {'errorCode': report.error.errorCode, 'operation': report.operation},
      );
    }

    // High error rate alert
    final recentErrors =
        MCPErrorHandler.instance.getRecentErrors(within: Duration(minutes: 10));
    if (recentErrors.length > 10) {
      _createAlert(
        AlertType.highErrorRate,
        'High error rate detected',
        'Detected ${recentErrors.length} errors in the last 10 minutes',
        AlertSeverity.high,
        {'errorCount': recentErrors.length},
      );
    }
  }

  /// Create and emit alert
  void _createAlert(
    AlertType type,
    String title,
    String message,
    AlertSeverity severity,
    Map<String, dynamic>? data,
  ) {
    // Check if similar alert already exists
    final existingAlert = _activeAlerts
        .where((alert) =>
            alert.type == type &&
            alert.severity == severity &&
            DateTime.now().difference(alert.timestamp).inMinutes < 30)
        .firstOrNull;

    if (existingAlert != null) {
      // Update existing alert count
      existingAlert.count++;
      existingAlert.lastOccurrence = DateTime.now();
    } else {
      // Create new alert
      final alert = ErrorAlert(
        id: '${type.name}_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        title: title,
        message: message,
        severity: severity,
        timestamp: DateTime.now(),
        data: data,
      );

      _activeAlerts.add(alert);
      _alertController?.add(alert);

      // Publish alert event
      EventSystem.instance.publishTopic('error.alert', {
        'alertId': alert.id,
        'type': alert.type.name,
        'severity': alert.severity.name,
        'title': alert.title,
        'message': alert.message,
        'timestamp': alert.timestamp.toIso8601String(),
      });

      _logger.warning('Error alert: ${alert.title} - ${alert.message}');
    }

    // Clean up old alerts
    _cleanupOldAlerts();
  }

  /// Clean up old alerts
  void _cleanupOldAlerts() {
    final cutoff = DateTime.now().subtract(Duration(hours: 24));
    _activeAlerts.removeWhere((alert) => alert.timestamp.isBefore(cutoff));
  }

  /// Update dashboard with current metrics
  void _updateDashboard() {
    if (_dashboardController == null) return;

    final dashboard = ErrorDashboard(
      timestamp: DateTime.now(),
      currentMetrics: _metrics.isNotEmpty ? _metrics.last : null,
      totalErrors:
          _metrics.fold<int>(0, (sum, metric) => sum + metric.totalErrors),
      errorRate: _calculateErrorRate(),
      topErrorTypes: _getTopErrorTypes(),
      activeAlerts: List.from(_activeAlerts),
      systemHealth: _calculateSystemHealth(),
    );

    _dashboardController?.add(dashboard);
  }

  /// Calculate current error rate (errors per minute)
  double _calculateErrorRate() {
    if (_metrics.length < 2) return 0.0;

    final recentMetrics = _metrics.length > 10
        ? _metrics.toList().sublist(_metrics.length - 10)
        : _metrics.toList();

    final totalErrors =
        recentMetrics.fold<int>(0, (sum, metric) => sum + metric.totalErrors);
    return totalErrors / recentMetrics.length;
  }

  /// Get top error types
  Map<String, int> _getTopErrorTypes() {
    final allTypes = <String, int>{};

    for (final metric in _metrics) {
      metric.errorsByType.forEach((type, count) {
        allTypes[type] = (allTypes[type] ?? 0) + count;
      });
    }

    // Sort by count and take top 5
    final sortedEntries = allTypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Map.fromEntries(sortedEntries.take(5));
  }

  /// Calculate system health score (0-100)
  int _calculateSystemHealth() {
    if (_metrics.isEmpty) return 100;

    final recentMetrics = _metrics.length > 60
        ? _metrics.toList().sublist(_metrics.length - 60) // Last hour
        : _metrics.toList();

    final totalErrors =
        recentMetrics.fold<int>(0, (sum, metric) => sum + metric.totalErrors);
    final criticalAlerts =
        _activeAlerts.where((a) => a.severity == AlertSeverity.critical).length;

    // Start with perfect health
    var health = 100;

    // Reduce health based on error rate
    final avgErrorsPerMinute = totalErrors / recentMetrics.length;
    health -= (avgErrorsPerMinute * 10).round(); // -10 per error per minute

    // Reduce health based on critical alerts
    health -= criticalAlerts * 20; // -20 per critical alert

    // Reduce health based on unrecovered errors
    final unrecoveredErrors = recentMetrics.fold<int>(0,
        (sum, metric) => sum + (metric.totalErrors - metric.recoveredErrors));
    health -= (unrecoveredErrors * 2); // -2 per unrecovered error

    return math.max(0, health);
  }

  /// Get alerts stream
  Stream<ErrorAlert> get alertsStream =>
      _alertController?.stream ?? Stream.empty();

  /// Get dashboard stream
  Stream<ErrorDashboard> get dashboardStream =>
      _dashboardController?.stream ?? Stream.empty();

  /// Get current error patterns
  Map<String, ErrorPattern> get errorPatterns => Map.from(_patterns);

  /// Get active alerts
  List<ErrorAlert> get activeAlerts => List.from(_activeAlerts);

  /// Clear error monitoring data
  void clearData() {
    _metrics.clear();
    _patterns.clear();
    _activeAlerts.clear();
    _logger.info('Cleared error monitoring data');
  }

  /// Export monitoring data
  Map<String, dynamic> exportData() {
    return {
      'metadata': {
        'exportTime': DateTime.now().toIso8601String(),
        'monitoringInterval': _monitoringInterval.inMinutes,
        'metricsCount': _metrics.length,
      },
      'metrics': _metrics.map((m) => m.toJson()).toList(),
      'patterns':
          _patterns.map((key, pattern) => MapEntry(key, pattern.toJson())),
      'activeAlerts': _activeAlerts.map((a) => a.toJson()).toList(),
      'systemHealth': _calculateSystemHealth(),
    };
  }

  /// Dispose the monitor
  void dispose() {
    stopMonitoring();
    clearData();
  }
}

/// Error metric data point
class ErrorMetric {
  final DateTime timestamp;
  final int totalErrors;
  final Map<String, int> errorsByType;
  final Map<String, int> errorsBySeverity;
  final int recoveredErrors;
  final Duration? averageResolutionTime;

  ErrorMetric({
    required this.timestamp,
    required this.totalErrors,
    required this.errorsByType,
    required this.errorsBySeverity,
    required this.recoveredErrors,
    this.averageResolutionTime,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'totalErrors': totalErrors,
        'errorsByType': errorsByType,
        'errorsBySeverity': errorsBySeverity,
        'recoveredErrors': recoveredErrors,
        'averageResolutionTimeMs': averageResolutionTime?.inMilliseconds,
      };
}

/// Error pattern tracking
class ErrorPattern {
  final String errorType;
  final String? errorCode;
  final DateTime firstOccurrence;
  DateTime? lastOccurrence;
  final List<DateTime> occurrences;

  ErrorPattern({
    required this.errorType,
    this.errorCode,
    required this.firstOccurrence,
    this.lastOccurrence,
    required this.occurrences,
  });

  int get frequency => occurrences.length;

  Duration get duration => lastOccurrence != null
      ? lastOccurrence!.difference(firstOccurrence)
      : Duration.zero;

  Map<String, dynamic> toJson() => {
        'errorType': errorType,
        'errorCode': errorCode,
        'firstOccurrence': firstOccurrence.toIso8601String(),
        'lastOccurrence': lastOccurrence?.toIso8601String(),
        'frequency': frequency,
        'durationMs': duration.inMilliseconds,
      };
}

/// Error alert
class ErrorAlert {
  final String id;
  final AlertType type;
  final String title;
  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  DateTime lastOccurrence;
  int count;
  final Map<String, dynamic>? data;

  ErrorAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.data,
  })  : lastOccurrence = timestamp,
        count = 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
        'lastOccurrence': lastOccurrence.toIso8601String(),
        'count': count,
        'data': data,
      };
}

/// Error monitoring dashboard data
class ErrorDashboard {
  final DateTime timestamp;
  final ErrorMetric? currentMetrics;
  final int totalErrors;
  final double errorRate;
  final Map<String, int> topErrorTypes;
  final List<ErrorAlert> activeAlerts;
  final int systemHealth;

  ErrorDashboard({
    required this.timestamp,
    this.currentMetrics,
    required this.totalErrors,
    required this.errorRate,
    required this.topErrorTypes,
    required this.activeAlerts,
    required this.systemHealth,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'currentMetrics': currentMetrics?.toJson(),
        'totalErrors': totalErrors,
        'errorRate': errorRate,
        'topErrorTypes': topErrorTypes,
        'activeAlerts': activeAlerts.map((a) => a.toJson()).toList(),
        'systemHealth': systemHealth,
      };
}

/// Alert types
enum AlertType {
  criticalError,
  highErrorRate,
  errorSpike,
  recurringError,
  systemDegraded,
}

/// Alert severity levels
enum AlertSeverity {
  low,
  medium,
  high,
  critical,
}
