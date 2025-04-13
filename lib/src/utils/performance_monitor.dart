import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

/// Performance monitoring utility for tracking operation metrics
class PerformanceMonitor {
  final MCPLogger _logger = MCPLogger('mcp.performance_monitor');

  // Active timers
  final Map<String, Stopwatch> _activeTimers = {};

  // Performance metrics
  final Map<String, _MetricCounter> _counters = {};
  final Map<String, _MetricTimer> _timers = {};
  final Map<String, _ResourceUsage> _resources = {};

  // Recent operations queue (limited size)
  final Queue<_OperationRecord> _recentOperations = Queue();
  final int _maxRecentOperations;

  // Topics that should cache events
  final Set<String> _cachingTopics = {};

  // Monitoring configuration
  final bool _enableLogging;
  final bool _enableMetricsExport;
  final Duration _autoExportInterval;
  Timer? _exportTimer;
  String? _exportPath;

  // Singleton instance
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();

  /// Get singleton instance
  static PerformanceMonitor get instance => _instance;

  /// Internal constructor
  PerformanceMonitor._internal({
    int maxRecentOperations = 100,
    bool enableLogging = false,
    bool enableMetricsExport = false,
    Duration autoExportInterval = const Duration(minutes: 5),
  }) :
        _maxRecentOperations = maxRecentOperations,
        _enableLogging = enableLogging,
        _enableMetricsExport = enableMetricsExport,
        _autoExportInterval = autoExportInterval;

  /// Initialize with custom configuration
  void initialize({
    int? maxRecentOperations,
    bool? enableLogging,
    bool? enableMetricsExport,
    Duration? autoExportInterval,
    String? exportPath,
  }) {
    if (maxRecentOperations != null && maxRecentOperations != _maxRecentOperations) {
      // Resize operations queue if needed
      while (_recentOperations.length > maxRecentOperations) {
        _recentOperations.removeFirst();
      }
    }

    // Set configuration values
    if (enableLogging != null && enableLogging != _enableLogging) {
      _logger.debug('Performance logging ${enableLogging ? 'enabled' : 'disabled'}');
    }

    // Update export path
    if (exportPath != null) {
      _exportPath = exportPath;
    }

    // Set up auto-export timer if enabled
    if (enableMetricsExport != null && enableMetricsExport != _enableMetricsExport) {
      if (enableMetricsExport) {
        _setupExportTimer(autoExportInterval ?? _autoExportInterval);
      } else if (_exportTimer != null) {
        _exportTimer!.cancel();
        _exportTimer = null;
      }
    } else if (_enableMetricsExport && autoExportInterval != null) {
      // Update export timer interval
      _setupExportTimer(autoExportInterval);
    }
  }

  /// Enable event caching for a topic
  void enableCaching(String topic) {
    _cachingTopics.add(topic);
    _logger.debug('Enabled caching for topic: $topic');
  }

  /// Disable event caching for a topic
  void disableCaching(String topic) {
    _cachingTopics.remove(topic);
    _logger.debug('Disabled caching for topic: $topic');
  }

  /// Start a timer for a specific operation
  String startTimer(String operation, {Map<String, dynamic>? metadata}) {
    final operationId = '${operation}|${DateTime.now().millisecondsSinceEpoch}';

    // Create and start new stopwatch
    final stopwatch = Stopwatch()..start();
    _activeTimers[operationId] = stopwatch;

    // Log start if enabled
    if (_enableLogging) {
      _logger.debug('Started operation: $operation (ID: $operationId)');
    }

    return operationId;
  }

  /// Stop a timer and record its duration
  Duration stopTimer(String operationId, {bool success = true, Map<String, dynamic>? metadata}) {
    final stopwatch = _activeTimers.remove(operationId);

    if (stopwatch == null) {
      _logger.warning('Tried to stop unknown timer: $operationId');
      return Duration.zero;
    }

    // Stop the stopwatch
    stopwatch.stop();
    final duration = stopwatch.elapsed;

    // Extract operation name from ID
    final operationName = operationId.split('|').first;

    // Record operation
    _recordOperation(
      operationName,
      duration,
      success: success,
      metadata: metadata,
    );

    // Log completion if enabled
    if (_enableLogging) {
      _logger.debug(
          'Completed operation: $operationName in ${duration.inMilliseconds}ms '
              '(ID: $operationId, success: $success)'
      );
    }

    return duration;
  }

  /// Increment a counter
  void incrementCounter(String name, [int value = 1]) {
    _counters.putIfAbsent(name, () => _MetricCounter(name));
    _counters[name]!.increment(value);

    if (_enableLogging) {
      _logger.debug('Counter $name incremented by $value');
    }
  }

  /// Decrement a counter
  void decrementCounter(String name, [int value = 1]) {
    _counters.putIfAbsent(name, () => _MetricCounter(name));
    _counters[name]!.increment(-value);

    if (_enableLogging) {
      _logger.debug('Counter $name decremented by $value');
    }
  }

  /// Record resource usage
  void recordResourceUsage(String resource, double usage, {double? capacity}) {
    _resources.putIfAbsent(resource, () => _ResourceUsage(resource, capacity));
    _resources[resource]!.record(usage);

    if (_enableLogging) {
      final capacityStr = capacity != null ? '/$capacity' : '';
      _logger.debug('Resource $resource usage: $usage$capacityStr');
    }
  }

  /// Record a generic metric with optional metadata
  void recordMetric(
      String name,
      int duration,
      {
        bool success = true,
        Map<String, dynamic>? metadata
      }
      ) {
    // Record as a timer metric
    _timers.putIfAbsent(name, () => _MetricTimer(name));
    _timers[name]!.record(Duration(milliseconds: duration), success);

    // Add to recent operations
    _recentOperations.add(_OperationRecord(
      name: name,
      duration: Duration(milliseconds: duration),
      timestamp: DateTime.now(),
      success: success,
      metadata: metadata,
    ));

    // Trim recent operations queue if needed
    while (_recentOperations.length > _maxRecentOperations) {
      _recentOperations.removeFirst();
    }

    // Optional logging if enabled
    if (_enableLogging) {
      _logger.debug(
          'Metric $name: ${duration}ms (success: $success, metadata: $metadata)'
      );
    }
  }

  /// Record an operation
  void _recordOperation(
      String operation,
      Duration duration,
      {bool success = true, Map<String, dynamic>? metadata}
      ) {
    // Update timer metrics
    _timers.putIfAbsent(operation, () => _MetricTimer(operation));
    _timers[operation]!.record(duration, success);

    // Add to recent operations
    _recentOperations.add(_OperationRecord(
      name: operation,
      duration: duration,
      timestamp: DateTime.now(),
      success: success,
      metadata: metadata,
    ));

    // Trim recent operations queue if needed
    while (_recentOperations.length > _maxRecentOperations) {
      _recentOperations.removeFirst();
    }
  }

  /// Check if a topic has caching enabled
  bool hasCachingEnabled(String topic) {
    return _cachingTopics.contains(topic);
  }

  /// Get timer metrics for a specific operation
  Map<String, dynamic>? getTimerMetrics(String name) {
    final timer = _timers[name];
    if (timer == null) return null;
    return timer.toJson();
  }

  /// Get metrics report
  Map<String, dynamic> getMetricsReport() {
    final now = DateTime.now();

    return {
      'timestamp': now.toIso8601String(),
      'counters': _counters.map((key, value) => MapEntry(key, value.toJson())),
      'timers': _timers.map((key, value) => MapEntry(key, value.toJson())),
      'resources': _resources.map((key, value) => MapEntry(key, value.toJson())),
      'recent_operations': _recentOperations.map((op) => op.toJson()).toList(),
      'caching_topics': _cachingTopics.toList(),
    };
  }

  /// Get metrics summary
  Map<String, dynamic> getMetricsSummary() {
    final Map<String, dynamic> summary = {};

    // Add counter summaries
    final Map<String, dynamic> counters = {};
    for (final entry in _counters.entries) {
      counters[entry.key] = entry.value.value;
    }
    summary['counters'] = counters;

    // Add timer summaries
    final Map<String, dynamic> timers = {};
    for (final entry in _timers.entries) {
      timers[entry.key] = {
        'avg_ms': entry.value.averageDuration.inMilliseconds,
        'min_ms': entry.value.minDuration.inMilliseconds,
        'max_ms': entry.value.maxDuration.inMilliseconds,
        'count': entry.value.count,
        'success_rate': entry.value.successRate,
      };
    }
    summary['timers'] = timers;

    // Add resource summaries
    final Map<String, dynamic> resources = {};
    for (final entry in _resources.entries) {
      resources[entry.key] = {
        'current': entry.value.currentUsage,
        'avg': entry.value.averageUsage,
        'peak': entry.value.peakUsage,
        'capacity': entry.value.capacity,
      };
    }
    summary['resources'] = resources;

    return summary;
  }

  /// Export metrics to JSON file
  Future<bool> exportMetrics([String? filePath]) async {
    if (kIsWeb) {
      _logger.warning('Cannot export metrics to file in web platform');
      return false;
    }

    final path = filePath ?? _exportPath;
    if (path == null) {
      _logger.warning('No export path specified');
      return false;
    }

    try {
      final report = getMetricsReport();
      final json = jsonEncode(report);

      final file = File(path);
      await file.writeAsString(json);

      _logger.info('Metrics exported to $path');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to export metrics to file', e, stackTrace);
      return false;
    }
  }

  /// Set up auto-export timer
  void _setupExportTimer(Duration interval) {
    _exportTimer?.cancel();

    // Don't set up timer for web platform
    if (kIsWeb) return;

    if (_exportPath == null) {
      _logger.warning('Cannot set up auto-export: no export path specified');
      return;
    }

    _exportTimer = Timer.periodic(interval, (timer) {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      // Determine if we should use the provided path directly or create a timestamped file
      final filePath = _exportPath!.endsWith('.json')
          ? _exportPath!
          : '$_exportPath/metrics_$timestamp.json';

      exportMetrics(filePath);
    });

    _logger.debug('Auto-export timer set up with interval: ${interval.inSeconds}s');
  }

  /// Reset all metrics
  void reset() {
    _activeTimers.clear();
    _counters.clear();
    _timers.clear();
    _resources.clear();
    _recentOperations.clear();

    _logger.info('Performance metrics reset');
  }

  /// Clean up resources
  void dispose() {
    _exportTimer?.cancel();
    _exportTimer = null;

    reset();
  }
}

/// Counter metric
class _MetricCounter {
  final String name;
  int _value = 0;
  final DateTime _createdAt = DateTime.now();
  DateTime _lastUpdated = DateTime.now();

  _MetricCounter(this.name);

  /// Current counter value
  int get value => _value;

  /// Increment counter
  void increment([int value = 1]) {
    _value += value;
    _lastUpdated = DateTime.now();
  }

  /// Reset counter
  void reset() {
    _value = 0;
    _lastUpdated = DateTime.now();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': _value,
      'created_at': _createdAt.toIso8601String(),
      'last_updated': _lastUpdated.toIso8601String(),
    };
  }
}

/// Timer metric
class _MetricTimer {
  final String name;
  int _count = 0;
  int _successCount = 0;
  Duration _totalDuration = Duration.zero;
  Duration _minDuration = Duration(days: 365 * 100);
  Duration _maxDuration = Duration.zero;
  final List<Duration> _recentDurations = [];
  final int _maxRecentDurations = 100;

  _MetricTimer(this.name);

  /// Number of recorded operations
  int get count => _count;

  /// Success rate (0.0 to 1.0)
  double get successRate => _count > 0 ? _successCount / _count : 0.0;

  /// Average duration
  Duration get averageDuration => _count > 0
      ? Duration(microseconds: _totalDuration.inMicroseconds ~/ _count)
      : Duration.zero;

  /// Minimum duration
  Duration get minDuration => _count > 0 ? _minDuration : Duration.zero;

  /// Maximum duration
  Duration get maxDuration => _maxDuration;

  /// Recent average duration (last 100 operations)
  Duration get recentAverageDuration {
    if (_recentDurations.isEmpty) return Duration.zero;

    final total = _recentDurations.fold<int>(
        0, (sum, duration) => sum + duration.inMicroseconds
    );

    return Duration(microseconds: total ~/ _recentDurations.length);
  }

  /// Record a new duration
  void record(Duration duration, bool success) {
    _count++;
    if (success) _successCount++;

    _totalDuration += duration;

    if (duration < _minDuration) {
      _minDuration = duration;
    }

    if (duration > _maxDuration) {
      _maxDuration = duration;
    }

    // Add to recent durations
    _recentDurations.add(duration);

    // Trim recent durations if needed
    if (_recentDurations.length > _maxRecentDurations) {
      _recentDurations.removeAt(0);
    }
  }

  /// Reset timer
  void reset() {
    _count = 0;
    _successCount = 0;
    _totalDuration = Duration.zero;
    _minDuration = Duration(days: 365 * 100);
    _maxDuration = Duration.zero;
    _recentDurations.clear();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'count': _count,
      'success_count': _successCount,
      'success_rate': successRate,
      'average_ms': averageDuration.inMilliseconds,
      'min_ms': minDuration.inMilliseconds,
      'max_ms': maxDuration.inMilliseconds,
      'recent_average_ms': recentAverageDuration.inMilliseconds,
      'recent_durations_ms': _recentDurations.map((d) => d.inMilliseconds).toList(),
    };
  }
}

/// Resource usage metric
class _ResourceUsage {
  final String name;
  double? _capacity;
  double _currentUsage = 0.0;
  double _peakUsage = 0.0;
  double _totalUsage = 0.0;
  int _usageCount = 0;

  _ResourceUsage(this.name, this._capacity);

  /// Current resource usage
  double get currentUsage => _currentUsage;

  /// Peak resource usage
  double get peakUsage => _peakUsage;

  /// Resource capacity (if set)
  double? get capacity => _capacity;

  /// Average usage
  double get averageUsage => _usageCount > 0 ? _totalUsage / _usageCount : 0.0;

  /// Usage percentage (if capacity is set)
  double? get usagePercentage => _capacity != null && _capacity! > 0
      ? (_currentUsage / _capacity! * 100.0)
      : null;

  /// Record a new usage value
  void record(double usage) {
    _currentUsage = usage;
    _totalUsage += usage;
    _usageCount++;

    if (usage > _peakUsage) {
      _peakUsage = usage;
    }
  }

  /// Update resource capacity
  void setCapacity(double capacity) {
    _capacity = capacity;
  }

  /// Reset usage metrics
  void reset() {
    _currentUsage = 0.0;
    _peakUsage = 0.0;
    _totalUsage = 0.0;
    _usageCount = 0;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final json = {
      'name': name,
      'current': _currentUsage,
      'peak': _peakUsage,
      'average': averageUsage,
      'samples': _usageCount,
    };

    if (_capacity != null) {
      json['capacity'] = _capacity as Object;

      final percentage = usagePercentage;
      if (percentage != null) {
        json['usage_percentage'] = percentage;
      }
    }

    return json;
  }
}

/// Operation record
class _OperationRecord {
  final String name;
  final Duration duration;
  final DateTime timestamp;
  final bool success;
  final Map<String, dynamic>? metadata;

  _OperationRecord({
    required this.name,
    required this.duration,
    required this.timestamp,
    required this.success,
    this.metadata,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'name': name,
      'duration_ms': duration.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
    };

    if (metadata != null) {
      json['metadata'] = metadata;
    }

    return json;
  }
}