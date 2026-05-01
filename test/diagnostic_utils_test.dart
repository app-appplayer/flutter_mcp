import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/utils/diagnostic_utils.dart';

class _FakeMcp {
  bool isInitialized = true;
  Map<String, dynamic> getSystemStatus() => {
        'initialized': true,
        'clients': 1,
        'servers': 0,
        'llms': 0,
        'platformName': 'test',
        'platformFeatures': const {},
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectSystemDiagnostics', () {
    test('returns a populated map without an mcp argument', () {
      final d = DiagnosticUtils.collectSystemDiagnostics(null);
      expect(d, contains('timestamp'));
      expect(d, contains('platformInfo'));
      expect(d, contains('resources'));
      expect(d, contains('performanceMetrics'));
      expect(d, contains('featureSupport'));
      expect(d, isNot(contains('mcpState')));
    });

    test('includes mcpState when mcp is supplied', () {
      final d = DiagnosticUtils.collectSystemDiagnostics(_FakeMcp());
      expect(d, contains('mcpState'));
      expect(d['mcpState']['initialized'], isTrue);
    });

    test('platformInfo includes core flags', () {
      final d = DiagnosticUtils.collectSystemDiagnostics(null);
      final info = d['platformInfo'] as Map<String, dynamic>;
      expect(info, contains('platform'));
      expect(info, contains('isWeb'));
      expect(info, contains('isMobile'));
      expect(info, contains('isDesktop'));
    });
  });

  group('runDiagnostics', () {
    test('returns a populated diagnostic shape', () async {
      final d = await DiagnosticUtils.runDiagnostics(null);
      expect(d, contains('timestamp'));
      expect(d, contains('version'));
      expect(d, contains('diagnosticResults'));
      final results = d['diagnosticResults'] as Map<String, dynamic>;
      expect(results, contains('connectivity'));
      expect(results, contains('performance'));
      expect(results, contains('resources'));
    });
  });

  group('checkHealth', () {
    test('returns a status map', () async {
      final h = await DiagnosticUtils.checkHealth(null);
      expect(h, isA<Map>());
      expect(h, contains('status'));
    });
  });

  group('getMcpState', () {
    test('handles non-initialized mcp safely', () {
      final fake = _FakeMcp()..isInitialized = false;
      final state = DiagnosticUtils.getMcpState(fake);
      expect(state['initialized'], isFalse);
    });

    test('returns map when mcp is null', () {
      final state = DiagnosticUtils.getMcpState(null);
      expect(state, isA<Map>());
    });
  });
}
