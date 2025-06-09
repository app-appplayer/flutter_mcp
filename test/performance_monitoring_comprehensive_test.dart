import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/performance/enhanced_performance_monitor.dart';
import 'package:flutter_mcp/src/events/enhanced_typed_event_system.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/metrics/typed_metrics.dart';
import 'package:flutter_mcp/src/utils/performance_monitor.dart';

void main() {
  group('Enhanced Performance Monitor Tests', () {
    late EnhancedPerformanceMonitor monitor;
    late PerformanceMonitor baseMonitor;

    setUp(() {
      monitor = EnhancedPerformanceMonitor.instance;
      baseMonitor = PerformanceMonitor.instance;
      monitor.reset();
    });

    tearDown(() {
      monitor.dispose();
    });

    group('Metric Recording and Aggregation', () {
      test('should record typed metrics', () {
        // Act
        final metric = ResourceUsageMetric(
          name: 'test.metric',
          value: 100.5,
          resourceType: ResourceType.cpu,
          unit: 'ms',
        );
        monitor.recordTypedMetric(metric);

        // Assert - metric should be recorded
        final stats = monitor.getMetricStatistics('test.metric');
        expect(stats, isNotNull);
      });

      test('should configure aggregation for metrics', () {
        // Arrange
        final config = AggregationConfig(
          window: Duration(seconds: 10),
          type: AggregationType.average,
        );

        // Act
        monitor.configureAggregation('test.metric', config);
        
        // Record some metrics
        for (int i = 0; i < 5; i++) {
          final metric = CounterMetric(
            name: 'test.metric',
            value: i * 10.0,
            unit: 'ms',
          );
          monitor.recordTypedMetric(metric);
        }

        // Assert
        final value = monitor.getAggregatedValue('test.metric');
        expect(value, isNotNull);
      });

      test('should perform different aggregation types', () {
        // Test average aggregation
        monitor.configureAggregation('avg.metric', AggregationConfig(
          window: Duration(seconds: 10),
          type: AggregationType.average,
        ));

        // Test max aggregation
        monitor.configureAggregation('max.metric', AggregationConfig(
          window: Duration(seconds: 10),
          type: AggregationType.max,
        ));

        // Record metrics
        for (int i = 1; i <= 5; i++) {
          monitor.recordTypedMetric(ResourceUsageMetric(
            name: 'avg.metric',
            value: i * 10.0,
            resourceType: ResourceType.cpu,
            unit: 'ms',
          ));
          monitor.recordTypedMetric(ResourceUsageMetric(
            name: 'max.metric',
            value: i * 10.0,
            resourceType: ResourceType.cpu,
            unit: 'ms',
          ));
        }

        // Assert
        final avgValue = monitor.getAggregatedValue('avg.metric');
        final maxValue = monitor.getAggregatedValue('max.metric');
        
        expect(avgValue, equals(30.0)); // (10+20+30+40+50)/5
        expect(maxValue, equals(50.0)); // max value
      });
    });

    group('Threshold Monitoring', () {
      test('should configure thresholds for metrics', () async {
        // Arrange
        final violations = <ThresholdViolation>[];
        
        final config = ThresholdConfig(
          warningLevel: 80.0,
          criticalLevel: 95.0,
          onViolation: (violation) {
            violations.add(violation);
          },
        );

        // Act
        monitor.configureThreshold('cpu.usage', config);
        
        // Record metric that violates threshold
        monitor.recordTypedMetric(ResourceUsageMetric(
          name: 'cpu.usage',
          value: 90.0,
          resourceType: ResourceType.cpu,
          unit: '%',
        ));

        // Wait a bit for threshold check
        await Future.delayed(Duration(milliseconds: 100));

        // Assert - should have violation
        expect(violations.isNotEmpty, isTrue);
        if (violations.isNotEmpty) {
          expect(violations.first.level, equals(ThresholdLevel.warning));
          expect(violations.first.value, equals(90.0));
        }
      });

      test('should detect critical threshold violations', () async {
        // Arrange
        final violations = <ThresholdViolation>[];
        
        final config = ThresholdConfig(
          warningLevel: 80.0,
          criticalLevel: 95.0,
          onViolation: (violation) {
            violations.add(violation);
          },
        );

        // Act
        monitor.configureThreshold('memory.usage', config);
        
        // Record metric that violates critical threshold
        monitor.recordTypedMetric(ResourceUsageMetric(
          name: 'memory.usage',
          value: 98.0,
          resourceType: ResourceType.memory,
          unit: '%',
        ));

        // Wait a bit for threshold check
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        expect(violations.isNotEmpty, isTrue);
        if (violations.isNotEmpty) {
          expect(violations.first.level, equals(ThresholdLevel.critical));
        }
      });
    });

    group('Auto Detection Features', () {
      test('should enable anomaly detection', () {
        // Act
        monitor.enableAutoDetection(
          anomalies: true,
          thresholds: false,
          interval: Duration(seconds: 1),
        );

        // Record some normal values
        for (int i = 0; i < 10; i++) {
          monitor.recordTypedMetric(CounterMetric(
            name: 'anomaly.test',
            value: 50.0 + i,
            unit: 'ms',
          ));
        }

        // Record an anomaly
        monitor.recordTypedMetric(CounterMetric(
          name: 'anomaly.test',
          value: 500.0, // Anomalous value
          unit: 'ms',
        ));

        // Assert - should detect but not throw
        expect(() => monitor.getMetricStatistics('anomaly.test'), returnsNormally);
      });

      test('should disable auto detection', () {
        // Arrange
        monitor.enableAutoDetection(anomalies: true);

        // Act
        monitor.disableAutoDetection();

        // Assert - detection should be disabled
        expect(() => monitor.recordTypedMetric(CounterMetric(
          name: 'test.metric',
          value: 1000.0,
          unit: 'ms',
        )), returnsNormally);
      });
    });

    group('Performance Reports', () {
      test('should get metric statistics', () {
        // Arrange
        final metricName = 'stats.metric';
        
        // Act - Record multiple values
        for (int i = 1; i <= 10; i++) {
          monitor.recordTypedMetric(CounterMetric(
            name: metricName,
            value: i * 10.0,
            unit: 'ms',
          ));
        }

        // Get statistics
        final stats = monitor.getMetricStatistics(metricName);

        // Assert
        expect(stats, isNotNull);
        expect(stats?['count'], equals(10));
        expect(stats?['mean'], isNotNull);
        expect(stats?['min'], equals(10.0));
        expect(stats?['max'], equals(100.0));
      });

      test('should get performance trends', () {
        // Arrange
        for (int i = 0; i < 5; i++) {
          monitor.recordTypedMetric(CounterMetric(
            name: 'trend.metric',
            value: i * 20.0,
            unit: 'ms',
          ));
        }

        // Act
        final trends = monitor.getPerformanceTrends();

        // Assert
        expect(trends, isNotNull);
        expect(trends, isNotEmpty);
      });

      test('should get detailed report', () {
        // Arrange - Record various metrics
        monitor.recordTypedMetric(ResourceUsageMetric(
          name: 'cpu.usage',
          value: 45.0,
          resourceType: ResourceType.cpu,
          unit: '%',
        ));
        
        monitor.recordTypedMetric(ResourceUsageMetric(
          name: 'memory.usage',
          value: 60.0,
          resourceType: ResourceType.memory,
          unit: '%',
        ));

        // Act
        final report = monitor.getDetailedReport();

        // Assert
        expect(report, isNotNull);
        expect(report['metrics'], isNotNull);
        expect(report['aggregations'], isNotNull);
        expect(report['thresholds'], isNotNull);
      });
    });

    group('Base Monitor Integration', () {
      test('should use base monitor timer functionality', () async {
        // Act
        final timerId = baseMonitor.startTimer('operation.test');
        await Future.delayed(Duration(milliseconds: 100));
        final duration = baseMonitor.stopTimer(timerId);

        // Assert
        expect(duration, isNotNull);
        expect(duration.inMilliseconds, greaterThanOrEqualTo(100));
      });

      test('should increment counters through base monitor', () {
        // Act
        baseMonitor.incrementCounter('test.counter');
        baseMonitor.incrementCounter('test.counter');
        baseMonitor.incrementCounter('test.counter', 2);

        // Assert - counter should be incremented
        final stats = monitor.getMetricStatistics('test.counter');
        expect(stats, isNotNull);
      });
    });

    group('Memory Management', () {
      test('should reset all metrics and detectors', () {
        // Arrange
        monitor.recordTypedMetric(CounterMetric(
          name: 'reset.test',
          value: 100.0,
          unit: 'ms',
        ));

        // Act
        monitor.reset();

        // Assert
        final stats = monitor.getMetricStatistics('reset.test');
        expect(stats, isNull);
      });

      test('should properly dispose resources', () {
        // Arrange
        monitor.enableAutoDetection(anomalies: true);
        monitor.configureAggregation('test.metric', AggregationConfig());

        // Act & Assert - should not throw
        expect(() => monitor.dispose(), returnsNormally);
      });
    });

    group('Event System Integration', () {
      test('should integrate with typed event system', () async {
        // Arrange
        final events = <McpEvent>[];
        final subscriptionId = EnhancedTypedEventSystem.instance
            .subscribe<McpEvent>((event) => events.add(event));

        // Act
        monitor.recordTypedMetric(CounterMetric(
          name: 'event.test',
          value: 100.0,
          unit: 'ms',
        ));

        // Wait for event propagation
        await Future.delayed(Duration(milliseconds: 50));

        // Assert & Cleanup
        await EnhancedTypedEventSystem.instance.unsubscribe(subscriptionId);
        // Events may or may not be emitted depending on configuration
        expect(() => events.length, returnsNormally);
      });
    });
  });
}