// Targeted toMap/fromMap and aggregate-stats coverage for typed_metrics.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/metrics/typed_metrics.dart';
import 'package:flutter_mcp/src/events/event_models.dart';

void main() {
  group('PerformanceMetric base behaviour', () {
    test('utilizationPercentage divides value/capacity when both set', () {
      final m = ResourceUsageMetric(
        name: 'mem',
        value: 250,
        capacity: 1000,
        resourceType: ResourceType.memory,
      );
      expect(m.utilizationPercentage, 25.0);
    });

    test('utilizationPercentage is null when capacity is null/zero', () {
      expect(
        ResourceUsageMetric(
          name: 'cpu',
          value: 1,
          resourceType: ResourceType.cpu,
        ).utilizationPercentage,
        isNull,
      );
      expect(
        ResourceUsageMetric(
          name: 'mem',
          value: 1,
          capacity: 0,
          resourceType: ResourceType.memory,
        ).utilizationPercentage,
        isNull,
      );
    });

    test('toEvent forwards key fields', () {
      final m = ResourceUsageMetric(
        name: 'cpu',
        value: 0.42,
        capacity: 1.0,
        resourceType: ResourceType.cpu,
        unit: 'ratio',
      );
      final e = m.toEvent();
      expect(e.metricName, 'cpu');
      expect(e.value, 0.42);
      expect(e.capacity, 1.0);
      expect(e.unit, 'ratio');
      expect(e.type, MetricType.gauge);
    });
  });

  group('ResourceUsageMetric.fromMap', () {
    test('roundtrip preserves all fields', () {
      final m = ResourceUsageMetric(
        name: 'mem',
        value: 100,
        capacity: 200,
        resourceType: ResourceType.memory,
        unit: 'MB',
        timestamp: DateTime.parse('2030-01-01T00:00:00Z'),
      );
      final r = ResourceUsageMetric.fromMap(m.toMap());
      expect(r.name, m.name);
      expect(r.value, m.value);
      expect(r.capacity, m.capacity);
      expect(r.resourceType, m.resourceType);
      expect(r.unit, m.unit);
      expect(r.timestamp, m.timestamp);
    });

    test('handles missing capacity + unit', () {
      final r = ResourceUsageMetric.fromMap({
        'name': 'cpu',
        'value': 0.5,
        'resourceType': 'cpu',
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'gauge',
      });
      expect(r.capacity, isNull);
      expect(r.unit, isNull);
    });
  });

  group('CounterMetric.fromMap', () {
    test('roundtrip preserves increment + unit', () {
      final c = CounterMetric(
        name: 'reqs',
        value: 7,
        increment: 2,
        unit: 'count',
        timestamp: DateTime.parse('2030-01-01T00:00:00Z'),
      );
      final r = CounterMetric.fromMap(c.toMap());
      expect(r.value, 7);
      expect(r.increment, 2);
      expect(r.unit, 'count');
      expect(r.timestamp, c.timestamp);
    });

    test('defaults increment to 1.0 when missing', () {
      final c = CounterMetric.fromMap({
        'name': 'r',
        'value': 1,
        'type': 'counter',
        'timestamp': DateTime.now().toIso8601String(),
      });
      expect(c.increment, 1.0);
      expect(c.capacity, isNull);
      expect(c.type, MetricType.counter);
    });
  });

  group('TimerMetric', () {
    test('value is duration.inMicroseconds, unit/type fixed', () {
      final t = TimerMetric(
        name: 'op',
        duration: const Duration(milliseconds: 100),
        operation: 'fetch',
      );
      expect(t.value, 100 * 1000);
      expect(t.unit, 'microseconds');
      expect(t.type, MetricType.timer);
      expect(t.capacity, isNull);
      expect(t.success, isTrue);
    });

    test('fromMap restores all fields', () {
      final t = TimerMetric(
        name: 'op',
        duration: const Duration(milliseconds: 250),
        operation: 'save',
        success: false,
        errorMessage: 'oops',
        timestamp: DateTime.parse('2030-01-01T00:00:00Z'),
      );
      final r = TimerMetric.fromMap(t.toMap());
      expect(r.duration.inMilliseconds, 250);
      expect(r.operation, 'save');
      expect(r.success, isFalse);
      expect(r.errorMessage, 'oops');
    });

    test('fromMap defaults success to true when missing', () {
      final r = TimerMetric.fromMap({
        'name': 'op',
        'durationMs': 5,
        'operation': 'load',
        'type': 'timer',
        'timestamp': DateTime.now().toIso8601String(),
      });
      expect(r.success, isTrue);
    });
  });

  group('HistogramMetric edge cases', () {
    test('empty samples produce zero stats', () {
      final h = HistogramMetric(name: 'x', samples: [], buckets: [10]);
      expect(h.value, 0.0);
      expect(h.min, 0.0);
      expect(h.max, 0.0);
      expect(h.stdDev, 0.0);
      expect(h.getPercentile(50), 0.0);
    });

    test('single sample stdDev is 0', () {
      final h = HistogramMetric(name: 'x', samples: [42.0], buckets: [42]);
      expect(h.stdDev, 0.0);
    });

    test('getPercentile picks sorted index', () {
      final h = HistogramMetric(
        name: 'x',
        samples: [1, 5, 10, 50, 100],
        buckets: [1, 5, 10, 50, 100],
      );
      expect(h.getPercentile(0), 1);
      expect(h.getPercentile(50), 10);
      expect(h.getPercentile(100), 100);
    });

    test('toMap / fromMap roundtrip restores samples + buckets', () {
      final h = HistogramMetric(
        name: 'x',
        samples: [1.0, 2.0, 3.0, 4.0, 5.0],
        buckets: [2, 4, 6],
      );
      final r = HistogramMetric.fromMap(h.toMap());
      expect(r.samples, [1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(r.buckets, [2, 4, 6]);
    });
  });

  group('NetworkMetric', () {
    test('unit varies by NetworkOperation', () {
      final t = NetworkMetric(
        name: 'fetch',
        value: 0,
        operation: NetworkOperation.throughput,
        latency: const Duration(milliseconds: 50),
        bytes: 1024,
      );
      expect(t.unit, 'bytes_per_second');

      final l = NetworkMetric(
        name: 'fetch',
        value: 0,
        operation: NetworkOperation.latency,
        latency: const Duration(milliseconds: 50),
        bytes: 0,
      );
      expect(l.unit, 'milliseconds');
    });

    test('fromMap roundtrip', () {
      final n = NetworkMetric(
        name: 'fetch',
        value: 100,
        operation: NetworkOperation.request,
        latency: const Duration(milliseconds: 50),
        bytes: 1024,
        statusCode: 200,
        endpoint: '/api/test',
      );
      final r = NetworkMetric.fromMap(n.toMap());
      expect(r.operation, NetworkOperation.request);
      expect(r.latency.inMilliseconds, 50);
      expect(r.bytes, 1024);
      expect(r.statusCode, 200);
      expect(r.endpoint, '/api/test');
    });
  });

  group('CustomMetric', () {
    test('roundtrip preserves metadata + category + type', () {
      final c = CustomMetric(
        name: 'biz',
        value: 0.5,
        capacity: 1.0,
        type: MetricType.gauge,
        unit: 'ratio',
        category: 'business',
        metadata: {'k': 'v'},
      );
      final r = CustomMetric.fromMap(c.toMap());
      expect(r.value, 0.5);
      expect(r.capacity, 1.0);
      expect(r.unit, 'ratio');
      expect(r.category, 'business');
      expect(r.metadata, {'k': 'v'});
      expect(r.utilizationPercentage, 50.0);
    });

    test('default metadata is empty', () {
      final c = CustomMetric(
        name: 'biz',
        value: 1,
        type: MetricType.gauge,
        category: 'business',
      );
      expect(c.metadata, isEmpty);
    });
  });

  group('MetricCollection helpers', () {
    test('getMetricsByType filters by class', () {
      final c = MetricCollection(name: 'col', metrics: [
        ResourceUsageMetric(
          name: 'm1',
          value: 1,
          resourceType: ResourceType.memory,
        ),
        CounterMetric(name: 'c1', value: 2),
      ]);
      expect(c.getMetricsByType<ResourceUsageMetric>(), hasLength(1));
      expect(c.getMetricsByType<CounterMetric>(), hasLength(1));
      expect(c.getMetricsByType<NetworkMetric>(), isEmpty);
    });

    test('getMetricsByName filters by pattern', () {
      final c = MetricCollection(name: 'col', metrics: [
        CounterMetric(name: 'requests.api', value: 1),
        CounterMetric(name: 'requests.web', value: 2),
        CounterMetric(name: 'errors.api', value: 3),
      ]);
      expect(c.getMetricsByName(RegExp(r'^requests\.')), hasLength(2));
    });

    test('getAggregateStats returns count/sum/avg/min/max/median', () {
      final c = MetricCollection(name: 'col', metrics: [
        CounterMetric(name: 'a', value: 1),
        CounterMetric(name: 'b', value: 2),
        CounterMetric(name: 'c', value: 3),
      ]);
      final stats = c.getAggregateStats();
      expect(stats['count'], 3);
      expect(stats['sum'], 6);
      expect(stats['avg'], 2);
      expect(stats['min'], 1);
      expect(stats['max'], 3);
      expect(stats['median'], 2);
    });

    test('getAggregateStats returns empty map for empty collection', () {
      final c = MetricCollection(name: 'col', metrics: []);
      expect(c.getAggregateStats(), isEmpty);
    });

    test('toMap + fromMap roundtrip preserves metric subtypes', () {
      final c = MetricCollection(name: 'col', metrics: [
        ResourceUsageMetric(
          name: 'mem',
          value: 100,
          resourceType: ResourceType.memory,
        ),
        CounterMetric(name: 'reqs', value: 7),
        TimerMetric(
          name: 'op',
          duration: const Duration(milliseconds: 50),
          operation: 'fetch',
        ),
        NetworkMetric(
          name: 'http',
          value: 1,
          operation: NetworkOperation.request,
          latency: const Duration(milliseconds: 100),
          bytes: 1024,
        ),
        CustomMetric(
          name: 'biz',
          value: 1,
          type: MetricType.gauge,
          category: 'business',
        ),
      ]);
      final r = MetricCollection.fromMap(c.toMap());
      expect(r.metrics, hasLength(5));
      expect(r.metrics[0], isA<ResourceUsageMetric>());
      expect(r.metrics[1], isA<CounterMetric>());
      expect(r.metrics[2], isA<TimerMetric>());
      expect(r.metrics[3], isA<NetworkMetric>());
      expect(r.metrics[4], isA<CustomMetric>());
    });
  });
}
