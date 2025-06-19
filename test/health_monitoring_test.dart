import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/monitoring/health_monitor.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:async';

void main() {
  group('Health Monitor Tests', () {
    late HealthMonitor healthMonitor;

    setUp(() {
      healthMonitor = HealthMonitor.instance;
      healthMonitor.initialize();
    });

    tearDown(() {
      healthMonitor.dispose();
    });

    group('Component Health Tracking', () {
      test('should track component health status', () {
        // Act
        healthMonitor.updateComponentHealth(
          'test_component',
          MCPHealthStatus.healthy,
          'Component is running normally',
        );

        // Assert
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.containsKey('test_component'), isTrue);
        expect(components['test_component']['status'], equals('healthy'));
        expect(components['test_component']['message'],
            equals('Component is running normally'));
      });

      test('should update existing component health', () {
        // Arrange
        healthMonitor.updateComponentHealth(
          'test_component',
          MCPHealthStatus.healthy,
          'Initial status',
        );

        // Act
        healthMonitor.updateComponentHealth(
          'test_component',
          MCPHealthStatus.degraded,
          'Updated status',
        );

        // Assert
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components['test_component']['status'], equals('degraded'));
        expect(
            components['test_component']['message'], equals('Updated status'));
      });

      test('should handle multiple component tracking', () {
        // Act
        healthMonitor.updateComponentHealth(
            'component1', MCPHealthStatus.healthy, 'Component 1 OK');
        healthMonitor.updateComponentHealth(
            'component2', MCPHealthStatus.degraded, 'Component 2 Warning');
        healthMonitor.updateComponentHealth(
            'component3', MCPHealthStatus.unhealthy, 'Component 3 Error');

        // Assert
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.length, equals(3));
        expect(components['component1']['status'], equals('healthy'));
        expect(components['component2']['status'], equals('degraded'));
        expect(components['component3']['status'], equals('unhealthy'));
      });
    });

    group('Overall Health Assessment', () {
      test('should return healthy when all components are healthy', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'component1', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'component2', MCPHealthStatus.healthy, 'OK');

        // Act
        bool isHealthy = healthMonitor.isHealthy();

        // Assert
        expect(isHealthy, isTrue);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        expect(currentHealth['status'], equals('healthy'));
      });

      test('should return degraded when some components are degraded', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'component1', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'component2', MCPHealthStatus.degraded, 'Warning');

        // Act
        bool isHealthy = healthMonitor.isHealthy();

        // Assert
        expect(isHealthy, isFalse);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        expect(currentHealth['status'], equals('degraded'));
      });

      test('should return unhealthy when any component is unhealthy', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'component1', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'component2', MCPHealthStatus.degraded, 'Warning');
        healthMonitor.updateComponentHealth(
            'component3', MCPHealthStatus.unhealthy, 'Error');

        // Act
        bool isHealthy = healthMonitor.isHealthy();

        // Assert
        expect(isHealthy, isFalse);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        expect(currentHealth['status'], equals('unhealthy'));
      });

      test('should return healthy with no components', () {
        // Act
        bool isHealthy = healthMonitor.isHealthy();

        // Assert
        expect(isHealthy, isTrue);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        expect(currentHealth['status'], equals('healthy'));
      });
    });

    group('Health Event Streaming', () {
      test('should stream health updates', () async {
        // Arrange
        List<MCPHealthCheckResult> capturedResults = [];

        StreamSubscription subscription =
            healthMonitor.healthStream.listen((result) {
          capturedResults.add(result);
        });

        // Act
        healthMonitor.updateComponentHealth(
            'test_component', MCPHealthStatus.healthy, 'Initial');
        healthMonitor.updateComponentHealth(
            'test_component', MCPHealthStatus.degraded, 'Warning');

        // Wait for stream processing
        await Future.delayed(Duration(milliseconds: 100));

        // Assert
        expect(capturedResults.length, greaterThanOrEqualTo(2));
        expect(capturedResults.any((r) => r.status == MCPHealthStatus.healthy),
            isTrue);
        expect(capturedResults.any((r) => r.status == MCPHealthStatus.degraded),
            isTrue);

        // Cleanup
        await subscription.cancel();
      });

      test('should emit health events immediately', () async {
        // Arrange
        List<MCPHealthCheckResult> capturedResults = [];

        healthMonitor.healthStream.listen((result) {
          capturedResults.add(result);
        });

        // Act
        healthMonitor.updateComponentHealth('immediate_component',
            MCPHealthStatus.unhealthy, 'Immediate error');

        // Small delay for async processing
        await Future.delayed(Duration(milliseconds: 50));

        // Assert
        expect(capturedResults.length, greaterThanOrEqualTo(1));
        expect(capturedResults.last.status, equals(MCPHealthStatus.unhealthy));
      });
    });

    group('Component Registration', () {
      test('should register components for monitoring', () {
        // Act
        healthMonitor.registerComponent('registered_component');

        // Assert
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.containsKey('registered_component'), isTrue);
        expect(components['registered_component']['status'], equals('healthy'));
        expect(components['registered_component']['message'],
            equals('Component registered'));
      });

      test('should unregister components', () {
        // Arrange
        healthMonitor.registerComponent('temp_component');

        Map<String, dynamic> beforeHealth = healthMonitor.currentHealth;
        Map<String, dynamic> beforeComponents = beforeHealth['components'];
        expect(beforeComponents.containsKey('temp_component'), isTrue);

        // Act
        healthMonitor.unregisterComponent('temp_component');

        // Assert
        Map<String, dynamic> afterHealth = healthMonitor.currentHealth;
        Map<String, dynamic> afterComponents = afterHealth['components'];
        expect(afterComponents.containsKey('temp_component'), isFalse);
      });

      test('should handle duplicate registration gracefully', () {
        // Act
        healthMonitor.registerComponent('duplicate_component');
        expect(() => healthMonitor.registerComponent('duplicate_component'),
            returnsNormally);

        // Assert - Should still exist
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.containsKey('duplicate_component'), isTrue);
      });
    });

    group('Health Summary', () {
      test('should generate health summary', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'healthy1', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'healthy2', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'degraded1', MCPHealthStatus.degraded, 'Warning');
        healthMonitor.updateComponentHealth(
            'unhealthy1', MCPHealthStatus.unhealthy, 'Error');

        // Act
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> summary = currentHealth['summary'];

        // Assert
        expect(summary['totalComponents'], equals(4));
        expect(summary['healthy'], equals(2));
        expect(summary['degraded'], equals(1));
        expect(summary['unhealthy'], equals(1));
      });
    });

    group('Full Health Check', () {
      test('should perform full health check', () async {
        // Arrange
        healthMonitor.registerComponent('component1');
        healthMonitor.registerComponent('component2');
        healthMonitor.updateComponentHealth(
            'component1', MCPHealthStatus.healthy, 'OK');
        healthMonitor.updateComponentHealth(
            'component2', MCPHealthStatus.degraded, 'Warning');

        // Act
        Map<String, dynamic> healthReport =
            await healthMonitor.performFullHealthCheck();

        // Assert
        expect(healthReport['status'], isNotNull);
        expect(healthReport['components'], isNotNull);
        expect(healthReport['summary'], isNotNull);
        expect(healthReport['timestamp'], isNotNull);
      });
    });

    group('Component History', () {
      test('should track component history', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'history_component', MCPHealthStatus.healthy, 'Initial');

        // Act
        List<ComponentHealth> history =
            healthMonitor.getComponentHistory('history_component');

        // Assert
        expect(history.length, equals(1));
        expect(history.first.componentId, equals('history_component'));
        expect(history.first.status, equals(MCPHealthStatus.healthy));
        expect(history.first.message, equals('Initial'));
      });

      test('should return empty history for non-existent component', () {
        // Act
        List<ComponentHealth> history =
            healthMonitor.getComponentHistory('non_existent');

        // Assert
        expect(history.isEmpty, isTrue);
      });
    });

    group('Error Handling', () {
      test('should handle empty component IDs gracefully', () {
        // Act & Assert - Should not throw
        expect(
            () => healthMonitor.updateComponentHealth(
                '', MCPHealthStatus.healthy, 'Test'),
            returnsNormally);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.containsKey(''), isTrue);
      });

      test('should handle null messages gracefully', () {
        // Act & Assert - Should not throw
        expect(
            () => healthMonitor.updateComponentHealth(
                'test', MCPHealthStatus.healthy, null),
            returnsNormally);

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components['test']['message'], isNull);
      });

      test('should handle rapid updates gracefully', () {
        // Act - Rapid updates
        for (int i = 0; i < 100; i++) {
          healthMonitor.updateComponentHealth(
            'rapid_component',
            i % 2 == 0 ? MCPHealthStatus.healthy : MCPHealthStatus.degraded,
            'Update $i',
          );
        }

        // Assert - Should not crash and should have latest update
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components['rapid_component']['message'], equals('Update 99'));
      });
    });

    group('Resource Management', () {
      test('should clean up resources on dispose', () {
        // Arrange
        healthMonitor.updateComponentHealth(
            'disposable_component', MCPHealthStatus.healthy, 'Test');

        // Act
        healthMonitor.dispose();

        // Assert - Should not throw when trying to use after dispose
        expect(() => healthMonitor.isHealthy(), returnsNormally);
        expect(() => healthMonitor.currentHealth, returnsNormally);
      });
    });

    group('Performance', () {
      test('should handle large numbers of components efficiently', () {
        // Arrange
        Stopwatch stopwatch = Stopwatch()..start();

        // Act - Add many components
        for (int i = 0; i < 1000; i++) {
          healthMonitor.updateComponentHealth(
            'component_$i',
            MCPHealthStatus.healthy,
            'Component $i status',
          );
        }

        bool isHealthy = healthMonitor.isHealthy();
        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        stopwatch.stop();

        // Assert - Should complete quickly (under 500ms for 1000 components)
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(isHealthy, isTrue);
        expect(currentHealth['summary']['totalComponents'], equals(1000));
      });

      test('should efficiently update existing components', () {
        // Arrange - Create initial components
        for (int i = 0; i < 100; i++) {
          healthMonitor.updateComponentHealth(
              'perf_component_$i', MCPHealthStatus.healthy, 'Initial');
        }

        Stopwatch stopwatch = Stopwatch()..start();

        // Act - Update all components
        for (int i = 0; i < 100; i++) {
          healthMonitor.updateComponentHealth(
              'perf_component_$i', MCPHealthStatus.degraded, 'Updated');
        }

        stopwatch.stop();

        // Assert - Updates should be fast
        expect(stopwatch.elapsedMilliseconds, lessThan(50));

        Map<String, dynamic> currentHealth = healthMonitor.currentHealth;
        Map<String, dynamic> components = currentHealth['components'];
        expect(components.length, equals(100));

        // Check that all components were updated
        bool allUpdated = components.values.every((component) =>
            component['status'] == 'degraded' &&
            component['message'] == 'Updated');
        expect(allUpdated, isTrue);
      });
    });
  });
}
