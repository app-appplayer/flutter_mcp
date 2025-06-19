import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/performance/enhanced_performance_monitor.dart';
import 'package:flutter_mcp/src/metrics/typed_metrics.dart';

void main() {
  test('Enhanced performance monitor basic functionality', () {
    final monitor = EnhancedPerformanceMonitor.instance;
    monitor.reset();

    // Configure simple aggregation
    monitor.configureAggregation(
      'test_metric',
      AggregationConfig(
        window: Duration(seconds: 10),
        type: AggregationType.average,
      ),
    );

    // Record metrics
    monitor.recordTypedMetric(
      CounterMetric(
        name: 'test_metric',
        value: 10,
        increment: 1,
        unit: 'count',
      ),
    );

    monitor.recordTypedMetric(
      CounterMetric(
        name: 'test_metric',
        value: 20,
        increment: 1,
        unit: 'count',
      ),
    );

    // Check aggregated value
    final aggregated = monitor.getAggregatedValue('test_metric');
    expect(aggregated, equals(15.0)); // Average of 10 and 20

    // Get statistics
    final stats = monitor.getMetricStatistics('test_metric');
    expect(stats, isNotNull);
    expect(stats!['count'], equals(2));
    expect(stats['average'], equals(15.0));
    expect(stats['min'], equals(10.0));
    expect(stats['max'], equals(20.0));

    // Clean up
    monitor.dispose();
  });
}
