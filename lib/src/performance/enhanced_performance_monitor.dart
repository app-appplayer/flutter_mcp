import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import '../utils/logger.dart';
import '../utils/performance_monitor.dart';
import '../metrics/typed_metrics.dart';
import '../events/event_models.dart';
import '../events/enhanced_typed_event_system.dart';

/// Performance aggregation configuration
class AggregationConfig {
  final Duration window;
  final AggregationType type;
  final int? maxSamples;
  final bool autoFlush;
  final Duration? flushInterval;
  
  AggregationConfig({
    this.window = const Duration(minutes: 1),
    this.type = AggregationType.average,
    this.maxSamples,
    this.autoFlush = true,
    this.flushInterval,
  });
}

enum AggregationType { average, sum, min, max, median, percentile }

/// Performance threshold configuration
class ThresholdConfig {
  final double? warningLevel;
  final double? criticalLevel;
  final Duration? sustainedDuration;
  final void Function(ThresholdViolation)? onViolation;
  
  ThresholdConfig({
    this.warningLevel,
    this.criticalLevel,
    this.sustainedDuration,
    this.onViolation,
  });
}

/// Threshold violation event
class ThresholdViolation {
  final String metricName;
  final double value;
  final double threshold;
  final ThresholdLevel level;
  final DateTime timestamp;
  final Duration? duration;
  
  ThresholdViolation({
    required this.metricName,
    required this.value,
    required this.threshold,
    required this.level,
    required this.timestamp,
    this.duration,
  });
}

enum ThresholdLevel { warning, critical }

/// Performance anomaly detection
class AnomalyDetector {
  final int windowSize;
  final double zScoreThreshold;
  final Queue<double> _window = Queue();
  double? _mean;
  double? _stdDev;
  
  AnomalyDetector({
    this.windowSize = 100,
    this.zScoreThreshold = 3.0,
  });
  
  bool isAnomaly(double value) {
    _window.add(value);
    
    if (_window.length > windowSize) {
      _window.removeFirst();
    }
    
    if (_window.length < windowSize ~/ 2) {
      return false; // Not enough data
    }
    
    _calculateStats();
    
    if (_mean == null || _stdDev == null || _stdDev == 0) {
      return false;
    }
    
    final zScore = (value - _mean!).abs() / _stdDev!;
    return zScore > zScoreThreshold;
  }
  
  void _calculateStats() {
    if (_window.isEmpty) return;
    
    _mean = _window.reduce((a, b) => a + b) / _window.length;
    
    final variance = _window
        .map((x) => math.pow(x - _mean!, 2))
        .reduce((a, b) => a + b) / _window.length;
    
    _stdDev = math.sqrt(variance);
  }
  
  void reset() {
    _window.clear();
    _mean = null;
    _stdDev = null;
  }
}

/// Metric aggregator
class MetricAggregator {
  final String name;
  final AggregationConfig config;
  final Queue<_MetricSample> _samples = Queue();
  Timer? _flushTimer;
  
  MetricAggregator({
    required this.name,
    required this.config,
  }) {
    if (config.autoFlush && config.flushInterval != null) {
      _flushTimer = Timer.periodic(config.flushInterval!, (_) => flush());
    }
  }
  
  void addSample(double value, {DateTime? timestamp}) {
    final sample = _MetricSample(
      value: value,
      timestamp: timestamp ?? DateTime.now(),
    );
    
    _samples.add(sample);
    
    // Remove old samples outside the window
    final cutoff = DateTime.now().subtract(config.window);
    while (_samples.isNotEmpty && _samples.first.timestamp.isBefore(cutoff)) {
      _samples.removeFirst();
    }
    
    // Limit samples if maxSamples is set
    if (config.maxSamples != null) {
      while (_samples.length > config.maxSamples!) {
        _samples.removeFirst();
      }
    }
  }
  
  double? getAggregatedValue() {
    if (_samples.isEmpty) return null;
    
    final values = _samples.map((s) => s.value).toList();
    
    switch (config.type) {
      case AggregationType.average:
        return values.reduce((a, b) => a + b) / values.length;
        
      case AggregationType.sum:
        return values.reduce((a, b) => a + b);
        
      case AggregationType.min:
        return values.reduce(math.min);
        
      case AggregationType.max:
        return values.reduce(math.max);
        
      case AggregationType.median:
        values.sort();
        final mid = values.length ~/ 2;
        if (values.length % 2 == 0) {
          return (values[mid - 1] + values[mid]) / 2;
        } else {
          return values[mid];
        }
        
      case AggregationType.percentile:
        // Default to 95th percentile
        values.sort();
        final index = (values.length * 0.95).floor();
        return values[math.min(index, values.length - 1)];
    }
  }
  
  Map<String, dynamic> getStatistics() {
    if (_samples.isEmpty) {
      return {'count': 0};
    }
    
    final values = _samples.map((s) => s.value).toList();
    values.sort();
    
    final sum = values.reduce((a, b) => a + b);
    final avg = sum / values.length;
    
    // Calculate standard deviation
    final variance = values
        .map((x) => math.pow(x - avg, 2))
        .reduce((a, b) => a + b) / values.length;
    final stdDev = math.sqrt(variance);
    
    return {
      'count': values.length,
      'sum': sum,
      'average': avg,
      'min': values.first,
      'max': values.last,
      'median': values[values.length ~/ 2],
      'stdDev': stdDev,
      'p50': values[(values.length * 0.5).floor()],
      'p90': values[(values.length * 0.9).floor()],
      'p95': values[(values.length * 0.95).floor()],
      'p99': values[(values.length * 0.99).floor()],
    };
  }
  
  void flush() {
    _samples.clear();
  }
  
  void dispose() {
    _flushTimer?.cancel();
    flush();
  }
}

/// Enhanced performance monitor with aggregation and auto-detection
class EnhancedPerformanceMonitor {
  final Logger _logger = Logger('flutter_mcp.enhanced_performance_monitor');
  final EnhancedTypedEventSystem _eventSystem = EnhancedTypedEventSystem.instance;
  final PerformanceMonitor _baseMonitor = PerformanceMonitor.instance;
  
  // Metric aggregators
  final Map<String, MetricAggregator> _aggregators = {};
  
  // Anomaly detectors
  final Map<String, AnomalyDetector> _anomalyDetectors = {};
  
  // Threshold configurations
  final Map<String, ThresholdConfig> _thresholds = {};
  
  // Threshold violation tracking
  final Map<String, _ThresholdTracker> _thresholdTrackers = {};
  
  // Auto-detection configuration
  bool _autoDetectAnomalies = false;
  Duration _detectionInterval = Duration(seconds: 5);
  Timer? _detectionTimer;
  
  // Performance trends
  final Map<String, _PerformanceTrend> _trends = {};
  
  // Singleton instance
  static EnhancedPerformanceMonitor? _instance;
  
  /// Get singleton instance
  static EnhancedPerformanceMonitor get instance {
    _instance ??= EnhancedPerformanceMonitor._internal();
    return _instance!;
  }
  
  EnhancedPerformanceMonitor._internal();
  
  /// Configure metric aggregation
  void configureAggregation(
    String metricName,
    AggregationConfig config,
  ) {
    _aggregators[metricName]?.dispose();
    _aggregators[metricName] = MetricAggregator(
      name: metricName,
      config: config,
    );
    
    _logger.info('Configured aggregation for metric: $metricName');
  }
  
  /// Configure threshold monitoring
  void configureThreshold(
    String metricName,
    ThresholdConfig config,
  ) {
    _thresholds[metricName] = config;
    _thresholdTrackers[metricName] = _ThresholdTracker();
    
    _logger.info('Configured threshold for metric: $metricName');
  }
  
  /// Enable auto-detection features
  void enableAutoDetection({
    bool anomalies = true,
    bool thresholds = true,
    Duration? interval,
  }) {
    _autoDetectAnomalies = anomalies;
    
    if (interval != null) {
      _detectionInterval = interval;
    }
    
    _startDetectionTimer();
    
    _logger.info('Auto-detection enabled (anomalies: $anomalies, thresholds: $thresholds)');
  }
  
  /// Disable auto-detection
  void disableAutoDetection() {
    _autoDetectAnomalies = false;
    _stopDetectionTimer();
    
    _logger.info('Auto-detection disabled');
  }
  
  /// Record a typed metric with enhanced processing
  void recordTypedMetric(PerformanceMetric metric) {
    // Delegate to base monitor
    _baseMonitor.recordTypedMetric(metric);
    
    // Add to aggregator if configured
    final aggregator = _aggregators[metric.name];
    if (aggregator != null) {
      aggregator.addSample(metric.value, timestamp: metric.timestamp);
    }
    
    // Update trend tracking
    _trends.putIfAbsent(metric.name, () => _PerformanceTrend(metric.name));
    _trends[metric.name]!.addSample(metric.value);
    
    // Check for anomalies
    if (_autoDetectAnomalies) {
      _checkAnomaly(metric);
    }
    
    // Check thresholds - always check if there's a configured threshold
    if (_thresholds.containsKey(metric.name)) {
      _checkThreshold(metric);
    }
  }
  
  /// Get aggregated metric value
  double? getAggregatedValue(String metricName) {
    return _aggregators[metricName]?.getAggregatedValue();
  }
  
  /// Get metric statistics
  Map<String, dynamic>? getMetricStatistics(String metricName) {
    // First check aggregators
    final aggregatorStats = _aggregators[metricName]?.getStatistics();
    if (aggregatorStats != null) {
      return aggregatorStats;
    }
    
    // If no aggregator, create temporary statistics from trend data
    final trend = _trends[metricName];
    if (trend != null && trend._samples.isNotEmpty) {
      final values = trend._samples.map((s) => s.value).toList();
      values.sort();
      
      final sum = values.reduce((a, b) => a + b);
      final avg = sum / values.length;
      
      // Calculate standard deviation
      final variance = values
          .map((x) => math.pow(x - avg, 2))
          .reduce((a, b) => a + b) / values.length;
      final stdDev = math.sqrt(variance);
      
      return {
        'count': values.length,
        'sum': sum,
        'mean': avg,
        'average': avg,
        'min': values.first,
        'max': values.last,
        'median': values[values.length ~/ 2],
        'stdDev': stdDev,
      };
    }
    
    // Fall back to base monitor
    final report = _baseMonitor.getMetricsReport();
    
    // Check typed metrics
    if (report['typed_metrics'] != null && report['typed_metrics'].containsKey(metricName)) {
      final metric = report['typed_metrics'][metricName];
      return {
        'value': metric['value'],
        'type': metric['type'] ?? 'metric',
        'unit': metric['unit'],
        'timestamp': metric['timestamp'],
      };
    }
    
    // Check counters
    final summary = _baseMonitor.getMetricsSummary();
    if (summary['counters'] != null && summary['counters'].containsKey(metricName)) {
      return {
        'count': summary['counters'][metricName],
        'type': 'counter',
      };
    }
    
    // Check timers
    if (summary['timers'] != null && summary['timers'].containsKey(metricName)) {
      return summary['timers'][metricName];
    }
    
    return null;
  }
  
  /// Get performance trends
  Map<String, TrendInfo> getPerformanceTrends() {
    final trends = <String, TrendInfo>{};
    
    for (final entry in _trends.entries) {
      final trend = entry.value.calculateTrend();
      if (trend != null) {
        trends[entry.key] = trend;
      }
    }
    
    return trends;
  }
  
  /// Check if metric has threshold violations
  bool hasThresholdViolations(String metricName) {
    final tracker = _thresholdTrackers[metricName];
    return tracker?.hasViolations ?? false;
  }
  
  /// Get threshold violations for a metric
  List<ThresholdViolation> getThresholdViolations(String metricName) {
    final tracker = _thresholdTrackers[metricName];
    if (tracker == null) return [];
    
    return tracker._violations.toList();
  }
  
  /// Check for anomalies in metric
  void _checkAnomaly(PerformanceMetric metric) {
    // Get or create anomaly detector
    final detector = _anomalyDetectors.putIfAbsent(
      metric.name,
      () => AnomalyDetector(),
    );
    
    if (detector.isAnomaly(metric.value)) {
      _logger.warning('Anomaly detected in metric ${metric.name}: ${metric.value}');
      
      // Publish anomaly event
      _eventSystem.publish(PerformanceEvent(
        metricName: '${metric.name}.anomaly',
        value: metric.value,
        type: MetricType.gauge,
        unit: metric.unit,
      ));
    }
  }
  
  /// Check threshold violations
  void _checkThreshold(PerformanceMetric metric) {
    final config = _thresholds[metric.name];
    if (config == null) return;
    
    final tracker = _thresholdTrackers[metric.name];
    if (tracker == null) return;
    ThresholdViolation? violation;
    
    if (config.criticalLevel != null && metric.value >= config.criticalLevel!) {
      violation = ThresholdViolation(
        metricName: metric.name,
        value: metric.value,
        threshold: config.criticalLevel!,
        level: ThresholdLevel.critical,
        timestamp: DateTime.now(),
      );
    } else if (config.warningLevel != null && metric.value >= config.warningLevel!) {
      violation = ThresholdViolation(
        metricName: metric.name,
        value: metric.value,
        threshold: config.warningLevel!,
        level: ThresholdLevel.warning,
        timestamp: DateTime.now(),
      );
    }
    
    if (violation != null) {
      tracker.recordViolation(violation);
      
      // Check sustained duration
      if (config.sustainedDuration != null) {
        final sustained = tracker.getSustainedViolation(config.sustainedDuration!);
        if (sustained != null) {
          config.onViolation?.call(sustained);
          
          _logger.warning(
            'Sustained threshold violation for ${metric.name}: '
            '${sustained.value} > ${sustained.threshold} for ${sustained.duration?.inSeconds}s'
          );
        }
      } else {
        config.onViolation?.call(violation);
      }
    } else {
      tracker.clearViolations();
    }
  }
  
  
  /// Start auto-detection timer
  void _startDetectionTimer() {
    _stopDetectionTimer();
    
    _detectionTimer = Timer.periodic(_detectionInterval, (_) {
      _performAutoDetection();
    });
  }
  
  /// Stop auto-detection timer
  void _stopDetectionTimer() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
  }
  
  /// Perform auto-detection
  void _performAutoDetection() {
    // This method can be extended to perform more sophisticated
    // detection logic, such as:
    // - Cross-metric correlation
    // - Pattern recognition
    // - Predictive analysis
    
    _logger.finest('Performing auto-detection cycle');
  }
  
  /// Get detailed performance report
  Map<String, dynamic> getDetailedReport() {
    // Get base report from base monitor
    final report = _baseMonitor.getMetricsReport();
    
    // Ensure required keys exist
    report['metrics'] ??= <String, dynamic>{};
    report['thresholds'] ??= <String, dynamic>{};
    
    // Add aggregation data
    final aggregations = <String, dynamic>{};
    for (final entry in _aggregators.entries) {
      aggregations[entry.key] = {
        'value': entry.value.getAggregatedValue(),
        'statistics': entry.value.getStatistics(),
      };
    }
    report['aggregations'] = aggregations;
    
    // Add trends
    final trends = <String, dynamic>{};
    for (final entry in _trends.entries) {
      final trend = entry.value.calculateTrend();
      if (trend != null) {
        trends[entry.key] = trend.toMap();
      }
    }
    report['trends'] = trends;
    
    // Add threshold violations
    final violations = <String, dynamic>{};
    for (final entry in _thresholdTrackers.entries) {
      if (entry.value.hasViolations) {
        violations[entry.key] = {
          'count': entry.value.violationCount,
          'lastViolation': entry.value.lastViolation?.timestamp.toIso8601String(),
        };
      }
    }
    report['threshold_violations'] = violations;
    
    return report;
  }
  
  /// Reset all metrics and detectors
  void reset() {
    // Reset base monitor
    _baseMonitor.reset();
    
    // Dispose aggregators
    for (final aggregator in _aggregators.values) {
      aggregator.dispose();
    }
    _aggregators.clear();
    
    // Reset detectors and trackers
    for (final detector in _anomalyDetectors.values) {
      detector.reset();
    }
    _anomalyDetectors.clear();
    
    _thresholdTrackers.clear();
    _trends.clear();
  }
  
  /// Dispose resources
  void dispose() {
    _stopDetectionTimer();
    reset();
    _baseMonitor.dispose();
  }
}

/// Metric sample
class _MetricSample {
  final double value;
  final DateTime timestamp;
  
  _MetricSample({
    required this.value,
    required this.timestamp,
  });
}

/// Threshold tracker
class _ThresholdTracker {
  final Queue<ThresholdViolation> _violations = Queue();
  static const int _maxViolations = 100;
  
  void recordViolation(ThresholdViolation violation) {
    _violations.add(violation);
    
    if (_violations.length > _maxViolations) {
      _violations.removeFirst();
    }
  }
  
  void clearViolations() {
    _violations.clear();
  }
  
  bool get hasViolations => _violations.isNotEmpty;
  
  int get violationCount => _violations.length;
  
  ThresholdViolation? get lastViolation => 
      _violations.isNotEmpty ? _violations.last : null;
  
  ThresholdViolation? getSustainedViolation(Duration duration) {
    if (_violations.isEmpty) return null;
    
    final cutoff = DateTime.now().subtract(duration);
    final sustainedViolations = _violations
        .where((v) => v.timestamp.isAfter(cutoff))
        .toList();
    
    if (sustainedViolations.length == _violations.length) {
      // All violations are within the duration
      final first = sustainedViolations.first;
      final last = sustainedViolations.last;
      
      return ThresholdViolation(
        metricName: last.metricName,
        value: last.value,
        threshold: last.threshold,
        level: last.level,
        timestamp: last.timestamp,
        duration: last.timestamp.difference(first.timestamp),
      );
    }
    
    return null;
  }
}

/// Performance trend calculator
class _PerformanceTrend {
  final String metricName;
  final Queue<_MetricSample> _samples = Queue();
  static const int _maxSamples = 1000;
  static const Duration _trendWindow = Duration(minutes: 5);
  
  _PerformanceTrend(this.metricName);
  
  void addSample(double value) {
    _samples.add(_MetricSample(
      value: value,
      timestamp: DateTime.now(),
    ));
    
    // Remove old samples
    final cutoff = DateTime.now().subtract(_trendWindow);
    while (_samples.isNotEmpty && _samples.first.timestamp.isBefore(cutoff)) {
      _samples.removeFirst();
    }
    
    // Limit samples
    while (_samples.length > _maxSamples) {
      _samples.removeFirst();
    }
  }
  
  TrendInfo? calculateTrend() {
    if (_samples.length < 2) return null; // Need at least 2 samples for trend
    
    final values = _samples.map((s) => s.value).toList();
    final timestamps = _samples
        .map((s) => s.timestamp.millisecondsSinceEpoch.toDouble())
        .toList();
    
    // Calculate linear regression
    final n = values.length;
    final sumX = timestamps.reduce((a, b) => a + b);
    final sumY = values.reduce((a, b) => a + b);
    final sumXY = List.generate(n, (i) => timestamps[i] * values[i])
        .reduce((a, b) => a + b);
    final sumX2 = timestamps.map((x) => x * x).reduce((a, b) => a + b);
    
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    // final intercept = (sumY - slope * sumX) / n; // Not used currently
    
    // Calculate trend direction
    TrendDirection direction;
    if (slope.abs() < 0.0001) {
      direction = TrendDirection.stable;
    } else if (slope > 0) {
      direction = TrendDirection.increasing;
    } else {
      direction = TrendDirection.decreasing;
    }
    
    // Calculate change rate (per minute)
    final changeRate = slope * 60000; // Convert from per millisecond to per minute
    
    return TrendInfo(
      metricName: metricName,
      direction: direction,
      changeRate: changeRate,
      currentValue: values.last,
      samples: n,
    );
  }
}

/// Trend information
class TrendInfo {
  final String metricName;
  final TrendDirection direction;
  final double changeRate;
  final double currentValue;
  final int samples;
  
  TrendInfo({
    required this.metricName,
    required this.direction,
    required this.changeRate,
    required this.currentValue,
    required this.samples,
  });
  
  Map<String, dynamic> toMap() => {
    'metricName': metricName,
    'direction': direction.name,
    'changeRate': changeRate,
    'currentValue': currentValue,
    'samples': samples,
  };
}

enum TrendDirection { increasing, decreasing, stable }