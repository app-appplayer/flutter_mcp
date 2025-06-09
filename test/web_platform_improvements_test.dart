import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/web/web_platform_improvements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Web Platform Improvements Tests', () {
    late WebPlatformImprovements webPlatform;

    setUp(() {
      webPlatform = WebPlatformImprovements.instance;
    });

    test('Should create singleton instance', () {
      final instance1 = WebPlatformImprovements.instance;
      final instance2 = WebPlatformImprovements.instance;
      
      expect(identical(instance1, instance2), isTrue);
    });

    test('Should provide platform status', () {
      final status = webPlatform.getPlatformStatus();
      
      expect(status, isA<Map<String, dynamic>>());
      expect(status.containsKey('capabilities'), isTrue);
      expect(status.containsKey('storage'), isTrue);
      expect(status.containsKey('visibility'), isTrue);
      expect(status.containsKey('connection'), isTrue);
      expect(status.containsKey('performance'), isTrue);
    });

    test('Should track visibility state', () {
      expect(webPlatform.isVisible, isA<bool>());
    });

    test('Should track connection state', () {
      expect(webPlatform.isOnline, isA<bool>());
      expect(webPlatform.connectionType, isA<String>());
    });

    test('Should provide storage usage percentage', () {
      final usagePercent = webPlatform.storageUsagePercent;
      expect(usagePercent, isA<double>());
      expect(usagePercent, greaterThanOrEqualTo(0));
      expect(usagePercent, lessThanOrEqualTo(100));
    });

    test('Should manage performance metrics', () {
      final initialMetrics = webPlatform.getPerformanceMetrics();
      expect(initialMetrics, isA<List<Map<String, dynamic>>>());
      
      webPlatform.clearPerformanceMetrics();
      final clearedMetrics = webPlatform.getPerformanceMetrics();
      expect(clearedMetrics, isEmpty);
    });

    test('Should provide visibility change stream', () {
      final stream = webPlatform.onVisibilityChange;
      expect(stream, isA<Stream<bool>>());
    });

    test('Should provide connection change stream', () {
      final stream = webPlatform.onConnectionChange;
      expect(stream, isA<Stream<Map<String, dynamic>>>());
    });

    test('Should handle dispose gracefully', () {
      expect(() => webPlatform.dispose(), returnsNormally);
    });
  });

  group('Web Platform Capabilities', () {
    test('Should detect capabilities correctly', () {
      final webPlatform = WebPlatformImprovements.instance;
      final status = webPlatform.getPlatformStatus();
      final capabilities = status['capabilities'] as Map<String, dynamic>;
      
      // All capabilities should be boolean values
      for (final capability in capabilities.values) {
        expect(capability, isA<bool>());
      }
      
      // Should have expected capability keys
      expect(capabilities.containsKey('storageQuota'), isTrue);
      expect(capabilities.containsKey('performanceObserver'), isTrue);
      expect(capabilities.containsKey('navigationTiming'), isTrue);
      expect(capabilities.containsKey('visibilityAPI'), isTrue);
      expect(capabilities.containsKey('connectionAPI'), isTrue);
    });

    test('Should provide storage information', () {
      final webPlatform = WebPlatformImprovements.instance;
      final status = webPlatform.getPlatformStatus();
      final storage = status['storage'] as Map<String, dynamic>;
      
      expect(storage.containsKey('quota'), isTrue);
      expect(storage.containsKey('usage'), isTrue);
      expect(storage.containsKey('available'), isTrue);
      expect(storage.containsKey('quotaFormatted'), isTrue);
      expect(storage.containsKey('usageFormatted'), isTrue);
      expect(storage.containsKey('usagePercent'), isTrue);
      
      expect(storage['quota'], isA<int>());
      expect(storage['usage'], isA<int>());
      expect(storage['available'], isA<int>());
      expect(storage['quotaFormatted'], isA<String>());
      expect(storage['usageFormatted'], isA<String>());
      expect(storage['usagePercent'], isA<double>());
    });

    test('Should format bytes correctly', () {
      final webPlatform = WebPlatformImprovements.instance;
      final status = webPlatform.getPlatformStatus();
      final storage = status['storage'] as Map<String, dynamic>;
      
      final quotaFormatted = storage['quotaFormatted'] as String;
      final usageFormatted = storage['usageFormatted'] as String;
      
      // Should contain size units
      final validUnits = ['B', 'KB', 'MB', 'GB'];
      final hasValidQuotaUnit = validUnits.any((unit) => quotaFormatted.contains(unit));
      final hasValidUsageUnit = validUnits.any((unit) => usageFormatted.contains(unit));
      
      expect(hasValidQuotaUnit, isTrue);
      expect(hasValidUsageUnit, isTrue);
    });
  });

  group('Performance Metrics', () {
    test('Should limit performance metrics collection', () {
      final webPlatform = WebPlatformImprovements.instance;
      
      // Clear existing metrics
      webPlatform.clearPerformanceMetrics();
      
      // Get limited metrics
      final limitedMetrics = webPlatform.getPerformanceMetrics(limit: 5);
      expect(limitedMetrics.length, lessThanOrEqualTo(5));
    });

    test('Should provide performance status', () {
      final webPlatform = WebPlatformImprovements.instance;
      final status = webPlatform.getPlatformStatus();
      final performance = status['performance'] as Map<String, dynamic>;
      
      expect(performance.containsKey('metricsCount'), isTrue);
      expect(performance.containsKey('observerSupported'), isTrue);
      
      expect(performance['metricsCount'], isA<int>());
      expect(performance['observerSupported'], isA<bool>());
    });
  });
}