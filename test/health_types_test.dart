import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/types/health_types.dart';

void main() {
  group('MCPHealthStatus', () {
    test('has 3 levels', () {
      expect(MCPHealthStatus.values, hasLength(3));
      expect(MCPHealthStatus.healthy.name, 'healthy');
      expect(MCPHealthStatus.degraded.name, 'degraded');
      expect(MCPHealthStatus.unhealthy.name, 'unhealthy');
    });
  });

  group('MCPHealthCheckResult', () {
    test('uses provided timestamp', () {
      final t = DateTime(2026, 5, 1);
      final r = MCPHealthCheckResult(
        status: MCPHealthStatus.healthy,
        timestamp: t,
      );
      expect(r.timestamp, t);
    });

    test('defaults timestamp to now', () {
      final before = DateTime.now();
      final r = MCPHealthCheckResult(status: MCPHealthStatus.degraded);
      final after = DateTime.now();
      expect(r.timestamp.isBefore(before), isFalse);
      expect(r.timestamp.isAfter(after), isFalse);
    });

    test('toJson serializes all fields', () {
      final t = DateTime(2026, 5, 1);
      final r = MCPHealthCheckResult(
        status: MCPHealthStatus.unhealthy,
        message: 'broken',
        details: {'reason': 'x'},
        timestamp: t,
      );
      expect(r.toJson(), {
        'status': 'unhealthy',
        'message': 'broken',
        'details': {'reason': 'x'},
        'timestamp': t.toIso8601String(),
      });
    });

    test('fromJson roundtrip', () {
      final t = DateTime(2026);
      final original = MCPHealthCheckResult(
        status: MCPHealthStatus.degraded,
        message: 'm',
        details: {'a': 1},
        timestamp: t,
      );
      final restored = MCPHealthCheckResult.fromJson(original.toJson());
      expect(restored.status, MCPHealthStatus.degraded);
      expect(restored.message, 'm');
      expect(restored.details, {'a': 1});
      expect(restored.timestamp, t);
    });
  });
}
