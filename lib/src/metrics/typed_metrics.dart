/// Type-safe performance metrics to replace Map`<String, dynamic>` usage
library;

import 'dart:math' as math;
import '../events/event_models.dart';

/// Base class for all performance metrics
abstract class PerformanceMetric {
  /// Unique identifier for this metric
  String get name;

  /// The measured value
  double get value;

  /// Optional maximum capacity (for utilization calculation)
  double? get capacity;

  /// When this metric was recorded
  DateTime get timestamp;

  /// Type of metric for categorization
  MetricType get type;

  /// Unit of measurement (optional)
  String? get unit;

  /// Calculate utilization percentage if capacity is available
  double? get utilizationPercentage {
    if (capacity != null && capacity! > 0) {
      return (value / capacity!) * 100;
    }
    return null;
  }

  /// Convert to map for serialization
  Map<String, dynamic> toMap();

  /// Create a PerformanceEvent from this metric
  PerformanceEvent toEvent() {
    return PerformanceEvent(
      metricName: name,
      value: value,
      capacity: capacity,
      type: type,
      unit: unit,
      timestamp: timestamp,
    );
  }
}

/// Resource usage metric (memory, CPU, disk, etc.)
class ResourceUsageMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final double value;

  @override
  final double? capacity;

  @override
  final DateTime timestamp;

  @override
  final String? unit;

  final ResourceType resourceType;

  ResourceUsageMetric({
    required this.name,
    required this.value,
    this.capacity,
    required this.resourceType,
    this.unit,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  MetricType get type => MetricType.gauge;

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'capacity': capacity,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'resourceType': resourceType.name,
      'utilizationPercentage': utilizationPercentage,
    };
  }

  factory ResourceUsageMetric.fromMap(Map<String, dynamic> map) {
    return ResourceUsageMetric(
      name: map['name'] as String,
      value: (map['value'] as num).toDouble(),
      capacity: (map['capacity'] as num?)?.toDouble(),
      resourceType: ResourceType.values.byName(map['resourceType'] as String),
      unit: map['unit'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum ResourceType { memory, cpu, disk, network, battery }

/// Counter metric for tracking cumulative values
class CounterMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final double value;

  @override
  final DateTime timestamp;

  @override
  final String? unit;

  final double increment;

  CounterMetric({
    required this.name,
    required this.value,
    this.increment = 1.0,
    this.unit,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  MetricType get type => MetricType.counter;

  @override
  double? get capacity => null; // Counters don't have capacity

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'increment': increment,
    };
  }

  factory CounterMetric.fromMap(Map<String, dynamic> map) {
    return CounterMetric(
      name: map['name'] as String,
      value: (map['value'] as num).toDouble(),
      increment: (map['increment'] as num?)?.toDouble() ?? 1.0,
      unit: map['unit'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Timer metric for measuring duration
class TimerMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final DateTime timestamp;

  final Duration duration;
  final String operation;
  final bool success;
  final String? errorMessage;

  TimerMetric({
    required this.name,
    required this.duration,
    required this.operation,
    this.success = true,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  double get value => duration.inMicroseconds.toDouble();

  @override
  String get unit => 'microseconds';

  @override
  MetricType get type => MetricType.timer;

  @override
  double? get capacity => null; // Timers don't have capacity

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'durationMs': duration.inMilliseconds,
      'operation': operation,
      'success': success,
      'errorMessage': errorMessage,
    };
  }

  factory TimerMetric.fromMap(Map<String, dynamic> map) {
    return TimerMetric(
      name: map['name'] as String,
      duration: Duration(milliseconds: map['durationMs'] as int),
      operation: map['operation'] as String,
      success: map['success'] as bool? ?? true,
      errorMessage: map['errorMessage'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Histogram metric for tracking distribution of values
class HistogramMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final DateTime timestamp;

  @override
  final String? unit;

  final List<double> samples;
  final List<double> buckets;
  final Map<double, int> bucketCounts;

  HistogramMetric({
    required this.name,
    required this.samples,
    required this.buckets,
    this.unit,
    DateTime? timestamp,
  })  : timestamp = timestamp ?? DateTime.now(),
        bucketCounts = _calculateBucketCounts(samples, buckets);

  @override
  double get value => samples.isNotEmpty
      ? samples.reduce((a, b) => a + b) / samples.length
      : 0.0; // Average value

  @override
  MetricType get type => MetricType.histogram;

  @override
  double? get capacity => null; // Histograms don't have capacity

  /// Calculate percentiles
  double getPercentile(double p) {
    if (samples.isEmpty) return 0.0;

    final sorted = List<double>.from(samples)..sort();
    final index = (p / 100) * (sorted.length - 1);

    if (index.isFinite && index >= 0 && index < sorted.length) {
      return sorted[index.floor()];
    }
    return 0.0;
  }

  /// Get minimum value
  double get min =>
      samples.isNotEmpty ? samples.reduce((a, b) => a < b ? a : b) : 0.0;

  /// Get maximum value
  double get max =>
      samples.isNotEmpty ? samples.reduce((a, b) => a > b ? a : b) : 0.0;

  /// Get standard deviation
  double get stdDev {
    if (samples.length < 2) return 0.0;

    final mean = value;
    final variance =
        samples.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            samples.length;

    return variance.isFinite ? math.sqrt(variance) : 0.0;
  }

  static Map<double, int> _calculateBucketCounts(
      List<double> samples, List<double> buckets) {
    final counts = <double, int>{};

    for (final bucket in buckets) {
      counts[bucket] = 0;
    }

    for (final sample in samples) {
      for (final bucket in buckets) {
        if (sample <= bucket) {
          counts[bucket] = (counts[bucket] ?? 0) + 1;
          break;
        }
      }
    }

    return counts;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'samples': samples,
      'buckets': buckets,
      'bucketCounts': bucketCounts,
      'min': min,
      'max': max,
      'stdDev': stdDev,
      'p50': getPercentile(50),
      'p95': getPercentile(95),
      'p99': getPercentile(99),
    };
  }

  factory HistogramMetric.fromMap(Map<String, dynamic> map) {
    return HistogramMetric(
      name: map['name'] as String,
      samples: (map['samples'] as List<dynamic>).cast<double>(),
      buckets: (map['buckets'] as List<dynamic>).cast<double>(),
      unit: map['unit'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Network-specific metric
class NetworkMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final double value;

  @override
  final DateTime timestamp;

  final NetworkOperation operation;
  final Duration latency;
  final int bytes;
  final bool success;
  final int? statusCode;
  final String? endpoint;

  NetworkMetric({
    required this.name,
    required this.value,
    required this.operation,
    required this.latency,
    required this.bytes,
    this.success = true,
    this.statusCode,
    this.endpoint,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  MetricType get type => MetricType.timer;

  @override
  String get unit => operation == NetworkOperation.throughput
      ? 'bytes_per_second'
      : 'milliseconds';

  @override
  double? get capacity => null;

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'operation': operation.name,
      'latencyMs': latency.inMilliseconds,
      'bytes': bytes,
      'success': success,
      'statusCode': statusCode,
      'endpoint': endpoint,
    };
  }

  factory NetworkMetric.fromMap(Map<String, dynamic> map) {
    return NetworkMetric(
      name: map['name'] as String,
      value: (map['value'] as num).toDouble(),
      operation: NetworkOperation.values.byName(map['operation'] as String),
      latency: Duration(milliseconds: map['latencyMs'] as int),
      bytes: map['bytes'] as int,
      success: map['success'] as bool? ?? true,
      statusCode: map['statusCode'] as int?,
      endpoint: map['endpoint'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

enum NetworkOperation { request, response, throughput, latency }

/// Custom metric for application-specific measurements
class CustomMetric extends PerformanceMetric {
  @override
  final String name;

  @override
  final double value;

  @override
  final double? capacity;

  @override
  final DateTime timestamp;

  @override
  final MetricType type;

  @override
  final String? unit;

  final Map<String, dynamic> metadata;
  final String category;

  CustomMetric({
    required this.name,
    required this.value,
    required this.type,
    this.capacity,
    this.unit,
    required this.category,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'value': value,
      'capacity': capacity,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'unit': unit,
      'category': category,
      'metadata': metadata,
      'utilizationPercentage': utilizationPercentage,
    };
  }

  factory CustomMetric.fromMap(Map<String, dynamic> map) {
    return CustomMetric(
      name: map['name'] as String,
      value: (map['value'] as num).toDouble(),
      capacity: (map['capacity'] as num?)?.toDouble(),
      type: MetricType.values.byName(map['type'] as String),
      unit: map['unit'] as String?,
      category: map['category'] as String,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// Collection of metrics with statistical operations
class MetricCollection {
  final String name;
  final List<PerformanceMetric> metrics;
  final DateTime createdAt;

  MetricCollection({
    required this.name,
    required this.metrics,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Get metrics by type
  List<T> getMetricsByType<T extends PerformanceMetric>() {
    return metrics.whereType<T>().toList();
  }

  /// Get metrics by name pattern
  List<PerformanceMetric> getMetricsByName(Pattern pattern) {
    return metrics.where((m) => pattern.allMatches(m.name).isNotEmpty).toList();
  }

  /// Calculate aggregate statistics
  Map<String, double> getAggregateStats() {
    if (metrics.isEmpty) return {};

    final values = metrics.map((m) => m.value).toList();
    values.sort();

    final sum = values.reduce((a, b) => a + b);
    final avg = sum / values.length;

    return {
      'count': metrics.length.toDouble(),
      'sum': sum,
      'avg': avg,
      'min': values.first,
      'max': values.last,
      'median': values[values.length ~/ 2],
    };
  }

  /// Export to JSON-serializable format
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'metrics': metrics.map((m) => m.toMap()).toList(),
      'aggregateStats': getAggregateStats(),
    };
  }

  factory MetricCollection.fromMap(Map<String, dynamic> map) {
    final metricMaps = map['metrics'] as List<dynamic>;
    final metrics =
        metricMaps.map((m) => _parseMetric(m as Map<String, dynamic>)).toList();

    return MetricCollection(
      name: map['name'] as String,
      metrics: metrics,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  static PerformanceMetric _parseMetric(Map<String, dynamic> map) {
    final type = MetricType.values.byName(map['type'] as String);

    switch (type) {
      case MetricType.gauge:
        if (map.containsKey('resourceType')) {
          return ResourceUsageMetric.fromMap(map);
        }
        return CustomMetric.fromMap(map);
      case MetricType.counter:
        return CounterMetric.fromMap(map);
      case MetricType.timer:
        if (map.containsKey('operation') && map.containsKey('latencyMs')) {
          return NetworkMetric.fromMap(map);
        }
        if (map.containsKey('durationMs')) {
          return TimerMetric.fromMap(map);
        }
        return CustomMetric.fromMap(map);
      case MetricType.histogram:
        return HistogramMetric.fromMap(map);
    }
  }
}
