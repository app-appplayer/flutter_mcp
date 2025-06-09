# Performance Monitoring Guide

Flutter MCP provides comprehensive performance monitoring capabilities to help you optimize your application's performance and detect issues early. This guide covers all aspects of the performance monitoring system.

## Overview

The enhanced performance monitoring system includes:

- **Real-time Metrics Collection**: Memory, CPU, network, and custom metrics
- **Metric Aggregation**: Statistical analysis with configurable time windows
- **Anomaly Detection**: Automatic detection of performance issues
- **Threshold Monitoring**: Configurable alerts for performance violations
- **Performance Optimization**: Automatic resource management and cleanup
- **Detailed Reporting**: Comprehensive performance analytics

## Getting Started

### Basic Setup

```dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:logging/logging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Flutter MCP with performance monitoring
  await FlutterMCP.instance.init(MCPConfig(
    appName: 'Performance Demo',
    appVersion: '1.0.0',
    enablePerformanceMonitoring: true, // Enable performance monitoring
    highMemoryThresholdMB: 512, // Memory threshold for cleanup
    enableMetricsExport: true, // Enable metrics export
  ));
  
  runApp(MyApp());
}
```

### Advanced Configuration

```dart
import 'package:flutter_mcp/src/performance/enhanced_performance_monitor.dart';

class PerformanceConfigExample {
  void setupAdvancedMonitoring() {
    final monitor = EnhancedPerformanceMonitor.instance;
    
    // Configure metric aggregation
    monitor.configureAggregation('memory.usage', AggregationConfig(
      windowSize: Duration(minutes: 5),
      aggregationType: AggregationType.average,
      retentionPeriod: Duration(hours: 24),
    ));
    
    monitor.configureAggregation('api.response_time', AggregationConfig(
      windowSize: Duration(minutes: 1),
      aggregationType: AggregationType.percentile,
      percentile: 95, // P95 response time
      retentionPeriod: Duration(hours: 12),
    ));
    
    // Configure anomaly detection
    monitor.configureAnomalyDetection('memory.usage', AnomalyConfig(
      enabled: true,
      sensitivity: 0.8, // Higher sensitivity
      minimumSamples: 10,
      deviationThreshold: 2.0, // 2 standard deviations
    ));
    
    // Set up threshold monitoring
    monitor.setThreshold('memory.usage', ThresholdConfig(
      warningLevel: 400, // 400MB warning
      criticalLevel: 600, // 600MB critical
      checkInterval: Duration(seconds: 30),
      alertCallback: (violation) {
        _handlePerformanceViolation(violation);
      },
    ));
    
    // Configure custom metrics
    monitor.registerCustomMetric('user.interactions', MetricConfig(
      type: MetricType.counter,
      unit: 'count',
      description: 'Number of user interactions',
      aggregationEnabled: true,
    ));
  }
  
  void _handlePerformanceViolation(ThresholdViolation violation) {
    final logger = Logger('flutter_mcp.performance');
    logger.warning('Performance threshold violated: ${violation.metricName}');
    logger.warning('Current: ${violation.currentValue}, Threshold: ${violation.threshold}');
    
    // Take corrective action
    if (violation.metricName == 'memory.usage' && violation.level == ViolationLevel.critical) {
      _performEmergencyCleanup();
    }
  }
  
  void _performEmergencyCleanup() {
    FlutterMCP.instance.performMemoryCleanup();
  }
}
```

## Metric Collection

### Built-in Metrics

Flutter MCP automatically collects these metrics:

```dart
class BuiltInMetricsExample {
  void demonstrateBuiltInMetrics() {
    final monitor = EnhancedPerformanceMonitor.instance;
    
    // Memory metrics (automatically collected)
    // - memory.usage: Current memory usage in MB
    // - memory.peak: Peak memory usage since start
    // - memory.available: Available memory
    
    // Performance metrics (automatically collected)
    // - cpu.usage: CPU usage percentage
    // - frame.rate: Current frame rate (Flutter apps)
    // - frame.build_time: Frame build duration
    
    // Network metrics (automatically collected)
    // - network.requests: Number of network requests
    // - network.bytes_sent: Bytes sent over network
    // - network.bytes_received: Bytes received
    
    // Get current metric values
    double? memoryUsage = monitor.getCurrentValue('memory.usage');
    double? cpuUsage = monitor.getCurrentValue('cpu.usage');
    
    final logger = Logger('flutter_mcp.metrics');
    logger.info('Memory Usage: ${memoryUsage}MB');
    logger.info('CPU Usage: ${cpuUsage}%');
  }
}
```

### Custom Metrics

```dart
class CustomMetricsExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  final Logger _logger = Logger('flutter_mcp.custom_metrics');
  
  void setupCustomMetrics() {
    // Register business-specific metrics
    _monitor.registerCustomMetric('user.sessions', MetricConfig(
      type: MetricType.gauge,
      unit: 'count',
      description: 'Number of active user sessions',
    ));
    
    _monitor.registerCustomMetric('data.processing_time', MetricConfig(
      type: MetricType.timer,
      unit: 'milliseconds',
      description: 'Time taken to process data',
      aggregationEnabled: true,
    ));
    
    _monitor.registerCustomMetric('errors.rate', MetricConfig(
      type: MetricType.counter,
      unit: 'errors/minute',
      description: 'Error rate per minute',
    ));
  }
  
  void recordCustomMetrics() {
    // Record gauge metric (current value)
    _monitor.recordMetric('user.sessions', 15.0);
    
    // Record timer metric (duration)
    _monitor.startTimer('data.processing_time');
    _processData();
    _monitor.stopTimer('data.processing_time');
    
    // Record counter metric (increment)
    _monitor.incrementCounter('errors.rate');
    
    // Record histogram metric (value distribution)
    _monitor.recordMetric('api.response_size', 2048.0);
  }
  
  void _processData() {
    // Simulate data processing
    Future.delayed(Duration(milliseconds: 150));
  }
  
  void monitorUserInteractions() {
    // Monitor button clicks
    _monitor.incrementCounter('user.button_clicks');
    
    // Monitor screen navigation
    _monitor.recordMetric('user.screen_transitions', 1.0);
    
    // Monitor feature usage
    _monitor.incrementCounter('feature.search_usage');
    _monitor.incrementCounter('feature.export_usage');
  }
}
```

## Metric Aggregation

### Statistical Analysis

```dart
class AggregationExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  
  void setupAggregation() {
    // Average aggregation for smooth trends
    _monitor.configureAggregation('memory.usage', AggregationConfig(
      windowSize: Duration(minutes: 5),
      aggregationType: AggregationType.average,
      retentionPeriod: Duration(hours: 24),
    ));
    
    // Maximum aggregation for peak tracking
    _monitor.configureAggregation('memory.usage', AggregationConfig(
      windowSize: Duration(minutes: 15),
      aggregationType: AggregationType.maximum,
      retentionPeriod: Duration(days: 7),
    ));
    
    // Percentile aggregation for SLA monitoring
    _monitor.configureAggregation('api.response_time', AggregationConfig(
      windowSize: Duration(minutes: 1),
      aggregationType: AggregationType.percentile,
      percentile: 95, // P95
      retentionPeriod: Duration(hours: 12),
    ));
    
    // Sum aggregation for total counts
    _monitor.configureAggregation('user.interactions', AggregationConfig(
      windowSize: Duration(hours: 1),
      aggregationType: AggregationType.sum,
      retentionPeriod: Duration(days: 30),
    ));
  }
  
  Future<void> analyzePerformanceTrends() async {
    // Get aggregated data for analysis
    Map<String, dynamic> memoryTrends = await _monitor.getAggregatedData(
      'memory.usage',
      startTime: DateTime.now().subtract(Duration(hours: 6)),
      endTime: DateTime.now(),
    );
    
    List<AggregatedDataPoint> dataPoints = memoryTrends['dataPoints'];
    
    // Analyze trends
    double avgMemory = dataPoints
        .map((point) => point.value)
        .reduce((a, b) => a + b) / dataPoints.length;
    
    double maxMemory = dataPoints
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    
    final logger = Logger('flutter_mcp.analysis');
    logger.info('Average Memory (6h): ${avgMemory.toStringAsFixed(2)}MB');
    logger.info('Peak Memory (6h): ${maxMemory.toStringAsFixed(2)}MB');
    
    // Check for concerning trends
    if (avgMemory > 400) {
      logger.warning('High average memory usage detected');
    }
    
    if (maxMemory > 600) {
      logger.severe('Critical memory usage detected');
    }
  }
}
```

### Real-time Aggregation

```dart
class RealTimeAggregationExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  late StreamSubscription _subscription;
  
  void startRealTimeMonitoring() {
    // Subscribe to real-time aggregated data
    _subscription = _monitor.getAggregatedDataStream(
      'memory.usage',
      windowSize: Duration(minutes: 1),
    ).listen((aggregatedData) {
      _handleRealTimeData(aggregatedData);
    });
  }
  
  void _handleRealTimeData(AggregatedDataPoint data) {
    final logger = Logger('flutter_mcp.realtime');
    logger.info('Real-time Memory: ${data.value.toStringAsFixed(2)}MB at ${data.timestamp}');
    
    // Real-time alerting
    if (data.value > 500) {
      _triggerMemoryAlert(data.value);
    }
    
    // Update UI with real-time data
    _updatePerformanceUI(data);
  }
  
  void _triggerMemoryAlert(double memoryUsage) {
    // Trigger immediate alert for high memory usage
    FlutterMCP.instance.showNotification(
      title: 'High Memory Usage',
      body: 'Memory usage is ${memoryUsage.toStringAsFixed(0)}MB',
    );
  }
  
  void _updatePerformanceUI(AggregatedDataPoint data) {
    // Update performance dashboard UI
    // Implementation depends on your UI framework
  }
  
  void stopRealTimeMonitoring() {
    _subscription.cancel();
  }
}
```

## Anomaly Detection

### Automatic Anomaly Detection

```dart
class AnomalyDetectionExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  
  void setupAnomalyDetection() {
    // Configure anomaly detection for memory usage
    _monitor.configureAnomalyDetection('memory.usage', AnomalyConfig(
      enabled: true,
      sensitivity: 0.7, // 70% sensitivity
      minimumSamples: 20,
      deviationThreshold: 2.5, // 2.5 standard deviations
      consecutiveAnomalies: 3, // Require 3 consecutive anomalies
    ));
    
    // Configure anomaly detection for response times
    _monitor.configureAnomalyDetection('api.response_time', AnomalyConfig(
      enabled: true,
      sensitivity: 0.8, // High sensitivity for response times
      minimumSamples: 10,
      deviationThreshold: 2.0,
      consecutiveAnomalies: 2,
    ));
    
    // Configure anomaly detection for error rates
    _monitor.configureAnomalyDetection('errors.rate', AnomalyConfig(
      enabled: true,
      sensitivity: 0.9, // Very high sensitivity for errors
      minimumSamples: 5,
      deviationThreshold: 1.5,
      consecutiveAnomalies: 1, // Single anomaly triggers alert
    ));
  }
  
  void handleAnomalyDetection() {
    // Listen for anomaly events
    EnhancedTypedEventSystem.instance.listen<PerformanceEvent>((event) {
      if (event.type == MetricType.gauge && event.metricName.contains('anomaly')) {
        _handleAnomaly(event);
      }
    });
  }
  
  void _handleAnomaly(PerformanceEvent event) {
    final logger = Logger('flutter_mcp.anomaly');
    logger.warning('Anomaly detected: ${event.metricName}');
    logger.warning('Value: ${event.value}, Expected range: ${event.capacity}');
    
    // Take appropriate action based on metric
    switch (event.metricName) {
      case 'memory.usage':
        _handleMemoryAnomaly(event.value);
        break;
      case 'api.response_time':
        _handleResponseTimeAnomaly(event.value);
        break;
      case 'errors.rate':
        _handleErrorRateAnomaly(event.value);
        break;
    }
  }
  
  void _handleMemoryAnomaly(double memoryUsage) {
    if (memoryUsage > 600) {
      // Emergency memory cleanup
      FlutterMCP.instance.performMemoryCleanup();
      _notifyDevelopmentTeam('Critical memory anomaly detected');
    } else {
      // Gradual cleanup
      _scheduleMemoryCleanup();
    }
  }
  
  void _handleResponseTimeAnomaly(double responseTime) {
    if (responseTime > 5000) { // 5 seconds
      // Switch to fallback mode
      _enableFallbackMode();
      _notifyDevelopmentTeam('Critical response time anomaly detected');
    }
  }
  
  void _handleErrorRateAnomaly(double errorRate) {
    if (errorRate > 10) { // More than 10 errors per minute
      // Enable error recovery mode
      _enableErrorRecoveryMode();
      _notifyDevelopmentTeam('High error rate anomaly detected');
    }
  }
  
  void _scheduleMemoryCleanup() {
    Timer(Duration(seconds: 30), () {
      FlutterMCP.instance.performMemoryCleanup();
    });
  }
  
  void _enableFallbackMode() {
    // Implement fallback mode for poor network conditions
  }
  
  void _enableErrorRecoveryMode() {
    // Implement error recovery strategies
  }
  
  void _notifyDevelopmentTeam(String message) {
    // Send alert to development team
    final logger = Logger('flutter_mcp.alerts');
    logger.severe('DEVELOPMENT ALERT: $message');
  }
}
```

## Threshold Monitoring

### Configurable Thresholds

```dart
class ThresholdMonitoringExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  
  void setupThresholds() {
    // Memory usage thresholds
    _monitor.setThreshold('memory.usage', ThresholdConfig(
      warningLevel: 300, // 300MB warning
      criticalLevel: 500, // 500MB critical
      checkInterval: Duration(seconds: 15),
      alertCallback: (violation) => _handleMemoryViolation(violation),
    ));
    
    // CPU usage thresholds
    _monitor.setThreshold('cpu.usage', ThresholdConfig(
      warningLevel: 70, // 70% CPU warning
      criticalLevel: 90, // 90% CPU critical
      checkInterval: Duration(seconds: 10),
      alertCallback: (violation) => _handleCPUViolation(violation),
    ));
    
    // Frame rate thresholds (for Flutter UI performance)
    _monitor.setThreshold('frame.rate', ThresholdConfig(
      warningLevel: 45, // Below 45 FPS warning
      criticalLevel: 30, // Below 30 FPS critical
      checkInterval: Duration(seconds: 5),
      alertCallback: (violation) => _handleFrameRateViolation(violation),
      isMinimumThreshold: true, // Alert when below threshold
    ));
    
    // API response time thresholds
    _monitor.setThreshold('api.response_time', ThresholdConfig(
      warningLevel: 2000, // 2 seconds warning
      criticalLevel: 5000, // 5 seconds critical
      checkInterval: Duration(seconds: 20),
      alertCallback: (violation) => _handleResponseTimeViolation(violation),
    ));
  }
  
  void _handleMemoryViolation(ThresholdViolation violation) {
    final logger = Logger('flutter_mcp.memory_threshold');
    logger.warning('Memory threshold violated: ${violation.currentValue}MB > ${violation.threshold}MB');
    
    if (violation.level == ViolationLevel.critical) {
      // Immediate action for critical memory usage
      FlutterMCP.instance.performMemoryCleanup();
      _showUserNotification('High memory usage detected. Optimizing...');
    } else {
      // Gradual action for warning level
      _scheduleGradualCleanup();
    }
  }
  
  void _handleCPUViolation(ThresholdViolation violation) {
    final logger = Logger('flutter_mcp.cpu_threshold');
    logger.warning('CPU threshold violated: ${violation.currentValue}% > ${violation.threshold}%');
    
    if (violation.level == ViolationLevel.critical) {
      // Reduce background processing
      _throttleBackgroundTasks();
    }
  }
  
  void _handleFrameRateViolation(ThresholdViolation violation) {
    final logger = Logger('flutter_mcp.frame_rate_threshold');
    logger.warning('Frame rate below threshold: ${violation.currentValue} FPS < ${violation.threshold} FPS');
    
    if (violation.level == ViolationLevel.critical) {
      // Reduce UI complexity
      _enablePerformanceMode();
    }
  }
  
  void _handleResponseTimeViolation(ThresholdViolation violation) {
    final logger = Logger('flutter_mcp.response_time_threshold');
    logger.warning('Response time threshold violated: ${violation.currentValue}ms > ${violation.threshold}ms');
    
    if (violation.level == ViolationLevel.critical) {
      // Switch to offline mode or cached data
      _enableOfflineMode();
    }
  }
  
  void _scheduleGradualCleanup() {
    Timer(Duration(minutes: 1), () {
      FlutterMCP.instance.performMemoryCleanup();
    });
  }
  
  void _throttleBackgroundTasks() {
    // Reduce frequency of background operations
  }
  
  void _enablePerformanceMode() {
    // Reduce animation complexity, disable non-essential UI features
  }
  
  void _enableOfflineMode() {
    // Switch to cached data, queue operations for later
  }
  
  void _showUserNotification(String message) {
    FlutterMCP.instance.showNotification(
      title: 'Performance Optimization',
      body: message,
    );
  }
}
```

## Performance Reporting

### Comprehensive Reports

```dart
class PerformanceReportingExample {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  
  Future<Map<String, dynamic>> generatePerformanceReport() async {
    // Get system status from Flutter MCP
    Map<String, dynamic> systemStatus = FlutterMCP.instance.getSystemStatus();
    
    // Get detailed performance metrics
    Map<String, dynamic> performanceMetrics = systemStatus['performanceMetrics'] ?? {};
    
    // Generate custom analysis
    Map<String, dynamic> analysis = await _generateAnalysis();
    
    // Combine into comprehensive report
    return {
      'reportGeneratedAt': DateTime.now().toIso8601String(),
      'systemStatus': systemStatus,
      'performanceMetrics': performanceMetrics,
      'analysis': analysis,
      'recommendations': _generateRecommendations(analysis),
      'trends': await _generateTrends(),
      'alerts': _getRecentAlerts(),
    };
  }
  
  Future<Map<String, dynamic>> _generateAnalysis() async {
    final now = DateTime.now();
    final last24h = now.subtract(Duration(hours: 24));
    
    // Memory analysis
    Map<String, dynamic> memoryAnalysis = await _analyzeMemoryUsage(last24h, now);
    
    // Performance analysis
    Map<String, dynamic> performanceAnalysis = await _analyzePerformance(last24h, now);
    
    // Error analysis
    Map<String, dynamic> errorAnalysis = await _analyzeErrors(last24h, now);
    
    return {
      'memory': memoryAnalysis,
      'performance': performanceAnalysis,
      'errors': errorAnalysis,
      'overall_health_score': _calculateHealthScore(memoryAnalysis, performanceAnalysis, errorAnalysis),
    };
  }
  
  Future<Map<String, dynamic>> _analyzeMemoryUsage(DateTime start, DateTime end) async {
    Map<String, dynamic> memoryData = await _monitor.getAggregatedData(
      'memory.usage',
      startTime: start,
      endTime: end,
    );
    
    List<AggregatedDataPoint> dataPoints = memoryData['dataPoints'] ?? [];
    
    if (dataPoints.isEmpty) {
      return {'status': 'no_data'};
    }
    
    double avgMemory = dataPoints
        .map((point) => point.value)
        .reduce((a, b) => a + b) / dataPoints.length;
    
    double maxMemory = dataPoints
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    
    double minMemory = dataPoints
        .map((point) => point.value)
        .reduce((a, b) => a < b ? a : b);
    
    return {
      'average_mb': avgMemory,
      'peak_mb': maxMemory,
      'minimum_mb': minMemory,
      'variance': _calculateVariance(dataPoints.map((p) => p.value).toList()),
      'threshold_violations': _countThresholdViolations(dataPoints, 400), // 400MB threshold
      'status': _getMemoryStatus(avgMemory, maxMemory),
    };
  }
  
  Future<Map<String, dynamic>> _analyzePerformance(DateTime start, DateTime end) async {
    // Analyze frame rate, response times, etc.
    return {
      'frame_rate': await _analyzeFrameRate(start, end),
      'response_times': await _analyzeResponseTimes(start, end),
      'cpu_usage': await _analyzeCPUUsage(start, end),
    };
  }
  
  Future<Map<String, dynamic>> _analyzeErrors(DateTime start, DateTime end) async {
    // Analyze error rates and patterns
    return {
      'total_errors': await _countErrors(start, end),
      'error_rate_per_hour': await _calculateErrorRate(start, end),
      'error_categories': await _categorizeErrors(start, end),
    };
  }
  
  double _calculateHealthScore(
    Map<String, dynamic> memory,
    Map<String, dynamic> performance,
    Map<String, dynamic> errors,
  ) {
    double score = 100.0;
    
    // Deduct points based on memory issues
    if (memory['status'] == 'critical') score -= 30;
    else if (memory['status'] == 'warning') score -= 15;
    
    // Deduct points based on performance issues
    if (performance['frame_rate']?['status'] == 'poor') score -= 20;
    if (performance['response_times']?['status'] == 'slow') score -= 15;
    
    // Deduct points based on errors
    double errorRate = errors['error_rate_per_hour'] ?? 0;
    if (errorRate > 10) score -= 25;
    else if (errorRate > 5) score -= 10;
    
    return math.max(0, score);
  }
  
  List<String> _generateRecommendations(Map<String, dynamic> analysis) {
    List<String> recommendations = [];
    
    // Memory recommendations
    Map<String, dynamic> memory = analysis['memory'] ?? {};
    if (memory['status'] == 'critical') {
      recommendations.add('Implement aggressive memory cleanup strategies');
      recommendations.add('Review memory leaks in image caching and data structures');
    } else if (memory['status'] == 'warning') {
      recommendations.add('Consider implementing lazy loading for large datasets');
      recommendations.add('Optimize image compression and caching');
    }
    
    // Performance recommendations
    Map<String, dynamic> performance = analysis['performance'] ?? {};
    if (performance['frame_rate']?['status'] == 'poor') {
      recommendations.add('Optimize widget rebuilds using const constructors');
      recommendations.add('Consider using RepaintBoundary for complex widgets');
    }
    
    // Error recommendations
    double errorRate = analysis['errors']?['error_rate_per_hour'] ?? 0;
    if (errorRate > 5) {
      recommendations.add('Implement better error handling and retry mechanisms');
      recommendations.add('Review network timeout configurations');
    }
    
    // General recommendations
    double healthScore = analysis['overall_health_score'] ?? 100;
    if (healthScore < 70) {
      recommendations.add('Consider enabling performance profiling in production');
      recommendations.add('Implement circuit breaker pattern for external services');
    }
    
    return recommendations;
  }
  
  Future<Map<String, dynamic>> _generateTrends() async {
    // Generate 7-day trends
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(Duration(days: 7));
    
    return {
      'memory_trend': await _getMetricTrend('memory.usage', sevenDaysAgo, now),
      'performance_trend': await _getMetricTrend('frame.rate', sevenDaysAgo, now),
      'error_trend': await _getMetricTrend('errors.rate', sevenDaysAgo, now),
    };
  }
  
  Future<String> _getMetricTrend(String metricName, DateTime start, DateTime end) async {
    Map<String, dynamic> data = await _monitor.getAggregatedData(
      metricName,
      startTime: start,
      endTime: end,
    );
    
    List<AggregatedDataPoint> dataPoints = data['dataPoints'] ?? [];
    if (dataPoints.length < 2) return 'insufficient_data';
    
    double firstValue = dataPoints.first.value;
    double lastValue = dataPoints.last.value;
    
    double changePercent = ((lastValue - firstValue) / firstValue) * 100;
    
    if (changePercent > 10) return 'increasing';
    if (changePercent < -10) return 'decreasing';
    return 'stable';
  }
  
  List<Map<String, dynamic>> _getRecentAlerts() {
    // Get recent performance alerts
    return [
      // Implementation would fetch from alert storage
    ];
  }
  
  // Helper methods
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0;
    double mean = values.reduce((a, b) => a + b) / values.length;
    double sumSquaredDiffs = values
        .map((value) => math.pow(value - mean, 2))
        .reduce((a, b) => a + b);
    return sumSquaredDiffs / values.length;
  }
  
  int _countThresholdViolations(List<AggregatedDataPoint> dataPoints, double threshold) {
    return dataPoints.where((point) => point.value > threshold).length;
  }
  
  String _getMemoryStatus(double avgMemory, double maxMemory) {
    if (maxMemory > 600 || avgMemory > 400) return 'critical';
    if (maxMemory > 400 || avgMemory > 300) return 'warning';
    return 'good';
  }
  
  // Additional analysis methods would be implemented here
  Future<Map<String, dynamic>> _analyzeFrameRate(DateTime start, DateTime end) async {
    // Implementation for frame rate analysis
    return {'status': 'good', 'average_fps': 60.0};
  }
  
  Future<Map<String, dynamic>> _analyzeResponseTimes(DateTime start, DateTime end) async {
    // Implementation for response time analysis
    return {'status': 'good', 'average_ms': 150.0};
  }
  
  Future<Map<String, dynamic>> _analyzeCPUUsage(DateTime start, DateTime end) async {
    // Implementation for CPU usage analysis
    return {'status': 'good', 'average_percent': 25.0};
  }
  
  Future<int> _countErrors(DateTime start, DateTime end) async {
    // Implementation for error counting
    return 5;
  }
  
  Future<double> _calculateErrorRate(DateTime start, DateTime end) async {
    // Implementation for error rate calculation
    return 2.5;
  }
  
  Future<Map<String, int>> _categorizeErrors(DateTime start, DateTime end) async {
    // Implementation for error categorization
    return {'network': 3, 'validation': 1, 'system': 1};
  }
}
```

## Integration with UI

### Performance Dashboard Widget

```dart
class PerformanceDashboard extends StatefulWidget {
  @override
  _PerformanceDashboardState createState() => _PerformanceDashboardState();
}

class _PerformanceDashboardState extends State<PerformanceDashboard> {
  final EnhancedPerformanceMonitor _monitor = EnhancedPerformanceMonitor.instance;
  late StreamSubscription _subscription;
  
  double _memoryUsage = 0;
  double _cpuUsage = 0;
  double _frameRate = 60;
  List<ThresholdViolation> _recentViolations = [];
  
  @override
  void initState() {
    super.initState();
    _startRealTimeMonitoring();
  }
  
  void _startRealTimeMonitoring() {
    // Subscribe to real-time metrics
    _subscription = Stream.periodic(Duration(seconds: 2), (_) {
      return {
        'memory': _monitor.getCurrentValue('memory.usage') ?? 0,
        'cpu': _monitor.getCurrentValue('cpu.usage') ?? 0,
        'frameRate': _monitor.getCurrentValue('frame.rate') ?? 60,
      };
    }).listen((metrics) {
      setState(() {
        _memoryUsage = metrics['memory']!;
        _cpuUsage = metrics['cpu']!;
        _frameRate = metrics['frameRate']!;
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance Monitor', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 16),
            
            // Memory Usage
            _buildMetricRow('Memory Usage', '${_memoryUsage.toStringAsFixed(1)} MB', 
                _getMemoryColor(_memoryUsage)),
            
            // CPU Usage
            _buildMetricRow('CPU Usage', '${_cpuUsage.toStringAsFixed(1)}%', 
                _getCPUColor(_cpuUsage)),
            
            // Frame Rate
            _buildMetricRow('Frame Rate', '${_frameRate.toStringAsFixed(1)} FPS', 
                _getFrameRateColor(_frameRate)),
            
            SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                ElevatedButton(
                  onPressed: _performCleanup,
                  child: Text('Clean Up'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _generateReport,
                  child: Text('Generate Report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  Color _getMemoryColor(double memory) {
    if (memory > 500) return Colors.red;
    if (memory > 300) return Colors.orange;
    return Colors.green;
  }
  
  Color _getCPUColor(double cpu) {
    if (cpu > 80) return Colors.red;
    if (cpu > 60) return Colors.orange;
    return Colors.green;
  }
  
  Color _getFrameRateColor(double frameRate) {
    if (frameRate < 30) return Colors.red;
    if (frameRate < 45) return Colors.orange;
    return Colors.green;
  }
  
  void _performCleanup() {
    FlutterMCP.instance.performMemoryCleanup();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Memory cleanup performed')),
    );
  }
  
  void _generateReport() {
    // Navigate to detailed report screen
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PerformanceReportScreen()),
    );
  }
  
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
```

This comprehensive performance monitoring guide demonstrates:

1. **Setup and Configuration**: Complete initialization and configuration
2. **Metric Collection**: Built-in and custom metrics
3. **Real-time Monitoring**: Live performance tracking
4. **Aggregation**: Statistical analysis and trends
5. **Anomaly Detection**: Automatic issue detection
6. **Threshold Monitoring**: Configurable alerts
7. **Reporting**: Comprehensive performance reports
8. **UI Integration**: Performance dashboard widgets
9. **Optimization**: Automatic performance improvements
10. **Best Practices**: Production-ready monitoring strategies

The performance monitoring system provides deep insights into your application's behavior and helps maintain optimal performance across all platforms.