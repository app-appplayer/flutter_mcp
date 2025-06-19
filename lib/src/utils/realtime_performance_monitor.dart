import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'performance_monitor.dart';
import 'logger.dart';
import '../events/event_system.dart';

/// Real-time performance monitoring dashboard
class RealtimePerformanceMonitor {
  static final RealtimePerformanceMonitor _instance =
      RealtimePerformanceMonitor._internal();

  /// Get singleton instance
  static RealtimePerformanceMonitor get instance => _instance;

  RealtimePerformanceMonitor._internal();

  final Logger _logger = Logger('flutter_mcp.realtime_monitor');

  // Stream controllers for real-time data
  final _metricsStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _alertsStreamController =
      StreamController<PerformanceAlert>.broadcast();

  // Configuration
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  Duration _updateInterval = Duration(seconds: 1);

  // Thresholds for alerts
  final Map<String, double> _thresholds = {
    'cpu.usage': 80.0,
    'memory.usage': 75.0,
    'error.rate': 5.0,
    'response.time': 1000.0, // ms
  };

  // Recent metrics history
  final List<MetricSnapshot> _history = [];
  final int _maxHistorySize = 300; // 5 minutes at 1s intervals

  /// Get metrics stream
  Stream<Map<String, dynamic>> get metricsStream =>
      _metricsStreamController.stream;

  /// Get alerts stream
  Stream<PerformanceAlert> get alertsStream => _alertsStreamController.stream;

  /// Start real-time monitoring
  void startMonitoring({Duration? updateInterval}) {
    if (_isMonitoring) {
      _logger.warning('Real-time monitoring is already active');
      return;
    }

    if (updateInterval != null) {
      _updateInterval = updateInterval;
    }

    _logger.info('Starting real-time performance monitoring');
    _isMonitoring = true;

    // Start update timer
    _monitoringTimer = Timer.periodic(_updateInterval, (_) {
      _updateMetrics();
    });

    // Immediate update
    _updateMetrics();
  }

  /// Stop real-time monitoring
  void stopMonitoring() {
    if (!_isMonitoring) {
      return;
    }

    _logger.info('Stopping real-time performance monitoring');
    _isMonitoring = false;

    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Update metrics and check thresholds
  void _updateMetrics() {
    try {
      // Get current metrics from PerformanceMonitor
      final currentMetrics = PerformanceMonitor.instance.getMetricsSummary();

      // Add timestamp
      currentMetrics['timestamp'] = DateTime.now().toIso8601String();

      // Create snapshot
      final snapshot = MetricSnapshot(
        timestamp: DateTime.now(),
        metrics: currentMetrics,
      );

      // Add to history
      _history.add(snapshot);
      if (_history.length > _maxHistorySize) {
        _history.removeAt(0);
      }

      // Calculate additional real-time metrics
      final realtimeMetrics = _calculateRealtimeMetrics(currentMetrics);

      // Check thresholds and generate alerts
      _checkThresholds(realtimeMetrics);

      // Emit metrics
      _metricsStreamController.add(realtimeMetrics);

      // Publish to event system
      EventSystem.instance
          .publishTopic('performance.metrics.updated', realtimeMetrics);
    } catch (e, stackTrace) {
      _logger.severe('Error updating real-time metrics', e, stackTrace);
    }
  }

  /// Calculate additional real-time metrics
  Map<String, dynamic> _calculateRealtimeMetrics(
      Map<String, dynamic> baseMetrics) {
    final metrics = Map<String, dynamic>.from(baseMetrics);

    // Add real-time calculations
    if (_history.length > 1) {
      // Calculate trends
      final recent = _history.last;
      final previous = _history[_history.length - 2];

      metrics['trends'] = _calculateTrends(recent, previous);
    }

    // Add history summary
    metrics['history'] = {
      'count': _history.length,
      'duration': _history.isNotEmpty
          ? DateTime.now().difference(_history.first.timestamp).inSeconds
          : 0,
    };

    return metrics;
  }

  /// Calculate trends between snapshots
  Map<String, dynamic> _calculateTrends(
      MetricSnapshot recent, MetricSnapshot previous) {
    final trends = <String, dynamic>{};

    // Calculate memory trend
    final recentMemory =
        recent.metrics['resources']?['memory.usageMB']?['current'] ?? 0;
    final previousMemory =
        previous.metrics['resources']?['memory.usageMB']?['current'] ?? 0;
    trends['memory.change'] = recentMemory - previousMemory;

    // Calculate error rate trend
    final recentErrors = recent.metrics['counters']?['errors'] ?? 0;
    final previousErrors = previous.metrics['counters']?['errors'] ?? 0;
    trends['errors.change'] = recentErrors - previousErrors;

    return trends;
  }

  /// Check thresholds and generate alerts
  void _checkThresholds(Map<String, dynamic> metrics) {
    // Check memory usage
    final memoryUsage =
        metrics['resources']?['memory.usageMB']?['current'] ?? 0;
    final memoryThreshold = _thresholds['memory.usage'] ?? 75.0;

    if (memoryUsage > memoryThreshold) {
      _emitAlert(PerformanceAlert(
        type: AlertType.memory,
        severity: AlertSeverity.warning,
        message:
            'Memory usage exceeded threshold: ${memoryUsage}MB > ${memoryThreshold}MB',
        value: memoryUsage,
        threshold: memoryThreshold,
      ));
    }

    // Check error rate
    final errorRate = _calculateErrorRate();
    final errorThreshold = _thresholds['error.rate'] ?? 5.0;

    if (errorRate > errorThreshold) {
      _emitAlert(PerformanceAlert(
        type: AlertType.error,
        severity: AlertSeverity.critical,
        message:
            'Error rate exceeded threshold: $errorRate% > $errorThreshold%',
        value: errorRate,
        threshold: errorThreshold,
      ));
    }
  }

  /// Calculate error rate
  double _calculateErrorRate() {
    if (_history.length < 2) return 0.0;

    final recent = _history.last;
    final totalRequests = recent.metrics['counters']?['total.requests'] ?? 0;
    final totalErrors = recent.metrics['counters']?['total.errors'] ?? 0;

    if (totalRequests == 0) return 0.0;

    return (totalErrors / totalRequests) * 100;
  }

  /// Emit performance alert
  void _emitAlert(PerformanceAlert alert) {
    _alertsStreamController.add(alert);

    // Log alert
    final logLevel = alert.severity == AlertSeverity.critical
        ? 'error'
        : alert.severity == AlertSeverity.warning
            ? 'warning'
            : 'info';

    if (logLevel == 'error') {
      _logger.severe(alert.message);
    } else if (logLevel == 'warning') {
      _logger.warning(alert.message);
    } else {
      _logger.info(alert.message);
    }

    // Publish alert event
    EventSystem.instance.publishTopic('performance.alert', {
      'alert': alert.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Set threshold for a metric
  void setThreshold(String metric, double value) {
    _thresholds[metric] = value;
    _logger.fine('Set threshold for $metric: $value');
  }

  /// Get current thresholds
  Map<String, double> get thresholds => Map.from(_thresholds);

  /// Export metrics for web platform
  String exportMetricsForWeb() {
    if (!kIsWeb) {
      _logger.warning('exportMetricsForWeb called on non-web platform');
    }

    final exportData = {
      'metrics': PerformanceMonitor.instance.getMetricsReport(),
      'history': _history.map((s) => s.toJson()).toList(),
      'thresholds': _thresholds,
      'timestamp': DateTime.now().toIso8601String(),
    };

    return jsonEncode(exportData);
  }

  /// Import metrics on web platform
  void importMetricsFromWeb(String jsonData) {
    if (!kIsWeb) {
      _logger.warning('importMetricsFromWeb called on non-web platform');
      return;
    }

    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;

      // Import thresholds
      if (data.containsKey('thresholds')) {
        final thresholds = data['thresholds'] as Map<String, dynamic>;
        thresholds.forEach((key, value) {
          if (value is num) {
            _thresholds[key] = value.toDouble();
          }
        });
      }

      _logger.info('Imported metrics configuration from web');
    } catch (e, stackTrace) {
      _logger.severe('Failed to import metrics from web', e, stackTrace);
    }
  }

  /// Get metrics history
  List<MetricSnapshot> getHistory({Duration? duration}) {
    if (duration == null) {
      return List.from(_history);
    }

    final cutoffTime = DateTime.now().subtract(duration);
    return _history.where((s) => s.timestamp.isAfter(cutoffTime)).toList();
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
    _logger.fine('Cleared metrics history');
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _metricsStreamController.close();
    _alertsStreamController.close();
  }
}

/// Metric snapshot
class MetricSnapshot {
  final DateTime timestamp;
  final Map<String, dynamic> metrics;

  MetricSnapshot({
    required this.timestamp,
    required this.metrics,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'metrics': metrics,
      };
}

/// Performance alert
class PerformanceAlert {
  final AlertType type;
  final AlertSeverity severity;
  final String message;
  final double value;
  final double threshold;
  final DateTime timestamp;

  PerformanceAlert({
    required this.type,
    required this.severity,
    required this.message,
    required this.value,
    required this.threshold,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type.toString(),
        'severity': severity.toString(),
        'message': message,
        'value': value,
        'threshold': threshold,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Alert type
enum AlertType {
  cpu,
  memory,
  error,
  latency,
  custom,
}

/// Alert severity
enum AlertSeverity {
  info,
  warning,
  critical,
}
