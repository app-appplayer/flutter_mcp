import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/metrics/typed_metrics.dart';
import 'package:flutter_mcp/src/utils/performance_monitor.dart';
import 'package:flutter_mcp/src/events/event_models.dart';
import 'package:flutter_mcp/src/utils/event_system.dart';

void main() {
  group('Typed Performance Metrics Tests', () {
    late PerformanceMonitor monitor;
    
    setUp(() {
      monitor = PerformanceMonitor.instance;
      monitor.reset();
    });
    
    tearDown(() {
      monitor.reset();
    });

    test('should create and record ResourceUsageMetric', () {
      print('=== ResourceUsageMetric Test ===');
      
      final metric = ResourceUsageMetric(
        name: 'memory.heap',
        value: 512.0,
        capacity: 1024.0,
        resourceType: ResourceType.memory,
        unit: 'MB',
      );
      
      expect(metric.name, equals('memory.heap'));
      expect(metric.value, equals(512.0));
      expect(metric.capacity, equals(1024.0));
      expect(metric.resourceType, equals(ResourceType.memory));
      expect(metric.unit, equals('MB'));
      expect(metric.type, equals(MetricType.gauge));
      expect(metric.utilizationPercentage, equals(50.0));
      
      // Test serialization
      final map = metric.toMap();
      expect(map['name'], equals('memory.heap'));
      expect(map['value'], equals(512.0));
      expect(map['utilizationPercentage'], equals(50.0));
      
      // Test deserialization
      final restored = ResourceUsageMetric.fromMap(map);
      expect(restored.name, equals(metric.name));
      expect(restored.value, equals(metric.value));
      expect(restored.capacity, equals(metric.capacity));
      
      print('ResourceUsageMetric creation and serialization successful');
    });

    test('should create and record CounterMetric', () {
      print('=== CounterMetric Test ===');
      
      final metric = CounterMetric(
        name: 'requests.total',
        value: 1500.0,
        increment: 5.0,
        unit: 'count',
      );
      
      expect(metric.name, equals('requests.total'));
      expect(metric.value, equals(1500.0));
      expect(metric.increment, equals(5.0));
      expect(metric.type, equals(MetricType.counter));
      expect(metric.capacity, isNull);
      
      // Test serialization roundtrip
      final map = metric.toMap();
      final restored = CounterMetric.fromMap(map);
      
      expect(restored.name, equals(metric.name));
      expect(restored.value, equals(metric.value));
      expect(restored.increment, equals(metric.increment));
      
      print('CounterMetric creation and serialization successful');
    });

    test('should create and record TimerMetric', () {
      print('=== TimerMetric Test ===');
      
      final duration = Duration(milliseconds: 250);
      final metric = TimerMetric(
        name: 'api.request',
        duration: duration,
        operation: 'fetch_user',
        success: true,
      );
      
      expect(metric.name, equals('api.request'));
      expect(metric.duration, equals(duration));
      expect(metric.operation, equals('fetch_user'));
      expect(metric.success, isTrue);
      expect(metric.type, equals(MetricType.timer));
      expect(metric.unit, equals('microseconds'));
      expect(metric.value, equals(duration.inMicroseconds.toDouble()));
      
      // Test with error
      final errorMetric = TimerMetric(
        name: 'api.error',
        duration: Duration(milliseconds: 100),
        operation: 'failed_request',
        success: false,
        errorMessage: 'Network timeout',
      );
      
      expect(errorMetric.success, isFalse);
      expect(errorMetric.errorMessage, equals('Network timeout'));
      
      print('TimerMetric creation and error handling successful');
    });

    test('should create and analyze HistogramMetric', () {
      print('=== HistogramMetric Test ===');
      
      final samples = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0];
      final buckets = [25.0, 50.0, 75.0, 100.0];
      
      final metric = HistogramMetric(
        name: 'response.times',
        samples: samples,
        buckets: buckets,
        unit: 'ms',
      );
      
      expect(metric.name, equals('response.times'));
      expect(metric.samples, equals(samples));
      expect(metric.buckets, equals(buckets));
      expect(metric.type, equals(MetricType.histogram));
      expect(metric.value, equals(55.0)); // Average
      expect(metric.min, equals(10.0));
      expect(metric.max, equals(100.0));
      
      // Test percentiles
      expect(metric.getPercentile(50), equals(50.0));
      expect(metric.getPercentile(95), equals(90.0));
      
      // Test standard deviation (approximately 28.72 for this dataset)
      expect(metric.stdDev, closeTo(28.72, 0.1));
      
      // Test bucket counts (each sample goes to first bucket >= sample)
      expect(metric.bucketCounts[25.0], equals(2)); // 10, 20
      expect(metric.bucketCounts[50.0], equals(3)); // 30, 40, 50
      expect(metric.bucketCounts[75.0], equals(2)); // 60, 70
      expect(metric.bucketCounts[100.0], equals(3)); // 80, 90, 100
      
      print('HistogramMetric analysis and statistics calculation successful');
    });

    test('should create and record NetworkMetric', () {
      print('=== NetworkMetric Test ===');
      
      final latency = Duration(milliseconds: 150);
      final metric = NetworkMetric(
        name: 'api.call',
        value: latency.inMilliseconds.toDouble(),
        operation: NetworkOperation.request,
        latency: latency,
        bytes: 2048,
        success: true,
        statusCode: 200,
        endpoint: '/api/users',
      );
      
      expect(metric.name, equals('api.call'));
      expect(metric.operation, equals(NetworkOperation.request));
      expect(metric.latency, equals(latency));
      expect(metric.bytes, equals(2048));
      expect(metric.statusCode, equals(200));
      expect(metric.endpoint, equals('/api/users'));
      expect(metric.unit, equals('milliseconds'));
      
      // Test throughput metric
      final throughputMetric = NetworkMetric(
        name: 'download.speed',
        value: 1000000.0, // 1MB/s
        operation: NetworkOperation.throughput,
        latency: Duration(seconds: 1),
        bytes: 1000000,
      );
      
      expect(throughputMetric.unit, equals('bytes_per_second'));
      
      print('NetworkMetric creation and throughput calculation successful');
    });

    test('should create and work with CustomMetric', () {
      print('=== CustomMetric Test ===');
      
      final metric = CustomMetric(
        name: 'cache.hit_rate',
        value: 85.5,
        type: MetricType.gauge,
        category: 'performance',
        unit: '%',
        metadata: {
          'cache_type': 'redis',
          'ttl': 3600,
          'keys_checked': 1000,
        },
      );
      
      expect(metric.name, equals('cache.hit_rate'));
      expect(metric.value, equals(85.5));
      expect(metric.type, equals(MetricType.gauge));
      expect(metric.category, equals('performance'));
      expect(metric.unit, equals('%'));
      expect(metric.metadata['cache_type'], equals('redis'));
      expect(metric.metadata['ttl'], equals(3600));
      
      print('CustomMetric creation and metadata processing successful');
    });

    test('should create and analyze MetricCollection', () {
      print('=== MetricCollection Test ===');
      
      final metrics = [
        CounterMetric(name: 'counter1', value: 10.0),
        CounterMetric(name: 'counter2', value: 20.0),
        ResourceUsageMetric(
          name: 'memory',
          value: 512.0,
          resourceType: ResourceType.memory,
        ),
        TimerMetric(
          name: 'timer1',
          duration: Duration(milliseconds: 100),
          operation: 'test',
        ),
      ];
      
      final collection = MetricCollection(
        name: 'test.collection',
        metrics: metrics,
      );
      
      expect(collection.name, equals('test.collection'));
      expect(collection.metrics.length, equals(4));
      
      // Test filtering by type
      final counters = collection.getMetricsByType<CounterMetric>();
      expect(counters.length, equals(2));
      expect(counters[0].name, equals('counter1'));
      expect(counters[1].name, equals('counter2'));
      
      final resources = collection.getMetricsByType<ResourceUsageMetric>();
      expect(resources.length, equals(1));
      expect(resources[0].name, equals('memory'));
      
      // Test filtering by name pattern
      final counterMetrics = collection.getMetricsByName(RegExp(r'^counter'));
      expect(counterMetrics.length, equals(2));
      
      // Test aggregate statistics
      final stats = collection.getAggregateStats();
      expect(stats['count'], equals(4.0));
      expect(stats['min'], equals(10.0));
      expect(stats['max'], equals(100000.0)); // TimerMetric value in microseconds
      
      print('MetricCollection filtering and statistical analysis successful');
    });

    test('should integrate typed metrics with PerformanceMonitor', () async {
      print('=== PerformanceMonitor Integration Test ===');
      
      // Test recording different types of metrics
      monitor.recordResourceUsage('memory.heap', 256.0, capacity: 1024.0);
      monitor.incrementCounter('requests.count', 5);
      
      monitor.recordNetworkMetric(
        name: 'api.latency',
        latency: Duration(milliseconds: 200),
        bytes: 1024,
        operation: NetworkOperation.request,
        statusCode: 200,
      );
      
      monitor.recordHistogramMetric(
        name: 'response.distribution',
        samples: [10.0, 20.0, 30.0, 40.0, 50.0],
        buckets: [25.0, 50.0, 100.0],
        unit: 'ms',
      );
      
      monitor.recordCustomMetric(
        name: 'custom.metric',
        value: 42.0,
        type: MetricType.gauge,
        category: 'business',
        unit: 'units',
      );
      
      // Test retrieval
      final memoryMetric = monitor.getTypedMetric('memory.heap');
      expect(memoryMetric, isNotNull);
      expect(memoryMetric!.value, equals(256.0));
      
      final counterMetric = monitor.getTypedMetric('requests.count');
      expect(counterMetric, isNotNull);
      expect(counterMetric!.value, equals(5.0));
      
      // Test filtering by type
      final counters = monitor.getTypedMetricsByType<CounterMetric>();
      expect(counters.length, equals(1));
      
      final resources = monitor.getTypedMetricsByType<ResourceUsageMetric>();
      expect(resources.length, equals(1));
      
      // Test metric collection creation
      final collection = monitor.createMetricCollection('all.metrics');
      expect(collection.metrics.length, greaterThan(0));
      
      final retrievedCollection = monitor.getMetricCollection('all.metrics');
      expect(retrievedCollection, isNotNull);
      expect(retrievedCollection!.name, equals('all.metrics'));
      
      // Test typed metrics summary
      final summary = monitor.getTypedMetricsSummary();
      expect(summary.containsKey('gauge'), isTrue);
      expect(summary.containsKey('counter'), isTrue);
      expect(summary.containsKey('timer'), isTrue);
      expect(summary.containsKey('histogram'), isTrue);
      
      // Test full metrics report includes typed metrics
      final report = monitor.getMetricsReport();
      expect(report.containsKey('typed_metrics'), isTrue);
      expect(report.containsKey('metric_collections'), isTrue);
      
      print('PerformanceMonitor integration test successful');
    });

    test('should handle event publishing for typed metrics', () async {
      print('=== Typed Metrics Event Publishing Test ===');
      
      // Reset the monitor to clean state
      monitor.reset();
      
      // Set up event listener for this test only
      List<PerformanceEvent> receivedEvents = [];
      
      EventSystem.instance.subscribeTyped<PerformanceEvent>((event) {
        // Only capture events from our test metrics
        if (event.metricName == 'isolated.cpu.usage' || event.metricName == 'isolated.errors.count') {
          receivedEvents.add(event);
        }
      });
      
      // Wait for subscription to be active
      await Future.delayed(Duration(milliseconds: 200));
      
      // Record metrics with unique names to isolate this test
      monitor.recordResourceUsage('isolated.cpu.usage', 75.0, capacity: 100.0);
      monitor.incrementCounter('isolated.errors.count', 1);
      
      // Allow events to propagate with increased delay
      await Future.delayed(Duration(milliseconds: 500));
      
      // Verify events were published (should be exactly 2)
      expect(receivedEvents.length, equals(2));
      
      final cpuEvent = receivedEvents.firstWhere((e) => e.metricName == 'isolated.cpu.usage');
      expect(cpuEvent.value, equals(75.0));
      expect(cpuEvent.capacity, equals(100.0));
      expect(cpuEvent.type, equals(MetricType.gauge));
      
      final errorEvent = receivedEvents.firstWhere((e) => e.metricName == 'isolated.errors.count');
      expect(errorEvent.value, equals(1.0));
      expect(errorEvent.type, equals(MetricType.counter));
      
      print('Typed metrics event publishing successful');
    });

    test('should handle resource type and unit detection', () {
      print('=== Resource Type Detection Test ===');
      
      // Test various resource names
      monitor.recordResourceUsage('memory.heap.mb', 512.0);
      monitor.recordResourceUsage('cpu.usage.percent', 85.0);
      monitor.recordResourceUsage('disk.free.bytes', 1024000.0);
      monitor.recordResourceUsage('network.bandwidth.mbps', 100.0);
      monitor.recordResourceUsage('battery.level.percent', 75.0);
      
      final memoryMetric = monitor.getTypedMetric('memory.heap.mb') as ResourceUsageMetric?;
      expect(memoryMetric?.resourceType, equals(ResourceType.memory));
      expect(memoryMetric?.unit, equals('MB'));
      
      final cpuMetric = monitor.getTypedMetric('cpu.usage.percent') as ResourceUsageMetric?;
      expect(cpuMetric?.resourceType, equals(ResourceType.cpu));
      expect(cpuMetric?.unit, equals('%'));
      
      final diskMetric = monitor.getTypedMetric('disk.free.bytes') as ResourceUsageMetric?;
      expect(diskMetric?.resourceType, equals(ResourceType.disk));
      expect(diskMetric?.unit, equals('bytes'));
      
      final networkMetric = monitor.getTypedMetric('network.bandwidth.mbps') as ResourceUsageMetric?;
      expect(networkMetric?.resourceType, equals(ResourceType.network));
      
      final batteryMetric = monitor.getTypedMetric('battery.level.percent') as ResourceUsageMetric?;
      expect(batteryMetric?.resourceType, equals(ResourceType.battery));
      expect(batteryMetric?.unit, equals('%'));
      
      print('Resource type and unit auto-detection successful');
    });

    test('should handle metric collection serialization', () {
      print('=== MetricCollection Serialization Test ===');
      
      final originalMetrics = [
        CounterMetric(name: 'test.counter', value: 42.0),
        ResourceUsageMetric(
          name: 'test.memory',
          value: 256.0,
          capacity: 1024.0,
          resourceType: ResourceType.memory,
        ),
      ];
      
      final originalCollection = MetricCollection(
        name: 'test.collection',
        metrics: originalMetrics,
      );
      
      // Serialize to map
      final map = originalCollection.toMap();
      expect(map['name'], equals('test.collection'));
      expect(map['metrics'], isA<List>());
      expect(map.containsKey('aggregateStats'), isTrue);
      
      // Deserialize from map
      final restoredCollection = MetricCollection.fromMap(map);
      expect(restoredCollection.name, equals(originalCollection.name));
      expect(restoredCollection.metrics.length, equals(originalCollection.metrics.length));
      
      // Verify metric types are preserved
      final counter = restoredCollection.getMetricsByType<CounterMetric>();
      expect(counter.length, equals(1));
      expect(counter.first.name, equals('test.counter'));
      
      final resources = restoredCollection.getMetricsByType<ResourceUsageMetric>();
      expect(resources.length, equals(1));
      expect(resources.first.name, equals('test.memory'));
      
      print('MetricCollection serialization and type preservation successful');
    });
  });
}